import Foundation

public enum UpdatePhase: Sendable, Equatable {
    case backingUp
    case downloading(received: Int64, total: Int64?)
    case verifying
    case mounting
    case copying
    case validating
    case activating
    case cleaningUp

    public var label: String {
        switch self {
        case .backingUp: return "Backing up user data…"
        case .downloading: return "Downloading…"
        case .verifying: return "Verifying download…"
        case .mounting: return "Opening disk image…"
        case .copying: return "Copying game files…"
        case .validating: return "Validating…"
        case .activating: return "Activating…"
        case .cleaningUp: return "Cleaning up…"
        }
    }
}

public enum UpdateError: Error, CustomStringConvertible {
    case gameRunning
    case noMacAsset(String)
    case noAppInImage
    case invalidAppBundle(String)

    public var description: String {
        switch self {
        case .gameRunning:
            return "Cataclysm: TLG is running. Close the game before updating."
        case .noMacAsset(let tag):
            return "Release \(tag) has no macOS tiles build."
        case .noAppInImage:
            return "No application bundle was found in the disk image."
        case .invalidAppBundle(let reason):
            return "The copied application failed validation: \(reason)"
        }
    }
}

/// Orchestrates one update as a transaction:
///
///   refuse if running → back up user data → download → verify digest →
///   mount read-only → copy to staging → validate → atomically activate →
///   keep previous for rollback → prune → clean up.
///
/// Any failure leaves the currently active version untouched and removes the
/// staging directory; the DMG is always detached. Nothing is ever written
/// inside the TLG user directory (enforced, not assumed).
public struct UpdateInstaller: Sendable {
    public let paths: LauncherPaths
    public let store: VersionStore
    private let downloader: Downloading
    private let mounter: DMGMounting
    private let detector: GameProcessDetecting
    private let backups: BackupManager
    private let runner: ProcessRunning
    private let now: @Sendable () -> Date

    /// Installed versions kept besides active + previous.
    public var retainedVersions: Int = 1
    /// Automatic pre-update backups kept.
    public var retainedAutoBackups: Int = 8

    public init(
        paths: LauncherPaths,
        downloader: Downloading,
        mounter: DMGMounting,
        detector: GameProcessDetecting,
        backups: BackupManager,
        runner: ProcessRunning = SystemProcessRunner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.paths = paths
        self.store = VersionStore(paths: paths)
        self.downloader = downloader
        self.mounter = mounter
        self.detector = detector
        self.backups = backups
        self.runner = runner
        self.now = now
    }

    @discardableResult
    public func install(
        release: GameRelease,
        onPhase: @escaping @Sendable (UpdatePhase) -> Void
    ) async throws -> InstalledVersion {
        guard let asset = AssetSelection.macTilesAsset(in: release) else {
            throw UpdateError.noMacAsset(release.tagName)
        }
        guard !detector.isGameRunning() else {
            throw UpdateError.gameRunning
        }

        // The invariant, checked before anything is written.
        try paths.ensureLauncherDirectories()
        for target in [paths.versionsDir, paths.stagingDir, paths.downloadsDir, paths.backupsDir] {
            try paths.assertOutsideGameUserData(target)
        }

        // 1. Backup — only when there is user data to protect.
        if FileManager.default.fileExists(atPath: paths.gameUserData.path) {
            onPhase(.backingUp)
            try backups.createBackup(
                reason: "Before updating to \(release.tagName)",
                gameVersionTag: store.loadState().activeTag
            )
        }

        // 2. Download (reusing a previous download only if its digest still verifies).
        let dmg = paths.downloadsDir.appendingPathComponent(asset.name)
        let fm = FileManager.default
        var needsDownload = true
        if fm.fileExists(atPath: dmg.path), let digest = asset.digest,
           (try? SHA256Verifier.verify(file: dmg, digest: digest)) != nil {
            needsDownload = false
        }
        if needsDownload {
            try? fm.removeItem(at: dmg)
            let partial = paths.downloadsDir.appendingPathComponent(asset.name + ".partial")
            onPhase(.downloading(received: 0, total: asset.size))
            do {
                try await downloader.download(from: asset.browserDownloadURL, to: partial) { received, total in
                    onPhase(.downloading(received: received, total: total ?? asset.size))
                }
                _ = try fm.replaceItemAt(dmg, withItemAt: partial)
            } catch {
                try? fm.removeItem(at: partial)
                throw error
            }
        }

        // 3. Verify digest when GitHub provides one.
        if let digest = asset.digest {
            onPhase(.verifying)
            do {
                try SHA256Verifier.verify(file: dmg, digest: digest)
            } catch {
                try? fm.removeItem(at: dmg)
                throw error
            }
        }

        // 4–7. Mount, copy to staging, validate. Detach always happens.
        onPhase(.mounting)
        let mountPoint = try mounter.mount(dmgAt: dmg)
        let staging = paths.stagingDir.appendingPathComponent("install-\(UUID().uuidString)", isDirectory: true)
        let staged: URL
        do {
            onPhase(.copying)
            let appInImage = try Self.findAppBundle(in: mountPoint)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            staged = staging.appendingPathComponent(VersionStore.appName, isDirectory: true)
            try fm.copyItem(at: appInImage, to: staged)

            onPhase(.validating)
            try Self.validateAppBundle(staged)
            // Downloaded-DMG quarantine would make Gatekeeper refuse the unsigned
            // game binary; the user asked for this install explicitly.
            _ = try? runner.run("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", staged.path])

            let metadata = InstalledVersion(
                tag: release.tagName,
                installedAt: now(),
                publishedAt: release.publishedAt,
                assetName: asset.name,
                digest: asset.digest
            )
            try JSONEncoder.launcher.encode(metadata)
                .write(to: staging.appendingPathComponent(VersionStore.metadataFilename))

            try? mounter.detach(mountPoint: mountPoint)

            // 8. Activate atomically: stage → versions/<tag> is a single rename.
            onPhase(.activating)
            let destination = paths.versionDir(forTag: release.tagName)
            try paths.assertOutsideGameUserData(destination)
            if fm.fileExists(atPath: destination.path) {
                let graveyard = paths.stagingDir.appendingPathComponent("replaced-\(UUID().uuidString)")
                try fm.moveItem(at: destination, to: graveyard)
                do {
                    try fm.moveItem(at: staging, to: destination)
                    try? fm.removeItem(at: graveyard)
                } catch {
                    // Put the old copy back so a reinstall failure changes nothing.
                    try? fm.moveItem(at: graveyard, to: destination)
                    throw error
                }
            } else {
                try fm.moveItem(at: staging, to: destination)
            }

            var state = store.loadState()
            if state.activeTag != release.tagName {
                state.previousTag = state.activeTag
                state.activeTag = release.tagName
            }
            try store.saveState(state)

            // 9. Retention: active + previous always survive.
            onPhase(.cleaningUp)
            try? store.prune(keep: retainedVersions)
            try? backups.pruneAutomaticBackups(keepLast: retainedAutoBackups)
            try? fm.removeItem(at: dmg)

            return metadata
        } catch {
            try? fm.removeItem(at: staging)
            try? mounter.detach(mountPoint: mountPoint)
            throw error
        }
    }

    /// First real .app in the image root (ignores the /Applications symlink
    /// DMGs conventionally carry).
    static func findAppBundle(in mountPoint: URL) throws -> URL {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
        )
        for entry in entries where entry.pathExtension == "app" {
            let isSymlink = (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
            if !isSymlink { return entry }
        }
        throw UpdateError.noAppInImage
    }

    /// The copied bundle must look like a launchable TLG build.
    static func validateAppBundle(_ bundle: URL) throws {
        let fm = FileManager.default
        let infoPlist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let plistData = fm.contents(atPath: infoPlist.path),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let executableName = plist["CFBundleExecutable"] as? String
        else {
            throw UpdateError.invalidAppBundle("missing or unreadable Info.plist")
        }
        let executable = bundle.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard fm.isExecutableFile(atPath: executable.path) else {
            throw UpdateError.invalidAppBundle("\(executableName) is missing or not executable")
        }
        // TLG's wrapper script runs Resources/cataclysm-tlg-tiles; require it
        // when present in name, but tolerate future layout changes by only
        // failing when the known binary exists and is broken.
        let tilesBinary = bundle.appendingPathComponent("Contents/Resources/cataclysm-tlg-tiles")
        if fm.fileExists(atPath: tilesBinary.path), !fm.isExecutableFile(atPath: tilesBinary.path) {
            throw UpdateError.invalidAppBundle("cataclysm-tlg-tiles is not executable")
        }
    }
}
