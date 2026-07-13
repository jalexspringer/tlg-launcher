import SwiftUI
import TLGLauncherCore

struct HomeView: View {
    @Environment(AppModel.self) private var model

    @State private var interfaceFontLabel = "—"
    @State private var colorSchemeLabel = "—"
    @State private var tilesetLabel = "—"
    @State private var soundpackLabel = "—"

    private static let artwork: NSImage? = Bundle.module
        .url(forResource: "tlg-artwork", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    private var currentLabel: String {
        model.launcherState.activeTag?.replacingOccurrences(of: "cataclysm-tlg-", with: "")
            ?? "None installed"
    }

    private var latestLabel: String {
        model.latestRelease?.shortLabel ?? (model.checkFailed == nil ? "Checking…" : "Unavailable")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            mainColumn
            artworkColumn
                .frame(width: 240)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { refreshSettingsSummary() }
        .confirmationDialog(
            "Roll back the application to the previous version?",
            isPresented: $rollbackRequested
        ) {
            Button("Roll Back", role: .destructive) { model.rollback() }
        } message: {
            Text("Only the game application changes — your user data stays as it is. Saves opened by a newer game version may not load with an older one; restore a matching backup from the Backups tab if needed.")
        }
    }

    private var mainColumn: some View {
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
                    GridRow {
                        Text("Interface font").foregroundStyle(.secondary)
                        Text(interfaceFontLabel)
                    }
                    GridRow {
                        Text("Colour scheme").foregroundStyle(.secondary)
                        Text(colorSchemeLabel)
                    }
                    GridRow {
                        Text("Tileset").foregroundStyle(.secondary)
                        Text(tilesetLabel)
                    }
                    GridRow {
                        Text("Soundpack").foregroundStyle(.secondary)
                        Text(soundpackLabel)
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var artworkColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let artwork = Self.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Cataclysm: The Last Generation artwork")
            }
            VStack(alignment: .leading, spacing: 4) {
                Link("cataclysmtlg.com",
                     destination: URL(string: "https://cataclysmtlg.com/")!)
                Link("Cataclysm-TLG on GitHub",
                     destination: URL(string: "https://github.com/Cataclysm-TLG/Cataclysm-TLG")!)
                // A single Text so the credit wraps as prose when space is tight.
                Text(.init("Created by [worm girl](https://www.youtube.com/@worm-girl) and contributors"))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    /// Reads the font and colour choices the other panes manage, so the Play
    /// pane reflects what the game will actually start with.
    private func refreshSettingsSummary() {
        let fonts = (try? model.fontStore.loadFonts()) ?? .tlgDefault
        let size = (try? model.fontStore.optionValue(.fontSize)) ?? FontOption.fontSize.tlgDefault
        let primary = fonts.typeface.first.map {
            (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
        } ?? "Default"
        interfaceFontLabel = "\(primary), \(size) pt"

        let current = (try? model.colorStore.currentColors()) ?? ColorTheme.tlgDefault.colors
        if current == ColorTheme.tlgDefault.colors {
            colorSchemeLabel = ColorTheme.tlgDefault.name
        } else if let bundle = model.store.activeAppBundle(),
                  let match = ColorThemeCatalog.bundledThemes(appBundle: bundle)
                      .first(where: { $0.colors == current }) {
            colorSchemeLabel = match.name
        } else {
            colorSchemeLabel = "Custom"
        }

        let option = { (name: String) in ((try? model.optionsStore.value(name)) ?? nil) }
        if option("USE_TILES") == "false" {
            tilesetLabel = "Off (ASCII)"
        } else {
            let tilesets = TilesetCatalog.tilesets(
                appBundle: model.store.activeAppBundle(), paths: model.paths
            )
            let name = option("TILES")
            tilesetLabel = tilesets.first { $0.name == name }?.viewName ?? name ?? "Default"
        }
        if option("SOUND_ENABLED") == "false" {
            soundpackLabel = "Sound off"
        } else {
            let packs = SoundpackCatalog.soundpacks(
                appBundle: model.store.activeAppBundle(), paths: model.paths
            )
            let name = option("SOUNDPACKS")
            soundpackLabel = packs.first { $0.name == name }?.viewName ?? name ?? "Default"
        }
    }

    @State private var rollbackRequested = false
}
