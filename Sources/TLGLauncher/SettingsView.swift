import SwiftUI
import TLGLauncherCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var retainedVersions = 1
    @State private var retainedAutoBackups = 8

    var body: some View {
        Form {
            Section("Updates") {
                LabeledContent("Check for updates") {
                    Text("On every launch")
                }
                Text("Updates are never installed while the game is running, and each one takes a fresh backup of your user data first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                Stepper(value: $retainedVersions, in: 0...10) {
                    LabeledContent("Extra game versions to keep", value: "\(retainedVersions)")
                }
                Text("The active and previous versions are always kept for rollback; this controls how many older ones survive beyond those. Each version is roughly 600 MB unpacked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper(value: $retainedAutoBackups, in: 1...50) {
                    LabeledContent("Automatic pre-update backups to keep", value: "\(retainedAutoBackups)")
                }
                Text("Manual backups are never removed automatically. Backups are APFS clones, so they consume little space until the originals change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Locations") {
                LabeledContent("Launcher data") {
                    PathLink(url: model.paths.launcherSupport)
                }
                LabeledContent("Managed game versions") {
                    PathLink(url: model.paths.versionsDir)
                }
                LabeledContent("TLG user data") {
                    PathLink(url: model.paths.gameUserData)
                }
                Text("The launcher never installs game files into the TLG user directory, and updates never modify it (beyond the backups you ask for).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            retainedVersions = model.retainedVersions
            retainedAutoBackups = model.retainedAutoBackups
        }
        .onChange(of: retainedVersions) { _, new in model.retainedVersions = new }
        .onChange(of: retainedAutoBackups) { _, new in model.retainedAutoBackups = new }
    }
}

private struct PathLink: View {
    @Environment(AppModel.self) private var model
    let url: URL

    var body: some View {
        Button {
            model.open(url)
        } label: {
            Text(url.path)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.link)
    }
}
