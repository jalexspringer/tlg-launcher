import SwiftUI
import Combine
import TLGLauncherCore

@main
struct TLGLauncherApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("TLG Launcher") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    await model.checkForUpdates()
                }
                .onReceive(
                    Timer.publish(every: 5, on: .main, in: .common).autoconnect()
                ) { _ in
                    model.refreshGameRunning()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
