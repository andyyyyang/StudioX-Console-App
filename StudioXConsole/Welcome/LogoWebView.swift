import SwiftUI
import WebKit

/// 歡迎頁的 3D 玻璃 Logo：App 裡的 welcome.html（Web/welcome 打包：studiox.tw 首頁同一份 logo3d.ts 與 three.js），
/// 不連網路。下方被登入面板蓋住的高度傳給網頁，Logo 擺在剩下的空間正中間；按下登入時讓積木立刻組合起來。
struct LogoWebView: UIViewRepresentable {
    /// 下方被面板蓋住多高（pt）
    var coveredBottom: CGFloat
    /// 每加一次：積木立刻組合起來
    var assemble: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "welcome")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.navigationDelegate = context.coordinator
        web.isInspectable = false
        web.accessibilityElementsHidden = true
        context.coordinator.web = web
        if let url = Bundle.main.url(forResource: "welcome", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.setCovered(coveredBottom)
        if assemble != context.coordinator.assembled {
            context.coordinator.assembled = assemble
            web.evaluateJavaScript("window.studiox && studiox.assemble()", completionHandler: nil)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "welcome")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var web: WKWebView?
        var assembled = 0
        private var covered: CGFloat = 0
        private var loaded = false

        func setCovered(_ value: CGFloat) {
            guard value != covered || !loaded else { return }
            covered = value
            push()
        }

        private func push() {
            guard loaded else { return }
            web?.evaluateJavaScript("window.studiox && studiox.setSheet(\(Double(covered)))", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            push()
        }

        /// 網頁說 3D 好了（ready）或用平面 Logo（flat）：目前不需要做什麼，留著除錯
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
    }
}
