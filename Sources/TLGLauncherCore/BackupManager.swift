import Foundation

public enum BackupError: Error, CustomStringConvertible {
    case gameRunning
    case backupMissing(String)

    public var description: String {
        switch self {
        case .gameRunning:
            return "Cataclysm: TLG is running. Close it before working with backups."
        case .backupMissing(let id):
            return "Backup \(id) is no longer on disk."
        }
    }
}

/// Timestamped, complete copies of the TLG user directory, kept under the
/// launcher's own Application Support tree. On APFS the copies are clone-based,
/// so they are fast and initially occupy little extra space.
public struct BackupManager: Sendable {
    static let metadataFilename = "metadata.json"
    static let payloadDirname = "UserData"

    public let paths: LauncherPaths
    private let detector: GameProcessDetecting
    private let now: @Sendable () -> Date

    public init(
        paths: LauncherPaths,
        detector: GameProcessDetecting,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.paths = paths
        self.detector = detector
        self.now = now
    }

    private func backupDir(id: String) -> URL {
        paths.backupsDir.appendingPathComponent(id, isDirectory: true)
    }

    public func payloadDir(for record: BackupRecord) -> URL {
        backupDir(id: record.id).appendingPathComponent(Self.payloadDirname, isDirectory: true)
    }

    @discardableResult
    public func createBackup(reason: String, gameVersionTag: String?) throws -> BackupRecord {
        let date = now()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var id = formatter.string(from: date)
        let fm = FileManager.default
        var suffix = 1
        while fm.fileExists(atPath: backupDir(id: id).path) {
            suffix += 1
            id = formatter.string(from: date) + "-\(suffix)"
        }

        let dir = backupDir(id: id)
        let staging = paths.backupsDir.appendingPathComponent(".staging-\(id)", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try fm.copyItem(at: paths.gameUserData, to: staging.appendingPathComponent(Self.payloadDirname))
            var record = BackupRecord(
                id: id, createdAt: date, reason: reason,
                gameVersionTag: gameVersionTag, sizeBytes: nil
            )
            record.sizeBytes = try? Self.directorySize(staging)
            let metadata = try JSONEncoder.launcher.encode(record)
            try metadata.write(to: staging.appendingPathComponent(Self.metadataFilename))
            try fm.moveItem(at: staging, to: dir)
            return record
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    public func listBackups() -> [BackupRecord] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: paths.backupsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(Self.metadataFilename)),
                  let record = try? JSONDecoder.launcher.decode(BackupRecord.self, from: data)
            else { return nil }
            return record
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Replaces the TLG user directory with the backup's copy. The current
    /// user directory is itself backed up first, so a restore is reversible.
    public func restore(_ record: BackupRecord) throws {
        guard !detector.isGameRunning() else { throw BackupError.gameRunning }
        let fm = FileManager.default
        let payload = payloadDir(for: record)
        guard fm.fileExists(atPath: payload.path) else {
            throw BackupError.backupMissing(record.id)
        }
        if fm.fileExists(atPath: paths.gameUserData.path) {
            try createBackup(reason: "Safety copy before restoring \(record.id)", gameVersionTag: nil)
            try fm.removeItem(at: paths.gameUserData)
        }
        try fm.copyItem(at: payload, to: paths.gameUserData)
    }

    public func delete(_ record: BackupRecord) throws {
        try FileManager.default.removeItem(at: backupDir(id: record.id))
    }

    /// Removes the oldest automatic pre-update backups beyond `keepLast`.
    /// Manual backups (any other reason) are never auto-pruned.
    public func pruneAutomaticBackups(keepLast: Int) throws {
        let automatic = listBackups()
            .filter { $0.reason.hasPrefix("Before updating") }
            .sorted { $0.createdAt > $1.createdAt }
        for record in automatic.dropFirst(max(0, keepLast)) {
            try delete(record)
        }
    }

    public static func directorySize(_ dir: URL) throws -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
            for case let file as URL in enumerator {
                let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
