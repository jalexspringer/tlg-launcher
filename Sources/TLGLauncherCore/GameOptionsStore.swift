import Foundation

public enum GameConfigError: Error, CustomStringConvertible {
    case gameRunning
    case malformedFile(String)

    public var description: String {
        switch self {
        case .gameRunning:
            return "Cataclysm: TLG is running. Close the game before changing its settings."
        case .malformedFile(let name):
            return "\(name) could not be parsed. Fix or remove it, then try again."
        }
    }
}

/// Reads and writes entries in TLG's config/options.json by option name.
///
/// The file is edited through JSONSerialization so every field the launcher
/// does not understand survives a round trip untouched, entry order is kept,
/// and the file is backed up before every write. Writes are refused while
/// the game is running. The fonts, tilesets and sound panes all go through
/// this store.
public struct GameOptionsStore: Sendable {
    public let paths: LauncherPaths
    private let detector: GameProcessDetecting
    private let now: @Sendable () -> Date

    public init(
        paths: LauncherPaths,
        detector: GameProcessDetecting,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.paths = paths
        self.detector = detector
        self.now = now
    }

    /// Current value of one option, or nil when the file/entry is absent.
    public func value(_ name: String) throws -> String? {
        guard let entries = try loadEntries() else { return nil }
        for case let entry as [String: Any] in entries where entry["name"] as? String == name {
            return entry["value"] as? String
        }
        return nil
    }

    /// Rewrites options.json with the given values, preserving every other
    /// entry, unknown fields and entry order. Missing entries are appended
    /// (the game fills in its own metadata on next save). A missing file is
    /// created — the game treats a partial options.json as overrides on its
    /// defaults and completes it on its next save.
    public func setValues(_ values: [String: String]) throws {
        guard !detector.isGameRunning() else { throw GameConfigError.gameRunning }
        var entries: [Any]
        if let existing = try loadEntries() {
            entries = existing
            try ConfigFileBackup.backUp(paths.optionsJSON, paths: paths, at: now())
        } else {
            entries = []
            try FileManager.default.createDirectory(
                at: paths.configDir, withIntermediateDirectories: true
            )
        }
        var remaining = values
        for (index, item) in entries.enumerated() {
            guard var entry = item as? [String: Any],
                  let name = entry["name"] as? String,
                  let newValue = remaining.removeValue(forKey: name)
            else { continue }
            entry["value"] = newValue
            entries[index] = entry
        }
        for (name, value) in remaining.sorted(by: { $0.key < $1.key }) {
            entries.append(["name": name, "value": value] as [String: Any])
        }
        let data = try JSONSerialization.data(
            withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
        )
        try data.atomicWrite(to: paths.optionsJSON)
    }

    private func loadEntries() throws -> [Any]? {
        guard FileManager.default.fileExists(atPath: paths.optionsJSON.path) else { return nil }
        let data = try Data(contentsOf: paths.optionsJSON)
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw GameConfigError.malformedFile("options.json")
        }
        return entries
    }
}
