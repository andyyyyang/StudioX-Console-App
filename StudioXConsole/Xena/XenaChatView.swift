import SwiftUI

/// 跟 Xena 的對話（和網頁版同一個 Xena、同一份對話紀錄；樣式照 copilot/styles.ts 的 CHAT_CSS）：
/// 自己的訊息是主色橘的泡泡，Xena 的回答是一般文字；查了什麼用一行淡淡的小字；要動手前出確認卡片。
struct XenaChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showThreads = false
    @FocusState private var focused: Bool

    private let bottomID = "bottom"
    private var session: XenaSession { model.xena }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let problem = session.problem {
                            Text(problem)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.soft, in: .rect(cornerRadius: 12, style: .continuous))
                        }
                        if session.items.isEmpty {
                            emptyState
                        }
                        ForEach(session.items) { item in
                            ChatItemView(item: item)
                                .id(item.id)
                        }
                        if session.phase == .thinking {
                            ThinkingRow()
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.revision) {
                    withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        OrbIcon(size: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Xena")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(session.isBusy ? session.mood.label : (session.threadTitle ?? "你的店長"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showThreads = true } label: { HeroIcon("bars-3") }
                        .accessibilityLabel("對話紀錄")
                    Button { session.newThread() } label: { HeroIcon("pencil-square") }
                        .disabled(session.items.isEmpty)
                        .accessibilityLabel("新的對話")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { HeroIcon("x-mark") }
                        .accessibilityLabel("關閉")
                }
            }
            .sheet(isPresented: $showThreads) {
                ThreadListView()
            }
        }
        .task { await session.loadLatest() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            XenaOrb(mood: session.mood, size: 72, pulse: session.pulse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            Text("我是 Xena，你的店長。問我任何網站的事，或請我動手處理——要改東西之前，我一定先問你。")
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(Theme.muted)
            ChipFlow(items: XenaSession.starters) { session.send($0) }
        }
        .padding(.vertical, 8)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("跟 Xena 說…", text: $draft, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(focused ? Theme.ink.opacity(0.3) : Theme.line, lineWidth: 1)
                }
            Button {
                if session.isBusy {
                    session.stop()
                } else {
                    let text = draft
                    draft = ""
                    session.send(text)
                }
            } label: {
                Group {
                    if session.isBusy {
                        HeroIcon("stop", size: 18)
                    } else {
                        HeroIcon("arrow-up", size: 18)
                    }
                }
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 40, height: 40)
                .background(Theme.primary, in: .circle)
            }
            .buttonStyle(PressScale(scale: 0.92))
            .disabled(!session.isBusy && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(!session.isBusy && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
            .accessibilityLabel(session.isBusy ? "停止" : "送出")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.sheet)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}

/// 一排可以換行的小膠囊（.cp-chips）
struct ChipFlow: View {
    let items: [String]
    var disabled = false
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScale(scale: 0.92))
                .disabled(disabled)
            }
        }
    }
}

/// 由左而右排、放不下就換行
nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 對話裡的一項
struct ChatItemView: View {
    let item: ChatItem
    @Environment(AppModel.self) private var model

    var body: some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.primary, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
                    .textSelection(.enabled)
            }
        case .assistant(_, let text):
            Text(markdown(text))
                .font(.system(size: 15))
                .lineSpacing(5)
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .notice(_, let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.dangerFG)
        case .tool(let call):
            ToolRow(call: call)
        case .confirm(let card):
            XenaConfirmCard(card: card, busy: model.xena.deciding.contains(card.id)) { approve, typed in
                model.xena.decide(card.id, approve: approve, typed: typed)
            }
        case .cards(let cards):
            CardsRow(item: cards)
        case .ask(let ask):
            AskView(ask: ask, disabled: model.xena.isBusy) { answer in
                model.xena.send(answer, answering: ask.id)
            }
        }
    }
}

/// 一次工具呼叫：一行淡淡的小字（.cp-tool）
private struct ToolRow: View {
    let call: ToolRecord

    private var color: Color {
        switch call.status {
        case .error: Theme.dangerFG.opacity(0.85)
        case .proposed: Theme.warningFG
        default: Theme.faint
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Group {
                switch call.status {
                case .running: ProgressView().controlSize(.mini)
                case .ok: HeroIcon("check", size: 13)
                case .error: HeroIcon("x-circle", size: 13)
                case .proposed: HeroIcon("hand-raised", size: 13)
                }
            }
            .frame(width: 14, height: 14)
            Text(call.label)
                .lineLimit(1)
            if call.status == .proposed {
                Text("等你確認").fontWeight(.semibold)
            }
            if let ms = call.ms {
                Text(ms < 1000 ? "\(ms) ms" : "\((Double(ms) / 1000).formatted(.number.precision(.fractionLength(1)))) 秒")
                    .monospacedDigit()
                    .opacity(0.8)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
    }
}

/// Xena 的確認卡片（.cp-card）：確認碼只在伺服器，這裡只送「確認／取消」
struct XenaConfirmCard: View {
    let card: ConfirmCard
    var busy = false
    var onDecide: (Bool, String?) -> Void

    @State private var typed = ""

    private var typedOK: Bool {
        guard let word = card.typed else { return true }
        return typed.trimmingCharacters(in: .whitespaces) == word
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.danger ? "危險動作・要你確認" : "要你確認")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.46)
                .foregroundStyle(card.danger ? Theme.dangerFG : Theme.muted)
            Text(card.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(card.detail)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            switch card.status {
            case .pending:
                if let word = card.typed {
                    TextField("輸入「\(word)」確認", text: $typed)
                        .font(.system(size: 16))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Theme.sheet, in: .rect(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line) }
                }
                HStack(spacing: 8) {
                    Button("取消") { onDecide(false, nil) }
                        .buttonStyle(XenaPillStyle(go: false, danger: card.danger))
                        .disabled(busy)
                    Button {
                        onDecide(true, card.typed == nil ? nil : typed)
                    } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().controlSize(.small).tint(card.danger ? Color.white : Theme.onPrimary) }
                            Text("確認執行")
                        }
                    }
                    .buttonStyle(XenaPillStyle(go: true, danger: card.danger))
                    .disabled(busy || !typedOK)
                }
                .padding(.top, 4)
                if let note = card.result {
                    Text(note).font(.system(size: 13)).foregroundStyle(Theme.dangerFG)
                }
            case .done:
                result(card.result ?? "完成了", color: Theme.successFG)
            case .failed:
                result(card.result ?? "沒有成功", color: Theme.dangerFG)
            case .cancelled:
                result(card.result ?? "取消了，什麼都沒改", color: Theme.muted)
            case .expired:
                result(card.result ?? "這張確認卡已經過期", color: Theme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.soft, in: .rect(cornerRadius: Metric.xenaCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metric.xenaCard, style: .continuous)
                .strokeBorder(card.danger && card.status == .pending ? Theme.dangerFG.opacity(0.45) : Theme.line, lineWidth: 1)
        }
        .animation(.smooth(duration: 0.3), value: card)
    }

    private func result(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(2)
            .foregroundStyle(color)
    }
}

/// 卡片裡的膠囊按鈕（.cp-btn：38 高；確認＝主色，危險＝紅）
struct XenaPillStyle: ButtonStyle {
    var go: Bool
    var danger = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(go ? (danger ? Color.white : Theme.onPrimary) : Theme.ink)
            .background {
                if go {
                    Capsule().fill(danger ? Theme.dangerFG : Theme.primary)
                } else {
                    Capsule().strokeBorder(Theme.line, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Xena 做的卡片：一筆一張，點了到 App 裡那一頁（訂單、客服信），其他的開後台
private struct CardsRow: View {
    let item: CardsItem
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = item.title {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.46)
                    .foregroundStyle(Theme.muted)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(item.cards, id: \.self) { card in
                        Button { open(card) } label: { EntityCardView(card: card) }
                            .buttonStyle(PressScale(scale: 0.92))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func open(_ card: EntityCard) {
        if let site = card.site, model.site(site) != nil {
            switch card.entity {
            case "order":
                model.open(.order(site: site, id: card.id))
                return
            case "support_thread":
                model.open(.thread(site: site, id: card.id))
                return
            case "assistant_conversation":
                model.open(.xenaConversation(site: site, id: card.id))
                return
            default:
                break
            }
        }
        if let href = card.href, let url = URL(string: href, relativeTo: ConsoleConfig.baseURL)?.absoluteURL {
            openURL(url)
        }
    }
}

private struct EntityCardView: View {
    let card: EntityCard

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(card.kind)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 6)
                if let badge = card.badge {
                    StatusBadge(badge.label, tone: Tone(card: badge.tone))
                }
            }
            Text(card.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            ForEach(card.fields.prefix(3), id: \.self) { field in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(field.label).foregroundStyle(Theme.faint)
                    Text(field.value).foregroundStyle(Theme.ink)
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }
        }
        .frame(width: 230, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: Metric.xenaCard, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Metric.xenaCard, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
    }
}

/// Xena 問你（ask_user）：選一個，或自己寫
private struct AskView: View {
    let ask: AskItem
    var disabled = false
    var onAnswer: (String) -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ask.question)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if let answer = ask.answer {
                Label { Text(answer) } icon: { HeroIcon("check", size: 14) }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } else {
                ChipFlow(items: ask.options, disabled: disabled, onTap: onAnswer)
                if ask.allowText {
                    HStack(spacing: 8) {
                        TextField("自己寫…", text: $text)
                            .font(.system(size: 15))
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line) }
                        Button("送出") { onAnswer(text) }
                            .buttonStyle(.brand(.primary, size: .lg))
                            .disabled(disabled || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.soft, in: .rect(cornerRadius: Metric.xenaCard, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Metric.xenaCard, style: .continuous).strokeBorder(Theme.line) }
    }
}

/// Xena 在查資料（.cp-status：三個跳動的點）
private struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            OrbIcon(size: 16)
            TimelineView(.periodic(from: .now, by: 0.15)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.15) % 8
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .frame(width: 5, height: 5)
                            .opacity(step == i * 2 || step == i * 2 + 1 ? 1 : 0.25)
                            .offset(y: step == i * 2 ? -2 : 0)
                    }
                }
            }
            Text("Xena 正在查…")
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.muted)
    }
}

/// 對話紀錄（和網頁版共用）
private struct ThreadListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.xena.threads) { thread in
                    Button {
                        Task { await model.xena.open(thread: thread.id) }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thread.title)
                                .textRole(.h4)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            if let date = thread.updatedAt.flatMap({ JSONValue.string($0).date }) {
                                Text(date.shortText)
                                    .textRole(.xs)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .listRowBackground(thread.id == model.xena.threadID ? Theme.accentSoft : Theme.surface)
                }
                .onDelete { offsets in
                    let ids = offsets.map { model.xena.threads[$0].id }
                    Task { for id in ids { await model.xena.deleteThread(id) } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sheet)
            .overlay {
                if model.xena.threads.isEmpty {
                    EmptyState(title: "還沒有對話", message: "在網頁或 App 跟 Xena 說過的話都會在這裡。")
                }
            }
            .navigationTitle("對話紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await model.xena.loadThreads() }
        .presentationDetents([.medium, .large])
    }
}

/// tab bar 上面常駐的 Xena（後台右下角的水滴）：輪播她正在看著的事，點了打開對話
struct XenaAccessory: View {
    @Environment(AppModel.self) private var model

    private var lines: [String] {
        let b = model.briefing
        var out = ["值班中・看著 \(model.sites.count) 個網站"]
        if !b.awaiting.isEmpty { out.append("\(b.awaiting.count) 位客人在等回覆") }
        let ship = b.toShip.values.reduce(0) { $0 + $1.count }
        if ship > 0 { out.append("\(ship) 筆訂單等出貨") }
        let live = model.sites.reduce(0) { $0 + ($1.stats?.live ?? 0) }
        if live > 0 { out.append("現在 \(live) 人在你的網站上") }
        return out
    }

    var body: some View {
        Button {
            model.showXena = true
        } label: {
            HStack(spacing: 10) {
                OrbIcon(size: 24)
                TimelineView(.periodic(from: .now, by: 4)) { context in
                    let all = lines
                    let index = Int(context.date.timeIntervalSinceReferenceDate / 4) % max(all.count, 1)
                    Text(model.xena.isBusy ? model.xena.mood.label : all[index])
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(.smooth, value: index)
                }
                Spacer(minLength: 0)
                HeroIcon("sparkles", size: 16)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("跟 Xena 說話")
    }
}
