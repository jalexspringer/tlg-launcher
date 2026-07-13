import SwiftUI
import TLGLauncherCore

struct ReleasesView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingInstall: GameRelease?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Release history").font(.title2.bold())
                Spacer()
                StatusBadge(running: model.gameRunning)
                Button("Refresh") {
                    Task { await model.checkForUpdates() }
                }
                .disabled(model.isBusy)
            }
            .padding()

            if model.installableReleases.isEmpty {
                ContentUnavailableView(
                    model.checkFailed == nil ? "No releases loaded yet" : "Could not reach GitHub",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(model.checkFailed ?? "Use Refresh to fetch the release list.")
                )
            } else {
                List(model.installableReleases) { release in
                    ReleaseRow(release: release, pendingInstall: $pendingInstall)
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Install \(pendingInstall?.shortLabel ?? "")?",
            isPresented: Binding(
                get: { pendingInstall != nil },
                set: { if !$0 { pendingInstall = nil } }
            )
        ) {
            Button("Back Up and Install") {
                if let release = pendingInstall {
                    Task { await model.install(release) }
                }
                pendingInstall = nil
            }
        } message: {
            Text("Your TLG user data is backed up first, and the download (~200 MB) is verified against GitHub's published checksum. The previous version is kept for rollback.")
        }
    }
}

private struct ReleaseRow: View {
    @Environment(AppModel.self) private var model
    let release: GameRelease
    @Binding var pendingInstall: GameRelease?

    private var isActive: Bool { model.launcherState.activeTag == release.tagName }
    private var isInstalled: Bool {
        model.installedVersions.contains { $0.tag == release.tagName }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(release.shortLabel).font(.body.monospaced())
                    if isActive {
                        Text("Active")
                            .font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.green.opacity(0.2), in: Capsule())
                    } else if isInstalled {
                        Text("Installed")
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.secondary.opacity(0.2), in: Capsule())
                    }
                    if release.prerelease {
                        Text("Pre-release")
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.orange.opacity(0.2), in: Capsule())
                    }
                }
                HStack(spacing: 12) {
                    Text(release.publishedAt, format: .dateTime.day().month().year().hour().minute())
                    if let asset = AssetSelection.macTilesAsset(in: release) {
                        Text(ByteCountFormatter.file.string(fromByteCount: asset.size))
                        Text(asset.digest == nil ? "no checksum" : "SHA-256 published")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let url = release.htmlURL {
                Link("Notes", destination: url).font(.callout)
            }
            Button(isActive ? "Reinstall" : "Install") {
                pendingInstall = release
            }
            .disabled(model.isBusy || model.gameRunning)
        }
        .padding(.vertical, 4)
    }
}
