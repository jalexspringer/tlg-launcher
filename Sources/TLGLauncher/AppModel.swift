import SwiftUI
import Observation
import TLGLauncherCore

@MainActor
@Observable
final class AppModel {
    let paths: LauncherPaths
    let store: VersionStore
    let backups: BackupManager
    let fontStore: FontConfigStore
    private let detector = GameProcessDetector()
    private let client = GitHubReleaseClient()
    private var guideServer: GuideServer?

    // Release state
    var releases: [GameRelease] = []
    var lastChecked: Date?
    var checkFailed: String?

    // Install state
    var launcherState: LauncherState
    var installedVersions: [InstalledVersion] = []
    var phase: UpdatePhase?
    var isBusy = false

    // Data state
    var backupList: [BackupRecord] = []
    var gameRunning = false

    // Errors surfaced to the UI
    var alertMessage: String?

    // Settings
    var retainedVersions: Int {
        get { max(0, UserDefaults.standard.integer(forKey: "retainedVersions")) }
        set { UserDefaults.standard.set(newValue, forKey: "retainedVersions") }
    }
    var retainedAutoBackups: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "retainedAutoBackups")
            return stored == 0 ? 8 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: "retainedAutoBackups") }
    }

    init(paths: LauncherPaths = .standard()) {
        self.paths = paths
        self.store = VersionStore(paths: paths)
        self.backups = BackupManager(paths: paths, detector: detector)
        self.fontStore = FontConfigStore(paths: paths, detector: detector)
        self.launcherState = store.loadState()
        try? paths.ensureLauncherDirectories()
        reloadLocalState()
    }

    func reloadLocalState() {
        launcherState = store.loadState()
        installedVersions = store.installedVersions()
        backupList = backups.listBackups()
        refreshGameRunning()
    }

    func refreshGameRunning() {
        let detector = self.detector
        Task.detached {
            let running = detector.isGameRunning()
            await MainActor.run { self.gameRunning = running }
        }
    }

    // MARK: Releases

    var latestRelease: GameRelease? {
        AssetSelection.latestInstallable(from: releases)
    }

    var installableReleases: [GameRelease] {
        AssetSelection.installable(from: releases)
    }

    var updateAvailable: Bool {
        guard let latest = latestRelease else { return false }
        return latest.tagName != launcherState.activeTag
    }

    func checkForUpdates() async {
        checkFailed = nil
        do {
            releases = try await client.fetchReleases(count: 30)
            lastChecked = Date()
        } catch {
            checkFailed = String(describing: error)
        }
    }

    // MARK: Install / update / play

    private func makeInstaller() -> UpdateInstaller {
        var installer = UpdateInstaller(
            paths: paths,
            downloader: URLSessionDownloader(),
            mounter: HDIUtilMounter(),
            detector: detector,
            backups: backups
        )
        installer.retainedVersions = retainedVersions
        installer.retainedAutoBackups = retainedAutoBackups
        return installer
    }

    func install(_ release: GameRelease) async {
        guard !isBusy else { return }
        isBusy = true
        defer {
            isBusy = false
            phase = nil
            reloadLocalState()
        }
        do {
            try await makeInstaller().install(release: release) { phase in
                Task { @MainActor in self.phase = phase }
            }
        } catch {
            alertMessage = String(describing: error)
        }
    }

    func play() {
        refreshGameRunning()
        do {
            guard let bundle = store.activeAppBundle() else {
                throw LaunchError.noVersionInstalled
            }
            try GameLauncher.launch(appBundle: bundle, userDataDir: paths.gameUserData)
            gameRunning = true
        } catch {
            alertMessage = String(describing: error)
        }
    }

    func updateAndPlay() async {
        if updateAvailable, let latest = latestRelease {
            await install(latest)
            guard alertMessage == nil else { return }
        }
        play()
    }

    func rollback() {
        do {
            let tag = try store.rollback()
            reloadLocalState()
            alertMessage = "Rolled back to \(tag). Note: saves opened by a newer game version may not load with an older one — restore a matching backup if needed."
        } catch {
            alertMessage = String(describing: error)
        }
    }

    // MARK: Backups

    func createBackup() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false; reloadLocalState() }
        let backups = self.backups
        let tag = launcherState.activeTag
        do {
            try await Task.detached {
                try backups.createBackup(reason: "Manual backup", gameVersionTag: tag)
            }.value
        } catch {
            alertMessage = String(describing: error)
        }
    }

    func restore(_ record: BackupRecord) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false; reloadLocalState() }
        let backups = self.backups
        do {
            try await Task.detached { try backups.restore(record) }.value
        } catch {
            alertMessage = String(describing: error)
        }
    }

    func deleteBackup(_ record: BackupRecord) {
        do {
            try backups.delete(record)
            reloadLocalState()
        } catch {
            alertMessage = String(describing: error)
        }
    }

    // MARK: Folders

    func open(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    // MARK: Guide

    /// Root of the bundled guide dist: app resources when running from the
    /// bundle, the repo's GuideDist/ when running via `swift run`.
    static func guideRoot() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("GuideDist", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("GuideDist", isDirectory: true),
        ]
        return candidates
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }

    func guideBaseURL() -> URL? {
        if let server = guideServer, let base = server.baseURL {
            return base
        }
        guard let root = Self.guideRoot() else { return nil }
        let server = GuideServer(root: root)
        do {
            try server.start()
            guideServer = server
            return server.baseURL
        } catch {
            alertMessage = String(describing: error)
            return nil
        }
    }

    func stopGuideServer() {
        guideServer?.stop()
        guideServer = nil
    }
}

extension ByteCountFormatter {
    @MainActor static let file: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
