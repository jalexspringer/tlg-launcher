import SwiftUI
import UniformTypeIdentifiers
import TLGLauncherCore

enum TilesetTarget: String, CaseIterable, Identifiable {
    case map = "Map"
    case overmap = "Overmap"
    case distant = "Distant Zoom"

    var id: String { rawValue }

    /// The options.json entry naming the chosen tileset.
    var option: String {
        switch self {
        case .map: return "TILES"
        case .overmap: return "OVERMAP_TILES"
        case .distant: return "DISTANT_TILES"
        }
    }

    /// The options.json toggle enabling this kind of tile rendering.
    var useOption: String {
        switch self {
        case .map: return "USE_TILES"
        case .overmap: return "USE_OVERMAP_TILES"
        case .distant: return "USE_DISTANT_TILES"
        }
    }

    var toggleLabel: String {
        switch self {
        case .map: return "Draw the game map with tiles (off = pure ASCII)"
        case .overmap: return "Draw the overmap with tiles"
        case .distant: return "Use a separate tileset when zoomed far out"
        }
    }
}

struct TilesetsView: View {
    @Environment(AppModel.self) private var model

    @State private var tilesets: [Tileset] = []
    @State private var target: TilesetTarget = .map
    @State private var currentNames: [TilesetTarget: String] = [:]
    @State private var useValues: [TilesetTarget: Bool] = [:]

    /// The game's own overmap picker excludes isometric tilesets.
    private var choices: [Tileset] {
        target == .overmap ? tilesets.filter { !$0.isIsometric } : tilesets
    }

    private var selected: Tileset? {
        tilesets.first { $0.name == model.tilesetSelection[target] }
    }

    private var current: Tileset? {
        tilesets.first { $0.name == currentNames[target] }
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            controls
                .frame(minWidth: 380, idealWidth: 420, maxWidth: 480)
            Divider()
            TilesetPreviewPane(tileset: selected ?? current)
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { load() }
    }

    private var controls: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tilesets").font(.title2.bold())
                Spacer()
                StatusBadge(running: model.gameRunning)
            }

            Picker("Target", selection: $target) {
                ForEach(TilesetTarget.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle(target.toggleLabel, isOn: useBinding(target))
                .disabled(model.gameRunning)

            List(choices, selection: selectionBinding) { tileset in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tileset.viewName)
                        Text(tileset.isIsometric ? "\(tileset.name) — isometric" : tileset.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if tileset.name == currentNames[target] {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("Currently active for \(target.rawValue.lowercased())")
                    }
                }
                .padding(.vertical, 2)
                .tag(tileset.id)
            }
            .listStyle(.inset)

            HStack {
                Button("Apply Tileset") { applySelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil || selected?.name == currentNames[target] || model.gameRunning)
                Button("Install Tileset Folder…") { pickTilesetFolder() }
                    .disabled(model.gameRunning)
                Spacer()
                Button("Open Tilesets Folder") { model.open(model.paths.userGfxDir) }
                    .buttonStyle(.link)
            }

            Text("Choices are written to options.json in the TLG configuration folder (backed up first) and take effect when the game starts. Installed tilesets go to the persistent user gfx folder, so they survive game updates.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var selectionBinding: Binding<String?> {
        @Bindable var model = model
        return Binding(
            get: { model.tilesetSelection[target] },
            set: { model.tilesetSelection[target] = $0 }
        )
    }

    private func useBinding(_ target: TilesetTarget) -> Binding<Bool> {
        Binding(
            get: { useValues[target] ?? true },
            set: { newValue in
                useValues[target] = newValue
                write([target.useOption: newValue ? "true" : "false"])
            }
        )
    }

    // MARK: Actions

    private func load() {
        tilesets = TilesetCatalog.tilesets(
            appBundle: model.store.activeAppBundle(), paths: model.paths
        )
        for t in TilesetTarget.allCases {
            currentNames[t] = (try? model.optionsStore.value(t.option)) ?? nil
            useValues[t] = ((try? model.optionsStore.value(t.useOption)) ?? nil).map { $0 == "true" }
                ?? (t != .distant)   // the game defaults distant tiles off
            if model.tilesetSelection[t] == nil {
                model.tilesetSelection[t] = currentNames[t] ?? tilesets.first?.name
            }
        }
    }

    private func applySelected() {
        guard let selected else { return }
        write([target.option: selected.name])
        currentNames[target] = selected.name
    }

    private func write(_ values: [String: String]) {
        do {
            try model.optionsStore.setValues(values)
        } catch {
            model.alertMessage = String(describing: error)
        }
    }

    private func pickTilesetFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a tileset folder (containing tileset.txt)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let installed = try TilesetCatalog.install(from: url, paths: model.paths)
                load()
                model.tilesetSelection[target] = installed.name
            } catch {
                model.alertMessage = String(describing: error)
            }
        }
    }
}

// MARK: - Preview pane

/// Shows a corner of the tileset's sprite sheet, pixel-scaled the way the
/// game renders it.
struct TilesetPreviewPane: View {
    let tileset: Tileset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Preview").font(.title3.bold())
                    Spacer()
                    Text(tileset?.viewName ?? "").foregroundStyle(.secondary)
                }

                if let tileset, let image = Self.previewImage(for: tileset) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 560, alignment: .leading)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.separator, lineWidth: 1)
                        )
                    Text("A corner of the sprite sheet (\(tileset.imageURL?.lastPathComponent ?? "")), not a scene — sprites are composed in game.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No preview available for this tileset.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.background.secondary)
    }

    /// Top-left crop of the sprite sheet; whole sheets are tens of megapixels.
    static func previewImage(for tileset: Tileset) -> NSImage? {
        guard let url = tileset.imageURL,
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let side = min(512, min(cg.width, cg.height))
        guard let crop = cg.cropping(to: CGRect(x: 0, y: 0, width: min(cg.width, 640), height: side))
        else { return nil }
        return NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
    }
}
