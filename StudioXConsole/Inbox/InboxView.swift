import SwiftUI

/// 收件匣（網站後台的「客服收件匣」，所有網站放在一起）：
///   客服信：客人已發言、我們還沒回的（等最久的在前）
///   Xena 轉來：網站上的 Xena 判斷要找人、轉給專人的對話
///   專案詢問：網站聯絡表單的新詢問
///   信箱：寄到網站信箱、但不是客服對話的信（第一次寫信來的人、廠商…）
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
                                Text("從左邊選一封信或一段對話。")
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

struct InboxList: View {
    var picked: Binding<Route?>?

    @Environment(AppModel.self) private var model
    /// 現在看的分段（存在 AppModel：點了通知會直接切到對應的分段）；這個人沒有的分段就看客服
    private var segment: Segment {
        let wanted = Segment(rawValue: model.inboxSegment) ?? .support
        return segments.contains(wanted) ? wanted : .support
    }
    @State private var mailbox: [(site: String, row: RecordSummary)] = []
    @State private var mailboxLoaded = false

    enum Segment: String, CaseIterable, Identifiable {
        case support, handoffs, inquiries, mailbox
        var id: Self { self }
    }

    var body: some View {
        let b = model.briefing
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Headline("Your *inbox*", role: .h1)
                    Text(b.updatedAt.map { "\($0.clockText) 更新・下拉重新整理" } ?? "Xena 正在看各網站…")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
                FilterBar(items: segments, selection: Binding(get: { segment }, set: { model.inboxSegment = $0.rawValue }), title: { title($0) }, count: { count($0) })
                switch segment {
                case .support: supportList(b.awaiting)
                case .handoffs: handoffList(b.handoffs)
                case .inquiries: inquiryList(b.inquiries)
                case .mailbox: mailboxList
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .refreshable { [model] in await model.refreshAll() }
        .brandPage()
        .navigationTitle("收件匣")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: segment) {
            if segment == .mailbox { await loadMailbox() }
        }
    }

    private var segments: [Segment] {
        var out: [Segment] = [.support]
        if model.sites.contains(where: { ($0.tools.contains("list") && !$0.hasOrders) || $0.hasXenaDesk }) || !model.briefing.handoffs.isEmpty { out.append(.handoffs) }
        if model.sites.contains(where: { !$0.hasOrders }) || !model.briefing.inquiries.isEmpty { out.append(.inquiries) }
        if !model.supportSites.isEmpty { out.append(.mailbox) }
        return out
    }

    private func title(_ s: Segment) -> String {
        switch s {
        case .support: "客服信"
        case .handoffs: "Xena 轉來"
        case .inquiries: "專案詢問"
        case .mailbox: "信箱"
        }
    }

    private func count(_ s: Segment) -> Int? {
        switch s {
        case .support: model.briefing.awaiting.count
        case .handoffs: model.briefing.handoffs.count
        case .inquiries: model.briefing.inquiries.count
        case .mailbox: mailboxLoaded ? mailbox.count : nil
        }
    }

    private func loadMailbox() async {
        var out: [(site: String, row: RecordSummary)] = []
        for site in model.supportSites {
            do {
                let r = try await model.api.list(site: site.id, entity: "mailbox", filters: ["limit": 50])
                out += r.rows.map { (site.id, $0) }
            } catch {
                // 這個網站沒有信箱（或不給看）：略過
            }
        }
        mailbox = out.sorted { ($0.row.date ?? .distantPast) > ($1.row.date ?? .distantPast) }
        mailboxLoaded = true
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

    @ViewBuilder
    private func supportList(_ threads: [SupportThreadSummary]) -> some View {
        if threads.isEmpty {
            EmptyState(title: "客人都回覆過了", message: "有新的客服信會出現在這裡。")
        } else {
            RuledList {
                ForEach(Array(threads.enumerated()), id: \.element.key) { index, t in
                    open(.thread(site: t.site, id: t.id)) {
                        InboxRow(name: t.customer, title: t.subject, at: nil, badges: badges(for: t), site: model.site(t.site))
                    }
                    .reveal(index)
                }
            }
        }
    }

    private func badges(for t: SupportThreadSummary) -> [(String, Tone)] {
        var out: [(String, Tone)] = [(t.categoryLabel, Tone.neutral)]
        if let hours = t.waitingHours { out.append(("等了 \(Briefing.hours(hours))", Tone.warning)) }
        if let n = t.orderNumber { out.append(("#\(n)", Tone.gold)) }
        return out
    }

    @ViewBuilder
    private func handoffList(_ items: [XenaConversationSummary]) -> some View {
        if items.isEmpty {
            EmptyState(title: "沒有轉給專人的對話", message: "官網或 LINE 上的客人需要真人時（Jev、Xena 判斷或客人自己要求），對話會出現在這裡。")
        } else {
            RuledList {
                ForEach(Array(items.enumerated()), id: \.element.key) { index, c in
                    open(.xenaConversation(site: c.site, id: c.id)) {
                        InboxRow(
                            name: c.contactName ?? "訪客", title: c.firstQuestion ?? "（\(c.turns) 句對話）", at: c.at,
                            badges: [(c.channel.label, c.channel == .line ? Tone.active : Tone.neutral), (c.statusLabel, c.tone)] + c.tags.prefix(2).map { (String($0), Tone.neutral) },
                            site: model.site(c.site)
                        )
                    }
                    .reveal(index)
                }
            }
        }
    }

    @ViewBuilder
    private func inquiryList(_ items: [InquirySummary]) -> some View {
        if items.isEmpty {
            EmptyState(title: "沒有新的專案詢問", message: "網站聯絡表單送出的詢問會出現在這裡。")
        } else {
            RuledList {
                ForEach(Array(items.enumerated()), id: \.element.key) { index, q in
                    InquiryRow(inquiry: q, site: model.site(q.site))
                        .reveal(index)
                }
            }
        }
    }

    @ViewBuilder
    private var mailboxList: some View {
        if !mailboxLoaded {
            SkeletonRows(rows: 4)
        } else if mailbox.isEmpty {
            EmptyState(title: "信箱是空的", message: "寄到網站信箱、但不是客服對話的信會出現在這裡。")
        } else {
            RuledList {
                ForEach(Array(mailbox.enumerated()), id: \.offset) { index, item in
                    open(.record(site: item.site, entity: "mailbox", id: item.row.id)) {
                        InboxRow(
                            name: item.row.raw["from"]?.string ?? "寄件人",
                            title: item.row.title,
                            at: item.row.date,
                            badges: [(item.row.badge ?? "", item.row.tone), (item.row.raw["attachmentCount"]?.int.flatMap { $0 > 0 ? "附件 \($0)" : nil } ?? "", Tone.neutral)],
                            site: model.site(item.site)
                        )
                    }
                    .reveal(index)
                }
            }
        }
    }
}

/// 收件匣的一列：頭像、名字、主旨、狀態標籤、哪個網站
private struct InboxRow: View {
    let name: String
    let title: String
    let at: Date?
    let badges: [(String, Tone)]
    let site: SiteSummary?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(name: name, size: 38)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .textRole(.h4)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let at {
                        Text(at.relativeText)
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Text(title)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        if !badge.0.isEmpty { StatusBadge(badge.0, tone: badge.1) }
                    }
                    Spacer(minLength: 0)
                    if let site {
                        SiteIconView(site: site, size: 18)
                        Text(site.name)
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .contentShape(.rect)
    }
}

/// 一筆專案詢問（atelier-cms 的 inquiry）：誰、哪家公司、想做什麼、預算；回覆用 Email
private struct InquiryRow: View {
    let inquiry: InquirySummary
    let site: SiteSummary?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text([inquiry.name, inquiry.company].compactMap { $0 }.joined(separator: "・"))
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let at = inquiry.at {
                    Text(at.relativeText).textRole(.xs).foregroundStyle(Theme.muted)
                }
            }
            if !inquiry.types.isEmpty || inquiry.budget != nil {
                FlowLayout(spacing: 6) {
                    ForEach(inquiry.types, id: \.self) { Chip($0) }
                    if let budget = inquiry.budget { StatusBadge(budget, tone: .gold) }
                }
            }
            if let message = inquiry.message {
                Text(message)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(6)
            }
            HStack(spacing: 10) {
                if let mail = URL(string: "mailto:\(inquiry.email)") {
                    Button { openURL(mail) } label: { Text("回信") }
                        .buttonStyle(.brand(.ghost, size: .sm, arrow: true))
                }
                Spacer()
                if let site {
                    SiteIconView(site: site, size: 18)
                    Text(site.name).textRole(.xs).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, 18)
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
            let sent = result["sent"]?.array.first
            if let error = sent?["emailError"]?.string, !error.isEmpty {
                model.show("回覆存了，但信沒寄出：\(error)", tone: .danger)
            } else {
                model.show(sent != nil ? "已寄出回覆" : "已更新")
            }
            if sent != nil { draft = "" }
            Task {
                await load()
                await model.refreshAll()
            }
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

    private func propose(_ make: () async throws -> ConsoleAPI.WriteOutcome) async {
        working = true
        defer { working = false }
        do {
            let outcome = try await make()
            switch outcome {
            case .needsConfirmation(let p): proposal = p
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
                    Task { await propose { try await model.api.proposeReply(site: site, threadID: threadID, body: text, close: closeAfter) } }
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

/// 網站上 Xena 的客服對話：官網右下角的 Xena，或網站的 LINE 官方帳號（黃毛丫頭）。
/// 網站有 reply_xena（黃毛丫頭）就能在這裡回覆、接手、交還 Xena、結案 —— 官網的回覆出現在客人的 Xena 裡，
/// LINE 的回覆從官方帳號傳到客人的 LINE。沒有的網站（atelier-cms）照舊到後台處理。
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
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { _ in
            if replying {
                draft = ""
                model.show(detail?.channel == .line ? "已傳到客人的 LINE" : "已送出回覆")
            } else {
                model.show("已更新")
            }
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
                    Button("交還 Xena") { Task { await propose { try await model.api.proposeXena(site: site, id: conversationID, action: "release") } } }
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

    private func propose(reply: Bool = false, _ make: () async throws -> ConsoleAPI.WriteOutcome) async {
        working = true
        defer { working = false }
        do {
            switch try await make() {
            case .needsConfirmation(let p):
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
                Text(message.content)
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
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
