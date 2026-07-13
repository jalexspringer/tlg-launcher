import SwiftUI
import TLGLauncherCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case play = "Play"
    case releases = "Releases"
    case backups = "Backups"
    case fonts = "Fonts"
    case colors = "Colours"
    case tilesets = "Tilesets"
    case sound = "Sound"
    case guide = "Guide"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .play: return "play.circle"
        case .releases: return "clock.arrow.circlepath"
        case .backups: return "externaldrive.badge.timemachine"
        case .fonts: return "textformat"
        case .colors: return "paintpalette"
        case .tilesets: return "square.grid.3x3.square"
        case .sound: return "speaker.wave.2"
        case .guide: return "book"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    // Overridable at launch for scripted testing: open ... --args -initialTab Fonts
    @State private var selection: SidebarItem =
        SidebarItem(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .play

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                HStack {
                    Label(item.rawValue, systemImage: item.systemImage)
                    Spacer()
                    if item == .fonts, model.fontsDraft?.dirty == true {
                        Circle().fill(.orange).frame(width: 7, height: 7)
                            .help("Unsaved font changes")
                    }
                }
                .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection {
            case .play: HomeView()
            case .releases: ReleasesView()
            case .backups: BackupsView()
            case .fonts: FontsView()
            case .colors: ColorsView()
            case .tilesets: TilesetsView()
            case .sound: SoundView()
            case .guide: GuideView()
            case .settings: SettingsView()
            }
        }
        .alert(
            "TLG Launcher",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}

// MARK: - Shared bits

struct StatusBadge: View {
    let running: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(running ? .orange : .green)
                .frame(width: 8, height: 8)
            Text(running ? "Game running — updates and config changes disabled" : "Game not running")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

extension GameRelease {
    var displayName: String { name?.isEmpty == false ? name! : tagName }

    var shortLabel: String {
        // "cataclysm-tlg-1.0-2026-07-13-1202" reads better as its build stamp.
        tagName.replacingOccurrences(of: "cataclysm-tlg-", with: "")
    }
}
