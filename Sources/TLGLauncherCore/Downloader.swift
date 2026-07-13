import Foundation

public protocol Downloading: Sendable {
    /// Streams `url` to `destination`, overwriting it. Calls `progress` with
    /// (received, expectedTotal) as bytes arrive; total is nil when unknown.
    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws
}

public enum DownloadError: Error, CustomStringConvertible {
    case httpStatus(Int)
    public var description: String {
        switch self {
        case .httpStatus(let code): return "Download failed with HTTP \(code)."
        }
    }
}

public struct URLSessionDownloader: Downloading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.httpStatus(http.statusCode)
        }
        let expected = response.expectedContentLength
        let total: Int64? = expected > 0 ? expected : nil

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data(capacity: 1 << 20)
        var received: Int64 = 0
        var lastReport: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if received - lastReport >= 1 << 20 {
                    lastReport = received
                    progress(received, total)
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        progress(received, total)
    }
}
