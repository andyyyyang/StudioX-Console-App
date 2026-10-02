import SwiftUI

/// 收件匣（網站後台的「客服收件匣」，所有網站放在一起）：
///   客服信：客人已發言、我們還沒回的（等最久的在前）
///   Xena 轉來：網站上的 Xena 判斷要找人、轉給專人的對話
///   專案詢問：網站聯絡表單的新詢問
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var segment: Segment = .support

    enum Segment: String, CaseIterable, Identifiable {
        case support, handoffs, inquiries
        var id: Self { self }
    }

    var body: some View {
        let b = model.briefing
        NavigationStack(path: Bindable(model).inboxPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("收件匣", selection: $segment) {
                        Text("客服信 \(b.awaiting.count)").tag(Segment.support)
                        Text("Xena 轉來 \(b.handoffs.count)").tag(Segment.handoffs)
                        Text("專案詢問 \(b.inquiries.count)").tag(Segment.inquiries)
                    }
                    .pickerStyle(.segmented)

                    switch segment {
                    case .support: supportList(b.awaiting)
                    case .handoffs: handoffList(b.handoffs)
                    case .inquiries: inquiryList(b.inquiries)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable { [model] in await model.refreshAll() }
            .admPage()
            .navigationTitle("收件匣")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    @ViewBuilder
    private func supportList(_ threads: [SupportThreadSummary]) -> some View {
        if threads.isEmpty {
            empty("客人都回覆過了", "有新的客服信會出現在這裡。")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, t in
                    if index > 0 { Divider().overlay(Theme.hair).padding(.leading, 60) }
                    NavigationLink(value: Route.thread(site: t.site, id: t.id)) {
                        InboxRow(
                            name: t.customer, title: t.subject, at: nil,
                            badges: badges(for: t),
                            site: model.site(t.site)
                        )
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .admCard(padding: 0)
        }
    }

    private func badges(for t: SupportThreadSummary) -> [(String, Tone)] {
        var out: [(String, Tone)] = [(t.categoryLabel, Tone.neutral)]
        if let hours = t.waitingHours { out.append(("等了 \(Briefing.hours(hours))", Tone.warning)) }
        return out
    }

    @ViewBuilder
    private func handoffList(_ items: [XenaConversationSummary]) -> some View {
        if items.isEmpty {
            empty("沒有轉給專人的對話", "Xena 判斷需要真人時，對話會出現在這裡。")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, c in
                    if index > 0 { Divider().overlay(Theme.hair).padding(.leading, 60) }
                    NavigationLink(value: Route.xenaConversation(site: c.site, id: c.id)) {
                        InboxRow(
                            name: c.contactName ?? "訪客", title: c.firstQuestion ?? "（\(c.turns) 句對話）", at: c.at,
                            badges: [(c.statusLabel, c.tone)] + c.tags.prefix(2).map { (String($0), Tone.neutral) },
                            site: model.site(c.site)
                        )
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .admCard(padding: 0)
        }
    }

    @ViewBuilder
    private func inquiryList(_ items: [InquirySummary]) -> some View {
        if items.isEmpty {
            empty("沒有新的專案詢問", "網站聯絡表單送出的詢問會出現在這裡。")
        } else {
            VStack(spacing: 12) {
                ForEach(items) { q in
                    InquiryCard(inquiry: q, site: model.site(q.site))
                }
            }
        }
    }

    private func empty(_ title: String, _ message: String) -> some View {
        EmptyState(icon: "inbox", title: title, message: message)
            .admCard(padding: 0)
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
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: name, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.admCardTitle)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let at {
                        Text(at.shortText)
                            .font(.admMeta)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                Text(title)
                    .font(.admBody)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        if !badge.0.isEmpty { StatusBadge(badge.0, tone: badge.1) }
                    }
                    Spacer(minLength: 0)
                    if let site {
                        SiteIconView(site: site, size: 18)
                        Text(site.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// 一筆專案詢問（atelier-cms 的 inquiry）：誰、哪家公司、想做什麼、預算；回覆用 Email
private struct InquiryCard: View {
    let inquiry: InquirySummary
    let site: SiteSummary?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text([inquiry.name, inquiry.company].compactMap { $0 }.joined(separator: "・"))
                    .font(.admCardTitle)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let at = inquiry.at {
                    Text(at.shortText).font(.admMeta).foregroundStyle(Theme.inkMuted)
                }
            }
            if !inquiry.types.isEmpty || inquiry.budget != nil {
                HStack(spacing: 6) {
                    ForEach(inquiry.types, id: \.self) { StatusBadge($0, tone: .gold) }
                    if let budget = inquiry.budget { StatusBadge(budget, tone: .neutral) }
                }
            }
            if let message = inquiry.message {
                Text(message)
                    .font(.admBody)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(5)
            }
            HStack(spacing: 10) {
                if let mail = URL(string: "mailto:\(inquiry.email)") {
                    Button { openURL(mail) } label: {
                        Label { Text("回信") } icon: { HeroIcon("envelope", size: 16) }
                    }
                    .buttonStyle(.adm(.secondary, size: .md))
                }
                Spacer()
                if let site {
                    SiteIconView(site: site, size: 18)
                    Text(site.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .admCard()
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
                VStack(alignment: .leading, spacing: 12) {
                    if let d = detail {
                        summary(d)
                        ForEach(d.messages) { m in
                            MessageBubble(message: m).id(m.id)
                        }
                        if !d.orders.isEmpty { orders(d) }
                    } else if let error {
                        ErrorNote(message: error) { Task { await load() } }
                    } else {
                        LoadingRow().admCard(padding: 0)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: detail?.messages.count ?? 0) {
                if let last = detail?.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .admPage()
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(detail?.summary.customer ?? "客服信")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { model.askXena("幫我擬一封回覆給\(model.site(site)?.name ?? site)的客服信「\(detail?.summary.subject ?? "")」（\(threadID)）") } label: {
                        Label { Text("請 Xena 擬回覆") } icon: { HeroIcon("sparkles") }
                    }
                    if detail?.summary.status != "closed" {
                        Button { Task { await propose { try await model.api.proposeThreadStatus(site: site, id: threadID, status: "closed") } } } label: {
                            Label { Text("結案") } icon: { HeroIcon("check-circle") }
                        }
                    } else {
                        Button { Task { await propose { try await model.api.proposeThreadStatus(site: site, id: threadID, status: "open") } } } label: {
                            Label { Text("重新打開") } icon: { HeroIcon("arrow-path") }
                        }
                    }
                    if let url = detail?.adminURL {
                        Button { openURL(url) } label: {
                            Label { Text("在後台打開") } icon: { HeroIcon("arrow-top-right-on-square") }
                        }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(d.summary.subject)
                .font(.admSection)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                StatusBadge(d.summary.statusLabel, tone: d.summary.tone)
                if !d.summary.categoryLabel.isEmpty { StatusBadge(d.summary.categoryLabel) }
                if let n = d.summary.orderNumber { StatusBadge("#\(n)", tone: .gold) }
            }
            HStack(spacing: 6) {
                Text(d.contactEmail)
                if let name = d.memberName {
                    Text("・會員 \(name)" + (d.memberTier.map { "（\($0)）" } ?? ""))
                }
            }
            .font(.admMeta)
            .foregroundStyle(Theme.inkMuted)
            .lineLimit(1)
        }
        .admCard()
    }

    private func orders(_ d: SupportThreadDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel("這位客人的訂單")
            ForEach(d.orders) { o in
                Button { model.open(.order(site: site, id: o.id)) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("#\(o.number)").font(.system(.subheadline, weight: .semibold).monospacedDigit())
                            Text(o.items).font(.admMeta).foregroundStyle(Theme.inkMuted).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(o.totalLabel).font(.system(.footnote).monospacedDigit())
                            Text(o.statusLabel).font(.admMeta).foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .admCard()
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("回覆客人…", text: $draft, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...8)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.ink.opacity(0.3) : Theme.line))
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await propose { try await model.api.proposeReply(site: site, threadID: threadID, body: text, close: closeAfter) } }
                } label: {
                    HeroIcon("paper-airplane", size: 18)
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 40, height: 40)
                        .background(Theme.primary, in: .circle)
                }
                .buttonStyle(PressScale())
                .disabled(working || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                .accessibilityLabel("寄出")
            }
            if focused || !draft.isEmpty {
                Toggle(isOn: $closeAfter) {
                    Text("寄出後結案").font(.admMeta).foregroundStyle(Theme.inkMuted)
                }
                .toggleStyle(.switch)
                .tint(Theme.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.sheet)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
        .animation(.smooth, value: focused)
    }
}

/// 客服信的一則訊息：客人在左（白卡）、我們在右（主色）
private struct MessageBubble: View {
    let message: SupportMessage

    var body: some View {
        HStack {
            if !message.fromCustomer { Spacer(minLength: 40) }
            VStack(alignment: message.fromCustomer ? .leading : .trailing, spacing: 4) {
                Text("\(message.author)・\(message.at?.shortText ?? "")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.system(size: 15))
                        .foregroundStyle(message.fromCustomer ? Theme.ink : Theme.onPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            message.fromCustomer ? Theme.surface : Theme.primary,
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 18,
                                bottomLeadingRadius: message.fromCustomer ? 6 : 18,
                                bottomTrailingRadius: message.fromCustomer ? 18 : 6,
                                topTrailingRadius: 18,
                                style: .continuous
                            )
                        )
                }
                ForEach(message.attachments, id: \.self) { name in
                    Label { Text(name) } icon: { HeroIcon("document-text", size: 14) }
                        .font(.admMeta)
                        .foregroundStyle(Theme.inkMuted)
                }
                if let error = message.emailError, !error.isEmpty {
                    Text("信沒寄出：\(error)")
                        .font(.admMeta)
                        .foregroundStyle(Theme.dangerFG)
                }
            }
            if message.fromCustomer { Spacer(minLength: 40) }
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
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else if !loaded {
                    LoadingRow().admCard(padding: 0)
                }
                ForEach(messages) { m in
                    switch m.role {
                    case "event":
                        Text(m.content)
                            .font(.admMeta)
                            .foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity)
                    case "user":
                        Text(m.content)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.surface, in: .rect(cornerRadius: 18, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    default:
                        HStack(alignment: .top, spacing: 8) {
                            if m.role == "assistant" { OrbIcon(size: 18).padding(.top, 2) } else { Avatar(name: m.author ?? "專人", size: 20) }
                            Text(markdown(m.content))
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if loaded, let admin = model.site(site)?.adminURL {
                    Button { openURL(admin) } label: {
                        Label { Text("到後台接手回覆") } icon: { HeroIcon("arrow-top-right-on-square", size: 16) }
                    }
                    .buttonStyle(.adm(.secondary, size: .lg, fullWidth: true))
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, 8)
        }
        .admPage()
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
