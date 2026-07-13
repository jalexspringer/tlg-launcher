import Foundation

/// Every path the launcher reads or writes, derived from two roots so tests
/// can point both at temporary directories.
///
/// The one inviolable rule: nothing under `gameUserData` is ever written by
/// the update/install pipeline. `assertOutsideGameUserData` enforces it.
public struct LauncherPaths: Sendable {
    /// The launcher's own state root, e.g. ~/Library/Application Support/TLG Launcher
    public let launcherSupport: URL
    /// The canonical TLG user directory, e.g. ~/Library/Application Support/Cataclysm-TLG
    public let gameUserData: URL

    public init(launcherSupport: URL, gameUserData: URL) {
        self.launcherSupport = launcherSupport.standardizedFileURL
        self.gameUserData = gameUserData.standardizedFileURL
    }

    public static func standard() -> LauncherPaths {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return LauncherPaths(
            launcherSupport: appSupport.appendingPathComponent("TLG Launcher", isDirectory: true),
            gameUserData: appSupport.appendingPathComponent("Cataclysm-TLG", isDirectory: true)
        )
    }

    // Launcher-owned locations.
    public var versionsDir: URL { launcherSupport.appendingPathComponent("versions", isDirectory: true) }
    public var stagingDir: URL { launcherSupport.appendingPathComponent("staging", isDirectory: true) }
    public var downloadsDir: URL { launcherSupport.appendingPathComponent("downloads", isDirectory: true) }
    public var backupsDir: URL { launcherSupport.appendingPathComponent("backups", isDirectory: true) }
    public var configBackupsDir: URL { launcherSupport.appendingPathComponent("config-backups", isDirectory: true) }
    public var stateFile: URL { launcherSupport.appendingPathComponent("state.json") }

    // Game user-data locations (read, backed up, and — for fonts/config only —
    // deliberately written by the font manager, never by the installer).
    public var savesDir: URL { gameUserData.appendingPathComponent("save", isDirectory: true) }
    public var configDir: URL { gameUserData.appendingPathComponent("config", isDirectory: true) }
    public var userFontDir: URL { gameUserData.appendingPathComponent("font", isDirectory: true) }
    public var fontsJSON: URL { configDir.appendingPathComponent("fonts.json") }
    public var optionsJSON: URL { configDir.appendingPathComponent("options.json") }

    public func versionDir(forTag tag: String) -> URL {
        versionsDir.appendingPathComponent(tag, isDirectory: true)
    }

    public func ensureLauncherDirectories() throws {
        let fm = FileManager.default
        for dir in [launcherSupport, versionsDir, stagingDir, downloadsDir, backupsDir, configBackupsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public enum PathViolation: Error, CustomStringConvertible {
        case insideGameUserData(URL)
        public var description: String {
            switch self {
            case .insideGameUserData(let url):
                return "Refusing to write inside the TLG user directory: \(url.path)"
            }
        }
    }

    /// Throws if `url` is the game user directory or anything below it.
    public func assertOutsideGameUserData(_ url: URL) throws {
        let target = url.standardizedFileURL.path
        let userData = gameUserData.path
        if target == userData || target.hasPrefix(userData + "/") {
            throw PathViolation.insideGameUserData(url)
        }
    }
}
