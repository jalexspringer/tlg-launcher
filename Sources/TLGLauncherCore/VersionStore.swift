import Foundation

/// Owns state.json (active/previous tags) and the versions/ directory layout.
public struct VersionStore: Sendable {
    public static let metadataFilename = ".tlg-launcher-version.json"
    public static let appName = "Cataclysm.app"

    public let paths: LauncherPaths

    public init(paths: LauncherPaths) {
        self.paths = paths
    }

    // MARK: State

    public func loadState() -> LauncherState {
        guard let data = try? Data(contentsOf: paths.stateFile),
              let state = try? JSONDecoder.launcher.decode(LauncherState.self, from: data)
        else { return LauncherState() }
        return state
    }

    public func saveState(_ state: LauncherState) throws {
        try JSONEncoder.launcher.encode(state).atomicWrite(to: paths.stateFile)
    }

    // MARK: Installed versions

    public func installedVersions() -> [InstalledVersion] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: paths.versionsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { dir in
            let metaFile = dir.appendingPathComponent(Self.metadataFilename)
            guard let data = try? Data(contentsOf: metaFile),
                  let meta = try? JSONDecoder.launcher.decode(InstalledVersion.self, from: data)
            else { return nil }
            return meta
        }
        .sorted { $0.installedAt > $1.installedAt }
    }

    public func appBundle(forTag tag: String) -> URL {
        paths.versionDir(forTag: tag).appendingPathComponent(Self.appName, isDirectory: true)
    }

    public func activeAppBundle() -> URL? {
        guard let tag = loadState().activeTag else { return nil }
        let bundle = appBundle(forTag: tag)
        return FileManager.default.fileExists(atPath: bundle.path) ? bundle : nil
    }

    /// Makes `previousTag` active again. Application rollback only — user data
    /// is untouched; restoring a data backup is a separate, explicit action.
    public func rollback() throws -> String {
        var state = loadState()
        guard let previous = state.previousTag else {
            throw VersionError.nothingToRollBackTo
        }
        guard FileManager.default.fileExists(atPath: appBundle(forTag: previous).path) else {
            throw VersionError.versionMissing(previous)
        }
        let current = state.activeTag
        state.activeTag = previous
        state.previousTag = current
        try saveState(state)
        return previous
    }

    /// Deletes installed versions beyond `keep`, never touching the active or
    /// previous version.
    public func prune(keep: Int) throws {
        let state = loadState()
        let protected = Set([state.activeTag, state.previousTag].compactMap { $0 })
        let removable = installedVersions()
            .filter { !protected.contains($0.tag) }
            .sorted { $0.installedAt > $1.installedAt }
        let excess = removable.dropFirst(max(0, keep - protected.count))
        for version in excess {
            try FileManager.default.removeItem(at: paths.versionDir(forTag: version.tag))
        }
    }
}

public enum VersionError: Error, CustomStringConvertible, Equatable {
    case nothingToRollBackTo
    case versionMissing(String)

    public var description: String {
        switch self {
        case .nothingToRollBackTo:
            return "No previous version is available to roll back to."
        case .versionMissing(let tag):
            return "Version \(tag) is no longer on disk."
        }
    }
}

// MARK: - Shared JSON helpers

extension JSONDecoder {
    public static var launcher: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    public static var launcher: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension Data {
    /// Write via a sibling temporary file and atomic replace.
    public func atomicWrite(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try write(to: url, options: .atomic)
    }
}
