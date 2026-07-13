import Foundation

/// Micro test harness. The machine has Command Line Tools only — neither
/// XCTest nor Swift Testing ships with it — so checks are a plain executable:
/// `swift run tlg-checks`, non-zero exit on any failure.
struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    let file: String
    let line: Int
    var description: String { "\(file):\(line): \(message)" }
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "expectation failed",
    file: String = #fileID,
    line: Int = #line
) throws {
    if !condition() {
        throw CheckFailure(message: message(), file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ actual: T, _ expected: T,
    file: String = #fileID, line: Int = #line
) throws {
    if actual != expected {
        throw CheckFailure(message: "got \(actual), expected \(expected)", file: file, line: line)
    }
}

func expectThrows<E>(
    _ body: () throws -> Void,
    _ errorType: E.Type,
    file: String = #fileID, line: Int = #line
) throws {
    do {
        try body()
        throw CheckFailure(message: "expected \(E.self) to be thrown", file: file, line: line)
    } catch is E {
        // expected
    }
    // Any other error propagates and fails the check with its own message.
}

struct Check {
    let name: String
    let run: () async throws -> Void

    init(_ name: String, _ run: @escaping () async throws -> Void) {
        self.name = name
        self.run = run
    }
}

func runChecks(_ checks: [Check]) async -> Never {
    var failures = 0
    for check in checks {
        do {
            try await check.run()
            print("✓ \(check.name)")
        } catch {
            failures += 1
            print("✗ \(check.name)")
            print("    \(error)")
        }
    }
    print("\n\(checks.count - failures)/\(checks.count) checks passed")
    exit(failures == 0 ? 0 : 1)
}

/// Fresh temporary LauncherPaths for filesystem tests; both roots isolated.
func temporaryPaths() throws -> (LauncherPaths, cleanup: () -> Void) {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("tlg-checks-\(UUID().uuidString)", isDirectory: true)
    let paths = LauncherPaths(
        launcherSupport: base.appendingPathComponent("TLG Launcher", isDirectory: true),
        gameUserData: base.appendingPathComponent("Cataclysm-TLG", isDirectory: true)
    )
    try paths.ensureLauncherDirectories()
    return (paths, { try? FileManager.default.removeItem(at: base) })
}

@discardableResult
func write(_ text: String, to url: URL) throws -> URL {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url)
    return url
}

import TLGLauncherCore
