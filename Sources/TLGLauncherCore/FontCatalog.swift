import Foundation
import CoreText

public struct FontFile: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable {
        case bundled       // inside the active game version's data/font
        case imported      // in the persistent user font directory
        case system        // installed on this Mac
    }

    public let displayName: String
    public let url: URL
    public let source: Source

    public var id: String { source.rawValue + ":" + url.path }

    /// The value to put in fonts.json. TLG searches the user font directory
    /// before the game's bundled fonts, so imported fonts are referenced by
    /// bare filename; bundled fonts keep the game-relative path.
    public var configReference: String {
        switch source {
        case .imported: return url.lastPathComponent
        case .bundled: return "data/font/" + url.lastPathComponent
        case .system: return url.path
        }
    }
}

public enum FontFileError: Error, CustomStringConvertible {
    case unsupportedType(String)
    public var description: String {
        switch self {
        case .unsupportedType(let ext):
            return "Unsupported font type “.\(ext)”. Use .ttf, .otf or .ttc files."
        }
    }
}

public enum FontCatalog {
    public static let supportedExtensions: Set<String> = ["ttf", "otf", "ttc"]

    static func fontFiles(in directory: URL, source: FontFile.Source) -> [FontFile] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { FontFile(displayName: $0.deletingPathExtension().lastPathComponent, url: $0, source: source) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Fonts shipped inside a game version's app bundle.
    public static func bundledFonts(appBundle: URL) -> [FontFile] {
        fontFiles(
            in: appBundle.appendingPathComponent("Contents/Resources/data/font", isDirectory: true),
            source: .bundled
        )
    }

    /// Fonts previously imported into the persistent user font directory.
    public static func importedFonts(paths: LauncherPaths) -> [FontFile] {
        fontFiles(in: paths.userFontDir, source: .imported)
    }

    /// Copies a font into the persistent user font directory so it survives
    /// game updates. Identical re-imports are deduplicated; a name collision
    /// with different content gets a numbered filename. Returns the FontFile
    /// whose `configReference` should go into fonts.json.
    @discardableResult
    public static func importFont(from source: URL, paths: LauncherPaths) throws -> FontFile {
        let ext = source.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw FontFileError.unsupportedType(source.pathExtension)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.userFontDir, withIntermediateDirectories: true)

        let base = source.deletingPathExtension().lastPathComponent
        var candidate = paths.userFontDir.appendingPathComponent("\(base).\(ext)")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            if let existing = try? SHA256Verifier.hexDigest(of: candidate),
               let incoming = try? SHA256Verifier.hexDigest(of: source),
               existing == incoming {
                return FontFile(displayName: candidate.deletingPathExtension().lastPathComponent,
                                url: candidate, source: .imported)
            }
            counter += 1
            candidate = paths.userFontDir.appendingPathComponent("\(base)-\(counter).\(ext)")
        }
        try fm.copyItem(at: source, to: candidate)
        return FontFile(displayName: candidate.deletingPathExtension().lastPathComponent,
                        url: candidate, source: .imported)
    }

    // MARK: System fonts (via CoreText)

    /// Font files installed on this Mac, deduplicated by file URL.
    public static func systemFonts() -> [FontFile] {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        guard let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] else {
            return []
        }
        var seen = Set<URL>()
        var fonts: [FontFile] = []
        for descriptor in descriptors {
            guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL,
                  supportedExtensions.contains(url.pathExtension.lowercased()),
                  !seen.contains(url.standardizedFileURL)
            else { continue }
            seen.insert(url.standardizedFileURL)
            let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
            fonts.append(FontFile(
                displayName: family ?? url.deletingPathExtension().lastPathComponent,
                url: url,
                source: .system
            ))
        }
        return fonts.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// PostScript names contained in a font file, for previewing with
    /// `Font.custom`. Registers the file for this process if needed.
    public static func previewFontNames(for url: URL) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return descriptors.compactMap {
            CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String
        }
    }
}
