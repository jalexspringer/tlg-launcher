import SwiftUI
import Combine
import TLGLauncherCore

/// Blocks app termination while the Fonts pane holds unsaved edits.
@MainActor
final class QuitGuard: NSObject, NSApplicationDelegate {
    var hasUnsavedChanges: () -> Bool = { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard hasUnsavedChanges() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Unsaved font changes"
        alert.informativeText = "The Fonts pane has changes that have not been saved to the game configuration. They will be lost if you quit now."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

@main
struct TLGLauncherApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(QuitGuard.self) private var quitGuard

    var body: some Scene {
        WindowGroup("TLG Launcher") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear {
                    let model = self.model
                    quitGuard.hasUnsavedChanges = { model.fontsDraft?.dirty == true }
                }
                .task {
                    await model.checkForUpdates()
                }
                .task {
                    // Scripted UI check: open ... --args -screenshotTo /path.png
                    // captures the window (no screen-recording permission needed).
                    guard let path = UserDefaults.standard.string(forKey: "screenshotTo") else { return }
                    let delay = UserDefaults.standard.double(forKey: "screenshotDelay")
                    try? await Task.sleep(for: .seconds(delay > 0 ? delay : 2))
                    if let window = NSApp.windows.first(where: \.isVisible) {
                        await window.snapshotPNG(to: URL(fileURLWithPath: path))
                    }
                    NSApp.terminate(nil)
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

import WebKit

extension NSWindow {
    func snapshotPNG(to url: URL) async {
        // WKWebView renders out of process, so window-level captures show it
        // blank; ask the web view itself when one is on screen.
        if let webView = contentView.flatMap(Self.findWebView(in:)) {
            let image = try? await webView.takeSnapshot(configuration: nil)
            if let image, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                return
            }
        }
        // CGWindowListCreateImage captures the app's own windows without
        // screen-recording permission; cacheDisplay misses SwiftUI layers.
        guard let cg = CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(windowNumber), [.boundsIgnoreFraming]
        ) else { return }
        try? NSBitmapImageRep(cgImage: cg)
            .representation(using: .png, properties: [:])?
            .write(to: url)
    }

    private static func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = findWebView(in: subview) { return found }
        }
        return nil
    }
}
