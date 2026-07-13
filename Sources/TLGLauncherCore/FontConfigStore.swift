import Foundation

public enum FontConfigError: Error, CustomStringConvertible {
    case gameRunning
    case malformedFile(String)

    public var description: String {
        switch self {
        case .gameRunning:
            return "Cataclysm: TLG is running. Close the game before changing font settings."
        case .malformedFile(let name):
            return "\(name) could not be parsed. Fix or remove it, then try again."
        }
    }
}

/// The three typeface stacks TLG reads from config/fonts.json. Each is an
/// ordered list; later entries are fallbacks for missing glyphs.
public struct FontsConfig: Sendable, Equatable {
    public var typeface: [String]
    public var mapTypeface: [String]
    public var overmapTypeface: [String]

    public init(typeface: [String], mapTypeface: [String], overmapTypeface: [String]) {
        self.typeface = typeface
        self.mapTypeface = mapTypeface
        self.overmapTypeface = overmapTypeface
    }

    /// What a fresh TLG install writes.
    public static let tlgDefault = FontsConfig(
        typeface: ["data/font/Terminus.ttf", "data/font/unifont.ttf"],
        mapTypeface: ["data/font/Terminus.ttf", "data/font/unifont.ttf"],
        overmapTypeface: ["data/font/Terminus.ttf", "data/font/unifont.ttf"]
    )
}

/// The font-related entries in config/options.json (all stored as strings,
/// matching the game's own serialisation).
public enum FontOption: String, CaseIterable, Sendable {
    case fontWidth = "FONT_WIDTH"
    case fontHeight = "FONT_HEIGHT"
    case fontSize = "FONT_SIZE"
    case mapFontWidth = "MAP_FONT_WIDTH"
    case mapFontHeight = "MAP_FONT_HEIGHT"
    case mapFontSize = "MAP_FONT_SIZE"
    case overmapFontWidth = "OVERMAP_FONT_WIDTH"
    case overmapFontHeight = "OVERMAP_FONT_HEIGHT"
    case overmapFontSize = "OVERMAP_FONT_SIZE"
    case fontBlending = "FONT_BLENDING"
    case drawAsciiLines = "USE_DRAW_ASCII_LINES_ROUTINE"

    public var tlgDefault: String {
        switch self {
        case .fontWidth: return "8"
        case .fontHeight, .fontSize: return "16"
        case .mapFontWidth, .mapFontHeight, .mapFontSize: return "16"
        case .overmapFontWidth, .overmapFontHeight, .overmapFontSize: return "16"
        case .fontBlending: return "false"
        case .drawAsciiLines: return "true"
        }
    }
}

/// Reads and writes TLG's fonts.json and options.json.
///
/// Both files are edited through JSONSerialization dictionaries/arrays so
/// every field the launcher does not understand survives a round trip
/// untouched, and both are backed up before every write. Writes are refused
/// while the game is running.
public struct FontConfigStore: Sendable {
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

    // MARK: fonts.json

    public func loadFonts() throws -> FontsConfig {
        guard FileManager.default.fileExists(atPath: paths.fontsJSON.path) else {
            return .tlgDefault
        }
        let data = try Data(contentsOf: paths.fontsJSON)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FontConfigError.malformedFile("fonts.json")
        }
        return FontsConfig(
            typeface: Self.typefaceList(dict["typeface"]) ?? FontsConfig.tlgDefault.typeface,
            mapTypeface: Self.typefaceList(dict["map_typeface"]) ?? FontsConfig.tlgDefault.mapTypeface,
            overmapTypeface: Self.typefaceList(dict["overmap_typeface"]) ?? FontsConfig.tlgDefault.overmapTypeface
        )
    }

    /// TLG accepts a bare string or a list for each typeface key.
    static func typefaceList(_ value: Any?) -> [String]? {
        if let string = value as? String { return [string] }
        if let list = value as? [Any] { return list.compactMap { $0 as? String } }
        return nil
    }

    public func saveFonts(_ config: FontsConfig) throws {
        try guardWritable()
        var dict: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: paths.fontsJSON.path) {
            let data = try Data(contentsOf: paths.fontsJSON)
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FontConfigError.malformedFile("fonts.json")
            }
            dict = existing
            try backUp(paths.fontsJSON)
        }
        dict["typeface"] = config.typeface
        dict["map_typeface"] = config.mapTypeface
        dict["overmap_typeface"] = config.overmapTypeface
        let data = try JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        )
        try data.atomicWrite(to: paths.fontsJSON)
    }

    // MARK: options.json

    /// Current value of one option, or nil when the file/entry is absent.
    public func optionValue(_ option: FontOption) throws -> String? {
        guard let entries = try loadOptionEntries() else { return nil }
        for case let entry as [String: Any] in entries where entry["name"] as? String == option.rawValue {
            return entry["value"] as? String
        }
        return nil
    }

    /// Rewrites options.json with the given font option values, preserving
    /// every other entry, unknown fields and entry order. Missing entries are
    /// appended (the game fills in its own metadata on next save).
    public func setOptions(_ values: [FontOption: String]) throws {
        try guardWritable()
        guard var entries = try loadOptionEntries() else {
            throw FontConfigError.malformedFile("options.json (missing — run the game once first)")
        }
        try backUp(paths.optionsJSON)
        var remaining = values
        for (index, item) in entries.enumerated() {
            guard var entry = item as? [String: Any],
                  let name = entry["name"] as? String,
                  let option = FontOption(rawValue: name),
                  let newValue = remaining.removeValue(forKey: option)
            else { continue }
            entry["value"] = newValue
            entries[index] = entry
        }
        for (option, value) in remaining.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            entries.append(["name": option.rawValue, "value": value] as [String: Any])
        }
        let data = try JSONSerialization.data(
            withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
        )
        try data.atomicWrite(to: paths.optionsJSON)
    }

    private func loadOptionEntries() throws -> [Any]? {
        guard FileManager.default.fileExists(atPath: paths.optionsJSON.path) else { return nil }
        let data = try Data(contentsOf: paths.optionsJSON)
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw FontConfigError.malformedFile("options.json")
        }
        return entries
    }

    // MARK: shared

    private func guardWritable() throws {
        guard !detector.isGameRunning() else { throw FontConfigError.gameRunning }
    }

    private func backUp(_ file: URL) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: now())
        let dir = paths.configBackupsDir.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(file.lastPathComponent)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }
}
