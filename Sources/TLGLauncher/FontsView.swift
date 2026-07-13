import SwiftUI
import UniformTypeIdentifiers
import TLGLauncherCore

enum FontTarget: String, CaseIterable, Identifiable {
    case interface = "Interface"
    case map = "Map"
    case overmap = "Overmap"

    var id: String { rawValue }

    var widthOption: FontOption {
        switch self {
        case .interface: return .fontWidth
        case .map: return .mapFontWidth
        case .overmap: return .overmapFontWidth
        }
    }
    var heightOption: FontOption {
        switch self {
        case .interface: return .fontHeight
        case .map: return .mapFontHeight
        case .overmap: return .overmapFontHeight
        }
    }
    var sizeOption: FontOption {
        switch self {
        case .interface: return .fontSize
        case .map: return .mapFontSize
        case .overmap: return .overmapFontSize
        }
    }
}

struct FontsView: View {
    @Environment(AppModel.self) private var model

    @State private var config: FontsConfig = .tlgDefault
    @State private var target: FontTarget = .interface
    @State private var optionValues: [FontOption: String] = [:]
    @State private var importedFonts: [FontFile] = []
    @State private var bundledFonts: [FontFile] = []
    @State private var showSystemFontPicker = false
    @State private var dirty = false
    @State private var loaded = false

    private var stack: [String] {
        switch target {
        case .interface: return config.typeface
        case .map: return config.mapTypeface
        case .overmap: return config.overmapTypeface
        }
    }

    private func setStack(_ new: [String]) {
        switch target {
        case .interface: config.typeface = new
        case .map: config.mapTypeface = new
        case .overmap: config.overmapTypeface = new
        }
        dirty = true
    }

    var body: some View {
        HSplitView {
            controls
                .frame(minWidth: 380, idealWidth: 420, maxWidth: 480)
            FontPreviewPane(
                reference: stack.first,
                pointSize: Double(optionValues[target.sizeOption] ?? "16") ?? 16,
                blending: optionValues[.fontBlending] == "true",
                paths: model.paths,
                appBundle: model.store.activeAppBundle()
            )
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if !loaded { load() } }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Fonts").font(.title2.bold())
                    Spacer()
                    StatusBadge(running: model.gameRunning)
                }

                Picker("Configure", selection: $target) {
                    ForEach(FontTarget.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                GroupBox("Typeface stack (first is primary, the rest are glyph fallbacks)") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(stack.enumerated()), id: \.offset) { index, entry in
                            HStack {
                                Text(index == 0 ? "Primary" : "Fallback")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(entry).monospaced().lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if stack.count > 1 {
                                    Button {
                                        var s = stack; s.remove(at: index); setStack(s)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        HStack {
                            Menu("Set Primary…") {
                                fontMenuItems { reference in
                                    var s = stack
                                    s.removeAll { $0 == reference }
                                    s.insert(reference, at: 0)
                                    // Never leave the user without a Unicode fallback.
                                    if s.count == 1 { s.append("data/font/unifont.ttf") }
                                    setStack(s)
                                }
                            }
                            Menu("Add Fallback…") {
                                fontMenuItems { reference in
                                    guard !stack.contains(reference) else { return }
                                    setStack(stack + [reference])
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(6)
                }

                GroupBox("Dimensions (\(target.rawValue.lowercased()))") {
                    Grid(alignment: .leading, verticalSpacing: 8) {
                        dimensionRow("Width", option: target.widthOption)
                        dimensionRow("Height", option: target.heightOption)
                        dimensionRow("Point size", option: target.sizeOption)
                    }
                    .padding(6)
                }

                GroupBox("Rendering") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Font blending (smoother vector fonts)", isOn: optionBinding(.fontBlending))
                        Toggle("Draw ASCII lines with SDL routine (for fonts missing box-drawing glyphs)",
                               isOn: optionBinding(.drawAsciiLines))
                    }
                    .padding(6)
                }

                HStack {
                    Button("Save Changes") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!dirty || model.gameRunning)
                    Button("Reset to TLG Defaults") { resetToDefaults() }
                        .disabled(model.gameRunning)
                    Spacer()
                    Button("Open Fonts Folder") { model.open(model.paths.userFontDir) }
                        .buttonStyle(.link)
                }

                Text("Changes are written to fonts.json and options.json in the TLG configuration folder; both are backed up first. The game reads them at startup, so restart TLG after saving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .sheet(isPresented: $showSystemFontPicker) {
            SystemFontPicker { fontFile in
                importAndUse(url: fontFile.url)
            }
        }
    }

    @ViewBuilder
    private func fontMenuItems(action: @escaping (String) -> Void) -> some View {
        if !importedFonts.isEmpty {
            Section("Imported fonts") {
                ForEach(importedFonts) { font in
                    Button(font.displayName) { action(font.configReference) }
                }
            }
        }
        if !bundledFonts.isEmpty {
            Section("Bundled TLG fonts") {
                ForEach(bundledFonts) { font in
                    Button(font.displayName) { action(font.configReference) }
                }
            }
        }
        Divider()
        Button("Choose System Font…") { showSystemFontPicker = true }
        Button("Import Font File… (.ttf, .otf, .ttc)") { pickFontFile() }
    }

    private func dimensionRow(_ label: String, option: FontOption) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            TextField(
                "",
                text: Binding(
                    get: { optionValues[option] ?? option.tlgDefault },
                    set: { optionValues[option] = $0.filter(\.isNumber); dirty = true }
                )
            )
            .frame(width: 64)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            Stepper(
                "",
                value: Binding(
                    get: { Int(optionValues[option] ?? option.tlgDefault) ?? 16 },
                    set: { optionValues[option] = String(max(4, min(100, $0))); dirty = true }
                ),
                in: 4...100
            )
            .labelsHidden()
        }
    }

    private func optionBinding(_ option: FontOption) -> Binding<Bool> {
        Binding(
            get: { (optionValues[option] ?? option.tlgDefault) == "true" },
            set: { optionValues[option] = $0 ? "true" : "false"; dirty = true }
        )
    }

    // MARK: Actions

    private func load() {
        loaded = true
        do {
            config = try model.fontStore.loadFonts()
        } catch {
            model.alertMessage = String(describing: error)
        }
        for option in FontOption.allCases {
            optionValues[option] = (try? model.fontStore.optionValue(option)) ?? option.tlgDefault
        }
        refreshCatalogs()
        dirty = false
    }

    private func refreshCatalogs() {
        importedFonts = FontCatalog.importedFonts(paths: model.paths)
        bundledFonts = model.store.activeAppBundle().map(FontCatalog.bundledFonts(appBundle:)) ?? []
    }

    private func save() {
        do {
            try model.fontStore.saveFonts(config)
            try model.fontStore.setOptions(optionValues)
            dirty = false
        } catch {
            model.alertMessage = String(describing: error)
        }
    }

    private func resetToDefaults() {
        config = .tlgDefault
        for option in FontOption.allCases {
            optionValues[option] = option.tlgDefault
        }
        dirty = true
        save()
    }

    private func pickFontFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["ttf", "otf", "ttc"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importAndUse(url: url)
        }
    }

    /// Copies a font into the persistent user font directory and makes it the
    /// primary typeface for the current target, keeping existing fallbacks.
    private func importAndUse(url: URL) {
        do {
            let imported = try FontCatalog.importFont(from: url, paths: model.paths)
            refreshCatalogs()
            var s = stack
            s.removeAll { $0 == imported.configReference }
            s.insert(imported.configReference, at: 0)
            if s.count == 1 { s.append("data/font/unifont.ttf") }
            setStack(s)
        } catch {
            model.alertMessage = String(describing: error)
        }
    }
}

// MARK: - Preview pane

struct FontPreviewPane: View {
    let reference: String?
    let pointSize: Double
    let blending: Bool
    let paths: LauncherPaths
    let appBundle: URL?

    private var resolvedFont: Font {
        guard let reference,
              let url = resolveFontFile(reference),
              let name = FontCatalog.previewFontNames(for: url).first
        else {
            return .system(size: pointSize).monospaced()
        }
        return .custom(name, size: pointSize)
    }

    /// Mirrors TLG's search order: user font directory first, then the game's
    /// bundled data/font, then absolute paths.
    private func resolveFontFile(_ reference: String) -> URL? {
        let fm = FileManager.default
        if reference.hasPrefix("/") {
            return fm.fileExists(atPath: reference) ? URL(fileURLWithPath: reference) : nil
        }
        let inUserDir = paths.userFontDir.appendingPathComponent(reference)
        if fm.fileExists(atPath: inUserDir.path) { return inUserDir }
        let relative = reference.hasPrefix("data/font/") ? reference : "data/font/" + reference
        if let appBundle {
            let bundled = appBundle.appendingPathComponent("Contents/Resources/" + relative)
            if fm.fileExists(atPath: bundled.path) { return bundled }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Preview").font(.title3.bold())

                previewBlock("Ordinary text", """
                You see a moose — it looks angry.
                The quick brown fox jumps over the lazy dog. 0123456789
                """)

                previewBlock("ASCII", """
                @ Z z d # % & * ( ) [ ] { } < > / \\ | ~ ^
                !"#$%&'()*+,-./0123456789:;<=>?
                """)

                previewBlock("Unicode", """
                Wraith ・ 幽霊 ・ призрак ・ φάντασμα ・ şeytan
                Naïve façade — café • ½ ¾ ° ± µ Ω ∞ ✓
                """)

                previewBlock("Box drawing", """
                ┌─────┬─────┐  ╔══════╗
                │ ▒▒▒ │ ░░░ │  ║ ████ ║
                ├─────┼─────┤  ╚══════╝
                └─────┴─────┘  ═ ║ ╬ ╣ ╠
                """)

                Text(blending
                     ? "Font blending on — vector fonts render smoothed in game."
                     : "Font blending off — glyphs render unsmoothed in game.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The preview uses macOS text rendering; exact cell layout in game depends on the width and height settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.background.secondary)
    }

    private func previewBlock(_ title: String, _ sample: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(sample)
                .font(resolvedFont)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
    }
}

// MARK: - System font picker sheet

struct SystemFontPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (FontFile) -> Void

    @State private var fonts: [FontFile] = []
    @State private var query = ""

    private var filtered: [FontFile] {
        query.isEmpty
            ? fonts
            : fonts.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a system font").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            TextField("Search fonts", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            List(filtered) { font in
                HStack {
                    VStack(alignment: .leading) {
                        Text(font.displayName)
                        Text(font.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Use") {
                        onPick(font)
                        dismiss()
                    }
                }
            }
            Text("The font file is copied into TLG's persistent font folder, so it keeps working across game updates. Fonts must be fixed-width to line up well in game.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
        .frame(width: 420, height: 480)
        .task {
            fonts = await Task.detached { FontCatalog.systemFonts() }.value
        }
    }
}
