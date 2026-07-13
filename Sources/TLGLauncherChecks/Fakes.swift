import Foundation
import TLGLauncherCore

/// Writes canned bytes instead of touching the network.
struct FakeDownloader: Downloading {
    var payload: Data
    var error: Error?

    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws {
        if let error { throw error }
        try payload.write(to: destination)
        progress(Int64(payload.count), Int64(payload.count))
    }
}

/// "Mounts" by returning a prepared directory; records detach calls.
final class FakeMounter: DMGMounting, @unchecked Sendable {
    let mountPoint: URL
    let detached = Locked(0)

    init(mountPoint: URL) {
        self.mountPoint = mountPoint
    }

    func mount(dmgAt url: URL) throws -> URL { mountPoint }
    func detach(mountPoint: URL) throws { detached.set(detached.get() + 1) }
}

struct FakeDetector: GameProcessDetecting {
    var running = false
    func isGameRunning() -> Bool { running }
}

final class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
}

// MARK: Fixture builders

/// A directory shaped like a mounted TLG DMG: Cataclysm.app with the real
/// layout (Cataclysm.sh wrapper + cataclysm-tlg-tiles binary) plus the
/// /Applications symlink DMGs conventionally contain.
func makeFakeMountedImage(at root: URL, valid: Bool = true) throws {
    let fm = FileManager.default
    let app = root.appendingPathComponent("Cataclysm.app", isDirectory: true)
    try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    try fm.createDirectory(at: app.appendingPathComponent("Contents/Resources/data/font"), withIntermediateDirectories: true)

    let plist: [String: Any] = [
        "CFBundleExecutable": "Cataclysm.sh",
        "CFBundleIdentifier": "com.cataclysmdda.en.cataclysm",
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: app.appendingPathComponent("Contents/Info.plist"))

    let script = app.appendingPathComponent("Contents/MacOS/Cataclysm.sh")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
    if valid {
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    let binary = app.appendingPathComponent("Contents/Resources/cataclysm-tlg-tiles")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
    try fm.setAttributes([.posixPermissions: valid ? 0o755 : 0o644], ofItemAtPath: binary.path)

    try Data("fake font".utf8).write(
        to: app.appendingPathComponent("Contents/Resources/data/font/Terminus.ttf"))

    try? fm.createSymbolicLink(
        at: root.appendingPathComponent("Applications"),
        withDestinationURL: URL(fileURLWithPath: "/Applications")
    )
}

func makeRelease(tag: String, published: Date = Date(timeIntervalSince1970: 1_800_000_000),
                 assets: [ReleaseAsset]) -> GameRelease {
    GameRelease(
        tagName: tag, name: tag, prerelease: false, draft: false,
        publishedAt: published, htmlURL: nil, body: nil, assets: assets
    )
}

func makeTilesAsset(tag: String, digest: String?) -> ReleaseAsset {
    ReleaseAsset(
        name: "ctlg-osx-tiles-universal-\(tag).dmg",
        size: 1234,
        browserDownloadURL: URL(string: "https://example.invalid/\(tag).dmg")!,
        digest: digest
    )
}

func sha256Hex(of data: Data) -> String {
    // Convenience for building matching digests in checks.
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! data.write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    return try! SHA256Verifier.hexDigest(of: tmp)
}
