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
    @State private var segment: Segment = .support
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
                FilterBar(items: segments, selection: $segment, title: { title($0) }, count: { count($0) })
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
        if model.sites.contains(where: { $0.tools.contains("list") && !$0.hasOrders }) || !model.briefing.handoffs.isEmpty { out.append(.handoffs) }
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
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, t in
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
            EmptyState(title: "沒有轉給專人的對話", message: "Xena 判斷需要真人時，對話會出現在這裡。")
        } else {
            RuledList {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, c in
                    open(.xenaConversation(site: c.site, id: c.id)) {
                        InboxRow(
                            name: c.contactName ?? "訪客", title: c.firstQuestion ?? "（\(c.turns) 句對話）", at: c.at,
                            badges: [(c.statusLabel, c.tone)] + c.tags.prefix(2).map { (String($0), Tone.neutral) },
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
                ForEach(Array(items.enumerated()), id: \.element.id) { index, q in
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
                ForEach(Array(mailbox.enumerated()), id: \.element.row.id) { index, item in
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
            Text([d.contactEmail, d.memberName.map { "會員 \($0)" + (d.memberTier.map { "（\($0)）" } ?? "") }, d.memberSpend.map { "累積 \($0)" }].compactMap { $0 }.joined(separator: "・"))
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
        .padding(.bottom, 8)
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
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.accent : Theme.line))
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

/// 網站上 Xena 的客服對話（唯讀：要回覆請在後台的收件匣接手）
struct XenaConversationView: View {
    let site: String
    let conversationID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var messages: [XenaConversationMessage] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow("\(model.site(site)?.name ?? site)・網站上的 Xena")
                if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else if !loaded {
                    SkeletonRows(rows: 4)
                }
                ForEach(messages) { m in
                    switch m.role {
                    case "event":
                        Text(m.content)
                            .textRole(.xs)
                            .foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity)
                    case "user":
                        Text(m.content)
                            .textRole(.body)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    default:
                        HStack(alignment: .top, spacing: 10) {
                            if m.role == "assistant" { OrbIcon(size: 20).padding(.top, 2) } else { Avatar(name: m.author ?? "專人", size: 22) }
                            Text(markdown(m.content))
                                .textRole(.body)
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if loaded, let admin = model.site(site)?.adminURL {
                    Button { openURL(admin) } label: { Text("到後台接手回覆 ↗") }
                        .buttonStyle(.brand(.ghost, size: .lg, fullWidth: true))
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: Metric.readable, alignment: .leading)
            .pageWidth()
            .padding(.vertical, 16)
        }
        .brandPage()
        .navigationTitle("Xena 的對話")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            messages = try await model.api.xenaConversation(site: site, id: conversationID)
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}
