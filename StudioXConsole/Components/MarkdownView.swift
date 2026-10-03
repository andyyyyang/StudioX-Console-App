import SwiftUI

/// 一整篇 Markdown（和網站一樣是 GFM）：標題、段落、清單（可以多層、有編號）、引言、程式碼區塊、分隔線、表格、圖片，
/// 粗體、斜體、刪除線、行內程式碼、連結。解析交給系統（AttributedString 的 full 語法，cmark-gfm），這裡一塊一塊畫。
/// chat：對話用的（標題小一點、段落之間近一點、單一換行照原樣換行，Xena 寫的「・」清單才不會黏成一段）。
struct MarkdownView: View {
    enum Style {
        /// 文章、頁面內容（和網站一樣：單一換行不換行）
        case article
        /// Xena 的對話
        case chat
    }

    let text: String
    var style: Style = .article

    var body: some View {
        let blocks = MarkdownBlocks.parse(text, keepLineBreaks: style == .chat)
        VStack(alignment: .leading, spacing: style == .chat ? 10 : 14) {
            ForEach(blocks) { block in
                MarkdownBlockView(block: block, style: style)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 解析

/// Markdown 的一塊
struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int)
        case paragraph
        /// 清單的一項：depth 從 0 開始；marker 是「•」或「3.」；continuation＝同一項的第二段（不再放記號）
        case listItem(depth: Int, marker: String, continuation: Bool)
        case code(language: String?)
        case rule
        case image(URL, alt: String)
        /// 表格：第一列是標題列（GFM 一定有）
        case table([[AttributedString]])
    }

    let id: Int
    let kind: Kind
    var content: AttributedString = AttributedString()
    /// 在引言（>）裡
    var quoted = false
}

enum MarkdownBlocks {
    static func parse(_ raw: String, keepLineBreaks: Bool) -> [MarkdownBlock] {
        // ![說明](網址 "圖說")：圖說拿來當圖片下面的說明（系統的解析不留 title）
        let captioned = raw.replacing(/!\[([^\]]*)\]\((\S+)\s+"([^"]*)"\)/) { m in "![\(m.output.3)](\(m.output.2))" }
        let source = keepLineBreaks ? hardBreaks(captioned) : captioned
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let doc = try? AttributedString(markdown: source, options: options) else {
            return [MarkdownBlock(id: 0, kind: .paragraph, content: AttributedString(raw))]
        }

        var blocks: [MarkdownBlock] = []
        var seenListItems: Set<Int> = []
        // 表格：同一個表格的每一格先收起來，表格結束時放成一塊
        var tableID: Int?
        var tableRows: [Int: [Int: AttributedString]] = [:]
        var tableQuoted = false

        func add(_ kind: MarkdownBlock.Kind, _ content: AttributedString = AttributedString(), quoted: Bool = false) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind, content: content, quoted: quoted))
        }
        func flushTable() {
            guard tableID != nil else { return }
            let rows = tableRows.keys.sorted().map { r in
                let cells = tableRows[r] ?? [:]
                return (0...(cells.keys.max() ?? 0)).map { cells[$0] ?? AttributedString() }
            }
            if !rows.isEmpty { add(.table(rows), quoted: tableQuoted) }
            tableID = nil
            tableRows = [:]
        }

        for (intent, range) in doc.runs[\.presentationIntent] {
            guard let intent else { continue }
            var content = AttributedString(doc[range])
            content.presentationIntent = nil
            let kinds = intent.components.map(\.kind)
            let quoted = kinds.contains { if case .blockQuote = $0 { true } else { false } }

            // 表格的一格
            if let cell = intent.components.first(where: { if case .tableCell = $0.kind { true } else { false } }),
               case .tableCell(let column) = cell.kind {
                let table = intent.components.first { if case .table = $0.kind { true } else { false } }?.identity
                if table != tableID { flushTable(); tableID = table; tableQuoted = quoted }
                var row = 0
                for c in intent.components {
                    if case .tableRow(let index) = c.kind { row = index + 1 }
                    // 標題列是第 0 列
                }
                tableRows[row, default: [:]][column] = trimmed(content)
                continue
            }
            flushTable()

            if kinds.contains(where: { if case .thematicBreak = $0 { true } else { false } }) {
                add(.rule)
                continue
            }
            if let code = kinds.first(where: { if case .codeBlock = $0 { true } else { false } }), case .codeBlock(let language) = code {
                var text = String(content.characters)
                if text.hasSuffix("\n") { text.removeLast() }
                add(.code(language: language), AttributedString(text), quoted: quoted)
                continue
            }
            if let heading = kinds.first(where: { if case .header = $0 { true } else { false } }), case .header(let level) = heading {
                add(.heading(level), trimmed(content), quoted: quoted)
                continue
            }

            // 段落：圖片拆出來自己一塊（![說明](網址)）
            var pieces: [(image: URL?, text: AttributedString)] = []
            for (url, r) in content.runs[\.imageURL] {
                let piece = AttributedString(content[r])
                if let url {
                    pieces.append((url, piece))
                } else if let last = pieces.last, last.image == nil {
                    pieces[pieces.count - 1].text.append(piece)
                } else {
                    pieces.append((nil, piece))
                }
            }

            // 清單的一項
            let lists = kinds.filter {
                switch $0 {
                case .orderedList, .unorderedList: true
                default: false
                }
            }
            let item = intent.components.first { if case .listItem = $0.kind { true } else { false } }
            for piece in pieces {
                if let url = piece.image {
                    add(.image(url, alt: String(piece.text.characters)), quoted: quoted)
                    continue
                }
                let text = trimmed(piece.text)
                if text.characters.isEmpty { continue }
                if let item, case .listItem(let ordinal) = item.kind {
                    let ordered: Bool = {
                        if case .orderedList = lists.first { return true }
                        return false
                    }()
                    let continuation = seenListItems.contains(item.identity)
                    seenListItems.insert(item.identity)
                    add(.listItem(depth: max(lists.count - 1, 0), marker: ordered ? "\(ordinal)." : (lists.count > 1 ? "◦" : "•"), continuation: continuation), text, quoted: quoted)
                } else {
                    add(.paragraph, text, quoted: quoted)
                }
            }
        }
        flushTable()
        return blocks
    }

    /// 前後的空白、換行拿掉
    private static func trimmed(_ s: AttributedString) -> AttributedString {
        var out = s
        while let first = out.characters.first, first.isWhitespace { out.removeSubrange(out.startIndex..<out.index(afterCharacter: out.startIndex)) }
        while let last = out.characters.last, last.isWhitespace { out.removeSubrange(out.index(beforeCharacter: out.endIndex)..<out.endIndex) }
        return out
    }

    /// 單一換行改成真的換行（行尾兩個空白）；程式碼區塊裡不動
    static func hardBreaks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var fence = false
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                fence.toggle()
                out.append(line)
                continue
            }
            let next = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""
            if !fence, !t.isEmpty, !next.isEmpty, !t.hasSuffix("|") {
                out.append(line + "  ")
            } else {
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - 畫出來

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let style: MarkdownView.Style

    var body: some View {
        content
            .padding(.leading, block.quoted ? 14 : 0)
            .overlay(alignment: .leading) {
                if block.quoted {
                    // 引言左邊一條線（文章是品牌橘，和網站一樣）
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(style == .article ? Theme.accent : Theme.line)
                        .frame(width: 3)
                }
            }
            .foregroundStyle(block.quoted ? Theme.ink2 : Theme.ink)
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .heading(let level):
            Text(block.content)
                .font(headingFont(level))
                .tracking(style == .article ? -0.3 : 0)
                .padding(.top, style == .article && level <= 2 ? 10 : 2)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(block.content)
                .font(bodyFont)
                .lineSpacing(style == .article ? 7 : 3)
                .tint(Theme.accentText)
                .textSelection(.enabled)
        case .listItem(let depth, let marker, let continuation):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(continuation ? "" : listMarker(marker))
                    .font(bodyFont.monospacedDigit())
                    .foregroundStyle(style == .article && !marker.hasSuffix(".") ? Theme.accent : Theme.muted)
                    .frame(minWidth: 16, alignment: .trailing)
                Text(block.content)
                    .font(bodyFont)
                    .lineSpacing(style == .article ? 5 : 3)
                    .tint(Theme.accentText)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(depth) * 20)
        case .code:
            ScrollView(.horizontal) {
                Text(block.content)
                    .font(.system(style == .chat ? .footnote : .callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.soft, in: .rect(cornerRadius: 10, style: .continuous))
        case .rule:
            Rule().padding(.vertical, 4)
        case .image(let url, let alt):
            VStack(alignment: .leading, spacing: 6) {
                image(url, alt: alt)
                if style == .article, !alt.isEmpty {
                    Text(alt)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        case .table(let rows):
            table(rows)
        }
    }

    /// 文章的第一層清單用品牌橘的「—」（和網站一樣）
    private func listMarker(_ marker: String) -> String {
        style == .article && marker == "•" ? "—" : marker
    }

    private func image(_ url: URL, alt: String) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: Motion.fast)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
            case .failure:
                Label(alt.isEmpty ? "圖片載入不了" : alt, systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            default:
                Theme.soft.frame(height: 160).clipShape(.rect(cornerRadius: 10, style: .continuous)).shimmer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(alt.isEmpty ? "圖片" : alt)
    }

    private func table(_ rows: [[AttributedString]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(r == 0 ? bodyFont.weight(.semibold) : bodyFont)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(r == 0 ? Theme.soft : .clear)
                if r < rows.count - 1 {
                    Rule().gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
    }

    /// 內文的字：文章用系統的內文大小，對話小一號（和 Xena 對話的其他字一樣）
    private var bodyFont: Font { style == .chat ? .subheadline : .body }

    private func headingFont(_ level: Int) -> Font {
        switch (style, level) {
        case (.chat, 1), (.chat, 2): .headline
        case (.chat, _): .subheadline.weight(.semibold)
        // 文章：網站的標題字（news/[slug]：h2 22、h3 18，600）
        case (_, 1): .brand(26, .semibold, relativeTo: .title)
        case (_, 2): .brand(22, .semibold, relativeTo: .title2)
        case (_, 3): .brand(18, .semibold, relativeTo: .title3)
        default: .brand(16, .semibold, relativeTo: .headline)
        }
    }
}
