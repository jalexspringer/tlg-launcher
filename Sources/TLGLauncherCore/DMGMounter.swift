import Foundation

public protocol DMGMounting: Sendable {
    /// Mounts read-only without opening a Finder window; returns the mount point.
    func mount(dmgAt url: URL) throws -> URL
    func detach(mountPoint: URL) throws
}

public enum DMGError: Error, CustomStringConvertible {
    case attachFailed(String)
    case noMountPoint
    case detachFailed(String)

    public var description: String {
        switch self {
        case .attachFailed(let msg): return "hdiutil attach failed: \(msg)"
        case .noMountPoint: return "hdiutil attached the image but reported no mount point."
        case .detachFailed(let msg): return "hdiutil detach failed: \(msg)"
        }
    }
}

public struct HDIUtilMounter: DMGMounting {
    private let runner: ProcessRunning

    public init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func mount(dmgAt url: URL) throws -> URL {
        let result = try runner.run("/usr/bin/hdiutil", arguments: [
            "attach", url.path, "-readonly", "-nobrowse", "-noautoopen", "-plist",
        ])
        guard result.status == 0 else {
            throw DMGError.attachFailed(result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard
            let plist = try? PropertyListSerialization.propertyList(from: result.stdout, format: nil),
            let dict = plist as? [String: Any],
            let entities = dict["system-entities"] as? [[String: Any]],
            let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw DMGError.noMountPoint
        }
        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    public func detach(mountPoint: URL) throws {
        var result = try runner.run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path])
        if result.status != 0 {
            // A lingering Spotlight/Finder handle is common; give it a moment, then force.
            Thread.sleep(forTimeInterval: 1.5)
            result = try runner.run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
        }
        guard result.status == 0 else {
            throw DMGError.detachFailed(result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
