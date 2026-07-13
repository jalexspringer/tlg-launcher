import Foundation

/// How a managed TLG build gets started.
///
/// The release app's CFBundleExecutable is a shell script that does not
/// forward arguments, so `open --args --userdir …` would silently lose the
/// user directory. Instead we do exactly what the script does — run
/// Contents/Resources/cataclysm-tlg-tiles with the Resources directory as
/// both working directory and dyld search path — and add `--userdir`
/// pointing at the canonical TLG user directory.
public struct GameLaunchPlan: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let workingDirectory: URL
    public let environment: [String: String]
}

public enum LaunchError: Error, CustomStringConvertible {
    case noVersionInstalled
    case binaryMissing(URL)

    public var description: String {
        switch self {
        case .noVersionInstalled:
            return "No game version is installed yet. Use Update and Play first."
        case .binaryMissing(let url):
            return "Game binary not found at \(url.path)."
        }
    }
}

public enum GameLauncher {
    public static let tilesBinaryName = "cataclysm-tlg-tiles"

    /// Pure planning, so tests can verify arguments without spawning anything.
    public static func plan(appBundle: URL, userDataDir: URL) throws -> GameLaunchPlan {
        let resources = appBundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        let binary = resources.appendingPathComponent(tilesBinaryName)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw LaunchError.binaryMissing(binary)
        }
        // TLG concatenates paths onto the user dir, so the trailing slash matters.
        var userDir = userDataDir.standardizedFileURL.path
        if !userDir.hasSuffix("/") { userDir += "/" }
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_LIBRARY_PATH"] = "."
        environment["DYLD_FRAMEWORK_PATH"] = "."
        return GameLaunchPlan(
            executable: binary,
            arguments: ["--userdir", userDir],
            workingDirectory: resources,
            environment: environment
        )
    }

    @discardableResult
    public static func launch(appBundle: URL, userDataDir: URL) throws -> Process {
        let plan = try plan(appBundle: appBundle, userDataDir: userDataDir)
        let process = Process()
        process.executableURL = plan.executable
        process.arguments = plan.arguments
        process.currentDirectoryURL = plan.workingDirectory
        process.environment = plan.environment
        try process.run()
        return process
    }
}
