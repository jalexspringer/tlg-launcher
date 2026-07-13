import Foundation

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

/// Reads and writes TLG's fonts.json, plus the font entries of options.json
/// via GameOptionsStore.
///
/// fonts.json is edited through JSONSerialization dictionaries so every field
/// the launcher does not understand survives a round trip untouched, and is
/// backed up before every write. Writes are refused while the game is running.
public struct FontConfigStore: Sendable {
    public let paths: LauncherPaths
    private let detector: GameProcessDetecting
    private let options: GameOptionsStore
    private let now: @Sendable () -> Date

    public init(
        paths: LauncherPaths,
        detector: GameProcessDetecting,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.paths = paths
        self.detector = detector
        self.options = GameOptionsStore(paths: paths, detector: detector, now: now)
        self.now = now
    }

    // MARK: fonts.json

    public func loadFonts() throws -> FontsConfig {
        guard FileManager.default.fileExists(atPath: paths.fontsJSON.path) else {
            return .tlgDefault
        }
        let data = try Data(contentsOf: paths.fontsJSON)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GameConfigError.malformedFile("fonts.json")
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
        guard !detector.isGameRunning() else { throw GameConfigError.gameRunning }
        var dict: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: paths.fontsJSON.path) {
            let data = try Data(contentsOf: paths.fontsJSON)
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GameConfigError.malformedFile("fonts.json")
            }
            dict = existing
            try ConfigFileBackup.backUp(paths.fontsJSON, paths: paths, at: now())
        }
        dict["typeface"] = config.typeface
        dict["map_typeface"] = config.mapTypeface
        dict["overmap_typeface"] = config.overmapTypeface
        let data = try JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        )
        try data.atomicWrite(to: paths.fontsJSON)
    }

    // MARK: options.json (delegated)

    public func optionValue(_ option: FontOption) throws -> String? {
        try options.value(option.rawValue)
    }

    public func setOptions(_ values: [FontOption: String]) throws {
        try options.setValues(Dictionary(
            uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }
        ))
    }
}

/// Copies a config file into a timestamped folder under config-backups before
/// it is overwritten. Shared by the font, colour and options stores.
enum ConfigFileBackup {
    static func backUp(_ file: URL, paths: LauncherPaths, at date: Date) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = formatter.string(from: date)
        let dir = paths.configBackupsDir.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(file.lastPathComponent)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }
}
