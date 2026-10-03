import SwiftUI
import UIKit

/// 收件匣：所有網站、所有管道（官網、LINE、Email、聯絡表單）放在同一個清單，照「要不要你」分段：
///   要你處理：等專人的 Xena 對話、客人在等回覆的客服信、新的專案詢問（等最久的在上面）
///   Xena 正在回答：官網、LINE 上 Xena 正在回答的對話（24 小時內），點進去看、隨時可以接手
///   你們接手的：專人處理中、客人還沒再說話的
///   信箱：寄到網站信箱、還沒轉成客服對話的信
/// 每一列的類別是 Jev 自動判斷的（訂單、收貨問題、費用報價…）；類別多於一種時上面一排可以只看某一類。
/// iPad：左邊清單、右邊內容。
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var picked: Route?

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                InboxList(picked: $picked)
                    .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 480)
            } detail: {
                NavigationStack(path: Bindable(model).inboxPath) {
                    Group {
                        if let picked {
                            RouteView(route: picked).id(picked)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Headline("Pick a *conversation*", role: .h2)
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

/// 收件匣的四段（照「要不要你」分）
struct InboxSections {
    var needsYou: [InboxItem] = []
    var live: [InboxItem] = []
    var yours: [InboxItem] = []
    var mail: [InboxItem] = []

    init(_ b: Briefing) {
        // 同一段對話可能同時在兩份清單裡（例如剛轉給專人）：留第一次看到的
        var seen = Set<String>()
        let xena = (b.handoffs + b.live).filter { seen.insert($0.key).inserted }
        // 等專人的對話（舊資料掛著客服信的，在客服信那邊處理，網站給的 attention 是 false）、
        // 專人接手後客人又說話、Xena 回答中但客人留了聯絡資料
        let xenaNeeds = xena.filter(\.attention).map { InboxItem($0, needsYou: true) }
        needsYou = (xenaNeeds + b.awaiting.map { InboxItem($0) } + b.inquiries.map { InboxItem($0) })
            .sorted { ($0.since ?? .distantFuture) < ($1.since ?? .distantFuture) }
        live = xena.filter { $0.status == "ai" && !$0.attention }.map { InboxItem($0) }
        yours = xena.filter { $0.status == "human" && !$0.attention }.map { InboxItem($0) }
        mail = b.mail.map { InboxItem($0) }
    }

    var all: [InboxItem] { needsYou + live + yours + mail }
    var isEmpty: Bool { all.isEmpty }

    /// 有哪些類別（多的在前）
    var topics: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: all.compactMap(\.topic), by: { $0 }).mapValues(\.count)
        return counts.map { (name: $0.key, count: $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    /// 只看某一類
    func only(_ topic: String?) -> InboxSections {
        guard let topic else { return self }
        var s = self
        s.needsYou = needsYou.filter { $0.topic == topic }
        s.live = live.filter { $0.topic == topic }
        s.yours = yours.filter { $0.topic == topic }
        s.mail = mail.filter { $0.topic == topic }
        return s
    }
}

// MARK: - 清單

struct InboxList: View {
    var picked: Binding<Route?>?

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let b = model.briefing
        let all = InboxSections(b)
        let topics = all.topics
        // 選的類別已經沒有東西了：回到全部
        let topic = model.inboxTopic.flatMap { t in topics.contains { $0.name == t } ? t : nil }
        let shown = all.only(topic)
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header(all, updatedAt: b.updatedAt)
                if b.updatedAt == nil && all.isEmpty {
                    SkeletonRows(rows: 5)
                } else if all.isEmpty {
                    EmptyState(title: "收件匣是空的", message: "客人在官網、LINE、Email 或聯絡表單找你時會出現在這裡；Xena 正在回答的對話也看得到。")
                } else {
                    if topics.count > 1 {
                        FilterBar(
                            items: [nil] + topics.map { Optional($0.name) },
                            selection: Binding(get: { topic }, set: { model.inboxTopic = $0 }),
                            title: { $0 ?? "全部" },
                            count: { t in t.map { name in topics.first { $0.name == name }?.count ?? 0 } ?? all.all.count }
                        )
                    }
                    needsYouSection(shown.needsYou)
                    if !shown.live.isEmpty {
                        section("Xena is *on it*", aside: "她正在官網、LINE 上回答的對話。點進去看，隨時可以接手。", items: shown.live) {
                            HStack(spacing: 7) {
                                LiveDot()
                                Text("即時").textRole(.xs).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    if !shown.yours.isEmpty {
                        section("In your *hands*", aside: "你們接手了、客人還沒再說話的。", items: shown.yours) { EmptyView() }
                    }
                    if !shown.mail.isEmpty {
                        section("Unsorted *mail*", aside: "寄到網站信箱、還沒轉成客服對話的信。", items: shown.mail) { EmptyView() }
                    }
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .refreshable { [model] in await Task { await model.refreshAll() }.value }
        .brandPage()
        .navigationTitle("收件匣")
        .navigationBarTitleDisplayMode(.inline)
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

    private func header(_ all: InboxSections, updatedAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Headline("Your *inbox*", role: .h1)
            if updatedAt != nil {
                Text(summary(all))
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
            }
            Text(updatedAt.map { "\($0.clockText) 更新・下拉重新整理" } ?? "Xena 正在看各網站…")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
    }

    private func summary(_ all: InboxSections) -> String {
        var parts = [all.needsYou.isEmpty ? "沒有要你處理的事" : "\(all.needsYou.count) 件要你處理"]
        if !all.live.isEmpty { parts.append("Xena 正在回答 \(all.live.count) 段") }
        return parts.joined(separator: "・")
    }

    @ViewBuilder
    private func needsYouSection(_ items: [InboxItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHead("Needs *you*", aside: items.isEmpty ? nil : "客人在等你，等最久的在上面。", role: .h3)
            if items.isEmpty {
                EmptyState(title: "都處理好了", message: "有客人需要你時會出現在這裡，也會通知你。")
            } else {
                rows(items, waiting: true)
            }
        }
    }

    private func section<Action: View>(_ title: String, aside: String, items: [InboxItem], @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHead(title, aside: aside, role: .h3, action: action)
            rows(items, waiting: false)
        }
    }

    private func rows(_ items: [InboxItem], waiting: Bool) -> some View {
        RuledList {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                open(item.route) {
                    InboxRow(item: item, waiting: waiting, site: model.sites.count > 1 ? model.site(item.site) : nil)
                }
                .reveal(min(index, 8))
            }
        }
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

/// 一筆專案詢問（網站聯絡表單送來的）：誰、哪家公司、想做什麼、預算、完整的訊息；回信用 Email
struct InquiryView: View {
    let site: String
    let inquiryID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var data: JSONValue?
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let data {
                    content(data)
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
        .brandPage()
        .navigationTitle("專案詢問")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
            Eyebrow("專案詢問・\(model.site(site)?.name ?? site)")
            Text(name)
                .textRole(.h1)
                .foregroundStyle(Theme.ink)
            if let company = d["company"]?.string, !company.isEmpty {
                Text(company)
                    .textRole(.lead)
            }
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
        HStack(spacing: 10) {
            if let email, let mail = mailURL(email) {
                Button { openURL(mail) } label: { Text("回信") }
                    .buttonStyle(.brand(.primary, size: .md, arrow: true))
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

/// 一封客服信：來回的訊息、這位客人的訂單；回信（寄給客人）與結案都先出網站的確認
struct SupportThreadView: View {
    let site: String
    let threadID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var detail: SupportThreadDetail?
    @State private var error: String?
    @State private var draft = ""
    @State private var closeAfter = false
    @State private var proposal: Proposal?
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let d = detail {
                        summary(d)
                        ForEach(d.messages) { m in
                            MessageBubble(message: m).id(m.id)
                        }
                        if !d.orders.isEmpty { orders(d) }
                    } else if let error {
                        ErrorNote(message: error) { Task { await load() } }
                    } else {
                        SkeletonRows(rows: 4)
                    }
                }
                .frame(maxWidth: Metric.readable, alignment: .leading)
                .pageWidth()
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: detail?.messages.count ?? 0) {
                if let last = detail?.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .brandPage()
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(detail?.summary.customer ?? "客服信")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("請 Xena 擬回覆") {
                        model.askXena("幫我擬一封回覆給\(model.site(site)?.name ?? site)的客服信「\(detail?.summary.subject ?? "")」（\(threadID)）")
                    }
                    if detail?.summary.status != "closed" {
                        Button("結案") { Task { await propose { try await model.api.proposeThreadStatus(site: site, id: threadID, status: "closed") } } }
                    } else {
                        Button("重新打開") { Task { await propose { try await model.api.proposeThreadStatus(site: site, id: threadID, status: "open") } } }
                    }
                    if let url = detail?.adminURL {
                        Button("在後台打開") { openURL(url) }
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

    /// 寫入完成：回覆有沒有寄出（信沒寄出要讓專人知道）
    private func announce(_ result: JSONValue) {
        let sent = result["sent"]?.array.first
        if let error = sent?["emailError"]?.string, !error.isEmpty {
            model.show("回覆存了，但信沒寄出：\(error)", tone: .danger)
        } else {
            model.show(sent != nil ? "已寄出回覆" : "已更新")
        }
        if sent != nil { draft = "" }
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
        .padding(.top, 12)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("回覆客人…", text: $draft, axis: .vertical)
                    .fieldText()
                    .lineLimit(1...8)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.accent : Theme.line) }
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await propose(reply: true) { try await model.api.proposeReply(site: site, threadID: threadID, body: text, close: closeAfter) } }
                } label: {
                    Text("→")
                        .font(.brand(20, .medium))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent, in: .circle)
                }
                .buttonStyle(.press)
                .disabled(working || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("寄出")
            }
            if focused || !draft.isEmpty {
                Toggle(isOn: $closeAfter) {
                    Text("寄出後結案").textRole(.xs).foregroundStyle(Theme.muted)
                }
                .toggleStyle(.switch)
                .tint(Theme.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.sheet)
        .overlay(alignment: .top) { Rule() }
        .animation(Motion.ease, value: focused)
    }
}

/// 客服信的一則訊息：客人在左（白卡）、我們在右（品牌橘）
private struct MessageBubble: View {
    let message: SupportMessage

    var body: some View {
        HStack {
            if !message.fromCustomer { Spacer(minLength: 48) }
            VStack(alignment: message.fromCustomer ? .leading : .trailing, spacing: 5) {
                Text("\(message.author)・\(message.at?.shortText ?? "")")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                if !message.body.isEmpty {
                    Text(message.body)
                        .textRole(.body)
                        .foregroundStyle(message.fromCustomer ? Theme.ink : Theme.onAccent)
                        .textSelection(.enabled)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(
                            message.fromCustomer ? Theme.surface : Theme.accent,
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: message.fromCustomer ? 4 : 16,
                                bottomTrailingRadius: message.fromCustomer ? 16 : 4,
                                topTrailingRadius: 16,
                                style: .continuous
                            )
                        )
                        .overlay {
                            if message.fromCustomer {
                                UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: 1)
                            }
                        }
                }
                ForEach(message.attachments, id: \.self) { name in
                    Text("📎 \(name)")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
                if let error = message.emailError, !error.isEmpty {
                    Text("信沒寄出：\(error)")
                        .textRole(.xs)
                        .foregroundStyle(Theme.dangerFG)
                }
            }
            if message.fromCustomer { Spacer(minLength: 48) }
        }
    }
}

/// 網站上 Xena 的客服對話：官網右下角的 Xena，或網站的 LINE 官方帳號。
/// 網站有 reply_xena 就能在這裡回覆、接手、交給 Xena 繼續回答、結案 —— 官網的回覆出現在客人的 Xena 裡，
/// LINE 的回覆從官方帳號傳到客人的 LINE。沒有的網站（還沒更新的）照舊到後台處理。
struct XenaConversationView: View {
    let site: String
    let conversationID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var detail: XenaConversationDetail?
    @State private var error: String?
    @State private var draft = ""
    @State private var proposal: Proposal?
    @State private var replying = false
    @State private var working = false
    @FocusState private var focused: Bool

    /// 這個網站能在 App 裡回覆、接手
    private var desk: Bool { model.site(site)?.hasXenaDesk ?? false }
    private var status: String? { detail?.status }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let error, detail == nil {
                        ErrorNote(message: error) { Task { await load() } }
                    } else if detail == nil {
                        SkeletonRows(rows: 4)
                    }
                    ForEach(detail?.messages ?? []) { m in
                        XenaMessageRow(message: m, channel: detail?.channel ?? .web).id(m.id)
                    }
                    if detail != nil, !desk, let admin = detail?.adminURL ?? model.site(site)?.adminURL {
                        Button { openURL(admin) } label: { Text("到後台接手回覆 ↗") }
                            .buttonStyle(.brand(.ghost, size: .lg, fullWidth: true))
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: Metric.readable, alignment: .leading)
                .pageWidth()
                .padding(.vertical, 16)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: detail?.messages.count ?? 0) {
                if let last = detail?.messages.last?.id { withAnimation(Motion.ease) { proxy.scrollTo(last, anchor: .bottom) } }
            }
        }
        .brandPage()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if desk, detail != nil { composer }
        }
        .navigationTitle(detail?.who ?? "Xena 的對話")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .task { await load() }
        // 開著的時候每 20 秒看一次有沒有新訊息（客人在 LINE 或網站上又說話了）
        .task(id: conversationID) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                await load(quiet: true)
            }
        }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            if replying { announceReply(result) } else { model.show("已更新") }
            replying = false
            Task {
                await load()
                await model.refreshAll()
            }
        }
    }

    // MARK: 上方：來源、狀態、誰在處理

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("\(model.site(site)?.name ?? site)・Xena 客服")
            if let d = detail {
                FlowLayout(spacing: 6) {
                    StatusBadge(d.channel.label, tone: d.channel == .line ? .active : .neutral)
                    if let s = d.status { StatusBadge(XenaConversationSummary.label(s), tone: XenaConversationSummary.tone(s)) }
                    if let a = d.assignee, d.status == "human" { StatusBadge("\(a) 處理中") }
                    if d.lineBlocked { StatusBadge("已封鎖官方帳號", tone: .danger) }
                }
                if let reason = d.handoffReason, !reason.isEmpty {
                    Text("轉真人：\(reason)")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(3)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: 右上角：接手、交還 Xena、結案

    @ViewBuilder
    private var menu: some View {
        Menu {
            if desk, let status {
                if status == "ai" || status == "waiting" {
                    Button("接手（Xena 先停止回答）") { Task { await propose { try await model.api.proposeXena(site: site, id: conversationID, action: "takeover") } } }
                }
                if status == "human" || status == "waiting" {
                    Button("交給 Xena 繼續回答") { Task { await propose { try await model.api.proposeXena(site: site, id: conversationID, action: "release") } } }
                }
                if status != "closed" {
                    Button("結案") { Task { await propose { try await model.api.proposeXena(site: site, id: conversationID, action: "close") } } }
                } else {
                    Button("重新開啟") { Task { await propose { try await model.api.proposeXena(site: site, id: conversationID, action: "reopen") } } }
                }
            }
            Button("請 Xena 擬回覆") {
                let from = detail?.channel == .line ? "LINE 上" : "官網上"
                model.askXena("幫我看\(model.site(site)?.name ?? site)\(from)這段 Xena 客服對話（\(conversationID)），擬一段給客人的回覆")
            }
            if let url = detail?.adminURL ?? model.site(site)?.adminURL {
                Button("在後台打開") { openURL(url) }
            }
        } label: { HeroIcon("ellipsis-horizontal") }
    }

    // MARK: 下方：回覆

    @ViewBuilder
    private var composer: some View {
        if status == "closed" {
            Text("這段對話已結案。客人再開口會回到 Xena；要由專人繼續回覆，先從右上角「重新開啟」。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.sheet)
                .overlay(alignment: .top) { Rule() }
        } else {
            let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(status == "human" ? "回覆客人…" : "回覆客人（送出就等於接手）", text: $draft, axis: .vertical)
                        .fieldText()
                        .lineLimit(1...8)
                        .focused($focused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.accent : Theme.line) }
                    Button {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await propose(reply: true) { try await model.api.proposeXena(site: site, id: conversationID, action: "reply", text: text) } }
                    } label: {
                        Text("→")
                            .font(.brand(20, .medium))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 40, height: 40)
                            .background(Theme.accent, in: .circle)
                    }
                    .buttonStyle(.press)
                    .disabled(working || empty)
                    .opacity(empty ? 0.35 : 1)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("送出")
                }
                if focused || !draft.isEmpty {
                    Text(detail?.replyGoesTo ?? detail?.channel.replyHint ?? "")
                        .textRole(.xs)
                        .foregroundStyle(detail?.lineBlocked == true ? Theme.dangerFG : Theme.muted)
                        .padding(.horizontal, 6)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(Theme.sheet)
            .overlay(alignment: .top) { Rule() }
            .animation(Motion.ease, value: focused)
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

    private func propose(reply: Bool = false, _ make: () async throws -> ConsoleAPI.WriteOutcome) async {
        working = true
        defer { working = false }
        do {
            switch try await make() {
            case .needsConfirmation(let p):
                // 送出回覆：按「送出」就是確認了，不再跳一次確認（接手、結案這些選單裡的動作照樣確認）
                if reply, p.typed == nil, !p.danger {
                    switch try await model.api.confirm(p, typed: nil) {
                    case .done(let result):
                        announceReply(result)
                        await load()
                        Task { await model.refreshAll() }
                    case .needsOwner(let next):
                        replying = true
                        proposal = next
                    }
                    return
                }
                replying = reply
                proposal = p
            case .done:
                if reply { draft = "" }
                model.show("已更新")
                await load()
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }
}

/// 客人說的話，一行一行畫（和後台的收件匣一樣）：LINE 傳來的照片、貼圖顯示圖，影片、語音、檔案可以點開，
/// 其他的照原樣（網址可以點）。「［圖片］網址」「［貼圖：開心］網址」「［影片 12 秒］網址」「［語音 8 秒］網址」「［檔案］名稱 網址」
private struct VisitorContent: View {
    let text: String
    @Environment(\.openURL) private var openURL

    private enum Line: Identifiable {
        case image(URL, sticker: Bool, id: Int)
        case media(label: String, url: URL, id: Int)
        case text(String, id: Int)
        var id: Int {
            switch self {
            case .image(_, _, let id), .media(_, _, let id), .text(_, let id): id
            }
        }
    }

    private var lines: [Line] {
        text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").enumerated().map { (i, raw) -> Line in
            let line = raw.trimmingCharacters(in: .whitespaces)
            // ［標籤］ https://…（標籤後面可能有檔名）
            if line.hasPrefix("["), let close = line.firstIndex(of: "]"),
               let space = line.lastIndex(of: " "), space > close,
               let url = URL(string: String(line[line.index(after: space)...])), url.scheme == "https" {
                let label = String(line[line.index(after: line.startIndex)..<close])
                let rest = line[line.index(after: close)..<space].trimmingCharacters(in: .whitespaces)
                if label == "圖片" { return .image(url, sticker: false, id: i) }
                if label.hasPrefix("貼圖") { return .image(url, sticker: true, id: i) }
                if label.hasPrefix("影片") || label.hasPrefix("語音") || label.hasPrefix("檔案") || label.hasPrefix("位置") {
                    return .media(label: [label, rest].filter { !$0.isEmpty }.joined(separator: " "), url: url, id: i)
                }
            }
            return .text(raw, id: i)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines) { line in
                switch line {
                case .image(let url, let sticker, _):
                    Button { openURL(url) } label: {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Theme.soft
                        }
                        .frame(maxWidth: sticker ? 96 : 220, maxHeight: sticker ? 96 : 220, alignment: .leading)
                        .clipShape(.rect(cornerRadius: sticker ? 0 : 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sticker ? "客人傳的貼圖" : "客人傳的照片")
                case .media(let label, let url, _):
                    Button { openURL(url) } label: {
                        Label(label, systemImage: label.hasPrefix("影片") ? "play.rectangle" : label.hasPrefix("語音") ? "waveform" : label.hasPrefix("位置") ? "mappin.and.ellipse" : "doc")
                            .textRole(.body)
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                case .text(let s, _):
                    Text(Self.linked(s))
                        .textRole(.body)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// 網址可以點
    private static func linked(_ s: String) -> AttributedString {
        var out = AttributedString(s)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return out }
        for match in detector.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let url = match.url, let r = Range(match.range, in: s), let ar = Range(r, in: out) else { continue }
            out[ar].link = url
        }
        return out
    }
}

/// Xena 對話的一則：事件置中、客人在左（白卡；有 Jev 的分類與判斷）、Xena 與專人在右邊標名字
private struct XenaMessageRow: View {
    let message: XenaConversationMessage
    let channel: XenaChannel

    var body: some View {
        switch message.role {
        case "event":
            Text(message.content + (message.author.map { "（\($0)）" } ?? ""))
                .textRole(.xs)
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        case "user":
            VStack(alignment: .leading, spacing: 5) {
                if let meta = jevLine {
                    Text(meta)
                        .textRole(.xs)
                        .foregroundStyle(message.jevHuman?.yes == true ? Theme.warningFG : Theme.muted)
                }
                VisitorContent(text: message.content)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == "assistant" ? "Xena" : (message.author ?? "專人"))
                    .textRole(.xs)
                    .foregroundStyle(message.role == "assistant" ? Theme.accent : Theme.muted)
                Text(markdown(message.content))
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 客人（LINE）・訂單查詢・Jev：找人 92%
    private var jevLine: String? {
        var parts: [String] = [channel == .line ? "客人（LINE）" : "客人"]
        if let tag = message.tag, !tag.isEmpty { parts.append(tag) }
        if let h = message.jevHuman { parts.append("Jev：找人 \(Int((h.confidence * 100).rounded()))%") }
        if let at = message.at { parts.append(at.shortText) }
        return parts.joined(separator: "・")
    }
}
