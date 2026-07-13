import SwiftUI
import WebKit
import TLGLauncherCore

struct GuideView: View {
    @Environment(AppModel.self) private var model
    @State private var controller = GuideWebController()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { controller.webView.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!controller.canGoBack)
                .help("Back")

                Button { controller.webView.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!controller.canGoForward)
                .help("Forward")

                Button { controller.goHome() } label: {
                    Image(systemName: "house")
                }
                .help("Home")

                Button { controller.webView.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")

                if controller.isLoading {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                if controller.dataBase != nil {
                    Text("Offline game data (matches installed version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Game data fetched live from RenechCDDA/tlg-data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.launcherState.activeTag != nil {
                        if model.isGeneratingGuideData {
                            ProgressView().controlSize(.small)
                            Text("Generating offline data…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Generate Offline Data") {
                                Task {
                                    await model.regenerateGuideData()
                                    controller.configure(
                                        homeURL: model.guideBaseURL(),
                                        dataBase: model.guideDataBaseURL()
                                    )
                                }
                            }
                            .help("Builds the guide's game data from the installed version, so the guide matches what you play and works offline.")
                        }
                    }
                }

                Button {
                    if let url = controller.webView.url {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open current page in the default browser (works while the launcher is running)")
            }
            .buttonStyle(.borderless)
            .padding(10)

            Divider()

            if controller.homeURL != nil {
                GuideWebViewRepresentable(controller: controller)
            } else {
                ContentUnavailableView(
                    "Guide not bundled",
                    systemImage: "book",
                    description: Text("Run Scripts/build-guide.sh and rebuild the app to bundle the TLG Hitchhiker's Guide.")
                )
            }
        }
        .onAppear {
            if controller.homeURL == nil {
                let home = model.guideBaseURL()
                // Scripted testing: open ... --args -guidePath /monster/mon_zombie
                var initial: URL?
                if let path = UserDefaults.standard.string(forKey: "guidePath"), let home {
                    initial = URL(string: path.trimmingCharacters(in: ["/"]), relativeTo: home)
                }
                controller.configure(homeURL: home, dataBase: model.guideDataBaseURL(), initialURL: initial)
            }
        }
    }
}

/// Owns the WKWebView so navigation state survives SwiftUI view updates.
@MainActor
@Observable
final class GuideWebController: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var homeURL: URL?
    private(set) var dataBase: URL?
    var canGoBack = false
    var canGoForward = false
    var isLoading = false

    override init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// `dataBase` is where the guide fetches game data. When set, it is
    /// injected as `window.__HHG_DATA_BASE__` before every page load (the
    /// guide fork consults it and otherwise uses its remote default), so it
    /// survives reloads and in-app navigation alike.
    func configure(homeURL: URL?, dataBase: URL?, initialURL: URL? = nil) {
        self.homeURL = homeURL
        self.dataBase = dataBase
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        if let dataBase {
            let script = WKUserScript(
                source: "window.__HHG_DATA_BASE__ = \"\(dataBase.absoluteString)\";",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            controller.addUserScript(script)
        }
        if let initialURL {
            webView.load(URLRequest(url: initialURL))
        } else {
            goHome()
        }
    }

    func goHome() {
        if let homeURL {
            webView.load(URLRequest(url: homeURL))
        }
    }

    private func syncState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        MainActor.assumeIsolated { syncState() }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { syncState() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { syncState() }
    }

    /// Keep the guide inside the launcher; external links go to the browser.
    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // WKNavigationDelegate calls back on the main thread.
        MainActor.assumeIsolated {
            guard let url = navigationAction.request.url, let home = self.homeURL else {
                decisionHandler(.allow)
                return
            }
            if url.host == home.host && url.port == home.port {
                decisionHandler(.allow)
            } else if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                // Sub-resource fetches (tlg-data JSON etc.) must pass through.
                decisionHandler(.allow)
            }
        }
    }
}

struct GuideWebViewRepresentable: NSViewRepresentable {
    let controller: GuideWebController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
