import Foundation

/// A newer launcher release on GitHub.
public struct LauncherUpdate: Sendable, Equatable {
    public let version: String
    public let url: URL

    public init(version: String, url: URL) {
        self.version = version
        self.url = url
    }
}

/// Checks this launcher's own GitHub releases for something newer than the
/// running build. Deliberately quiet: any failure (offline, rate-limited,
/// missing data) just means "no update banner".
public struct LauncherUpdateChecker: Sendable {
    public static let repository = "jalexspringer/tlg-launcher"
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    private let client: ReleaseFetching

    public init(client: ReleaseFetching = GitHubReleaseClient(repository: repository)) {
        self.client = client
    }

    public func check(currentVersion: String) async -> LauncherUpdate? {
        guard let releases = try? await client.fetchReleases(count: 10) else { return nil }
        guard let latest = releases.first(where: { !$0.draft && !$0.prerelease }) else { return nil }
        let version = Self.normalise(latest.tagName)
        guard Self.isNewer(version, than: currentVersion) else { return nil }
        return LauncherUpdate(version: version, url: latest.htmlURL ?? Self.releasesPage)
    }

    /// "v0.2.0" → "0.2.0"
    public static func normalise(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Numeric dot-component comparison; missing components read as 0 and
    /// non-numeric components as 0 (so a malformed tag never "wins").
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
