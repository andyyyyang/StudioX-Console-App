import SwiftUI
import UIKit
import WebKit

/// 出貨單：在 App 裡看、列印、存成 PDF 分享。
/// 以前「出貨單 ↗」開的是網站後台的列印頁 —— 瀏覽器沒有登入後台，打開就是沒有權限。
/// 現在用網站的 packing_slip 工具（和後台列印頁同一份 HTML），經 App 自己的登入拿，不用再登入網站。
struct PackingSlipView: View {
    let site: String
    let orderIDs: [String]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var html: String?
    @State private var title = "出貨單"
    @State private var error: String?
    @State private var web = PackingSlipWeb()
    @State private var pdf: SharedFile?
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            Group {
                if let html {
                    PackingSlipWebView(html: html, web: web)
                        .ignoresSafeArea(edges: .bottom)
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                        .padding(20)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.white)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await sharePDF() }
                    } label: {
                        if exporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                    }
                    .accessibilityLabel("存成 PDF、分享")
                    .disabled(html == nil || exporting)
                    Button {
                        web.print(jobName: title)
                    } label: {
                        Image(systemName: "printer")
                    }
                    .accessibilityLabel("列印")
                    .disabled(html == nil)
                }
            }
        }
        .sheet(item: $pdf) { file in
            ActivitySheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            let r = try await model.api.tool("packing_slip", site: site, ["ids": .array(orderIDs.map { .string($0) })])
            guard let h = r["html"]?.string, !h.isEmpty else {
                error = "網站還沒有提供 App 用的出貨單，請更新網站後再試"
                return
            }
            title = r["title"]?.string ?? "出貨單"
            html = h
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sharePDF() async {
        exporting = true
        defer { exporting = false }
        do {
            let data = try await web.pdf()
            let name = title.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
            try data.write(to: url, options: .atomic)
            pdf = SharedFile(url: url)
        } catch {
            model.show("存成 PDF 失敗：\(error.localizedDescription)")
        }
    }
}

/// 要分享的暫存檔（.sheet(item:) 用）
struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// 出貨單的 WKWebView：列印、轉 PDF 都從同一個網頁來（和網站後台印出來的一樣）
@MainActor
final class PackingSlipWeb {
    let view: WKWebView = {
        let config = WKWebViewConfiguration()
        // 出貨單是網站給的靜態 HTML：不跑 JavaScript、不存任何資料（上面有客人的地址電話）
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let v = WKWebView(frame: .zero, configuration: config)
        v.isOpaque = false
        v.backgroundColor = .white
        return v
    }()

    func print(jobName: String) {
        let info = UIPrintInfo.printInfo()
        info.jobName = jobName
        info.outputType = .general
        let c = UIPrintInteractionController.shared
        c.printInfo = info
        c.printFormatter = view.viewPrintFormatter()
        _ = c.present(animated: true)
    }

    func pdf() async throws -> Data {
        try await view.pdf()
    }
}

/// 把網站給的出貨單 HTML 放進 App（連外部網址時改用 Safari 開，不在這裡載入）
struct PackingSlipWebView: UIViewRepresentable {
    let html: String
    let web: PackingSlipWeb

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        web.view.navigationDelegate = context.coordinator
        web.view.loadHTMLString(html, baseURL: nil)
        context.coordinator.loaded = html
        return web.view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated, let url = action.request.url {
                _ = await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}

/// 系統的分享選單（存到檔案、AirDrop、傳 LINE…）
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
