import Foundation

public struct ReleaseAsset: Codable, Sendable, Hashable {
    public let name: String
    public let size: Int64
    public let browserDownloadURL: URL
    /// GitHub asset digest, e.g. "sha256:dd0427…". Absent on older assets.
    public let digest: String?

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case browserDownloadURL = "browser_download_url"
    }

    public init(name: String, size: Int64, browserDownloadURL: URL, digest: String?) {
        self.name = name
        self.size = size
        self.browserDownloadURL = browserDownloadURL
        self.digest = digest
    }
}

public struct GameRelease: Codable, Sendable, Hashable, Identifiable {
    public let tagName: String
    public let name: String?
    public let prerelease: Bool
    public let draft: Bool
    public let publishedAt: Date
    public let htmlURL: URL?
    public let body: String?
    public let assets: [ReleaseAsset]

    public var id: String { tagName }

    enum CodingKeys: String, CodingKey {
        case name, prerelease, draft, assets, body
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }

    public init(tagName: String, name: String?, prerelease: Bool, draft: Bool,
                publishedAt: Date, htmlURL: URL?, body: String?, assets: [ReleaseAsset]) {
        self.tagName = tagName
        self.name = name
        self.prerelease = prerelease
        self.draft = draft
        self.publishedAt = publishedAt
        self.htmlURL = htmlURL
        self.body = body
        self.assets = assets
    }
}

/// Metadata written into each installed version directory.
public struct InstalledVersion: Codable, Sendable, Hashable, Identifiable {
    public let tag: String
    public let installedAt: Date
    public let publishedAt: Date?
    public let assetName: String?
    public let digest: String?

    public var id: String { tag }

    public init(tag: String, installedAt: Date, publishedAt: Date?, assetName: String?, digest: String?) {
        self.tag = tag
        self.installedAt = installedAt
        self.publishedAt = publishedAt
        self.assetName = assetName
        self.digest = digest
    }
}

/// Persistent launcher state (state.json).
public struct LauncherState: Codable, Sendable, Equatable {
    public var activeTag: String?
    public var previousTag: String?

    public init(activeTag: String? = nil, previousTag: String? = nil) {
        self.activeTag = activeTag
        self.previousTag = previousTag
    }
}

public struct BackupRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: String            // directory name, e.g. "2026-07-13-143005"
    public let createdAt: Date
    public let reason: String
    public let gameVersionTag: String?
    public var sizeBytes: Int64?

    public init(id: String, createdAt: Date, reason: String, gameVersionTag: String?, sizeBytes: Int64?) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        self.gameVersionTag = gameVersionTag
        self.sizeBytes = sizeBytes
    }
}
