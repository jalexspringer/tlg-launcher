import Foundation

/// Parses the "KEY: value" metadata files tilesets and soundpacks carry
/// (tileset.txt / soundpack.txt). Lines starting with # are comments.
enum PackMetadata {
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            // Only shouty keys are metadata; "Original Author: X" prose is not.
            if key == key.uppercased(), !key.isEmpty, !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }
}

/// One tileset: a gfx/<dir> with a tileset.txt describing it. `name` is the
/// value the game stores in the TILES / OVERMAP_TILES / DISTANT_TILES options;
/// `viewName` is what their in-game pickers display.
public struct Tileset: Sendable, Equatable, Identifiable {
    public let name: String
    public let viewName: String
    public let directory: URL
    public let imageURL: URL?
    /// Isometric tilesets cannot draw the overmap; the game's own
    /// OVERMAP_TILES list excludes them.
    public let isIsometric: Bool

    public var id: String { name }
}

public enum TilesetCatalog {
    public static func bundledGfxDirectory(appBundle: URL) -> URL {
        appBundle.appendingPathComponent("Contents/Resources/gfx", isDirectory: true)
    }

    /// Tilesets from the game bundle and the user gfx directory, deduplicated
    /// by name (a user tileset shadows a bundled one, as in the game) and
    /// sorted by display name.
    public static func tilesets(appBundle: URL?, paths: LauncherPaths) -> [Tileset] {
        var byName: [String: Tileset] = [:]
        if let appBundle {
            for tileset in scan(bundledGfxDirectory(appBundle: appBundle)) {
                byName[tileset.name] = tileset
            }
        }
        for tileset in scan(paths.userGfxDir) {
            byName[tileset.name] = tileset
        }
        return byName.values.sorted {
            $0.viewName.localizedStandardCompare($1.viewName) == .orderedAscending
        }
    }

    static func scan(_ gfxDir: URL) -> [Tileset] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: gfxDir, includingPropertiesForKeys: nil)
        else { return [] }
        return entries.compactMap { parse(directory: $0) }
    }

    /// Reads one tileset directory; nil when there is no parseable
    /// tileset.txt with a NAME.
    public static func parse(directory: URL) -> Tileset? {
        let metaURL = directory.appendingPathComponent("tileset.txt")
        guard let text = try? String(contentsOf: metaURL, encoding: .utf8) else { return nil }
        let meta = PackMetadata.parse(text)
        guard let name = meta["NAME"] else { return nil }

        var imageURL: URL?
        if let sheet = meta["TILESET"] {
            let url = directory.appendingPathComponent(sheet)
            if FileManager.default.fileExists(atPath: url.path) { imageURL = url }
        }
        return Tileset(
            name: name,
            viewName: meta["VIEW"] ?? name,
            directory: directory,
            imageURL: imageURL,
            isIsometric: isIsometric(directory: directory, json: meta["JSON"])
        )
    }

    /// Copies a tileset folder into the persistent user gfx directory so it
    /// survives game updates. Validates before copying.
    @discardableResult
    public static func install(from source: URL, paths: LauncherPaths) throws -> Tileset {
        guard parse(directory: source) != nil else {
            throw GameConfigError.malformedFile("tileset.txt (not a tileset folder)")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.userGfxDir, withIntermediateDirectories: true)
        let destination = paths.userGfxDir.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
        return parse(directory: destination)!
    }

    /// The iso flag lives in tile_config.json's tile_info block, which by
    /// convention opens the file — so only a prefix is read rather than the
    /// whole multi-megabyte config.
    static func isIsometric(directory: URL, json: String?) -> Bool {
        let configURL = directory.appendingPathComponent(json ?? "tile_config.json")
        guard let handle = try? FileHandle(forReadingFrom: configURL),
              let data = try? handle.read(upToCount: 16 * 1024)
        else { return false }
        try? handle.close()
        let prefix = String(decoding: data, as: UTF8.self)
        guard let infoRange = prefix.range(of: "\"tile_info\""),
              let isoRange = prefix.range(of: "\"iso\"", range: infoRange.upperBound..<prefix.endIndex)
        else { return false }
        let after = prefix[isoRange.upperBound...].prefix(12)
        return after.contains("true")
    }
}
