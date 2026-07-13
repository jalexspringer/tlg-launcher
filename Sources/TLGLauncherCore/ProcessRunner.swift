import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

/// Boundary for spawning external tools (hdiutil, pgrep, xattr) so tests can
/// substitute canned results.
public protocol ProcessRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> ProcessResult
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Drain before waiting so a chatty child can't deadlock on a full pipe.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
