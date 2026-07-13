import Foundation
import TLGLauncherCore

let guideDataChecks: [Check] = [

    Check("scanner: splits top-level objects with exact line ranges, braces in strings ignored") {
        let source = """
        [
          {
            "type": "ARMOR",
            "id": "hat",
            "name": { "str": "ha{t}" },
            "note": "quote \\" and \\\\ escapes { }"
          },
          { "type": "TOOL", "id": "torch" }
        ]
        """
        let objects = JSONObjectScanner.topLevelObjects(in: Data(source.utf8))
        try expectEqual(objects.count, 2)
        try expectEqual(objects[0].startLine, 2)
        try expectEqual(objects[0].endLine, 7)
        try expectEqual(objects[1].startLine, 8)
        try expectEqual(objects[1].endLine, 8)
        let first = try JSONSerialization.jsonObject(with: objects[0].bytes) as? [String: Any]
        try expectEqual(first?["id"] as? String, "hat")
        try expectEqual((first?["name"] as? [String: Any])?["str"] as? String, "ha{t}")
        // Nested objects are part of the enclosing one, not separate results.
        let second = try JSONSerialization.jsonObject(with: objects[1].bytes) as? [String: Any]
        try expectEqual(second?["type"] as? String, "TOOL")
    },

    Check("generator: all.json shape, __filename tags, mod handling (obsolete + MOD_INFO stripped)") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let bundle = paths.launcherSupport.appendingPathComponent("Game.app")
        let resources = bundle.appendingPathComponent("Contents/Resources")

        try write("""
        [
          { "type": "TOOL", "id": "hammer" },
          { "type": "TOOL", "id": "saw" }
        ]
        """, to: resources.appendingPathComponent("data/json/items/tools.json"))
        try write("""
        { "type": "MONSTER", "id": "zombie" }
        """, to: resources.appendingPathComponent("data/json/monsters.json"))

        try write("""
        [ { "type": "MOD_INFO", "id": "goodmod", "name": "Good Mod" } ]
        """, to: resources.appendingPathComponent("data/mods/GoodMod/modinfo.json"))
        try write("""
        [ { "type": "TOOL", "id": "modtool" } ]
        """, to: resources.appendingPathComponent("data/mods/GoodMod/items.json"))
        try write("""
        [ { "type": "MOD_INFO", "id": "oldmod", "obsolete": true } ]
        """, to: resources.appendingPathComponent("data/mods/OldMod/modinfo.json"))

        let generator = GuideDataGenerator(paths: paths)
        try generator.generate(forTag: "test-tag", appBundle: bundle)

        let allJSON = try JSONSerialization.jsonObject(
            with: Data(contentsOf: generator.dataDir(forTag: "test-tag").appendingPathComponent("all.json"))
        ) as! [String: Any]
        try expectEqual(allJSON["build_number"] as? String, "test-tag")
        let data = allJSON["data"] as! [[String: Any]]
        try expectEqual(data.count, 3)
        let hammer = data.first { $0["id"] as? String == "hammer" }!
        try expectEqual(hammer["__filename"] as? String, "data/json/items/tools.json#L2-L2")
        let zombie = data.first { $0["id"] as? String == "zombie" }!
        try expectEqual(zombie["__filename"] as? String, "data/json/monsters.json#L1-L1")

        // Mods: obsolete one skipped entirely; MOD_INFO not in mod data.
        let mods = allJSON["mods"] as! [String: [String: Any]]
        try expectEqual(Array(mods.keys), ["goodmod"])
        try expectEqual(mods["goodmod"]?["name"] as? String, "Good Mod")
        let allMods = try JSONSerialization.jsonObject(
            with: Data(contentsOf: generator.dataDir(forTag: "test-tag").appendingPathComponent("all_mods.json"))
        ) as! [String: [String: Any]]
        let goodmodData = allMods["goodmod"]?["data"] as! [[String: Any]]
        try expectEqual(goodmodData.count, 1)
        try expectEqual(goodmodData[0]["id"] as? String, "modtool")
        try expect(!goodmodData.contains { $0["type"] as? String == "MOD_INFO" },
                   "MOD_INFO must be stripped from mod data")
    },

    Check("generator: builds.json lists only generated versions, latest mirrors active tag") {
        let (paths, cleanup) = try temporaryPaths()
        defer { cleanup() }
        let bundle = paths.launcherSupport.appendingPathComponent("Game.app")
        try write("[ { \"type\": \"TOOL\", \"id\": \"x\" } ]",
                  to: bundle.appendingPathComponent("Contents/Resources/data/json/a.json"))

        let generator = GuideDataGenerator(paths: paths)
        try generator.generate(forTag: "v2", appBundle: bundle)

        let versions = [
            InstalledVersion(tag: "v2", installedAt: Date(timeIntervalSince1970: 2),
                             publishedAt: Date(timeIntervalSince1970: 2), assetName: nil, digest: nil),
            InstalledVersion(tag: "v1-no-data", installedAt: Date(timeIntervalSince1970: 1),
                             publishedAt: nil, assetName: nil, digest: nil),
        ]
        try generator.rebuildIndex(installedVersions: versions, activeTag: "v2")

        let builds = try JSONSerialization.jsonObject(
            with: Data(contentsOf: generator.buildsIndex)
        ) as! [[String: Any]]
        try expectEqual(builds.map { $0["build_number"] as! String }, ["v2"])
        try expect(generator.hasUsableIndex(), "index should be usable")

        let latest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: generator.cacheRoot.appendingPathComponent("data/latest/all.json"))
        ) as! [String: Any]
        try expectEqual(latest["build_number"] as? String, "v2")
    },

    Check("guide server: mounted local-data prefix serves exact files, no SPA fallback, traversal-safe") {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mount-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("dist")
        let dataRoot = base.appendingPathComponent("guide-data")
        try write("<html>shell</html>", to: root.appendingPathComponent("index.html"))
        try write("[{\"build_number\":\"t\"}]", to: dataRoot.appendingPathComponent("builds.json"))
        try write("{\"build_number\":\"t\"}", to: dataRoot.appendingPathComponent("data/t/all.json"))

        let server = GuideServer(root: root, mounts: ["local-data": dataRoot])
        try expectEqual(server.resolve(requestTarget: "/local-data/builds.json")?.lastPathComponent, "builds.json")
        try expectEqual(server.resolve(requestTarget: "/local-data/data/t/all.json")?.path,
                        dataRoot.appendingPathComponent("data/t/all.json").standardizedFileURL.path)
        // Missing files in the mount are 404s, never the SPA shell.
        try expectEqual(server.resolve(requestTarget: "/local-data/data/missing/all.json")?.path, nil)
        try expectEqual(server.resolve(requestTarget: "/local-data/nonexistent")?.path, nil)
        // Traversal out of the mount (towards the dist root or beyond) fails.
        try expectEqual(server.resolve(requestTarget: "/local-data/%2e%2e/dist/index.html")?.path, nil)
        try expectEqual(server.resolve(requestTarget: "/local-data/../../etc/passwd")?.path, nil)
        // The plain root still SPA-falls back.
        try expectEqual(server.resolve(requestTarget: "/monster/zed")?.lastPathComponent, "index.html")
    },
]
