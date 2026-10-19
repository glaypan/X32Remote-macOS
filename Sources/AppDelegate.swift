import AppKit
import WebKit

/// AppKit 外壳：菜单、窗口、WKWebView，以及模拟器生命周期的编排。
/// 只使用 macOS 10.14.6 可用的 API（不用 SwiftUI / Combine / async-await）。
final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {

    private var window: NSWindow!
    private var webView: WKWebView!
    private let simulator = SimulatorProcess()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildWindow()

        simulator.onLogLine = { [weak self] line in self?.handleLogLine(line) }
        simulator.onReady = { [weak self] port in self?.handleReady(port: port) }
        simulator.onFailure = { [weak self] message in self?.handleFailure(message) }
        simulator.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        simulator.stop()
    }

    // MARK: - 菜单（无 XIB，全代码构建）

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 X32 Remote", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 X32 Remote", action: #selector(quitApp), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "在浏览器中打开控制台", action: #selector(openInBrowser), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "打开配置文件夹", action: #selector(openConfigFolder), keyEquivalent: ",")
        fileMenu.addItem(withTitle: "显示模拟器日志", action: #selector(showLog), keyEquivalent: "l")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "显示")
        viewMenu.addItem(withTitle: "重新加载", action: #selector(reload), keyEquivalent: "r")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.close(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openInBrowser() {
        guard let port = simulator.currentPort else { return }
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)/")!)
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([simulator.configDirectory])
    }

    @objc private func showLog() {
        NSWorkspace.shared.open(simulator.logFile)
    }

    @objc private func reload() {
        simulator.restart()
    }

    // MARK: - 窗口与 WebView

    private func buildWindow() {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                          styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "X32 Remote 控制台"
        window.minSize = NSSize(width: 960, height: 600)
        window.center()

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 760), configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 模拟器回调

    private func handleReady(port: Int) {
        webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!))
    }

    private func handleFailure(_ message: String) {
        webView.loadHTMLString(errorHTML(message: message, log: simulator.logTail(12)), baseURL: nil)
    }

    /// 从日志里抓局域网 IP 更新窗口标题，方便手机端照着输地址。
    private func handleLogLine(_ line: String) {
        guard let m = line.range(of: #"UDP (\d+\.\d+\.\d+\.\d+):"#, options: .regularExpression) else { return }
        let raw = String(line[m])
        let ip = raw.replacingOccurrences(of: "UDP ", with: "").replacingOccurrences(of: ":", with: "")
        if let port = simulator.currentPort {
            window.title = "X32 Remote 控制台 · \(ip):\(port)"
        }
    }

    private func errorHTML(message: String, log: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>启动失败</title><style>
        body{background:#17171A;color:#E8E8ED;font:14px/1.65 -apple-system,"PingFang SC",sans-serif;margin:0;padding:44px;max-width:820px}
        h1{font-size:17px;color:#FFB340;margin:0 0 14px}
        p{white-space:pre-wrap}
        pre{background:#0C0C0E;border:1px solid #2C2C30;border-radius:8px;padding:14px;overflow:auto;color:#9AA0A6;font-size:12px;white-space:pre-wrap}
        </style></head><body>
        <h1>模拟器未能启动</h1>
        <p>\(esc(message))</p>
        <p>点按菜单「显示 → 重新加载」重试。</p>
        <pre>\(esc(log))</pre>
        </body></html>
        """
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let host = url.host ?? ""
        let isLocal = host == "127.0.0.1" || host == "localhost"
        if !isLocal && (url.scheme == "http" || url.scheme == "https") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure("控制台页面加载失败：\(error.localizedDescription)")
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}
