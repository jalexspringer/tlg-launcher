import SwiftUI
import TLGLauncherCore

struct HomeView: View {
    @Environment(AppModel.self) private var model

    private var currentLabel: String {
        model.launcherState.activeTag?.replacingOccurrences(of: "cataclysm-tlg-", with: "")
            ?? "None installed"
    }

    private var latestLabel: String {
        model.latestRelease?.shortLabel ?? (model.checkFailed == nil ? "Checking…" : "Unavailable")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cataclysm: The Last Generation")
                    .font(.largeTitle.bold())
                StatusBadge(running: model.gameRunning)
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("Installed version").foregroundStyle(.secondary)
                        Text(currentLabel).monospaced()
                    }
                    GridRow {
                        Text("Latest available").foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(latestLabel).monospaced()
                            if model.updateAvailable {
                                Text("Update available")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.blue.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                    if let checked = model.lastChecked {
                        GridRow {
                            Text("Last checked").foregroundStyle(.secondary)
                            Text(checked, format: .dateTime.hour().minute().second())
                        }
                    }
                    if let failure = model.checkFailed {
                        GridRow {
                            Text("Update check failed").foregroundStyle(.secondary)
                            Text(failure).foregroundStyle(.red).lineLimit(2)
                        }
                    }
                }
                .padding(6)
            }

            HStack(spacing: 12) {
                Button {
                    model.play()
                } label: {
                    Label("Play", systemImage: "play.fill").frame(minWidth: 90)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(model.launcherState.activeTag == nil || model.isBusy)

                Button {
                    Task { await model.updateAndPlay() }
                } label: {
                    Label("Update and Play", systemImage: "arrow.down.circle")
                }
                .controlSize(.large)
                .disabled(model.isBusy || model.gameRunning)

                Button("Check for Updates") {
                    Task { await model.checkForUpdates() }
                }
                .controlSize(.large)
                .disabled(model.isBusy)

                if model.launcherState.previousTag != nil {
                    Button("Roll Back…") {
                        rollbackRequested = true
                    }
                    .controlSize(.large)
                    .disabled(model.isBusy || model.gameRunning)
                }
            }

            if let phase = model.phase {
                VStack(alignment: .leading, spacing: 6) {
                    Text(phase.label).font(.callout)
                    if case .downloading(let received, let total) = phase, let total, total > 0 {
                        ProgressView(value: Double(received), total: Double(total))
                        Text("\(ByteCountFormatter.file.string(fromByteCount: received)) of \(ByteCountFormatter.file.string(fromByteCount: total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: 420)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Folders").font(.headline)
                HStack(spacing: 10) {
                    Button("User Data") { model.open(model.paths.gameUserData) }
                    Button("Saves") { model.open(model.paths.savesDir) }
                    Button("Configuration") { model.open(model.paths.configDir) }
                    Button("Fonts") { model.open(model.paths.userFontDir) }
                }
                .buttonStyle(.link)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Roll back the application to the previous version?",
            isPresented: $rollbackRequested
        ) {
            Button("Roll Back", role: .destructive) { model.rollback() }
        } message: {
            Text("Only the game application changes — your user data stays as it is. Saves opened by a newer game version may not load with an older one; restore a matching backup from the Backups tab if needed.")
        }
    }

    @State private var rollbackRequested = false
}
