import Foundation
import Network

/// Minimal loopback HTTP server for the bundled Hitchhiker's Guide.
///
/// Serves a static Vite SPA to WKWebView without file:// origin, CORS or
/// service-worker headaches. GET/HEAD only, bound to 127.0.0.1 on an
/// ephemeral port, path-traversal-proof, with client-side routes falling
/// back to index.html.
public final class GuideServer: @unchecked Sendable {
    public let root: URL
    private let queue = DispatchQueue(label: "tlg-launcher.guide-server")
    private var listener: NWListener?
    public private(set) var port: UInt16?

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    deinit { stop() }

    /// Starts listening and returns the chosen port.
    @discardableResult
    public func start() throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener

        let semaphore = DispatchSemaphore(value: 0)
        let resolved = Locked<Result<UInt16, Error>?>(nil)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                resolved.set(.success(listener.port?.rawValue ?? 0))
                semaphore.signal()
            case .failed(let error):
                resolved.set(.failure(error))
                semaphore.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 5)
        switch resolved.get() {
        case .success(let port):
            self.port = port
            return port
        case .failure(let error):
            self.listener = nil
            throw error
        case nil:
            self.listener = nil
            throw GuideServerError.startTimeout
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    public var baseURL: URL? {
        port.map { URL(string: "http://127.0.0.1:\($0)/")! }
    }

    // MARK: Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                let response = self.response(forRawRequest: buffer)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else if isComplete || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.receiveRequest(connection, buffer: buffer)
            }
        }
    }

    // MARK: Request → response (pure; exercised directly by the checks)

    public func response(forRawRequest raw: Data) -> Data {
        guard let head = String(data: raw, encoding: .utf8)?
                .components(separatedBy: "\r\n").first,
              case let parts = head.split(separator: " "),
              parts.count >= 2
        else {
            return Self.simpleResponse(status: "400 Bad Request")
        }
        let method = String(parts[0])
        guard method == "GET" || method == "HEAD" else {
            return Self.simpleResponse(status: "405 Method Not Allowed")
        }
        let target = String(parts[1])
        guard let resolved = resolve(requestTarget: target) else {
            return Self.simpleResponse(status: "404 Not Found")
        }
        guard let body = try? Data(contentsOf: resolved) else {
            return Self.simpleResponse(status: "404 Not Found")
        }
        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: \(Self.mimeType(for: resolved.pathExtension))\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Cache-Control: no-cache\r\n"
        response += "Connection: close\r\n\r\n"
        var data = Data(response.utf8)
        if method == "GET" { data.append(body) }
        return data
    }

    /// Maps a request target to a file inside `root`, or nil (404).
    /// Traversal is rejected twice over: ".." components are refused outright,
    /// and the standardised result must still live under root.
    public func resolve(requestTarget: String) -> URL? {
        var path = requestTarget
        if let q = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[..<q])
        }
        guard let decoded = path.removingPercentEncoding, !decoded.contains("\0") else {
            return nil
        }
        let components = decoded.split(separator: "/").map(String.init)
        guard !components.contains("..") else {
            return nil
        }

        var candidate = root
        for component in components {
            candidate.appendPathComponent(component)
        }
        candidate = candidate.standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }

        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let index = candidate.appendingPathComponent("index.html")
                return fm.fileExists(atPath: index.path) ? index : fallbackIndex()
            }
            return candidate
        }
        // SPA fallback: unknown extensionless routes get the app shell;
        // missing assets (anything with an extension) are honest 404s.
        return components.last?.contains(".") == true ? nil : fallbackIndex()
    }

    private func fallbackIndex() -> URL? {
        let index = root.appendingPathComponent("index.html")
        return FileManager.default.fileExists(atPath: index.path) ? index : nil
    }

    static func simpleResponse(status: String) -> Data {
        Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json", "map": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "wasm": return "application/wasm"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "txt": return "text/plain; charset=utf-8"
        case "webmanifest": return "application/manifest+json"
        default: return "application/octet-stream"
        }
    }
}

public enum GuideServerError: Error, CustomStringConvertible {
    case startTimeout
    public var description: String {
        switch self {
        case .startTimeout: return "The guide server did not start in time."
        }
    }
}

/// Tiny lock wrapper (no os.lock dependency on the checks target).
final class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
}
