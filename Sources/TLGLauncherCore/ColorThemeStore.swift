import Foundation

public enum ColorThemeError: Error, CustomStringConvertible {
    case gameRunning
    case malformedFile(String)

    public var description: String {
        switch self {
        case .gameRunning:
            return "Cataclysm: TLG is running. Close the game before changing the colour scheme."
        case .malformedFile(let name):
            return "\(name) could not be parsed. Fix or remove it, then try again."
        }
    }
}

/// The sixteen terminal colours a TLG colordef assigns, in the game's
/// canonical order (normal eight, then their bright variants).
public enum GameColor: String, CaseIterable, Sendable {
    case black = "BLACK"
    case red = "RED"
    case green = "GREEN"
    case brown = "BROWN"
    case blue = "BLUE"
    case magenta = "MAGENTA"
    case cyan = "CYAN"
    case gray = "GRAY"
    case darkGray = "DGRAY"
    case lightRed = "LRED"
    case lightGreen = "LGREEN"
    case yellow = "YELLOW"
    case lightBlue = "LBLUE"
    case lightMagenta = "LMAGENTA"
    case lightCyan = "LCYAN"
    case white = "WHITE"

    public var displayName: String {
        switch self {
        case .black: return "Black"
        case .red: return "Red"
        case .green: return "Green"
        case .brown: return "Brown"
        case .blue: return "Blue"
        case .magenta: return "Magenta"
        case .cyan: return "Cyan"
        case .gray: return "Grey"
        case .darkGray: return "Dark grey"
        case .lightRed: return "Light red"
        case .lightGreen: return "Light green"
        case .yellow: return "Yellow"
        case .lightBlue: return "Light blue"
        case .lightMagenta: return "Light magenta"
        case .lightCyan: return "Light cyan"
        case .white: return "White"
        }
    }
}

public struct RGB: Sendable, Equatable, Hashable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var hexString: String { String(format: "#%02X%02X%02X", r, g, b) }
}

/// One named colour scheme: a complete colordef mapping. Bundled themes come
/// from data/raw/color_themes in the game bundle.
public struct ColorTheme: Sendable, Equatable, Identifiable {
    public let name: String
    public let colors: [GameColor: RGB]

    public init(name: String, colors: [GameColor: RGB]) {
        self.name = name
        self.colors = colors
    }

    public var id: String { name }

    /// The palette a fresh TLG install uses (data/raw/colors.json). The game
    /// ships the same values as the bundled "Default" theme.
    public static let tlgDefault = ColorTheme(name: "TLG Default", colors: [
        .black: RGB(0, 0, 0),
        .red: RGB(255, 0, 0),
        .green: RGB(0, 110, 0),
        .brown: RGB(97, 56, 28),
        .blue: RGB(10, 10, 220),
        .magenta: RGB(139, 58, 98),
        .cyan: RGB(0, 150, 180),
        .gray: RGB(150, 150, 150),
        .darkGray: RGB(99, 99, 99),
        .lightRed: RGB(255, 150, 150),
        .lightGreen: RGB(0, 255, 0),
        .yellow: RGB(255, 255, 0),
        .lightBlue: RGB(100, 100, 255),
        .lightMagenta: RGB(254, 0, 254),
        .lightCyan: RGB(0, 240, 255),
        .white: RGB(255, 255, 255),
    ])
}

/// Finds and parses the colour themes bundled with an installed game version.
public enum ColorThemeCatalog {
    public static func themesDirectory(appBundle: URL) -> URL {
        appBundle.appendingPathComponent("Contents/Resources/data/raw/color_themes", isDirectory: true)
    }

    /// All parseable themes in the bundle, sorted by display name.
    /// Unparseable files are skipped rather than failing the whole list.
    public static func bundledThemes(appBundle: URL) -> [ColorTheme] {
        let dir = themesDirectory(appBundle: appBundle)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let colors = try? parseColordef(data)
                else { return nil }
                return ColorTheme(name: displayName(forFile: url.lastPathComponent), colors: colors)
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    /// "base_colors-blood_moon.json" → "Blood Moon". The shipped files mix
    /// "-" and "_" as separators, so both are treated alike.
    public static func displayName(forFile filename: String) -> String {
        var stem = (filename as NSString).deletingPathExtension
        if stem.lowercased().hasPrefix("base_colors") {
            stem = String(stem.dropFirst("base_colors".count))
        }
        let words = stem
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? stem : words.joined(separator: " ")
    }

    /// Parses a colordef file: a JSON array whose first colordef object maps
    /// colour names to [r, g, b]. Colours beyond the known sixteen are
    /// ignored; missing ones fall back to the TLG default so a partial
    /// theme still yields a complete palette.
    public static func parseColordef(_ data: Data) throws -> [GameColor: RGB] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ColorThemeError.malformedFile("colordef")
        }
        for case let object as [String: Any] in array {
            guard object["type"] as? String == "colordef" else { continue }
            var colors = ColorTheme.tlgDefault.colors
            for color in GameColor.allCases {
                guard let triple = object[color.rawValue] as? [Any] else { continue }
                let channels = triple.compactMap { ($0 as? NSNumber)?.intValue }
                guard channels.count == 3 else {
                    throw ColorThemeError.malformedFile("colordef")
                }
                colors[color] = RGB(channels[0], channels[1], channels[2])
            }
            return colors
        }
        throw ColorThemeError.malformedFile("colordef")
    }
}

/// Reads and writes TLG's config/base_colors.json — the file the game loads
/// its palette from at startup. Writes are backed up first and refused while
/// the game is running, matching FontConfigStore.
public struct ColorThemeStore: Sendable {
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

    /// The palette currently in config/base_colors.json, or the TLG default
    /// when the file does not exist yet (the game behaves the same way).
    public func currentColors() throws -> [GameColor: RGB] {
        guard FileManager.default.fileExists(atPath: paths.baseColorsJSON.path) else {
            return ColorTheme.tlgDefault.colors
        }
        let data = try Data(contentsOf: paths.baseColorsJSON)
        do {
            return try ColorThemeCatalog.parseColordef(data)
        } catch {
            throw ColorThemeError.malformedFile("base_colors.json")
        }
    }

    /// Writes the theme to config/base_colors.json in the game's own shape,
    /// backing up the previous file first.
    public func apply(_ theme: ColorTheme) throws {
        guard !detector.isGameRunning() else { throw ColorThemeError.gameRunning }
        if FileManager.default.fileExists(atPath: paths.baseColorsJSON.path) {
            try ConfigFileBackup.backUp(paths.baseColorsJSON, paths: paths, at: now())
        }
        var object: [String: Any] = ["type": "colordef"]
        for (color, rgb) in theme.colors {
            object[color.rawValue] = [rgb.r, rgb.g, rgb.b]
        }
        let data = try JSONSerialization.data(
            withJSONObject: [object], options: [.prettyPrinted, .sortedKeys]
        )
        try FileManager.default.createDirectory(
            at: paths.configDir, withIntermediateDirectories: true
        )
        try data.atomicWrite(to: paths.baseColorsJSON)
    }
}
