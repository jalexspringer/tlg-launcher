import SwiftUI
import TLGLauncherCore

struct ColorsView: View {
    @Environment(AppModel.self) private var model

    @State private var themes: [ColorTheme] = []
    @State private var current: [GameColor: RGB] = ColorTheme.tlgDefault.colors
    @State private var loaded = false

    private var selected: ColorTheme? {
        themes.first { $0.id == model.colorSelection }
    }

    private var activeTheme: ColorTheme? {
        themes.first { $0.colors == current }
    }

    var body: some View {
        // HStack rather than HSplitView, for the same layout reason as FontsView.
        HStack(spacing: 0) {
            controls
                .frame(minWidth: 380, idealWidth: 420, maxWidth: 480)
            Divider()
            ColorThemePreviewPane(theme: selected ?? activeTheme ?? .tlgDefault)
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if !loaded { load() } }
    }

    private var controls: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Colour Scheme").font(.title2.bold())
                Spacer()
                StatusBadge(running: model.gameRunning)
            }

            if themes.count <= 1 {
                Text("Install a TLG version to list its bundled colour schemes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            List(themes, selection: $model.colorSelection) { theme in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(theme.name)
                        swatchStrip(theme)
                    }
                    Spacer()
                    if theme.colors == current {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("Currently active")
                    }
                }
                .padding(.vertical, 3)
                .tag(theme.id)
            }
            .listStyle(.inset)

            HStack {
                Button("Apply Scheme") { apply(selected) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil || selected?.colors == current || model.gameRunning)
                Button("Reset to TLG Default") { apply(.tlgDefault) }
                    .disabled(current == ColorTheme.tlgDefault.colors || model.gameRunning)
                Spacer()
                Button("Open Config Folder") { model.open(model.paths.configDir) }
                    .buttonStyle(.link)
            }

            Text("The scheme is written to base_colors.json in the TLG configuration folder; the previous file is backed up first. The game reads it at startup, so restart TLG after applying.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func swatchStrip(_ theme: ColorTheme) -> some View {
        HStack(spacing: 1) {
            ForEach(GameColor.allCases, id: \.self) { color in
                Rectangle()
                    .fill(swiftUIColor(theme.colors[color] ?? RGB(0, 0, 0)))
                    .frame(width: 13, height: 13)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    // MARK: Actions

    private func load() {
        loaded = true
        refreshCurrent()
        var found: [ColorTheme] = []
        if let bundle = model.store.activeAppBundle() {
            found = ColorThemeCatalog.bundledThemes(appBundle: bundle)
        }
        // Without an installed version there is still one scheme to offer.
        themes = found.isEmpty ? [.tlgDefault] : found
        // Keep a selection made on an earlier visit; default to the active theme.
        if selected == nil {
            model.colorSelection = activeTheme?.id ?? themes.first?.id
        }
    }

    private func refreshCurrent() {
        do {
            current = try model.colorStore.currentColors()
        } catch {
            model.alertMessage = String(describing: error)
        }
    }

    private func apply(_ theme: ColorTheme?) {
        guard let theme else { return }
        do {
            try model.colorStore.apply(theme)
            refreshCurrent()
        } catch {
            model.alertMessage = String(describing: error)
        }
    }
}

// MARK: - Preview pane

/// A mock game scene plus labelled swatches, rendered in the theme's own
/// palette on its black background.
struct ColorThemePreviewPane: View {
    let theme: ColorTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Preview").font(.title3.bold())
                    Spacer()
                    Text(theme.name).foregroundStyle(.secondary)
                }

                gameMock

                swatchGrid

                Text("The preview approximates the game's terminal rendering; sprites and UI panels in game also draw on these sixteen colours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.background.secondary)
    }

    private func color(_ c: GameColor) -> Color {
        swiftUIColor(theme.colors[c] ?? RGB(0, 0, 0))
    }

    private func span(_ text: String, _ c: GameColor) -> Text {
        Text(text).foregroundColor(color(c))
    }

    private var gameMock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                span("│", .gray) + span("TT", .green) + span("....", .darkGray)
                    + span("~~", .blue) + span("│ ", .gray)
                    + span("HP ", .white) + span("67/84", .lightGreen)
                    + span("  Stamina ", .white) + span("████░", .lightBlue)
                span("│", .gray) + span("T", .green) + span(".", .darkGray)
                    + span("@", .white) + span("..", .darkGray) + span("~~", .blue)
                    + span("│ ", .gray)
                    + span("Peckish", .yellow) + span("  Cold", .lightBlue)
                    + span("  Tired", .lightRed)
                span("│", .gray) + span("..", .darkGray) + span("Z", .green)
                    + span("z", .lightGreen) + span(".", .darkGray) + span("~", .blue)
                    + span("f", .lightCyan) + span("│ ", .gray)
                    + span("Focus ", .white) + span("105", .cyan)
                    + span("  Morale ", .white) + span(":)", .lightGreen)
                span("│", .gray) + span("#", .brown) + span("&", .magenta)
                    + span("..", .darkGray) + span("!", .lightMagenta)
                    + span("*", .red) + span(".", .darkGray) + span("│ ", .gray)
                    + span("Deep Water  ", .lightBlue) + span("Fire!", .lightRed)
            }
            Divider().overlay(color(.darkGray))
            Group {
                span("You swing your crowbar at the zombie!", .gray)
                span("You hit the zombie for 12 damage.", .lightGreen)
                span("The zombie bites your arm!", .lightRed)
                span("The sun is setting. It will be dark soon.", .yellow)
                span("You feel a strange presence watching you…", .lightMagenta)
            }
        }
        .font(.system(size: 13).monospaced())
        .lineSpacing(2)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(.black))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private var swatchGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2),
            alignment: .leading, spacing: 8
        ) {
            ForEach(GameColor.allCases, id: \.self) { c in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(c))
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.separator, lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.displayName).font(.caption)
                        Text((theme.colors[c] ?? RGB(0, 0, 0)).hexString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private func swiftUIColor(_ rgb: RGB) -> Color {
    Color(
        .sRGB,
        red: Double(rgb.r) / 255,
        green: Double(rgb.g) / 255,
        blue: Double(rgb.b) / 255
    )
}
