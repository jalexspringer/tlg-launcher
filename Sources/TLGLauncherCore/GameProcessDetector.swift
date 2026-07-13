import Foundation

public protocol GameProcessDetecting: Sendable {
    func isGameRunning() -> Bool
}

/// Detects any running TLG instance — launcher-managed, DMG-installed or the
/// Steam build. All of them share the canonical user directory, so an update
/// or config write is unsafe while any of them is live. Detection is by
/// command line, because TLG's bundle identifier is shared with mainline CDDA.
public struct GameProcessDetector: GameProcessDetecting {
    private let runner: ProcessRunning
    /// Substrings matched against full process command lines.
    public static let defaultPatterns = [
        "cataclysm-tlg",                     // release binary names (tiles + curses)
        "Cataclysm The Last Generation",     // Steam install path
    ]
    private let patterns: [String]

    public init(runner: ProcessRunning = SystemProcessRunner(), patterns: [String] = defaultPatterns) {
        self.runner = runner
        self.patterns = patterns
    }

    public func isGameRunning() -> Bool {
        for pattern in patterns {
            guard let result = try? runner.run("/usr/bin/pgrep", arguments: ["-f", pattern]) else {
                continue
            }
            // pgrep: 0 = matches found, 1 = none. Treat other stats as "unknown", not "running".
            if result.status == 0 {
                let pids = result.stdoutText.split(separator: "\n").compactMap { Int32($0) }
                if pids.contains(where: { $0 != ProcessInfo.processInfo.processIdentifier }) {
                    return true
                }
            }
        }
        return false
    }
}
