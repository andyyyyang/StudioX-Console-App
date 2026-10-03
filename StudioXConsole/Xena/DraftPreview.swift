import SwiftUI
import UIKit

/// 確認卡片的「看完整內容」：Xena 改好的整份文章（照網站的樣子排版），以及和原本比改了哪些（新增綠、刪掉紅，沒變的收起來）
struct DraftPreviewView: View {
    let draftID: String
    var title: String?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var doc: DraftDocument?
    @State private var error: String?
    @State private var mode: Mode = .full

    enum Mode: Hashable { case full, changes }

    var body: some View {
        NavigationStack {
            Group {
                if let doc {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if doc.hunks != nil {
                                Picker("看什麼", selection: $mode) {
                                    Text("新版全文").tag(Mode.full)
                                    Text("改了哪些").tag(Mode.changes)
                                }
                                .pickerStyle(.segmented)
                            }
                            Text("\(doc.chars.formatted()) 字・\(formatLabel(doc.format))")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                            if mode == .changes, let hunks = doc.hunks {
                                DraftDiffView(hunks: hunks)
                            } else {
                                DraftBody(text: doc.text, format: doc.format)
                            }
                        }
                        .frame(maxWidth: Metric.readable, alignment: .leading)
                        .pageWidth()
                        .padding(.vertical, 16)
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                        .padding(16)
                } else {
                    BrandLoader(caption: "讀取 Xena 寫好的內容")
                }
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationTitle(doc?.title ?? title ?? "完整內容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { HeroIcon("x-mark") }
                        .accessibilityLabel("關閉")
                }
                if let doc {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("複製全文", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = doc.text
                                model.show("已複製全文")
                            }
                            ShareLink(item: doc.text, preview: SharePreview(doc.title)) {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                        } label: { HeroIcon("ellipsis-horizontal") }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            doc = try await model.api.draftDocument(draftID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func formatLabel(_ format: String) -> String {
        switch format {
        case "markdown": "Markdown"
        case "html": "HTML"
        default: "文字"
        }
    }
}

/// 草稿的內容：Markdown 照文章排版；HTML 照網頁排版（系統的 HTML 解析）；其他照原樣
struct DraftBody: View {
    let text: String
    let format: String

    var body: some View {
        switch format {
        case "markdown":
            MarkdownView(text: text, style: .article)
        case "html":
            HTMLText(html: text)
        default:
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// HTML 的內容排成文字（標題、段落、清單、粗體、連結；圖片不顯示）
struct HTMLText: View {
    let html: String
    @Environment(\.colorScheme) private var scheme
    @State private var rendered: AttributedString?

    var body: some View {
        Group {
            if let rendered {
                Text(rendered)
                    .tint(Theme.accentText)
                    .textSelection(.enabled)
            } else {
                Text(html)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(html.hashValue)-\(scheme == .dark)") { rendered = render() }
    }

    private func render() -> AttributedString? {
        let ink = scheme == .dark ? "#EEEBE5" : "#0F0F0E"
        let css = "<style>body{font-family:-apple-system;font-size:17px;line-height:1.6;color:\(ink)}h1{font-size:24px}h2{font-size:21px}h3{font-size:18px}img{display:none}</style>"
        guard let data = (css + html).data(using: .utf8),
              let ns = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              )
        else { return nil }
        return try? AttributedString(ns, including: \.uiKit)
    }
}

/// 改了哪些：新增的綠底、刪掉的紅底；沒變的長段落收起來，只留前後兩行
struct DraftDiffView: View {
    let hunks: [DraftHunk]
    @State private var expanded: Set<Int> = []

    private var changed: (added: Int, removed: Int) {
        hunks.reduce(into: (0, 0)) { acc, h in
            if h.op == "+" { acc.0 += h.lines.count }
            if h.op == "-" { acc.1 += h.lines.count }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("新增 \(changed.added) 行", systemImage: "plus")
                    .foregroundStyle(Theme.successFG)
                Label("刪掉 \(changed.removed) 行", systemImage: "minus")
                    .foregroundStyle(Theme.dangerFG)
            }
            .font(.footnote.weight(.medium))
            if changed.added + changed.removed == 0 {
                Text("內容和原本一樣，沒有改到。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hunks.enumerated()), id: \.offset) { index, hunk in
                    hunkView(index, hunk)
                }
            }
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        }
    }

    @ViewBuilder
    private func hunkView(_ index: Int, _ hunk: DraftHunk) -> some View {
        switch hunk.op {
        case "+":
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                lineRow("+", line, fg: Theme.successFG, bg: Theme.successFG.opacity(0.12))
            }
        case "-":
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                lineRow("−", line, fg: Theme.dangerFG, bg: Theme.dangerFG.opacity(0.1), strike: true)
            }
        default:
            let lines = hunk.lines
            let first = index == 0
            let last = index == hunks.count - 1
            // 沒變的：開頭的只留最後兩行、結尾的只留前兩行、中間的留前後兩行
            if lines.count <= 5 || expanded.contains(index) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in lineRow(" ", line) }
            } else {
                let head = first ? [] : Array(lines.prefix(2))
                let tail = last ? [] : Array(lines.suffix(2))
                ForEach(Array(head.enumerated()), id: \.offset) { _, line in lineRow(" ", line) }
                Button { withAnimation(Motion.fast) { _ = expanded.insert(index) } } label: {
                    Text("⋯ \(lines.count - head.count - tail.count) 行沒變（點開）")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Theme.soft)
                }
                .buttonStyle(.plain)
                ForEach(Array(tail.enumerated()), id: \.offset) { _, line in lineRow(" ", line) }
            }
        }
    }

    private func lineRow(_ mark: String, _ line: String, fg: Color = Theme.ink2, bg: Color = .clear, strike: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(mark)
                .font(.system(.footnote, design: .monospaced).weight(.bold))
                .foregroundStyle(fg)
                .frame(width: 12)
            Text(line.isEmpty ? " " : line)
                .font(.footnote)
                .foregroundStyle(mark == " " ? Theme.muted : Theme.ink)
                .strikethrough(strike, color: Theme.dangerFG.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(bg)
    }
}
