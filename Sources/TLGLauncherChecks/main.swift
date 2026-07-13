import Foundation
import TLGLauncherCore

// MARK: Fixtures

let releaseFixtureJSON = """
[
  {
    "tag_name": "cataclysm-tlg-1.0-2026-07-13-1202",
    "name": "Cataclysm-TLG 2026-07-13-1202",
    "draft": false,
    "prerelease": false,
    "published_at": "2026-07-13T12:02:55Z",
    "html_url": "https://github.com/Cataclysm-TLG/Cataclysm-TLG/releases/tag/x",
    "body": "changes",
    "assets": [
      {
        "name": "ctlg-linux-tiles-x64-2026-07-13-1202.tar.gz",
        "size": 100,
        "browser_download_url": "https://example.invalid/linux.tar.gz",
        "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      },
      {
        "name": "ctlg-osx-curses-universal-2026-07-13-1202.dmg",
        "size": 56010045,
        "browser_download_url": "https://example.invalid/curses.dmg",
        "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      },
      {
        "name": "ctlg-osx-tiles-universal-2026-07-13-1202.dmg",
        "size": 207119194,
        "browser_download_url": "https://example.invalid/tiles.dmg",
        "digest": "sha256:dd04273b4d2cb790110dfa8e8689f84a88a49dafda35e54d9d4d1cc0be2ae250"
      }
    ]
  },
  {
    "tag_name": "cataclysm-tlg-1.0-2026-07-13-0552",
    "name": null,
    "draft": false,
    "prerelease": false,
    "published_at": "2026-07-13T05:52:49Z",
    "html_url": null,
    "body": null,
    "assets": [
      {
        "name": "ctlg-windows-tiles-x64-2026-07-13-0552.zip",
        "size": 100,
        "browser_download_url": "https://example.invalid/win.zip"
      }
    ]
  }
]
"""

let optionsFixture = """
[
  {"info": "Default character name.", "default": "Default: ", "name": "DEF_CHAR_NAME", "value": "Maude"},
  {"info": "Set the font width.", "default": "Default: 8", "name": "FONT_WIDTH", "value": "10", "custom_unknown_field": [1, 2]},
  {"info": "If true, enable auto pickup.", "default": "Default: False", "name": "AUTO_PICKUP", "value": "true"},
  {"info": "Set the font height.", "default": "Default: 16", "name": "FONT_HEIGHT", "value": "20"}
]
"""

// MARK: Checks

let checks: [Check] = [

    // Release parsing and asset selection ------------------------------------

    Check("release JSON parses tags, dates, digests and optional fields") {
        let releases = try GitHubReleaseClient.parseReleases(Data(releaseFixtureJSON.utf8))
        try expectEqual(releases.count, 2)
        try expectEqual(releases[0].tagName, "cataclysm-tlg-1.0-2026-07-13-1202")
        try expect(releases[0].publishedAt > releases[1].publishedAt, "dates should decode as ISO 8601")
        try expectEqual(
            releases[0].assets[2].digest,
            "sha256:dd04273b4d2cb790110dfa8e8689f84a88a49dafda35e54d9d4d1cc0be2ae250"
        )
        try expectEqual(releases[1].assets[0].digest, nil)
        try expectEqual(releases[1].name, nil)
    },

    Check("asset selection picks the macOS tiles DMG and skips curses/other platforms") {
        let releases = try GitHubReleaseClient.parseReleases(Data(releaseFixtureJSON.utf8))
        let asset = AssetSelection.macTilesAsset(in: releases[0])
        try expectEqual(asset?.name, "ctlg-osx-tiles-universal-2026-07-13-1202.dmg")
        try expectEqual(AssetSelection.macTilesAsset(in: releases[1])?.name, nil)
    },

    Check("latest installable release is chosen by publication time, not list order") {
        let old = makeRelease(tag: "old", published: Date(timeIntervalSince1970: 1),
                              assets: [makeTilesAsset(tag: "old", digest: nil)])
        let new = makeRelease(tag: "new", published: Date(timeIntervalSince1970: 2),
                              assets: [makeTilesAsset(tag: "new", digest: nil)])
        let noMac = makeRelease(tag: "nomac", published: Date(timeIntervalSince1970: 3), assets: [])
        try expectEqual(AssetSelection.latestInstallable(from: [old, noMac, new])?.tagName, "new")
        try expectEqual(AssetSelection.installable(from: [old, noMac, new]).map(\.tagName), ["new", "old"])
    },

    // Digest verification -----------------------------------------------------

    Check("digest verification accepts matching sha256 and rejects mismatch") {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello tlg".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let good = try SHA256Verifier.hexDigest(of: file)
        try SHA256Verifier.verify(file: file, digest: "sha256:" + good)
        try SHA256Verifier.verify(file: file, digest: good.uppercased())
        try expectThrows({
            try SHA256Verifier.verify(file: file, digest: "sha256:" + String(repeating: "0", count: 64))
        }, DigestError.self)
        try expectThrows({
            try SHA256Verifier.verify(file: file, digest: "sha256:nonsense")
        }, DigestError.self)
    },

    // Transactional install ---------------------------------------------------

    Check("install: happy path activates atomically and preserves user data untouched") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }

        // Existing user data that must survive byte-for-byte.
        try write("save data", to: paths.savesDir.appendingPathComponent("world1/save.sav"))
        try write("{}", to: paths.fontsJSON)
        let userDataBefore = try snapshot(of: paths.gameUserData)

        let mounted = paths.launcherSupport.appendingPathComponent("fake-mount")
        try makeFakeMountedImage(at: mounted)
        let payload = Data("fake dmg bytes".utf8)
        let mounter = FakeMounter(mountPoint: mounted)
        let installer = UpdateInstaller(
            paths: paths,
            downloader: FakeDownloader(payload: payload, error: nil),
            mounter: mounter,
            detector: FakeDetector(running: false),
            backups: BackupManager(paths: paths, detector: FakeDetector(running: false))
        )
        let tag = "tlg-check-1"
        let release = makeRelease(tag: tag, assets: [
            ReleaseAsset(name: "ctlg-osx-tiles-universal-check.dmg", size: Int64(payload.count),
                         browserDownloadURL: URL(string: "https://example.invalid/a.dmg")!,
                         digest: "sha256:" + sha256Hex(of: payload)),
        ])
        let installed = try await installer.install(release: release) { _ in }
        try expectEqual(installed.tag, tag)

        let store = VersionStore(paths: paths)
        try expectEqual(store.loadState().activeTag, tag)
        let bundle = store.appBundle(forTag: tag)
        try expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Info.plist").path),
                   "activated bundle should exist")
        try expectEqual(mounter.detached.get(), 1)

        // Staging cleaned; user data byte-identical; a pre-update backup exists.
        let stagingLeft = try FileManager.default.contentsOfDirectory(atPath: paths.stagingDir.path)
        try expectEqual(stagingLeft, [])
        try expectEqual(try snapshot(of: paths.gameUserData), userDataBefore)
        let backups = BackupManager(paths: paths, detector: FakeDetector(running: false)).listBackups()
        try expectEqual(backups.count, 1)
        try expect(backups[0].reason.contains(tag), "backup reason should name the release")
    },

    Check("install: validation failure rolls everything back and detaches the image") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        try write("save data", to: paths.savesDir.appendingPathComponent("world1/save.sav"))

        let mounted = paths.launcherSupport.appendingPathComponent("fake-mount")
        try makeFakeMountedImage(at: mounted, valid: false)   // binary not executable
        let mounter = FakeMounter(mountPoint: mounted)
        let installer = UpdateInstaller(
            paths: paths,
            downloader: FakeDownloader(payload: Data("x".utf8), error: nil),
            mounter: mounter,
            detector: FakeDetector(running: false),
            backups: BackupManager(paths: paths, detector: FakeDetector(running: false))
        )
        let release = makeRelease(tag: "bad", assets: [makeTilesAsset(tag: "bad", digest: nil)])
        do {
            try await installer.install(release: release) { _ in }
            try expect(false, "install should have thrown")
        } catch is UpdateError {}

        let store = VersionStore(paths: paths)
        try expectEqual(store.loadState().activeTag, nil)
        try expectEqual(store.installedVersions().count, 0)
        try expectEqual(try FileManager.default.contentsOfDirectory(atPath: paths.stagingDir.path), [])
        try expectEqual(mounter.detached.get(), 1)
    },

    Check("install: digest mismatch aborts before mounting and deletes the download") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let mounted = paths.launcherSupport.appendingPathComponent("fake-mount")
        try makeFakeMountedImage(at: mounted)
        let installer = UpdateInstaller(
            paths: paths,
            downloader: FakeDownloader(payload: Data("corrupted".utf8), error: nil),
            mounter: FakeMounter(mountPoint: mounted),
            detector: FakeDetector(running: false),
            backups: BackupManager(paths: paths, detector: FakeDetector(running: false))
        )
        let release = makeRelease(tag: "t", assets: [
            makeTilesAsset(tag: "t", digest: "sha256:" + String(repeating: "0", count: 64)),
        ])
        do {
            try await installer.install(release: release) { _ in }
            try expect(false, "install should have thrown")
        } catch is DigestError {}
        let downloads = try FileManager.default.contentsOfDirectory(atPath: paths.downloadsDir.path)
        try expectEqual(downloads, [])
    },

    Check("install: refused while the game is running") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let installer = UpdateInstaller(
            paths: paths,
            downloader: FakeDownloader(payload: Data(), error: nil),
            mounter: FakeMounter(mountPoint: paths.launcherSupport),
            detector: FakeDetector(running: true),
            backups: BackupManager(paths: paths, detector: FakeDetector(running: true))
        )
        let release = makeRelease(tag: "t", assets: [makeTilesAsset(tag: "t", digest: nil)])
        do {
            try await installer.install(release: release) { _ in }
            try expect(false, "install should have thrown")
        } catch UpdateError.gameRunning {}
    },

    Check("invariant: launcher refuses to operate with its directories inside the TLG user directory") {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("tlg-inv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let userData = base.appendingPathComponent("Cataclysm-TLG")
        let paths = LauncherPaths(
            launcherSupport: userData.appendingPathComponent("TLG Launcher"),  // deliberately wrong
            gameUserData: userData
        )
        try paths.ensureLauncherDirectories()
        let installer = UpdateInstaller(
            paths: paths,
            downloader: FakeDownloader(payload: Data(), error: nil),
            mounter: FakeMounter(mountPoint: base),
            detector: FakeDetector(running: false),
            backups: BackupManager(paths: paths, detector: FakeDetector(running: false))
        )
        let release = makeRelease(tag: "t", assets: [makeTilesAsset(tag: "t", digest: nil)])
        do {
            try await installer.install(release: release) { _ in }
            try expect(false, "install should have thrown")
        } catch is LauncherPaths.PathViolation {}
    },

    // Versions: rollback and retention ---------------------------------------

    Check("rollback swaps active and previous; missing version refuses") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let store = VersionStore(paths: paths)
        for tag in ["v1", "v2"] {
            let dir = paths.versionDir(forTag: tag)
            try makeFakeMountedImage(at: dir)
            let meta = InstalledVersion(tag: tag, installedAt: Date(), publishedAt: nil, assetName: nil, digest: nil)
            try JSONEncoder.launcher.encode(meta).write(to: dir.appendingPathComponent(VersionStore.metadataFilename))
        }
        try store.saveState(LauncherState(activeTag: "v2", previousTag: "v1"))
        let rolledTo = try store.rollback()
        try expectEqual(rolledTo, "v1")
        try expectEqual(store.loadState(), LauncherState(activeTag: "v1", previousTag: "v2"))

        try store.saveState(LauncherState(activeTag: "v2", previousTag: "gone"))
        try expectThrows({ _ = try store.rollback() }, VersionError.self)
    },

    Check("pruning keeps active and previous versions") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let store = VersionStore(paths: paths)
        for (index, tag) in ["v1", "v2", "v3", "v4"].enumerated() {
            let dir = paths.versionDir(forTag: tag)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let meta = InstalledVersion(
                tag: tag, installedAt: Date(timeIntervalSince1970: Double(index)),
                publishedAt: nil, assetName: nil, digest: nil
            )
            try JSONEncoder.launcher.encode(meta).write(to: dir.appendingPathComponent(VersionStore.metadataFilename))
        }
        try store.saveState(LauncherState(activeTag: "v4", previousTag: "v1"))
        try store.prune(keep: 0)
        let remaining = Set(store.installedVersions().map(\.tag))
        try expectEqual(remaining, ["v4", "v1"])
    },

    // Backups -----------------------------------------------------------------

    Check("backup: create, list metadata, restore round-trip") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        try write("original save", to: paths.savesDir.appendingPathComponent("world/save.sav"))
        let manager = BackupManager(paths: paths, detector: FakeDetector(running: false))

        let record = try manager.createBackup(reason: "Manual backup", gameVersionTag: "v1")
        try expectEqual(manager.listBackups().map(\.id), [record.id])
        try expectEqual(manager.listBackups()[0].gameVersionTag, "v1")
        try expect((record.sizeBytes ?? 0) > 0, "backup size should be recorded")

        // Damage the live data, then restore.
        try write("corrupted", to: paths.savesDir.appendingPathComponent("world/save.sav"))
        try manager.restore(record)
        let restored = try String(contentsOf: paths.savesDir.appendingPathComponent("world/save.sav"), encoding: .utf8)
        try expectEqual(restored, "original save")
        // The pre-restore safety copy is itself listed.
        try expectEqual(manager.listBackups().count, 2)
    },

    Check("backup: restore refused while the game is running") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        try write("x", to: paths.savesDir.appendingPathComponent("s.sav"))
        let calm = BackupManager(paths: paths, detector: FakeDetector(running: false))
        let record = try calm.createBackup(reason: "Manual backup", gameVersionTag: nil)
        let busy = BackupManager(paths: paths, detector: FakeDetector(running: true))
        try expectThrows({ try busy.restore(record) }, BackupError.self)
    },

    Check("backup: automatic pruning spares manual backups") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        try write("x", to: paths.savesDir.appendingPathComponent("s.sav"))
        let tick = Locked(Date(timeIntervalSince1970: 0))
        let manager = BackupManager(paths: paths, detector: FakeDetector(running: false)) {
            let next = tick.get().addingTimeInterval(1)
            tick.set(next)
            return next
        }
        try manager.createBackup(reason: "Before updating to v1", gameVersionTag: nil)
        try manager.createBackup(reason: "Before updating to v2", gameVersionTag: nil)
        try manager.createBackup(reason: "Manual backup", gameVersionTag: nil)
        try manager.pruneAutomaticBackups(keepLast: 1)
        let reasons = manager.listBackups().map(\.reason).sorted()
        try expectEqual(reasons, ["Before updating to v2", "Manual backup"])
    },

    // Fonts and options -------------------------------------------------------

    Check("fonts.json: unknown keys survive, string typefaces normalise to lists") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        try write("""
        {"typeface": "data/font/Terminus.ttf",
         "map_typeface": ["data/font/Terminus.ttf", "data/font/unifont.ttf"],
         "overmap_typeface": ["data/font/Terminus.ttf"],
         "future_key": {"nested": true}}
        """, to: paths.fontsJSON)
        let store = FontConfigStore(paths: paths, detector: FakeDetector(running: false))
        var config = try store.loadFonts()
        try expectEqual(config.typeface, ["data/font/Terminus.ttf"])

        config.typeface = ["MyFont.ttf", "data/font/unifont.ttf"]
        try store.saveFonts(config)

        let round = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.fontsJSON)) as! [String: Any]
        try expectEqual((round["future_key"] as? [String: Any])?["nested"] as? Bool, true)
        try expectEqual(round["typeface"] as? [String], ["MyFont.ttf", "data/font/unifont.ttf"])
        try expectEqual(round["map_typeface"] as? [String], ["data/font/Terminus.ttf", "data/font/unifont.ttf"])
        // And a backup of the original was taken.
        let backups = try FileManager.default.contentsOfDirectory(atPath: paths.configBackupsDir.path)
        try expectEqual(backups.count, 1)
    },

    Check("options.json: updates values in place, preserves other entries, unknown fields and order") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        try write(optionsFixture, to: paths.optionsJSON)
        let store = FontConfigStore(paths: paths, detector: FakeDetector(running: false))
        try store.setOptions([.fontWidth: "12", .fontSize: "18"])   // fontSize absent, so appended

        let entries = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.optionsJSON)) as! [[String: Any]]
        try expectEqual(entries.map { $0["name"] as! String },
                        ["DEF_CHAR_NAME", "FONT_WIDTH", "AUTO_PICKUP", "FONT_HEIGHT", "FONT_SIZE"])
        let fontWidth = entries[1]
        try expectEqual(fontWidth["value"] as? String, "12")
        try expectEqual(fontWidth["info"] as? String, "Set the font width.")
        try expectEqual((fontWidth["custom_unknown_field"] as? [Int]), [1, 2])
        try expectEqual(entries[0]["value"] as? String, "Maude")
        try expectEqual(entries[4]["value"] as? String, "18")
        try expectEqual(try store.optionValue(.fontWidth), "12")
    },

    Check("options.json: writes refused while the game is running") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        try write(optionsFixture, to: paths.optionsJSON)
        let store = FontConfigStore(paths: paths, detector: FakeDetector(running: true))
        try expectThrows({ try store.setOptions([.fontWidth: "12"]) }, FontConfigError.self)
        try expectThrows({ try store.saveFonts(.tlgDefault) }, FontConfigError.self)
    },

    Check("font import: deduplicates identical files, suffixes name collisions, rejects odd types") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("Terminus.ttf")
        try Data("font A".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let first = try FontCatalog.importFont(from: source, paths: paths)
        try expectEqual(first.configReference, "Terminus.ttf")
        // Identical re-import: same file, no duplicate.
        let again = try FontCatalog.importFont(from: source, paths: paths)
        try expectEqual(again.url, first.url)
        // Same name, different content: suffixed.
        try Data("font B".utf8).write(to: source)
        let conflicted = try FontCatalog.importFont(from: source, paths: paths)
        try expectEqual(conflicted.configReference, "Terminus-2.ttf")
        try expectEqual(FontCatalog.importedFonts(paths: paths).count, 2)

        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        try expectThrows({ try FontCatalog.importFont(from: bad, paths: paths) }, FontFileError.self)
    },

    // Colour schemes ----------------------------------------------------------

    Check("colour themes: colordef parses, unknown keys ignored, missing colours default") {
        let colors = try ColorThemeCatalog.parseColordef(Data("""
        [{"type": "colordef", "BLACK": [1, 2, 3], "RED": [200, 0, 0], "FUTURE_COLOR": [9, 9, 9]}]
        """.utf8))
        try expectEqual(colors[.black], RGB(1, 2, 3))
        try expectEqual(colors[.red], RGB(200, 0, 0))
        // Colours the file omits fall back to the TLG default palette.
        try expectEqual(colors[.white], RGB(255, 255, 255))
        try expectEqual(colors.count, GameColor.allCases.count)
        try expectThrows({ _ = try ColorThemeCatalog.parseColordef(Data("[]".utf8)) },
                         ColorThemeError.self)
        try expectThrows({ _ = try ColorThemeCatalog.parseColordef(Data("""
        [{"type": "colordef", "RED": [1, 2]}]
        """.utf8)) }, ColorThemeError.self)
    },

    Check("colour themes: display names derive from mixed-separator filenames") {
        try expectEqual(ColorThemeCatalog.displayName(forFile: "base_colors-blood_moon.json"), "Blood Moon")
        try expectEqual(ColorThemeCatalog.displayName(forFile: "base_colors_gruvbox-light.json"), "Gruvbox Light")
        try expectEqual(ColorThemeCatalog.displayName(forFile: "base_colors-12bit-rainbow.json"), "12bit Rainbow")
    },

    Check("colour themes: bundled catalogue lists parseable themes sorted, skips malformed") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let bundle = paths.launcherSupport.appendingPathComponent("Cataclysm.app")
        let dir = ColorThemeCatalog.themesDirectory(appBundle: bundle)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try write(#"[{"type": "colordef", "BLACK": [5, 5, 5]}]"#,
                  to: dir.appendingPathComponent("base_colors-vintage.json"))
        try write(#"[{"type": "colordef", "BLACK": [9, 9, 9]}]"#,
                  to: dir.appendingPathComponent("base_colors_amber.json"))
        try write("not json", to: dir.appendingPathComponent("base_colors-broken.json"))
        try write("readme", to: dir.appendingPathComponent("notes.txt"))

        let themes = ColorThemeCatalog.bundledThemes(appBundle: bundle)
        try expectEqual(themes.map(\.name), ["Amber", "Vintage"])
        try expectEqual(themes[1].colors[.black], RGB(5, 5, 5))
    },

    Check("colour themes: apply writes base_colors.json, backs up, round-trips; refused while running") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let store = ColorThemeStore(paths: paths, detector: FakeDetector(running: false))
        // Absent file reads as the TLG default palette.
        try expectEqual(try store.currentColors(), ColorTheme.tlgDefault.colors)

        var colors = ColorTheme.tlgDefault.colors
        colors[.black] = RGB(56, 59, 65)
        try store.apply(ColorTheme(name: "Dark", colors: colors))
        try expectEqual(try store.currentColors(), colors)
        // First write had nothing to back up; the second must.
        try store.apply(.tlgDefault)
        try expectEqual(try store.currentColors(), ColorTheme.tlgDefault.colors)
        let backups = try FileManager.default.contentsOfDirectory(atPath: paths.configBackupsDir.path)
        try expectEqual(backups.count, 1)

        let busy = ColorThemeStore(paths: paths, detector: FakeDetector(running: true))
        try expectThrows({ try busy.apply(.tlgDefault) }, ColorThemeError.self)
    },

    // Game launch plan --------------------------------------------------------

    Check("launch plan: runs the tiles binary from Resources with --userdir and trailing slash") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let mounted = paths.launcherSupport.appendingPathComponent("fake-mount")
        try makeFakeMountedImage(at: mounted)
        let bundle = mounted.appendingPathComponent("Cataclysm.app")
        let plan = try GameLauncher.plan(appBundle: bundle, userDataDir: paths.gameUserData)
        try expectEqual(plan.arguments, ["--userdir", paths.gameUserData.path + "/"])
        try expectEqual(plan.workingDirectory.lastPathComponent, "Resources")
        try expectEqual(plan.executable.lastPathComponent, "cataclysm-tlg-tiles")
        try expectEqual(plan.environment["DYLD_LIBRARY_PATH"], ".")
        try expectEqual(plan.environment["DYLD_FRAMEWORK_PATH"], ".")
    },

    // Guide server ------------------------------------------------------------

    Check("guide server: serves files, SPA-falls back on routes, 404s missing assets") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guide-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write("<html>guide</html>", to: root.appendingPathComponent("index.html"))
        try write("console.log(1)", to: root.appendingPathComponent("assets/app.js"))

        let server = GuideServer(root: root)
        try expectEqual(server.resolve(requestTarget: "/")?.lastPathComponent, "index.html")
        try expectEqual(server.resolve(requestTarget: "/assets/app.js")?.lastPathComponent, "app.js")
        try expectEqual(server.resolve(requestTarget: "/assets/app.js?v=1")?.lastPathComponent, "app.js")
        // Client-side routes fall back to the shell, missing real assets do not.
        try expectEqual(server.resolve(requestTarget: "/item/flashlight")?.lastPathComponent, "index.html")
        try expectEqual(server.resolve(requestTarget: "/assets/missing.js")?.path, nil)
    },

    Check("guide server: path traversal rejected in raw and percent-encoded forms") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guide-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write("<html>guide</html>", to: root.appendingPathComponent("index.html"))

        let server = GuideServer(root: root)
        for target in [
            "/../etc/passwd",
            "/../../../../etc/passwd",
            "/%2e%2e/%2e%2e/etc/passwd",
            "/assets/%2e%2e/%2e%2e/secret.txt",
            "/..%2f..%2fetc/passwd",
            "/%00/index.html",
        ] {
            if let resolved = server.resolve(requestTarget: target) {
                try expect(resolved.path.hasPrefix(root.path + "/"),
                           "\(target) escaped the root: \(resolved.path)")
                try expect(!resolved.path.contains("passwd") && !resolved.path.contains("secret"),
                           "\(target) resolved to \(resolved.path)")
            }
        }
    },

    Check("guide server: live loopback round-trip with SPA fallback and 404") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guide-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write("<html>guide shell</html>", to: root.appendingPathComponent("index.html"))
        try write("body{}", to: root.appendingPathComponent("assets/style.css"))

        let server = GuideServer(root: root)
        let port = try server.start()
        defer { server.stop() }
        try expect(port > 0, "server should pick an ephemeral port")

        func get(_ path: String) async throws -> (Int, String, String?) {
            let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            let http = response as! HTTPURLResponse
            return (http.statusCode, String(decoding: data, as: UTF8.self),
                    http.value(forHTTPHeaderField: "Content-Type"))
        }

        let (rootStatus, rootBody, rootType) = try await get("/")
        try expectEqual(rootStatus, 200)
        try expectEqual(rootBody, "<html>guide shell</html>")
        try expectEqual(rootType, "text/html; charset=utf-8")

        let (cssStatus, cssBody, cssType) = try await get("/assets/style.css")
        try expectEqual(cssStatus, 200)
        try expectEqual(cssBody, "body{}")
        try expectEqual(cssType, "text/css")

        let (routeStatus, routeBody, _) = try await get("/monster/zombie")
        try expectEqual(routeStatus, 200)
        try expectEqual(routeBody, "<html>guide shell</html>")

        let (missingStatus, _, _) = try await get("/assets/missing.js")
        try expectEqual(missingStatus, 404)

        let (traversalStatus, traversalBody, _) = try await get("/%2e%2e/%2e%2e/etc/passwd")
        try expect(traversalStatus == 404, "traversal must 404, got \(traversalStatus)")
        try expect(!traversalBody.contains("root:"), "traversal must not leak files")
    },
]

func snapshot(of dir: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
        return result
    }
    for case let file as URL in enumerator {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey])
        if values.isRegularFile == true {
            let relative = file.path.replacingOccurrences(of: dir.path, with: "")
            result[relative] = try SHA256Verifier.hexDigest(of: file)
        }
    }
    return result
}

await runChecks(checks + guideDataChecks)
