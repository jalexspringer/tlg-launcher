import Foundation

/// One soundpack: a sound/<dir> with a soundpack.txt describing it. `name` is
/// the value the game stores in the SOUNDPACKS option; `viewName` is what its
/// in-game picker displays.
public struct Soundpack: Sendable, Equatable, Identifiable {
    public let name: String
    public let viewName: String
    public let directory: URL

    public var id: String { name }
}

public enum SoundpackCatalog {
    public static func bundledSoundDirectory(appBundle: URL) -> URL {
        appBundle.appendingPathComponent("Contents/Resources/data/sound", isDirectory: true)
    }

    /// Soundpacks from the game bundle and the user sound directory,
    /// deduplicated by name (user packs shadow bundled ones) and sorted by
    /// display name.
    public static func soundpacks(appBundle: URL?, paths: LauncherPaths) -> [Soundpack] {
        var byName: [String: Soundpack] = [:]
        if let appBundle {
            for pack in scan(bundledSoundDirectory(appBundle: appBundle)) {
                byName[pack.name] = pack
            }
        }
        for pack in scan(paths.userSoundDir) {
            byName[pack.name] = pack
        }
        return byName.values.sorted {
            $0.viewName.localizedStandardCompare($1.viewName) == .orderedAscending
        }
    }

    static func scan(_ soundDir: URL) -> [Soundpack] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: soundDir, includingPropertiesForKeys: nil)
        else { return [] }
        return entries.compactMap { parse(directory: $0) }
    }

    /// Reads one soundpack directory; nil when there is no parseable
    /// soundpack.txt with a NAME.
    public static func parse(directory: URL) -> Soundpack? {
        let metaURL = directory.appendingPathComponent("soundpack.txt")
        guard let text = try? String(contentsOf: metaURL, encoding: .utf8) else { return nil }
        let meta = PackMetadata.parse(text)
        guard let name = meta["NAME"] else { return nil }
        return Soundpack(name: name, viewName: meta["VIEW"] ?? name, directory: directory)
    }

    /// Copies a soundpack folder into the persistent user sound directory so
    /// it survives game updates. Validates before copying.
    @discardableResult
    public static func install(from source: URL, paths: LauncherPaths) throws -> Soundpack {
        guard parse(directory: source) != nil else {
            throw GameConfigError.malformedFile("soundpack.txt (not a soundpack folder)")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.userSoundDir, withIntermediateDirectories: true)
        let destination = paths.userSoundDir.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
        return parse(directory: destination)!
    }
}
