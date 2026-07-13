import Foundation
import CryptoKit

public enum DigestError: Error, CustomStringConvertible, Equatable {
    case malformedDigest(String)
    case mismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case .malformedDigest(let d):
            return "Unrecognised digest format: \(d)"
        case .mismatch(let expected, let actual):
            return "Digest mismatch — expected \(expected), got \(actual). The download is corrupt or tampered with."
        }
    }
}

public enum SHA256Verifier {
    /// Streaming SHA-256 of a file, as lowercase hex.
    public static func hexDigest(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Accepts GitHub's "sha256:<hex>" form or bare hex.
    public static func expectedHex(fromDigest digest: String) throws -> String {
        let lower = digest.lowercased()
        let hex = lower.hasPrefix("sha256:") ? String(lower.dropFirst("sha256:".count)) : lower
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else {
            throw DigestError.malformedDigest(digest)
        }
        return hex
    }

    public static func verify(file: URL, digest: String) throws {
        let expected = try expectedHex(fromDigest: digest)
        let actual = try hexDigest(of: file)
        guard actual == expected else {
            throw DigestError.mismatch(expected: expected, actual: actual)
        }
    }
}
