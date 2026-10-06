import SwiftUI
import UIKit

/// 收件匣：所有網站、所有管道（官網、LINE、Email、聯絡表單）的客服放在同一個清單，最近有動靜的在前，
/// 結束了的也在（往下捲載入更早的，見 InboxHistory）。上面一排篩選：全部、要你處理（等專人的對話、
/// 客人在等回覆的信、新的詢問，等最久的在上面）、各管道；右上角的放大鏡搜尋客人與內容。
/// 每一列標出來源、Jev 判斷的類別（訂單、收貨問題、費用報價…）和現在的狀態。iPad：左邊清單、右邊內容。
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                InboxList(picked: Bindable(model).inboxPicked)
                    .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 480)
                    .splitListColumn()
            } detail: {
                NavigationStack(path: Bindable(model).inboxPath) {
                    Group {
                        if let picked = model.inboxPicked {
                            RouteView(route: picked).id(picked)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("選一段對話")
                                    .textRole(.h2)
                                    .foregroundStyle(Theme.ink)
                                Text("從左邊選一段對話、一封信或一筆詢問。")
                                    .textRole(.small)
                                    .foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .brandPage()
                        }
                    }
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .brandSplitView()
            }
        } else {
            NavigationStack(path: Bindable(model).inboxPath) {
                InboxList(picked: nil)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        }
    }
}

// MARK: - 收件匣的一列（不管是 Xena 對話、客服信、詢問還是信）

struct InboxItem: Identifiable {
    enum Source {
        case line, web, email, form

        var label: String {
            switch self {
            case .line: "LINE"
            case .web: "官網"
            case .email: "Email"
            case .form: "表單"
            }
        }
    }

    let id: String
    var site: String
    var route: Route
    var name: String
    var picture: URL?
    var text: String
    /// 最近的動靜
    var at: Date?
    /// 從什麼時候開始等（要你處理的照這個排：等最久的在上面）
    var since: Date?
    var source: Source
    /// 類別（Jev 自動判斷的；客服信是它的問題分類）
    var topic: String?
    /// 這一列要特別說的狀態（客人又傳了訊息、留了聯絡資料、未讀）；分段已經說了的不重複
    var status: (text: String, tone: Tone)?
    /// 其他標籤（訂單編號、附件）
    var extra: (text: String, tone: Tone)?
    /// Xena 這幾分鐘還在回答
    var live = false

    /// Xena 的對話；needsYou：放在「要你處理」（狀態說為什麼要你）
    init(_ c: XenaConversationSummary, needsYou: Bool = false) {
        id = "xena|\(c.key)"
        site = c.site
        route = .xenaConversation(site: c.site, id: c.id)
        name = c.contactName ?? (c.channel == .line ? "LINE 好友" : "訪客")
        picture = c.picture
        text = c.preview ?? c.firstQuestion ?? "（\(c.turns) 句對話）"
        at = c.at
        since = c.at
        source = c.channel == .line ? .line : .web
        topic = c.topic
        // 等專人的不用再說（在「要你處理」裡就是在等你）
        if needsYou && c.status != "waiting" {
            status = (text: c.attentionLabel, tone: Tone.gold)
        }
        live = c.status == "ai" && (c.at.map { Date.now.timeIntervalSince($0) < 180 } ?? false)
    }

    /// 客服信（客人在等回覆）
    init(_ t: SupportThreadSummary) {
        id = "thread|\(t.key)"
        site = t.site
        route = .thread(site: t.site, id: t.id)
        name = t.customer
        text = t.subject
        since = t.waitingHours.map { Date.now.addingTimeInterval(-$0 * 3600) }
        at = since
        source = .email
        topic = t.categoryLabel.isEmpty ? nil : t.categoryLabel
        extra = t.orderNumber.map { (text: "#\($0)", tone: Tone.gold) }
    }

    /// 專案詢問（聯絡表單）
    init(_ q: InquirySummary) {
        id = "inquiry|\(q.key)"
        site = q.site
        route = .inquiry(site: q.site, id: q.id)
        name = [q.name, q.company].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "・")
        text = q.message ?? q.types.joined(separator: "、")
        at = q.at
        since = q.at
        source = .form
        topic = "專案詢問"
        extra = q.budget.map { (text: $0, tone: Tone.neutral) }
    }

    /// 信箱裡還沒分的信
    init(_ m: MailSummary) {
        id = "mail|\(m.id)"
        site = m.site
        route = .record(site: m.site, entity: "mailbox", id: m.row.id)
        name = m.row.raw["from"]?.string ?? "寄件人"
        text = m.row.title
        at = m.row.date
        since = m.row.date
        source = .email
        topic = "信件"
        if m.row.raw["unread"]?.bool == true { status = (text: "未讀", tone: Tone.gold) }
        if let n = m.row.raw["attachmentCount"]?.int, n > 0 { extra = (text: "附件 \(n)", tone: Tone.neutral) }
    }
}

/// 首頁的待辦裡「要你處理」的那幾件（收件匣的「要你處理」篩選）
struct InboxSections {
    var needsYou: [InboxItem] = []

    init(_ b: Briefing) {
        // 同一段對話可能同時在兩份清單裡（例如剛轉給專人）：留第一次看到的
        var seen = Set<String>()
        let xena = (b.handoffs + b.live).filter { seen.insert($0.key).inserted }
        // 等專人的對話（舊資料掛著客服信的，在客服信那邊處理，網站給的 attention 是 false）、
        // 專人接手後客人又說話、Xena 回答中但客人留了聯絡資料
        let xenaNeeds = xena.filter(\.attention).map { InboxItem($0, needsYou: true) }
        needsYou = (xenaNeeds + b.awaiting.map { InboxItem($0) } + b.inquiries.map { InboxItem($0) })
            .sorted { ($0.since ?? .distantFuture) < ($1.since ?? .distantFuture) }
    }
}

// MARK: - 清單

struct InboxList: View {
    var picked: Binding<Route?>?

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// 搜尋（右上角的放大鏡打開；打字停一下才去搜）
    @State private var search = ""
    @State private var searching = false
    /// 寫一封新信（右上角的筆）
    @State private var composing = false

    /// 有網站可以從 App 寄新信（網站後台有 send_email）
    private var canCompose: Bool { model.sites.contains { $0.tools.contains("send_email") } }

    private var composeButton: some View {
        Button { composing = true } label: {
            HeroIcon("pencil-square", size: 19)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .foregroundStyle(Theme.ink)
        .accessibilityLabel("寫信")
        .keyboardShortcut("n", modifiers: .command)
    }

    var body: some View {
        let b = model.briefing
        let needsYou = InboxSections(b).needsYou
        let history = model.inboxHistory
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader("收件匣", subtitle: summary(needsYou, live: b.live.filter { $0.status == "ai" }.count)) {
                        // iPad 的分欄沒有導覽列：筆、放大鏡放在大標旁邊
                        if picked != nil {
                            HStack(spacing: 14) {
                                if canCompose { composeButton }
                                SearchToggle(shown: $searching, text: $search)
                            }
                        }
                    }
                    if searching {
                        SearchField(text: $search, prompt: "搜尋客人、Email、對話內容", autofocus: true)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                InboxFeedList(history: history, needsYou: needsYou) { item, waiting in
                    open(item.route) {
                        InboxRow(item: item, waiting: waiting, site: model.sites.count > 1 ? model.site(item.site) : nil)
                    }
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { [model] in
            await Task {
                async let all: Void = model.refreshAll()
                async let list: Void = model.inboxHistory.restart(sites: model.sites)
                _ = await (all, list)
            }.value
        }
        .brandPage()
        .pageTitle("收件匣")
        .toolbar {
            if picked == nil {
                if canCompose {
                    ToolbarItem(placement: .topBarTrailing) { composeButton }
                }
                ToolbarItem(placement: .topBarTrailing) { SearchToggle(shown: $searching, text: $search) }
            }
        }
        .sheet(isPresented: $composing) { ComposeEmailView() }
        // 第一次打開才載
        .task {
            guard !history.loaded, !history.loading else { return }
            await history.restart(sites: model.sites)
        }
        // 別的頁面要搜的字（會員頁、搜尋頁）
        .onChange(of: model.inboxSearch, initial: true) { _, q in
            guard let q else { return }
            searching = true
            search = q
            model.inboxSearch = nil
        }
        // 搜尋：打字停 0.35 秒才去搜（清掉也是重新載）
        .task(id: search) {
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q != history.query else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await history.restart(sites: model.sites, query: q)
        }
        // 首頁的待辦更新了（每分鐘、通知進來、下拉）：清單最上面也拿一次新的
        .onChange(of: b.updatedAt) {
            Task { await history.refreshHead() }
        }
        // 開著收件匣時每分鐘更新一次（Xena 正在回答的對話、新進來的客人）
        .task(id: scenePhase) {
            guard scenePhase == .active, !DemoServer.screenshots else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                await model.briefing.refresh(sites: model.sites)
            }
        }
    }

    private func summary(_ needsYou: [InboxItem], live: Int) -> String? {
        guard model.briefing.updatedAt != nil else { return nil }
        var parts = [needsYou.isEmpty ? "沒有要你處理的事" : "\(needsYou.count) 件要你處理"]
        if live > 0 { parts.append("Xena 回答中 \(live) 段") }
        return parts.joined(separator: "・")
    }

    /// 點一列：手機推下一頁，iPad 在右邊打開
    @ViewBuilder
    private func open<Label: View>(_ route: Route, @ViewBuilder label: () -> Label) -> some View {
        if let picked {
            Button {
                picked.wrappedValue = route
                model.inboxPath = []
            } label: {
                label()
                    .padding(.horizontal, 10)
                    .background(picked.wrappedValue == route ? Theme.accentSoft : .clear)
            }
            .buttonStyle(.row)
        } else {
            NavigationLink(value: route) { label() }
                .buttonStyle(.row)
        }
    }
}

/// 收件匣的一列：頭像、名字、哪個網站（只有一個網站時不放）、多久了；最新的一句；來源、類別、狀態
private struct InboxRow: View {
    let item: InboxItem
    /// 在「要你處理」：右上角寫等了多久（不是最後的動靜）
    var waiting = false
    let site: SiteSummary?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(name: item.name, imageURL: item.picture, size: 38)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name)
                        .textRole(.h4)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if item.live {
                        LiveDot()
                            .accessibilityLabel("Xena 正在回答")
                    }
                    Spacer(minLength: 6)
                    if let site {
                        SiteIconView(site: site, size: 16)
                            .accessibilityLabel(site.name)
                    }
                    if let when {
                        Text(when.text)
                            .textRole(.xs)
                            .foregroundStyle(when.urgent ? Theme.warningFG : Theme.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text(item.text)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // 放不下就換行，不截字
                FlowLayout(spacing: 6) {
                    StatusBadge(item.source.label, tone: item.source == .line ? .active : .neutral)
                    if let topic = item.topic { Chip(topic) }
                    if let status = item.status { StatusBadge(status.text, tone: status.tone) }
                    if let extra = item.extra { StatusBadge(extra.text, tone: extra.tone) }
                }
            }
        }
        .padding(.vertical, 16)
        .contentShape(.rect)
    }

    /// 右上角：要你處理的寫等了多久（超過一小時標橘色）；其他寫最後的動靜
    private var when: (text: String, urgent: Bool)? {
        if waiting, let since = item.since {
            let hours = Date.now.timeIntervalSince(since) / 3600
            return hours < 1 / 60 ? (text: "剛剛", urgent: false) : (text: "等了 \(Briefing.hours(hours))", urgent: hours >= 1)
        }
        return item.at.map { (text: $0.relativeText, urgent: false) }
    }
}

// MARK: - 專案詢問

/// 一筆專案詢問（網站聯絡表單送來的）：誰、哪家公司、想做什麼、預算、完整的訊息。
/// 下面的回覆框直接寄信給他（網站的 reply_inquiry，信末附上你的簽名）：寄出後詢問變成一條客服信，他回信會接回那條對話，
/// 同一個網站的客服人員都看得到、都能回。✦ 請 Xena 照詢問內容擬第一封回信。網站還沒更新時照舊用 Email App 回。
struct InquiryView: View {
    let site: String
    let inquiryID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var data: JSONValue?
    @State private var error: String?
    @State private var copied = false
    @State private var proposal: Proposal?
    @State private var working = false
    /// 下面回覆框的字、Xena 正在擬、寄出的確認
    @State private var draft = ""
    @State private var drafting = false
    @State private var sending = false
    @State private var replyProposal: Proposal?

    /// 這個網站能從 App 回覆詢問（網站後台有 reply_inquiry）
    private var canReply: Bool { model.site(site)?.tools.contains("reply_inquiry") == true }
    /// 回覆過：變成的那條客服信（之後的往來都在那裡）
    private var threadID: String? { data?["threadId"]?.string.flatMap { $0.isEmpty ? nil : $0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let data {
                    content(data)
                    statusActions(data["status"]?.string ?? "new")
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 4)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .brandPage()
        // 回覆框：直接寄信給他（信末附上你的簽名）；✦ 請 Xena 照詢問擬第一封回信（輸入框有字就當重點）
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let data, canReply, let email = data["email"]?.string {
                ChatComposer(
                    text: $draft,
                    placeholder: drafting ? "Xena 正在寫…" : threadID == nil ? "回覆 \(data["name"]?.string ?? "對方")…" : "再寫一封…",
                    hint: "寄到 \(email)・信末附上你的簽名",
                    sending: sending,
                    draftWithXena: xenaDraft,
                    sendBlocked: drafting,
                    send: sendReply
                )
            }
        }
        .toolbar(sizeClass == .regular ? .automatic : .hidden, for: .tabBar)
        .pageTitle(data?["name"]?.string ?? "專案詢問")
        .task { await load() }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { _ in
            model.show("已更新")
            Task {
                await load()
                await model.refreshAll()
            }
        }
        .confirmSheet($replyProposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            replied(result)
        }
    }

    /// Xena 照詢問內容擬第一封回信（輸入框有字就當重點）；放進輸入框，不會自己寄
    private func xenaDraft() {
        guard !drafting else { return }
        let notes = draft
        drafting = true
        Task {
            defer { drafting = false }
            do {
                let text = try await model.api.replyDraft(site: site, id: inquiryID, polish: false, text: notes, kind: "inquiry")
                withAnimation(Motion.ease) { draft = draft == notes ? text : draft + "\n\n" + text }
            } catch {
                model.show(error.localizedDescription, tone: .danger)
            }
        }
    }

    /// 寄出回覆（網站的 reply_inquiry）：先跳確認，收件人與全文攤開
    private func sendReply() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                switch try await model.api.proposeInquiryReply(site: site, inquiryID: inquiryID, body: text) {
                case .needsConfirmation(let p): replyProposal = p
                case .done(let result): replied(result)
                }
            } catch {
                model.show(error.localizedDescription, tone: .danger)
            }
        }
    }

    /// 寄出了：打開變成的那條客服信（他回信會接回那裡）
    private func replied(_ result: JSONValue) {
        let sent = result["sent"]?.array.first
        if let error = sent?["emailError"]?.string, !error.isEmpty {
            model.show("回覆存進客服信了，但信沒寄出：\(error)", tone: .danger)
        } else {
            model.show("已寄出回覆")
        }
        draft = ""
        Task {
            await load()
            await model.refreshAll()
            if let thread = sent?["threadId"]?.string ?? threadID {
                model.open(.thread(site: site, id: thread))
            }
        }
    }

    /// 回了信就標「已回覆」；不做的「封存」；封存、回過的可以改回新詢問（網站的 update inquiry，照樣先確認）
    @ViewBuilder
    private func statusActions(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("處理狀態")
            FlowLayout(spacing: 8) {
                if status != "replied" {
                    Button("標成已回覆") { Task { await setStatus("replied") } }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
                if status != "archived" {
                    Button("封存") { Task { await setStatus("archived") } }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
                if status != "new" {
                    Button("改回新詢問") { Task { await setStatus("new") } }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
            }
            .disabled(working)
        }
    }

    private func setStatus(_ status: String) async {
        working = true
        defer { working = false }
        do {
            switch try await model.api.proposeUpdate(site: site, entity: "inquiry", id: inquiryID, fields: ["status": .string(status)]) {
            case .needsConfirmation(let p): proposal = p
            case .done:
                model.show("已更新")
                await load()
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    private func load() async {
        error = nil
        do {
            data = try await model.api.get(site: site, entity: "inquiry", id: inquiryID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func content(_ d: JSONValue) -> some View {
        let name = d["name"]?.string ?? "（沒有名字）"
        let email = d["email"]?.string
        let types = (d["types"]?.array ?? []).compactMap(\.string)
        let budget = d["budget"]?.string
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(name, eyebrow: "專案詢問・\(model.site(site)?.name ?? site)", subtitle: d["company"]?.string)
            HStack(spacing: 8) {
                StatusBadge(Self.statusLabel(d["status"]?.string), tone: d["status"]?.string == "new" ? .gold : .neutral)
                if let at = d["createdAt"]?.date {
                    Text(at.relativeText)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        if !types.isEmpty || budget != nil {
            FlowLayout(spacing: 6) {
                ForEach(types, id: \.self) { Chip($0) }
                if let budget { StatusBadge(budget, tone: .gold) }
            }
        }
        if let message = d["message"]?.string, !message.isEmpty {
            Text(message)
                .textRole(.body)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
        }
        VStack(alignment: .leading, spacing: 10) {
            if let email {
                HStack(spacing: 10) {
                    Text(email)
                        .textRole(.small)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button(copied ? "已複製" : "複製") {
                        UIPasteboard.general.string = email
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                    .buttonStyle(.brand(.ghost, size: .sm))
                    .haptic(.success, trigger: copied) { _, now in now }
                }
            }
            if let path = d["sourcePath"]?.string, !path.isEmpty {
                Text("從 \(path) 送出")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }
        FlowLayout(spacing: 10) {
            if let threadID {
                Button { model.open(.thread(site: site, id: threadID)) } label: { Text("看往來的信") }
                    .buttonStyle(.brand(.primary, size: .md, arrow: true))
            } else if !canReply, let email, let mail = mailURL(email) {
                Button { openURL(mail) } label: { Text("回信") }
                    .buttonStyle(.brand(.primary, size: .md, arrow: true))
            }
            if canReply, let email, let mail = mailURL(email) {
                Button { openURL(mail) } label: { Text("用自己的 Email 回") }
                    .buttonStyle(.brand(.ghost, size: .md))
            }
            if let admin = d["adminUrl"]?.string.flatMap(URL.init(string:)) {
                Button { openURL(admin) } label: { Text("到後台 ↗") }
                    .buttonStyle(.brand(.ghost, size: .md))
            }
        }
    }

    private func mailURL(_ email: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [URLQueryItem(name: "subject", value: "Re: 你在 \(model.site(site)?.name ?? site) 的專案詢問")]
        return c.url
    }

    static func statusLabel(_ status: String?) -> String {
        switch status {
        case "replied": "已回覆"
        case "archived": "已封存"
        default: "新詢問"
        }
    }
}

/// 一封客服信：來回的訊息（和 Xena 對話同一套泡泡：客人在左、我們在右，跨天放日期）、這位客人的訂單；
/// 回信（寄給客人）按送出就寄，結案先出網站的確認
struct SupportThreadView: View {
    let site: String
    let threadID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var detail: SupportThreadDetail?
    @State private var error: String?
    @State private var draft = ""
    @State private var closeAfter = false
    @State private var proposal: Proposal?
    @State private var working = false
    /// Xena 正在寫回覆
    @State private var drafting = false
    @State private var position = ScrollPosition(edge: .bottom)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let d = detail {
                    summary(d)
                    ForEach(Self.rows(d.messages), id: \.message.id) { row in
                        if let at = row.time {
                            ChatTimeHeader(date: at)
                                .padding(.top, 20)
                                .padding(.bottom, 4)
                        }
                        MessageBubble(message: row.message, first: row.first, last: row.last)
                            .padding(.top, row.first ? 10 : 2)
                    }
                    if !d.orders.isEmpty { orders(d) }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 4)
                }
            }
            .pageWidth(Metric.readable)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await load() }
        .onChange(of: detail?.messages.count ?? 0) { old, _ in
            Task {
                await Task.yield()
                if old == 0 {
                    position.scrollTo(edge: .bottom)
                } else {
                    withAnimation(Motion.ease) { position.scrollTo(edge: .bottom) }
                }
            }
        }
        .onAppear { model.openChats += 1 }
        .onDisappear { model.openChats = max(0, model.openChats - 1) }
        .brandPage()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if detail != nil {
                ChatComposer(
                    text: $draft,
                    placeholder: drafting ? "Xena 正在寫…" : "回覆客人…",
                    hint: detail.map { "寄到 \($0.contactEmail)・信末附上你的簽名" },
                    sending: working,
                    draftWithXena: { xenaWrite(polish: false) },
                    sendBlocked: drafting,
                    send: send
                ) {
                    if !draft.isEmpty {
                        Toggle(isOn: $closeAfter) {
                            Text("寄出後結案").textRole(.xs).foregroundStyle(Theme.muted)
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.primary)
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        // 聊天畫面：手機上收起底部的分頁列，留給回覆
        .toolbar(sizeClass == .regular ? .automatic : .hidden, for: .tabBar)
        .navigationTitle(detail?.summary.customer ?? "客服信")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("請 Xena 擬回覆", systemImage: "sparkles") { xenaWrite(polish: false) }
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("請 Xena 潤飾我寫的", systemImage: "wand.and.stars") { xenaWrite(polish: true) }
                    }
                    if detail?.summary.status != "closed" {
                        Button("結案", systemImage: "checkmark.circle") { Task { await propose { try await model.api.proposeThreadStatus(site: site, id: threadID, status: "closed") } } }
                    } else {
                        Button("重新打開", systemImage: "arrow.uturn.backward.circle") { Task { await propose { try await model.api.proposeThreadStatus(site: site, id: threadID, status: "open") } } }
                    }
                    if let url = detail?.adminURL {
                        Button("在後台打開", systemImage: "arrow.up.right.square") { openURL(url) }
                    }
                } label: { HeroIcon("ellipsis-horizontal") }
            }
        }
        .task { await load() }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            announce(result)
            Task {
                await load()
                await model.refreshAll()
            }
        }
    }

    /// 一則客服信前面要不要放時間、是不是一組（同一邊、同一個人連著寫）的頭尾
    private struct Row {
        let message: SupportMessage
        let time: Date?
        let first: Bool
        let last: Bool
    }

    private static func rows(_ messages: [SupportMessage]) -> [Row] {
        var times: [Date?] = []
        var lastAt: Date?
        for m in messages {
            times.append(ChatEntry.needsTime(m.at, after: lastAt) ? m.at : nil)
            if let at = m.at { lastAt = at }
        }
        func same(_ a: SupportMessage, _ b: SupportMessage) -> Bool { a.fromCustomer == b.fromCustomer && a.author == b.author }
        return messages.enumerated().map { i, m in
            let first = i == 0 || times[i] != nil || !same(messages[i - 1], m)
            let last = i == messages.count - 1 || times[i + 1] != nil || !same(m, messages[i + 1])
            return Row(message: m, time: times[i], first: first, last: last)
        }
    }

    /// Xena 讀整串信、這位客人的訂單擬一封回覆（輸入框有字就當重點），或潤飾輸入框裡的那段；放進輸入框，不會自己寄出。
    /// 要先同意 Xena 使用雲端 AI
    private func xenaWrite(polish: Bool) {
        guard !drafting else { return }
        model.withCloudAI {
            let input = draft
            drafting = true
            Task {
                defer { drafting = false }
                do {
                    let text = try await model.api.replyDraft(site: site, id: threadID, polish: polish, text: input, kind: "thread")
                    withAnimation(Motion.ease) {
                        // 寫的時候又打了字：接在後面，不蓋掉
                        draft = draft == input ? text : draft + "\n\n" + text
                    }
                } catch {
                    model.show(error.localizedDescription, tone: .danger)
                }
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !working else { return }
        Task { await propose(reply: true) { try await model.api.proposeReply(site: site, threadID: threadID, body: text, close: closeAfter) } }
    }

    /// 寫入完成：回覆有沒有寄出（信沒寄出要讓專人知道）
    private func announce(_ result: JSONValue) {
        let sent = result["sent"]?.array.first
        if let error = sent?["emailError"]?.string, !error.isEmpty {
            model.show("回覆存了，但信沒寄出：\(error)", tone: .danger)
        } else {
            model.show(sent != nil ? "已寄出回覆" : "已更新")
        }
        if sent != nil {
            draft = ""
            closeAfter = false
        }
    }

    private func load() async {
        error = nil
        do {
            detail = try await model.api.supportThread(site: site, id: threadID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func propose(reply: Bool = false, _ make: () async throws -> ConsoleAPI.WriteOutcome) async {
        working = true
        defer { working = false }
        do {
            let outcome = try await make()
            switch outcome {
            case .needsConfirmation(let p):
                // 送出回覆：按「送出」就是確認了，不再跳一次確認（要打字、危險的動作照樣確認）
                if reply, p.typed == nil, !p.danger {
                    switch try await model.api.confirm(p, typed: nil) {
                    case .done(let result):
                        announce(result)
                        await load()
                        Task { await model.refreshAll() }
                    case .needsOwner(let next):
                        proposal = next
                    }
                } else {
                    proposal = p
                }
            case .done:
                model.show("已更新")
                await load()
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    private func summary(_ d: SupportThreadDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(model.site(site)?.name ?? site)
            Headline(d.summary.subject, role: .h3)
            FlowLayout(spacing: 6) {
                StatusBadge(d.summary.statusLabel, tone: d.summary.tone)
                if !d.summary.categoryLabel.isEmpty { StatusBadge(d.summary.categoryLabel) }
                if let n = d.summary.orderNumber { StatusBadge("#\(n)", tone: .gold) }
            }
            Text(contactLine(d))
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
        .padding(.bottom, 8)
    }

    /// email・會員（等級）・累積消費
    private func contactLine(_ d: SupportThreadDetail) -> String {
        var parts: [String] = [d.contactEmail]
        if let name = d.memberName {
            let tier = d.memberTier.map { "（\($0)）" } ?? ""
            parts.append("會員 \(name)\(tier)")
        }
        if let spend = d.memberSpend { parts.append("累積 \(spend)") }
        return parts.filter { !$0.isEmpty }.joined(separator: "・")
    }

    private func orders(_ d: SupportThreadDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("這位客人的訂單")
            RuledList {
                ForEach(d.orders) { o in
                    Button { model.open(.order(site: site, id: o.id)) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("#\(o.number)").font(.brand(15, .medium).monospacedDigit())
                                Text(o.items).textRole(.xs).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(o.totalLabel).font(.brand(15, .medium).monospacedDigit())
                                Text(o.statusLabel).textRole(.xs).foregroundStyle(Theme.muted)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.row)
                }
            }
        }
        .padding(.top, 28)
    }
}

/// 客服信的一則（iMessage）：客人在左（灰）、我們在右（品牌橘白字）；組的最後一個有小尾巴，我們這邊寫是誰回的
private struct MessageBubble: View {
    let message: SupportMessage
    var first = true
    var last = true

    private var mine: Bool { !message.fromCustomer }

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            if first, mine, !message.author.isEmpty {
                Text(message.author)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .padding(.trailing, 8)
            }
            if !message.body.isEmpty {
                ChatBubble(mine ? .staff : .customer, tail: last) {
                    Text(bubbleText(message.body, markdown: false))
                }
                .contextMenu {
                    Button("複製", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.body }
                    if let at = message.at { Text("\(at.dayTitle) \(at.clockText)") }
                }
            }
            ForEach(message.attachments, id: \.self) { name in
                Label(name, systemImage: "paperclip")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
            }
            if let error = message.emailError, !error.isEmpty {
                Label("信沒寄出：\(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.dangerFG)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: 520, alignment: mine ? .trailing : .leading)
        .padding(mine ? .leading : .trailing, 56)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}
