import Foundation

/// Selects the macOS graphical build from a release's assets.
/// TLG publishes several releases a day; selection is by publication time and
/// asset compatibility, never by date arithmetic.
public enum AssetSelection {
    /// Matches e.g. "ctlg-osx-tiles-universal-2026-07-13-1202.dmg".
    public static func macTilesAsset(in release: GameRelease) -> ReleaseAsset? {
        release.assets.first { asset in
            asset.name.hasPrefix("ctlg-osx-tiles-universal-") && asset.name.hasSuffix(".dmg")
        }
    }

    /// Newest non-draft release that actually carries a macOS tiles DMG.
    public static func latestInstallable(from releases: [GameRelease]) -> GameRelease? {
        releases
            .filter { !$0.draft && macTilesAsset(in: $0) != nil }
            .max(by: { $0.publishedAt < $1.publishedAt })
    }

    /// All installable releases, newest first, for the release history list.
    public static func installable(from releases: [GameRelease]) -> [GameRelease] {
        releases
            .filter { !$0.draft && macTilesAsset(in: $0) != nil }
            .sorted(by: { $0.publishedAt > $1.publishedAt })
    }
}
