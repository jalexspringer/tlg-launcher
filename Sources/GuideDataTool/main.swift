import Foundation
import TLGLauncherCore

// Usage: GuideDataTool <Cataclysm.app path> <tag> <output cache root>
// Writes <output>/data/<tag>/all.json and all_mods.json.

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data(
        "usage: GuideDataTool <app-bundle> <tag> <output-root>\n".utf8))
    exit(64)
}

let appBundle = URL(fileURLWithPath: arguments[1], isDirectory: true)
let tag = arguments[2]
let outputRoot = URL(fileURLWithPath: arguments[3], isDirectory: true)

// The generator writes under launcherSupport/guide-data; point that at the
// requested output. gameUserData is unused here but must be disjoint.
let paths = LauncherPaths(
    launcherSupport: outputRoot,
    gameUserData: outputRoot.appendingPathComponent("unused-user-data")
)
let generator = GuideDataGenerator(paths: paths)

do {
    let started = Date()
    try generator.generate(forTag: tag, appBundle: appBundle)
    let allJSON = generator.dataDir(forTag: tag).appendingPathComponent("all.json")
    let size = ((try? FileManager.default.attributesOfItem(atPath: allJSON.path))?[.size] as? Int64) ?? 0
    print("Generated \(allJSON.path)")
    print(String(format: "%.1f MB in %.1fs", Double(size) / 1_048_576, Date().timeIntervalSince(started)))
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
