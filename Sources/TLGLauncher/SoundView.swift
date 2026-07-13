import SwiftUI
import TLGLauncherCore

/// The sound entries in config/options.json. Volumes are 0–128 in the game.
private enum SoundOption: String, CaseIterable {
    case enabled = "SOUND_ENABLED"
    case soundpack = "SOUNDPACKS"
    case music = "MUSIC_VOLUME"
    case effects = "SOUND_EFFECT_VOLUME"
    case ambient = "AMBIENT_SOUND_VOLUME"
}

struct SoundView: View {
    @Environment(AppModel.self) private var model

    @State private var soundpacks: [Soundpack] = []
    @State private var enabled = true
    @State private var packName = ""
    @State private var volumes: [SoundOption: Double] = [:]

    private static let volumeRows: [(SoundOption, String)] = [
        (.music, "Music"),
        (.effects, "Sound effects"),
        (.ambient, "Ambient sounds"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Sound").font(.title2.bold())
                    Spacer()
                    StatusBadge(running: model.gameRunning)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable music and sound", isOn: enabledBinding)

                        Picker("Soundpack", selection: packBinding) {
                            ForEach(soundpacks) { pack in
                                Text(pack.viewName).tag(pack.name)
                            }
                            if !packName.isEmpty, !soundpacks.contains(where: { $0.name == packName }) {
                                Text("\(packName) (missing)").tag(packName)
                            }
                        }
                        .frame(maxWidth: 320)
                    }
                    .padding(6)
                }
                .disabled(model.gameRunning)

                GroupBox("Volume") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        ForEach(Self.volumeRows, id: \.0) { option, label in
                            GridRow {
                                Text(label).foregroundStyle(.secondary)
                                    .gridColumnAlignment(.leading)
                                Slider(value: volumeBinding(option), in: 0...128, step: 1) { editing in
                                    // Write once per adjustment, not per tick.
                                    if !editing { writeVolume(option) }
                                }
                                .frame(minWidth: 220)
                                Text("\(Int(volumes[option] ?? 100))")
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                    .padding(6)
                }
                .disabled(model.gameRunning || !enabled)

                HStack {
                    Button("Install Soundpack Folder…") { pickSoundpackFolder() }
                        .disabled(model.gameRunning)
                    Spacer()
                    Button("Open Sound Folder") { model.open(model.paths.userSoundDir) }
                        .buttonStyle(.link)
                }

                Text("Changes are written straight to options.json in the TLG configuration folder (backed up first); the game reads them at startup, and switching soundpack requires a restart. Installed soundpacks go to the persistent user sound folder, so they survive game updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { load() }
    }

    // MARK: Bindings (each write goes straight to options.json)

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { enabled = $0; write([SoundOption.enabled.rawValue: $0 ? "true" : "false"]) }
        )
    }

    private var packBinding: Binding<String> {
        Binding(
            get: { packName },
            set: { packName = $0; write([SoundOption.soundpack.rawValue: $0]) }
        )
    }

    private func volumeBinding(_ option: SoundOption) -> Binding<Double> {
        Binding(
            get: { volumes[option] ?? 100 },
            set: { volumes[option] = $0.rounded() }
        )
    }

    private func writeVolume(_ option: SoundOption) {
        write([option.rawValue: String(Int(volumes[option] ?? 100))])
    }

    // MARK: Actions

    private func load() {
        soundpacks = SoundpackCatalog.soundpacks(
            appBundle: model.store.activeAppBundle(), paths: model.paths
        )
        enabled = ((try? model.optionsStore.value(SoundOption.enabled.rawValue)) ?? nil) != "false"
        packName = ((try? model.optionsStore.value(SoundOption.soundpack.rawValue)) ?? nil)
            ?? soundpacks.first?.name ?? ""
        for (option, _) in Self.volumeRows {
            let raw = ((try? model.optionsStore.value(option.rawValue)) ?? nil) ?? "100"
            volumes[option] = Double(raw) ?? 100
        }
    }

    private func write(_ values: [String: String]) {
        do {
            try model.optionsStore.setValues(values)
        } catch {
            model.alertMessage = String(describing: error)
            load()   // roll the UI back to what is actually on disk
        }
    }

    private func pickSoundpackFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a soundpack folder (containing soundpack.txt)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let installed = try SoundpackCatalog.install(from: url, paths: model.paths)
                load()
                packBinding.wrappedValue = installed.name
            } catch {
                model.alertMessage = String(describing: error)
            }
        }
    }
}
