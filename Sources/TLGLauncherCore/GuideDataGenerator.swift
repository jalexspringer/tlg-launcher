import Foundation

public enum GuideDataError: Error, CustomStringConvertible {
    case missingGameData(URL)
    case unparsableObject(file: String, line: Int, underlying: Error)

    public var description: String {
        switch self {
        case .missingGameData(let url):
            return "No game data found at \(url.path)."
        case .unparsableObject(let file, let line, let underlying):
            return "Could not parse an object in \(file) near line \(line): \(underlying)"
        }
    }
}

/// Generates the Hitchhiker's Guide data files (all.json, all_mods.json,
/// builds.json) locally from an installed game version, in the same shape as
/// RenechCDDA/tlg-data's GitHub Action produces them from the source zipball.
/// The installed app carries the identical inputs — TLG's Makefile copies
/// data/json and data/mods wholesale into Contents/Resources.
///
/// Output layout under `cacheRoot` mirrors the remote repo, so the guide can
/// be pointed at either interchangeably:
///
///   guide-data/builds.json
///   guide-data/data/<tag>/all.json
///   guide-data/data/<tag>/all_mods.json
///   guide-data/data/latest/…          (copy of the active tag)
public struct GuideDataGenerator: Sendable {
    public let paths: LauncherPaths

    public init(paths: LauncherPaths) {
        self.paths = paths
    }

    public var cacheRoot: URL {
        paths.launcherSupport.appendingPathComponent("guide-data", isDirectory: true)
    }

    public var buildsIndex: URL {
        cacheRoot.appendingPathComponent("builds.json")
    }

    public func dataDir(forTag tag: String) -> URL {
        cacheRoot.appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent(tag, isDirectory: true)
    }

    public func hasData(forTag tag: String) -> Bool {
        FileManager.default.fileExists(atPath: dataDir(forTag: tag).appendingPathComponent("all.json").path)
    }

    /// True when a guide pointed at `cacheRoot` would find something to show.
    public func hasUsableIndex() -> Bool {
        FileManager.default.fileExists(atPath: buildsIndex.path)
            && FileManager.default.fileExists(
                atPath: cacheRoot.appendingPathComponent("data/latest/all.json").path)
    }

    // MARK: Generation

    /// Builds all.json and all_mods.json for one installed version.
    /// `release` enriches the embedded release object when available (the
    /// guide currently stores but never reads it; shape is kept regardless).
    public func generate(forTag tag: String, appBundle: URL, release: GameRelease? = nil) throws {
        let resources = appBundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        let jsonRoot = resources.appendingPathComponent("data/json", isDirectory: true)
        let modsRoot = resources.appendingPathComponent("data/mods", isDirectory: true)
        guard FileManager.default.fileExists(atPath: jsonRoot.path) else {
            throw GuideDataError.missingGameData(jsonRoot)
        }

        var data: [Any] = []
        for relative in try jsonFiles(under: jsonRoot, prefix: "data/json") {
            data.append(contentsOf: try objects(inFile: resources.appendingPathComponent(relative),
                                                taggedAs: relative))
        }

        // Mods: skip obsolete ones and strip MOD_INFO entries from data,
        // exactly as the upstream pipeline does.
        var modInfos: [String: Any] = [:]
        var modData: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: modsRoot.path) {
            let modDirs = (try? FileManager.default.contentsOfDirectory(
                at: modsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
            for modDir in modDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let modinfoFile = modDir.appendingPathComponent("modinfo.json")
                guard let raw = try? Data(contentsOf: modinfoFile),
                      let parsed = try? JSONSerialization.jsonObject(with: raw),
                      let info = Self.modInfoEntry(in: parsed),
                      let modId = info["id"] as? String,
                      (info["obsolete"] as? Bool) != true
                else { continue }

                var objectsInMod: [Any] = []
                let modPrefix = "data/mods/\(modDir.lastPathComponent)"
                for relative in try jsonFiles(under: modDir, prefix: modPrefix) {
                    for object in try objects(inFile: resources.appendingPathComponent(relative),
                                              taggedAs: relative) {
                        if (object as? [String: Any])?["type"] as? String == "MOD_INFO" { continue }
                        objectsInMod.append(object)
                    }
                }
                modInfos[modId] = info
                modData[modId] = ["info": info, "data": objectsInMod]
            }
        }

        let releaseObject: Any
        if let release, let encoded = try? JSONEncoder.launcher.encode(release),
           let dict = try? JSONSerialization.jsonObject(with: encoded) {
            releaseObject = dict
        } else {
            releaseObject = ["tag_name": tag]
        }

        let allJSON: [String: Any] = [
            "build_number": tag,
            "release": releaseObject,
            "data": data,
            "mods": modInfos,
        ]

        // Stage, then swap into place so readers never see a half-written set.
        let destination = dataDir(forTag: tag)
        let staging = cacheRoot.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try JSONSerialization.data(withJSONObject: allJSON)
                .write(to: staging.appendingPathComponent("all.json"))
            try JSONSerialization.data(withJSONObject: modData)
                .write(to: staging.appendingPathComponent("all_mods.json"))
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: staging, to: destination)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Rewrites builds.json from the versions that actually have generated
    /// data, newest first, and refreshes data/latest as a copy of the active
    /// tag (matching the remote repo's layout, which the guide's "latest"
    /// version key resolves to).
    public func rebuildIndex(installedVersions: [InstalledVersion], activeTag: String?) throws {
        let withData = installedVersions.filter { hasData(forTag: $0.tag) }
        let formatter = ISO8601DateFormatter()
        let builds: [[String: Any]] = withData
            .sorted { ($0.publishedAt ?? $0.installedAt) > ($1.publishedAt ?? $1.installedAt) }
            .map {
                [
                    "build_number": $0.tag,
                    "prerelease": false,
                    "created_at": formatter.string(from: $0.publishedAt ?? $0.installedAt),
                ]
            }
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: builds).atomicWrite(to: buildsIndex)

        let latest = cacheRoot.appendingPathComponent("data/latest", isDirectory: true)
        try? FileManager.default.removeItem(at: latest)
        if let activeTag, hasData(forTag: activeTag) {
            // APFS clone: cheap even for a large all.json.
            try FileManager.default.copyItem(at: dataDir(forTag: activeTag), to: latest)
        }
    }

    public func removeData(forTag tag: String) {
        try? FileManager.default.removeItem(at: dataDir(forTag: tag))
    }

    // MARK: Helpers

    /// Relative paths (prefix included) of all .json files under `root`,
    /// sorted for deterministic output.
    private func jsonFiles(under root: URL, prefix: String) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var results: [String] = []
        for case let file as URL in enumerator {
            guard file.pathExtension.lowercased() == "json",
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            let relativeTail = file.standardizedFileURL.path
                .replacingOccurrences(of: root.standardizedFileURL.path + "/", with: "")
            results.append(prefix + "/" + relativeTail)
        }
        return results.sorted()
    }

    /// Top-level objects of one file, each tagged with
    /// `__filename: "<relative>#L<start>-L<end>"`.
    private func objects(inFile file: URL, taggedAs relative: String) throws -> [Any] {
        let raw = try Data(contentsOf: file)
        return try JSONObjectScanner.topLevelObjects(in: raw).map { scanned in
            let parsed: Any
            do {
                parsed = try JSONSerialization.jsonObject(with: scanned.bytes)
            } catch {
                throw GuideDataError.unparsableObject(
                    file: relative, line: scanned.startLine, underlying: error)
            }
            guard var object = parsed as? [String: Any] else {
                return parsed
            }
            object["__filename"] = "\(relative)#L\(scanned.startLine)-L\(scanned.endLine)"
            return object
        }
    }

    /// modinfo.json is conventionally an array containing a MOD_INFO object.
    static func modInfoEntry(in parsed: Any) -> [String: Any]? {
        if let array = parsed as? [Any] {
            return array
                .compactMap { $0 as? [String: Any] }
                .first { $0["type"] as? String == "MOD_INFO" }
        }
        if let dict = parsed as? [String: Any], dict["type"] as? String == "MOD_INFO" {
            return dict
        }
        return nil
    }
}
