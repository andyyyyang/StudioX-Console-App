import AVKit
import SwiftUI
import UIKit

// MARK: - Xena 的客服對話

/// 網站上 Xena 的客服對話：官網右下角的 Xena，或網站的 LINE 官方帳號。
/// 版面照聊天 App：客人在左（頭像、白泡泡），我們在右（Xena 是彩虹細框、專人是品牌色）；
/// 同一個人連著說的合成一組、跨天放日期；上方是客人與狀態（右邊一顆主要動作），下方回覆。
/// 照片點開全螢幕（可以放大、分享），語音、影片直接播；專人附的卡片、Xena 帶客人去的頁面照客人看到的畫。
/// 網站有 reply_xena 就能在這裡回覆、接手、交給 Xena 繼續回答、結案；沒有的網站（還沒更新的）照舊到後台處理。
struct XenaConversationView: View {
    let site: String
    let conversationID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var detail: XenaConversationDetail?
    @State private var error: String?
    @State private var draft = ""
    /// 送出中的回覆：先畫出來，網站回來再換成真的
    @State private var pending: String?
    @State private var proposal: Proposal?
    @State private var replying = false
    @State private var working = false
    @State private var viewing: ViewedMedia?
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true
    /// 捲在上面時進來的新訊息
    @State private var unseen = 0

    /// 這個網站能在 App 裡回覆、接手
    private var desk: Bool { model.site(site)?.hasXenaDesk ?? false }
    private var status: String? { detail?.status }
    private var siteName: String { model.site(site)?.name ?? site }
    private var who: String { detail?.who ?? (detail?.channel == .line ? "LINE 好友" : "網站訪客") }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let d = detail {
                    ConversationIntro(detail: d, siteName: siteName, site: site)
                        .padding(.bottom, 8)
                    timeline(d)
                    if let pending {
                        PendingReply(text: pending)
                            .padding(.top, 14)
                    }
                    if !desk, let admin = d.adminURL ?? model.site(site)?.adminURL {
                        Button { openURL(admin) } label: { Text("這個網站要到後台回覆 ↗") }
                            .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
                            .padding(.top, 24)
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 5)
                }
            }
            .frame(maxWidth: Metric.readable)
            .pageWidth()
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { g in
            g.contentOffset.y + g.containerSize.height - g.contentInsets.bottom >= g.contentSize.height - 120
        } action: { _, bottom in
            atBottom = bottom
            if bottom { unseen = 0 }
        }
        .refreshable { await load() }
        .brandPage()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if desk, detail != nil { composer }
        }
        // 聊天畫面：手機上收起底部的分頁列，留給回覆
        .toolbar(sizeClass == .regular ? .automatic : .hidden, for: .tabBar)
        .navigationTitle(who)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task { await load() }
        // 開著的時候每 15 秒看一次有沒有新訊息（客人在 LINE 或網站上又說話了）
        .task(id: conversationID) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                await load(quiet: true)
            }
        }
        .onChange(of: detail?.messages.count ?? 0) { old, new in
            guard new > old else { return }
            // 剛打開、在最下面、或是自己剛送出的：跟著捲到最新；捲在上面看舊的就不打斷，右下角提示
            if old == 0 || atBottom || detail?.messages.last?.role == "staff" {
                withAnimation(Motion.ease) { position.scrollTo(edge: .bottom) }
            } else {
                unseen += new - old
            }
        }
        .fullScreenCover(item: $viewing) { MediaViewer(media: $0) }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            if replying { announceReply(result) } else { model.show("已更新") }
            replying = false
            Task {
                await load()
                await model.refreshAll()
            }
        }
    }

    // MARK: 對話

    @ViewBuilder
    private func timeline(_ d: XenaConversationDetail) -> some View {
        // 轉真人的原因放在最後一次「通知專人」的事件下面
        let lastHandoff = d.messages.last { $0.role == "event" && ChatEventRow.kind(of: $0) == "handoff" }?.id
        ForEach(ChatEntry.build(d.messages)) { entry in
            switch entry {
            case .day(let date):
                ChatDayDivider(date: date)
                    .padding(.top, 22)
                    .padding(.bottom, 4)
            case .event(let m):
                ChatEventRow(message: m, reason: m.id == lastHandoff ? d.handoffReason : nil)
                    .padding(.top, 14)
            case .message(let m, let first, let last):
                XenaChatRow(
                    message: m, first: first, last: last,
                    who: who, picture: d.picture, site: site, siteURL: model.site(site)?.url
                ) { viewing = $0 }
                .padding(.top, first ? 14 : 3)
            }
        }
    }

    // MARK: 上方：客人、狀態、主要動作

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) { title }
        if desk, let action = primaryAction {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action.label) { act(action.id) }
                    .font(.brand(14, .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .disabled(working || detail == nil)
            }
        }
        ToolbarItem(placement: .topBarTrailing) { menu }
    }

    private var title: some View {
        HStack(spacing: 9) {
            Avatar(name: who, imageURL: detail?.picture, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(who)
                    .font(.brand(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let detail {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        HStack(spacing: 5) {
                            Circle().fill(statusTone.dot).frame(width: 6, height: 6)
                            Text("\(detail.channel.label)・\(statusText)")
                                .lineLimit(1)
                        }
                        .font(.brand(11.5, .medium, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch status {
        case "waiting":
            if let at = detail?.handoffAt { return "等專人 \(waited(since: at))" }
            return "等專人"
        case "human": return "\(assigneeLabel)接手中"
        case "closed": return "已結案"
        case "ai": return "Xena 回答中"
        default: return status.map(XenaConversationSummary.label) ?? "Xena 客服"
        }
    }

    private var statusTone: Tone { status.map(XenaConversationSummary.tone) ?? .neutral }

    /// 誰接手：自己就說「你」；網站給的是 Email（atelier-cms）就不顯示地址
    private var assigneeLabel: String {
        guard let a = detail?.assignee, !a.isEmpty else { return "專人" }
        if let me = model.me, a.caseInsensitiveCompare(me.email) == .orderedSame || a == me.name { return "你" }
        return a.contains("@") ? "專人" : a
    }

    private func waited(since date: Date) -> String {
        let s = max(0, Date.now.timeIntervalSince(date))
        if s < 60 { return "剛剛" }
        if s < 3600 { return "\(Int(s / 60)) 分鐘" }
        if s < 86400 { return "\(Int(s / 3600)) 小時" }
        return "\(Int(s / 86400)) 天"
    }

    private var primaryAction: (id: String, label: String)? {
        switch status {
        case "ai", "waiting": (id: "takeover", label: "接手")
        case "human": (id: "release", label: "交給 Xena")
        case "closed": (id: "reopen", label: "重新開啟")
        default: nil
        }
    }

    @ViewBuilder
    private var menu: some View {
        Menu {
            if desk, let status {
                if status == "ai" || status == "waiting" {
                    Button("接手（Xena 先停止回答）", systemImage: "hand.raised") { act("takeover") }
                }
                if status == "human" || status == "waiting" {
                    Button("交給 Xena 繼續回答", systemImage: "sparkles") { act("release") }
                }
                if status != "closed" {
                    Button("結案", systemImage: "checkmark.circle") { act("close") }
                } else {
                    Button("重新開啟", systemImage: "arrow.uturn.backward.circle") { act("reopen") }
                }
            }
            Button("請 Xena 擬回覆", systemImage: "sparkles") { askXenaForDraft() }
            if let url = detail?.adminURL ?? model.site(site)?.adminURL {
                Button("在後台打開", systemImage: "arrow.up.right.square") { openURL(url) }
            }
        } label: { HeroIcon("ellipsis-horizontal") }
    }

    private func act(_ action: String) {
        Task { await propose { try await model.api.proposeXena(site: site, id: conversationID, action: action) } }
    }

    private func askXenaForDraft() {
        let from = detail?.channel == .line ? "LINE 上" : "官網上"
        model.askXena("幫我看\(siteName)\(from)這段 Xena 客服對話（\(conversationID)），擬一段給客人的回覆")
    }

    // MARK: 下方：回覆

    @ViewBuilder
    private var composer: some View {
        if status == "closed" {
            HStack(spacing: 12) {
                Text("已結案。客人再開口會回到 Xena。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                Button("重新開啟") { act("reopen") }
                    .buttonStyle(.brand(.ghost, size: .sm))
                    .disabled(working)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.sheet)
            .overlay(alignment: .top) { Rule() }
        } else {
            ChatComposer(
                text: $draft,
                placeholder: status == "human" ? "回覆客人…" : "回覆客人（送出就由你接手）",
                hint: detail?.replyGoesTo ?? detail?.channel.replyHint,
                hintWarning: detail?.lineBlocked == true,
                sending: pending != nil,
                draftWithXena: askXenaForDraft,
                send: send
            )
            .overlay(alignment: .topTrailing) {
                if !atBottom {
                    JumpToLatest(count: unseen) {
                        withAnimation(Motion.ease) { position.scrollTo(edge: .bottom) }
                    }
                    .padding(.trailing, 16)
                    .offset(y: -54)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(Motion.fast, value: atBottom)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, pending == nil else { return }
        pending = text
        draft = ""
        withAnimation(Motion.ease) { position.scrollTo(edge: .bottom) }
        Task {
            let sent = await propose(reply: true) { try await model.api.proposeXena(site: site, id: conversationID, action: "reply", text: text) }
            // 沒送出（出錯、要另外確認）：字放回輸入框，不會不見
            if !sent, draft.isEmpty { draft = text }
            pending = nil
        }
    }

    private func load(quiet: Bool = false) async {
        do {
            detail = try await model.api.xenaConversation(site: site, id: conversationID)
            error = nil
        } catch {
            if !quiet { self.error = error.localizedDescription }
        }
    }

    /// 回覆送出了：照網站回報的說有沒有真的傳到客人的 LINE、有沒有寄信（沒傳到要讓專人知道）
    private func announceReply(_ result: JSONValue) {
        draft = ""
        if result["lineSent"]?.bool == false {
            model.show("回覆存下來了，但沒有傳到客人的 LINE（可能封鎖了官方帳號，或本月訊息量用完）", tone: .warning)
        } else if let error = result["emailError"]?.string, !error.isEmpty {
            model.show("回覆已送出，但通知信沒寄出：\(error)", tone: .warning)
        } else if result["lineSent"]?.bool == true {
            model.show("已傳到客人的 LINE")
        } else {
            model.show(result["emailed"]?.bool == true ? "已送出回覆，也寄信通知客人" : "已送出回覆")
        }
    }

    /// 回傳 true：回覆已經送出（不用再確認）
    @discardableResult
    private func propose(reply: Bool = false, _ make: () async throws -> ConsoleAPI.WriteOutcome) async -> Bool {
        working = true
        defer { working = false }
        do {
            switch try await make() {
            case .needsConfirmation(let p):
                // 送出回覆：按「送出」就是確認了，不再跳一次確認（接手、結案這些動作照樣確認）
                if reply, p.typed == nil, !p.danger {
                    switch try await model.api.confirm(p, typed: nil) {
                    case .done(let result):
                        announceReply(result)
                        await load()
                        Task { await model.refreshAll() }
                        return true
                    case .needsOwner(let next):
                        replying = true
                        proposal = next
                        return false
                    }
                }
                replying = reply
                proposal = p
                return false
            case .done:
                if reply { draft = "" }
                model.show("已更新")
                await load()
                return true
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
            return false
        }
    }
}

// MARK: - 對話的一列一列

/// 對話排成一列一列：日期、事件、訊息（同一個人五分鐘內連著說的合成一組：第一則放名字與時間，客人的第一則放頭像）
enum ChatEntry: Identifiable {
    case day(Date)
    case event(XenaConversationMessage)
    case message(XenaConversationMessage, first: Bool, last: Bool)

    var id: String {
        switch self {
        case .day(let d): "day-\(Int(d.timeIntervalSince1970))"
        case .event(let m), .message(let m, _, _): "m-\(m.id)"
        }
    }

    static func build(_ messages: [XenaConversationMessage]) -> [ChatEntry] {
        var out: [ChatEntry] = []
        var day: Date?
        for (i, m) in messages.enumerated() {
            if let at = m.at {
                let d = Calendar.taipei.startOfDay(for: at)
                if d != day {
                    out.append(.day(d))
                    day = d
                }
            }
            if m.role == "event" {
                out.append(.event(m))
                continue
            }
            let previous = i > 0 ? messages[i - 1] : nil
            let next = i + 1 < messages.count ? messages[i + 1] : nil
            out.append(.message(m, first: !sameRun(previous, m), last: !sameRun(m, next)))
        }
        return out
    }

    /// 同一個人、同一天、隔不到 5 分鐘
    private static func sameRun(_ a: XenaConversationMessage?, _ b: XenaConversationMessage?) -> Bool {
        guard let a, let b, a.role == b.role, a.role != "event", a.author == b.author else { return false }
        guard let ta = a.at, let tb = b.at else { return true }
        return abs(tb.timeIntervalSince(ta)) < 300 && Calendar.taipei.isDate(ta, inSameDayAs: tb)
    }
}

/// 泡泡的形狀：一組的第一則靠說話的人那一側的上角是尖的（像 LINE）
private func bubbleShape(mine: Bool, first: Bool) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        topLeadingRadius: !mine && first ? 5 : 18,
        bottomLeadingRadius: 18,
        bottomTrailingRadius: 18,
        topTrailingRadius: mine && first ? 5 : 18,
        style: .continuous
    )
}

/// 一則訊息：客人在左、Xena 與專人在右
private struct XenaChatRow: View {
    let message: XenaConversationMessage
    let first: Bool
    let last: Bool
    let who: String
    let picture: URL?
    let site: String
    let siteURL: URL?
    let open: (ViewedMedia) -> Void

    var body: some View {
        if message.role == "user" { customer } else { ours }
    }

    // MARK: 客人

    private var customer: some View {
        HStack(alignment: .top, spacing: 8) {
            if first {
                Avatar(name: who, imageURL: picture, size: 30)
            } else {
                Color.clear.frame(width: 30, height: 1)
            }
            VStack(alignment: .leading, spacing: 5) {
                if first, let at = message.at {
                    Text(at.clockText)
                        .font(.brand(11.5, .regular, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                VisitorContent(text: message.content, first: first, open: open)
                if let jev = message.jevHuman, jev.yes {
                    Label("Jev 判斷要找人（\(Int((jev.confidence * 100).rounded()))%）", systemImage: "exclamationmark.bubble.fill")
                        .font(.brand(11.5, .medium, relativeTo: .caption))
                        .foregroundStyle(Theme.warningFG)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .contextMenu { menu }
        }
        .padding(.trailing, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Xena、專人

    private var xena: Bool { message.role == "assistant" }

    private var ours: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if first { oursHeader }
            if !message.content.isEmpty, !message.isOnlyCardLabel {
                Text(markdown(message.content))
                    .textRole(.body)
                    .foregroundStyle(xena ? Theme.ink : Theme.onPrimary)
                    .tint(xena ? Theme.accentText : Theme.onPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(xena ? Theme.surface : Theme.primary, in: bubbleShape(mine: true, first: first))
                    .overlay {
                        if xena {
                            bubbleShape(mine: true, first: first)
                                .strokeBorder(Theme.xenaGradient, lineWidth: 1)
                                .opacity(0.55)
                        }
                    }
                    .contextMenu { menu }
            }
            if let nav = message.navigate {
                NavigateChip(title: nav.title, url: URL(string: nav.path, relativeTo: siteURL)?.absoluteURL)
            }
            if let card = message.card {
                StaffCardView(card: card)
            }
            if !message.products.isEmpty {
                ProductPicks(site: site, products: message.products)
            }
            if message.emailed {
                Text("也寄了 Email 給客人")
                    .font(.brand(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: 520, alignment: .trailing)
        .padding(.leading, 48)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var oursHeader: some View {
        HStack(spacing: 5) {
            if xena {
                Circle()
                    .fill(AngularGradient(colors: [Theme.xenaPink, Theme.xenaViolet, Theme.xenaCyan, Theme.xenaPink], center: .center))
                    .frame(width: 9, height: 9)
                Text("Xena").foregroundStyle(Theme.ink2)
            } else {
                Text(message.author ?? "專人").foregroundStyle(Theme.ink2)
            }
            if let at = message.at {
                Text(at.clockText).foregroundStyle(Theme.muted)
            }
        }
        .font(.brand(11.5, .medium, relativeTo: .caption))
    }

    @ViewBuilder
    private var menu: some View {
        Button("複製", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = message.role == "user" ? VisitorContent.plain(message.content) : message.content
        }
        if message.role == "user", message.tag != nil || message.jevHuman != nil {
            let parts = [message.tag, message.jevHuman.map { "找人 \(Int(($0.confidence * 100).rounded()))%" }].compactMap { $0 }
            Text("Jev：\(parts.joined(separator: "・"))")
        }
    }
}

/// 送出中的回覆（淡一點）
private struct PendingReply: View {
    let text: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(text)
                .textRole(.body)
                .foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.primary, in: bubbleShape(mine: true, first: true))
                .opacity(0.55)
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("傳送中…")
            }
            .font(.brand(11, .regular, relativeTo: .caption2))
            .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: 520, alignment: .trailing)
        .padding(.leading, 48)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - 客人傳來的內容

/// 客人說的話，一行一行看：LINE 傳來的照片、貼圖顯示圖（點開全螢幕），影片、語音可以播，檔案、位置可以打開，
/// 語音轉成的文字跟在下面，其他照原樣（網址可以點）。
/// 「[圖片] 網址」「[貼圖：開心] 網址」「[影片 12 秒] 網址」「[語音 8 秒] 網址」「[檔案] 名稱 網址」「[位置] 地址 網址」
struct VisitorContent: View {
    let text: String
    var first = true
    let open: (ViewedMedia) -> Void

    @Environment(\.openURL) private var openURL

    /// 一則裡的一段
    struct Part: Identifiable {
        enum Kind {
            case photo(URL)
            case sticker(URL)
            /// 影片、語音（App 裡播）；檔案、位置（kind 是 nil：交給系統打開）
            case media(ViewedMedia.Kind?, title: String, url: URL, location: Bool)
            /// 客人傳了東西，但原檔沒有存下來（舊的訊息、網站當時沒開圖片儲存）
            case missing(String)
            /// 語音轉成的文字
            case transcript(String)
            case text(String)
        }

        let id: Int
        let kind: Kind

        /// 照片、貼圖：不用包泡泡
        var isPicture: Bool {
            switch kind {
            case .photo, .sticker: true
            default: false
            }
        }
    }

    static func parse(_ text: String) -> [Part] {
        var parts: [Part] = []
        var paragraph: [String] = []
        func add(_ kind: Part.Kind) { parts.append(Part(id: parts.count, kind: kind)) }
        func flush() {
            let s = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { add(.text(s)) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "［", with: "[")
                .replacingOccurrences(of: "］", with: "]")
            if line.hasPrefix("["), let close = line.firstIndex(of: "]"), let kind = attachment(label: String(line[line.index(after: line.startIndex)..<close]), rest: String(line[line.index(after: close)...])) {
                flush()
                add(kind)
                continue
            }
            if let said = line.wholeMatch(of: /（語音內容：(.+)）/) {
                flush()
                add(.transcript(String(said.1)))
                continue
            }
            paragraph.append(raw)
        }
        flush()
        return parts
    }

    /// 「[標籤] … https://…」：標籤後面可能有檔名、地址，最後是網址；沒有網址的是原檔沒存下來（舊的訊息有「（沒有存下來：…）」）
    private static func attachment(label: String, rest raw: String) -> Part.Kind? {
        var rest = raw.trimmingCharacters(in: .whitespaces)
        var url: URL?
        let start = rest.lastIndex(of: " ").map { rest.index(after: $0) } ?? (rest.hasPrefix("https://") ? rest.startIndex : nil)
        if let start, let u = URL(string: String(rest[start...])), u.scheme == "https" {
            url = u
            rest = String(rest[..<start]).trimmingCharacters(in: .whitespaces)
        }
        let lost = url == nil && (rest.isEmpty || rest.hasPrefix("（沒有存下來"))
        if label == "圖片" {
            if let url { return .photo(url) }
            return lost ? .missing("照片沒有存下來") : nil
        }
        if label.hasPrefix("貼圖") {
            if let url { return .sticker(url) }
            return .text("［\(label)］")
        }
        if label.hasPrefix("影片") || label.hasPrefix("語音") {
            let video = label.hasPrefix("影片")
            if let url { return .media(video ? ViewedMedia.Kind.video : ViewedMedia.Kind.audio, title: label, url: url, location: false) }
            return lost ? .missing(video ? "影片沒有存下來" : "語音沒有存下來") : nil
        }
        if label.hasPrefix("檔案") {
            if let url { return .media(nil, title: rest.isEmpty ? "檔案" : rest, url: url, location: false) }
            return lost ? .missing("檔案沒有存下來") : nil
        }
        if label.hasPrefix("位置"), let url {
            return .media(nil, title: rest.isEmpty ? "位置" : rest, url: url, location: true)
        }
        return nil
    }

    /// 複製用：網址、系統附註拿掉
    static func plain(_ text: String) -> String {
        parse(text).map { part in
            switch part.kind {
            case .photo: "［照片］"
            case .sticker: "［貼圖］"
            case .media(_, let title, _, _): "［\(title)］"
            case .missing(let s): "［\(s)］"
            case .transcript(let s): "（語音內容：\(s)）"
            case .text(let s): s
            }
        }.joined(separator: "\n")
    }

    var body: some View {
        let parts = Self.parse(text)
        if !parts.isEmpty, parts.allSatisfy(\.isPicture) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(parts) { part($0) }
            }
        } else {
            let shape = bubbleShape(mine: false, first: first)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(parts) { part($0) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface, in: shape)
            .overlay { shape.strokeBorder(Theme.line, lineWidth: 1) }
        }
    }

    @ViewBuilder
    private func part(_ part: Part) -> some View {
        switch part.kind {
        case .photo(let url):
            PhotoThumb(url: url) { open(ViewedMedia(url: url, kind: .photo)) }
        case .sticker(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: 110, height: 110, alignment: .leading)
            .accessibilityLabel("客人傳的貼圖")
        case .media(let kind, let title, let url, let location):
            MediaRow(kind: kind, title: title, location: location) {
                if let kind { open(ViewedMedia(url: url, kind: kind)) } else { openURL(url) }
            }
        case .missing(let text):
            MissingMedia(text: text)
        case .transcript(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Text(text)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
            }
            .accessibilityLabel("語音內容：\(text)")
        case .text(let s):
            Text(Self.linked(s))
                .textRole(.body)
                .foregroundStyle(Theme.ink)
                .tint(Theme.accentText)
        }
    }

    /// 網址可以點
    static func linked(_ s: String) -> AttributedString {
        var out = AttributedString(s)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return out }
        for match in detector.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let url = match.url, let r = Range(match.range, in: s), let ar = Range(r, in: out) else { continue }
            out[ar].link = url
        }
        return out
    }
}

/// 客人傳的照片：照比例的縮圖（長邊最多 240、高最多 300），點了全螢幕
private struct PhotoThumb: View {
    let url: URL
    let action: () -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                let size = Self.fit(image.size)
                Button(action: action) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
                }
                .buttonStyle(.press)
                .accessibilityLabel("客人傳的照片，點一下放大")
                .transition(.opacity)
            } else if failed {
                // 網站沒開圖片儲存時是向 LINE 拿的：LINE 刪掉之後就拿不到了
                MissingMedia(text: "照片載入不了（LINE 只保留一段時間）")
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.soft)
                    .frame(width: 220, height: 165)
                    .shimmer()
            }
        }
        .task(id: url) {
            let loaded = await ChatImages.thumbnail(url)
            withAnimation(Motion.fast) {
                image = loaded
                failed = loaded == nil
            }
        }
    }

    static func fit(_ s: CGSize) -> CGSize {
        guard s.width > 0, s.height > 0 else { return CGSize(width: 220, height: 165) }
        let scale = min(240 / s.width, 300 / s.height, 1)
        return CGSize(width: max((s.width * scale).rounded(), 72), height: max((s.height * scale).rounded(), 72))
    }
}

/// 對話裡的照片：下載一次、縮成畫面用得到的大小（原圖可能是 1200 萬畫素），捲來捲去不會重抓
enum ChatImages {
    private static let cache = NSCache<NSURL, UIImage>()

    static func thumbnail(_ url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let result = try? await URLSession.shared.data(from: url) else { return nil }
        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let full = UIImage(data: data) else { return nil }
        let longest = max(full.size.width, full.size.height, 1)
        let scale = min(1, 900 / longest)
        let target = CGSize(width: (full.size.width * scale).rounded(), height: (full.size.height * scale).rounded())
        let thumb = await full.byPreparingThumbnail(ofSize: target) ?? full
        cache.setObject(thumb, forKey: url as NSURL)
        return thumb
    }
}

/// 影片、語音、檔案、位置：一列（圖示、名稱、要做什麼）
private struct MediaRow: View {
    let kind: ViewedMedia.Kind?
    let title: String
    var location = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSoft, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.brand(14.5, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text(hint)
                        .font(.brand(11.5, .regular, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
    }

    private var icon: String {
        switch kind {
        case .video: "play.fill"
        case .audio: "waveform"
        case .photo: "photo"
        case nil: location ? "mappin.and.ellipse" : "doc.fill"
        }
    }

    private var hint: String {
        switch kind {
        case .video, .audio: "點一下播放"
        case .photo: "點一下放大"
        case nil: location ? "在地圖打開" : "點一下打開"
        }
    }
}

/// 看不到的照片、影片：一塊淡底、一個圖示、一句說明
struct MissingMedia: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "photo")
            .textRole(.small)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.soft, in: .rect(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 我們這邊附的東西

/// Xena 帶客人去的頁面（客人在 LINE 上看到的是一顆按鈕；網站上是直接帶過去）
private struct NavigateChip: View {
    let title: String
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { if let url { openURL(url) } } label: {
            HStack(spacing: 6) {
                HeroIcon("arrow-top-right-on-square", size: 13)
                Text("帶客人看：\(title)")
                    .lineLimit(1)
            }
            .font(.brand(12.5, .medium, relativeTo: .caption))
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.press)
        .disabled(url == nil)
    }
}

/// 專人附的行銷卡片：照客人在 LINE 上看到的畫（大圖、標題、說明、優惠碼、按鈕）
private struct StaffCardView: View {
    let card: StaffCard
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = card.imageURL {
                AsyncImage(url: image) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Theme.soft
                    }
                }
                .frame(height: 136)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.brand(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                if let text = card.body {
                    Text(text)
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(6)
                }
                if let code = card.couponCode { coupon(code) }
                Button { if let url = card.url { openURL(url) } } label: {
                    Text(card.buttonLabel ?? "看看")
                        .font(.brand(14, .semibold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Theme.primary, in: .rect(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.press)
                .disabled(card.url == nil)
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: 264)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("附上的卡片：\(card.title)")
    }

    private func coupon(_ code: String) -> some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            HStack(spacing: 8) {
                HeroIcon("ticket", size: 15)
                    .foregroundStyle(Theme.accentText)
                Text(code)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                Text(copied ? "已複製" : "複製")
                    .font(.brand(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accentText.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .haptic(.success, trigger: copied) { _, new in new }
        .accessibilityLabel("優惠碼 \(code)，點一下複製")
    }
}

/// 專人推薦的商品（LINE 上是左右滑的商品卡片）：點了打開那個商品
private struct ProductPicks: View {
    let site: String
    let products: [(name: String, slug: String)]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("推薦的商品")
                .font(.brand(11, .medium, relativeTo: .caption2))
                .foregroundStyle(Theme.muted)
            FlowLayout(spacing: 6) {
                ForEach(Array(products.enumerated()), id: \.offset) { _, p in
                    NavigationLink(value: Route.record(site: site, entity: "product", id: p.slug)) {
                        HStack(spacing: 5) {
                            HeroIcon("shopping-bag", size: 13)
                            Text(p.name).lineLimit(1)
                        }
                        .font(.brand(12.5, .medium, relativeTo: .caption))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface, in: .capsule)
                        .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
                    }
                    .buttonStyle(.press)
                    .disabled(p.slug.isEmpty)
                }
            }
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }
}

// MARK: - 事件、日期

/// 對話裡發生的事（通知專人、接手、交還、結案）：置中的一顆小膠囊，用專人看得懂的話說；
/// 通知專人的那一則下面放轉真人的原因
struct ChatEventRow: View {
    let message: XenaConversationMessage
    var reason: String?
    @State private var expanded = false

    /// 舊的網站沒給種類：從客人看到的那句話猜
    static func kind(of m: XenaConversationMessage) -> String {
        if let e = m.event, !e.isEmpty { return e }
        let c = m.content
        if c.contains("通知專人") || c.contains("通知真人") || c.contains("找專人") { return "handoff" }
        if c.contains("接手") { return "takeover" }
        if c.contains("Xena 繼續") || c.contains("交還") { return "release" }
        if c.contains("重新開啟") { return "reopened" }
        if c.contains("結束") || c.contains("結案") { return "closed" }
        return "other"
    }

    private var described: (icon: String, text: String) {
        switch Self.kind(of: message) {
        case "handoff": (icon: "bell.fill", text: "Xena 通知了專人")
        case "takeover": (icon: "person.fill.checkmark", text: "\(message.author ?? "專人")接手了")
        case "release": (icon: "sparkles", text: "交給 Xena 繼續回答")
        case "closed": (icon: "checkmark.circle.fill", text: "結案")
        case "reopened": (icon: "arrow.uturn.backward.circle", text: "重新開啟")
        case "contact": (icon: "envelope.fill", text: "客人留了聯絡資料")
        case "login": (icon: "person.crop.circle.badge.checkmark", text: "客人登入了")
        case "logout": (icon: "rectangle.portrait.and.arrow.right", text: "客人登出了")
        default: (icon: "info.circle", text: message.content)
        }
    }

    var body: some View {
        let d = described
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: d.icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(d.text)
                    .lineLimit(2)
                if let at = message.at {
                    Text(at.clockText).foregroundStyle(Theme.faint)
                }
            }
            .font(.brand(12, .medium, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Theme.press, in: .capsule)
            if let reason, !reason.isEmpty {
                Button { withAnimation(Motion.fast) { expanded.toggle() } } label: {
                    Text("原因：\(reason)")
                        .font(.brand(12, .regular, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(expanded ? nil : 2)
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityHint(message.content)
    }
}

/// 跨天的日期：今天、昨天、10月2日 星期五
struct ChatDayDivider: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.brand(11.5, .medium, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.press, in: .capsule)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    private var label: String {
        let cal = Calendar.taipei
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) { return date.dayTitle }
        return date.dayText
    }
}

// MARK: - 最上面：這是誰

/// 對話最上面：頭像、名字、從哪裡來、聊了哪些類別；同一位 LINE 好友之前的對話
private struct ConversationIntro: View {
    let detail: XenaConversationDetail
    let siteName: String
    let site: String

    private var name: String { detail.who ?? (detail.channel == .line ? "LINE 好友" : "網站訪客") }

    var body: some View {
        VStack(spacing: 6) {
            Avatar(name: name, imageURL: detail.picture, size: 58)
                .padding(.bottom, 4)
            Text(name)
                .font(.brand(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                if detail.visitorOnline {
                    LiveDot()
                    Text("正在網站上・")
                }
                Text(origin)
            }
            .font(.brand(12.5, .regular, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            if !detail.topics.isEmpty {
                Text(detail.topics.prefix(6).joined(separator: "・"))
                    .font(.brand(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Theme.faint)
            }
            if detail.lineBlocked {
                StatusBadge("封鎖了官方帳號，回覆傳不到他的 LINE", tone: .danger)
                    .padding(.top, 4)
            }
            if !detail.orders.isEmpty {
                orders.padding(.top, 14)
            }
            if !detail.earlier.isEmpty {
                earlier.padding(.top, detail.orders.isEmpty ? 14 : 10)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// 會員最近的訂單（客人問到貨、退換貨時不用離開對話）
    private var orders: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近的訂單")
                .font(.brand(11.5, .medium, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 4)
            ForEach(detail.orders.prefix(3)) { o in
                NavigationLink(value: Route.order(site: site, id: o.id)) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(o.number)")
                                .font(.brand(14, .medium).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                            Text(o.items)
                                .font(.brand(11.5, .regular, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(o.totalLabel)
                                .font(.brand(14, .medium).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                            Text(o.statusLabel)
                                .font(.brand(11.5, .regular, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 9)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.row)
            }
        }
        .panel(padding: 14, radius: 14)
    }

    private var origin: String {
        var parts = [detail.channel == .line ? "LINE" : "官網", siteName]
        if let at = detail.startedAt { parts.append("\(at.shortText) 開始") }
        return parts.joined(separator: "・")
    }

    private var earlier: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("之前的對話")
                .font(.brand(11.5, .medium, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 4)
            ForEach(detail.earlier) { e in
                NavigationLink(value: Route.xenaConversation(site: site, id: e.id)) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.firstQuestion.map(VisitorPreview.text) ?? "一段對話")
                                .font(.brand(14, .medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text([e.startedAt?.shortText, e.statusLabel].compactMap { $0 }.joined(separator: "・"))
                                .font(.brand(11.5, .regular, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        HeroIcon("chevron-right", size: 14)
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(.vertical, 9)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.row)
            }
        }
        .panel(padding: 14, radius: 14)
    }
}

// MARK: - 回覆框

/// 聊天的回覆框：左邊請 Xena 幫忙擬、中間打字（會長高）、右邊送出；打字時上面一行說回覆會送到哪裡
struct ChatComposer<Accessory: View>: View {
    @Binding var text: String
    let placeholder: String
    var hint: String?
    var hintWarning: Bool
    var sending: Bool
    var draftWithXena: (() -> Void)?
    let send: () -> Void
    let accessory: Accessory

    @FocusState private var focused: Bool

    init(
        text: Binding<String>, placeholder: String, hint: String? = nil, hintWarning: Bool = false, sending: Bool = false,
        draftWithXena: (() -> Void)? = nil, send: @escaping () -> Void, @ViewBuilder accessory: () -> Accessory
    ) {
        _text = text
        self.placeholder = placeholder
        self.hint = hint
        self.hintWarning = hintWarning
        self.sending = sending
        self.draftWithXena = draftWithXena
        self.send = send
        self.accessory = accessory()
    }

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if focused || !text.isEmpty || hintWarning, let hint, !hint.isEmpty {
                Label(hint, systemImage: hintWarning ? "exclamationmark.triangle.fill" : "arrow.turn.down.right")
                    .font(.brand(11.5, .regular, relativeTo: .caption))
                    .foregroundStyle(hintWarning ? Theme.dangerFG : Theme.muted)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
            accessory
            HStack(alignment: .bottom, spacing: 8) {
                if let draftWithXena {
                    Button(action: draftWithXena) {
                        HeroIcon("sparkles", size: 19)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 40, height: 40)
                            .background(Theme.surface, in: .circle)
                            .overlay { Circle().strokeBorder(Theme.line) }
                    }
                    .buttonStyle(PressScale(scale: 0.92))
                    .accessibilityLabel("請 Xena 擬回覆")
                }
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...8)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(focused ? Theme.ink.opacity(0.3) : Theme.line, lineWidth: 1)
                    }
                Button(action: send) {
                    Group {
                        if sending {
                            ProgressView().tint(Theme.onPrimary)
                        } else {
                            HeroIcon("arrow-up", size: 18)
                        }
                    }
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.primary, in: .circle)
                }
                .buttonStyle(PressScale(scale: 0.92))
                .disabled(empty || sending)
                .opacity(empty && !sending ? 0.35 : 1)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("送出")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.sheet)
        .overlay(alignment: .top) { Rule() }
        .animation(Motion.fast, value: focused)
    }
}

extension ChatComposer where Accessory == EmptyView {
    init(
        text: Binding<String>, placeholder: String, hint: String? = nil, hintWarning: Bool = false, sending: Bool = false,
        draftWithXena: (() -> Void)? = nil, send: @escaping () -> Void
    ) {
        self.init(text: text, placeholder: placeholder, hint: hint, hintWarning: hintWarning, sending: sending, draftWithXena: draftWithXena, send: send) { EmptyView() }
    }
}

/// 捲在上面時：右下角回到最新（有新訊息時標數字）
private struct JumpToLatest: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                HeroIcon("chevron-down", size: 15)
                if count > 0 {
                    Text("\(count)").font(.brand(13, .semibold)).monospacedDigit()
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, count > 0 ? 12 : 0)
            .frame(minWidth: 38, minHeight: 38)
            .background(Theme.surface, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(PressScale(scale: 0.92))
        .accessibilityLabel(count > 0 ? "\(count) 則新訊息，捲到最新" : "捲到最新")
    }
}

// MARK: - 全螢幕看照片、播影片與語音

struct ViewedMedia: Identifiable {
    enum Kind { case photo, video, audio }
    let id = UUID()
    let url: URL
    let kind: Kind
}

/// 客人傳的照片（可以放大、拖曳、往下拉關掉、分享或存起來）；影片與語音直接播
struct MediaViewer: View {
    let media: ViewedMedia

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch media.kind {
            case .photo:
                if let image {
                    ZoomableImage(image: image) { dismiss() }
                } else if failed {
                    unavailable("照片載入不了（LINE 只保留一段時間）")
                } else {
                    ProgressView().tint(.white)
                }
            case .video, .audio:
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay {
                            if media.kind == .audio {
                                Image(systemName: "waveform")
                                    .font(.system(size: 64, weight: .light))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
        .overlay(alignment: .top) { bar }
        .statusBarHidden()
        .task { await prepare() }
        .onDisappear { player?.pause() }
    }

    private var bar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("關閉")
            Spacer()
            if let image {
                let picture = Image(uiImage: image)
                ShareLink(item: picture, preview: SharePreview("客人傳的照片", image: picture)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("分享或儲存照片")
            } else if media.kind != .photo {
                ShareLink(item: media.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("分享")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func unavailable(_ text: String) -> some View {
        Label(text, systemImage: "photo")
            .font(.brand(14, .medium))
            .foregroundStyle(.white.opacity(0.7))
            .padding(24)
    }

    private func prepare() async {
        switch media.kind {
        case .photo:
            do {
                let (data, response) = try await URLSession.shared.data(from: media.url)
                let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
                if ok, let img = UIImage(data: data) { image = img } else { failed = true }
            } catch {
                failed = true
            }
        case .video, .audio:
            let p = AVPlayer(url: media.url)
            player = p
            p.play()
        }
    }
}

/// 可以兩指放大、拖曳、點兩下放大縮小；沒放大時往下拉就關掉
private struct ZoomableImage: View {
    let image: UIImage
    let close: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .opacity(scale <= 1 ? 1 - min(abs(offset.height) / 600, 0.5) : 1)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(max(lastScale * v.magnification, 1), 5) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { withAnimation(Motion.fast) { reset() } }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { v in
                            offset = scale > 1
                                ? CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                                : CGSize(width: 0, height: v.translation.height)
                        }
                        .onEnded { v in
                            if scale > 1 {
                                lastOffset = offset
                            } else if abs(v.translation.height) > 120 {
                                close()
                            } else {
                                withAnimation(Motion.fast) { offset = .zero }
                            }
                        })
            )
            .onTapGesture(count: 2) {
                withAnimation(Motion.spring) {
                    if scale > 1 {
                        reset()
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
            .accessibilityLabel("客人傳的照片")
            .accessibilityAddTraits(.isImage)
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
