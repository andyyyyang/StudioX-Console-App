import SwiftUI

/// 用說的跟 Xena 聊（整個畫面）：中間是會動的 3D 水珠（你說話時跟著你的音量、她說話時跟著每個字），
/// 下面是字幕（你說的、她說的），最下面一個大按鈕。點水珠也可以：她在說就打斷換你說，你在說就當作說完。
struct XenaVoiceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL
    /// 對話的捲動位置：在最下面就跟著新的字往下；你往上翻在看之前的，就不拉你下來
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var pinned = true

    var body: some View {
        let c = model.conversation
        let regular = sizeClass == .regular
        // 她丟出東西（問題、卡片、確認）時水珠縮小，讓位給畫面上的東西
        let busy = !c.turnItems.isEmpty || c.readingCard != nil
        let orb: CGFloat = busy ? (regular ? 150 : 104) : (regular ? 240 : 190)
        let light = orb * 2.4
        VStack(spacing: 0) {
            header

            Spacer(minLength: busy ? 4 : 12)

            Button { Task { await c.tap() } } label: {
                XenaOrb(mood: c.mood, size: orb, pulse: model.xena.pulse, voice: c.activeVoice, light: light)
                    .background { XenaLight(radius: light) }
                    .contentShape(Circle())
            }
            .buttonStyle(.press)
            .accessibilityLabel(orbHint)
            .zIndex(-1)

            Text(status)
                .textRole(.small)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.smooth, value: status)
                .padding(.top, 4)
                .padding(.horizontal, 32)

            Spacer(minLength: busy ? 8 : 12)

            conversation
                .frame(maxWidth: 600)
                .padding(.horizontal, 20)

            if XenaMouth.usingCompactVoice && AppSettings.shared.speakReplies && !DemoServer.screenshots {
                voiceTip
                    .padding(.top, 8)
            }

            mainButton
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.page.ignoresSafeArea() }
        .animation(Motion.ease, value: busy)
        .task { await c.start() }
        .onDisappear { c.end() }
        .onChange(of: model.xena.revision) { c.sessionChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                c.end()
                model.showVoice = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.showVoice = false
            } label: {
                HeroIcon("x-mark", size: 20)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.press)
            .accessibilityLabel("結束")
            Spacer()
            VStack(spacing: 1) {
                Text("Xena")
                    .font(.brand(16, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("用說的")
                    .font(.brand(12, .regular))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            // 改用打字：同一個對話
            Button {
                model.showVoice = false
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    model.showXena = true
                }
            } label: {
                HeroIcon("chat-bubble-left-right", size: 20)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.press)
            .accessibilityLabel("改用打字")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 一輪一輪的對話（你說的、她說的、她丟出來的問題和卡片，和打字的對話同一個樣子，可以直接按）。
    /// 之前的每一輪都留著，往上滑找得回來；說完時你說的那一塊直接接成新的一輪，上一輪的字變淡往上移
    private var conversation: some View {
        let c = model.conversation
        let turns = c.turns
        return ScrollView {
            VStack(spacing: 28) {
                ForEach(turns) { turn in
                    TurnView(turn: turn, live: turn.id == c.liveID || turn.id == c.nextID) { c.readAloud($0) }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 18)),
                            removal: .opacity
                        ))
                }
            }
            .padding(.top, c.history.isEmpty ? 0 : 28)
            .padding(.bottom, 8)
            .animation(.smooth(duration: 0.45), value: turns.map(\.id))
            .animation(.smooth, value: c.heard)
            .animation(.smooth, value: c.reply)
            .animation(.smooth, value: c.turnItems.map(\.id))
            .animation(.smooth, value: c.readingCard)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 48
        } action: { _, atBottom in
            pinned = atBottom
        }
        .onChange(of: scrollKey) {
            guard pinned else { return }
            withAnimation(.smooth(duration: 0.45)) { position.scrollTo(edge: .bottom) }
        }
        .scrollIndicators(.hidden)
        // 上緣淡出：之前的對話在上面慢慢消失，不是一刀切
        .mask {
            if c.history.isEmpty {
                Rectangle()
            } else {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.16),
                    .init(color: .black, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(maxHeight: c.turnItems.isEmpty && c.readingCard == nil ? (sizeClass == .regular ? 260 : 200) : .infinity)
    }

    /// 內容有變（新的一輪、新的字、新的卡片）就捲到最下面（你在最下面的時候）
    private var scrollKey: String {
        let c = model.conversation
        return "\(c.history.count)|\(c.said)|\(c.heard)|\(c.reply.count)|\(c.turnItems.map(\.id))|\(c.readingCard?.points.count ?? -1)"
    }

    /// 用的是精簡版的聲音：提醒可以免費換成自然一點的
    private var voiceTip: some View {
        Button {
            model.showVoice = false
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                model.goToAccount()
            }
        } label: {
            Text("聲音太機械？免費換 Han 或 Lilian →")
                .font(.brand(13, .medium))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.press)
    }

    @ViewBuilder
    private var mainButton: some View {
        let c = model.conversation
        if c.needsSettings {
            Button("打開 iPhone 的設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.brand(.primary, size: .lg))
        } else {
            Button(mainTitle) { Task { await c.tap() } }
                .buttonStyle(.brand(c.state == .listening ? .primary : .ghost, size: .lg))
                .disabled(c.state == .preparing)
        }
    }

    private var mainTitle: String {
        switch model.conversation.state {
        case .listening: "說完了"
        case .speaking, .thinking: "打斷，換我說"
        case .preparing: "準備中…"
        case .failed: "再試一次"
        case .paused, .off: "按一下說話"
        }
    }

    private var status: String {
        let c = model.conversation
        switch c.state {
        case .off, .preparing: return "準備中…"
        case .listening:
            if c.pendingCard != nil && c.heard.isEmpty { return "說「確認」或「取消」" }
            if c.pendingAsk != nil && c.heard.isEmpty { return "直接說你的答案，或按選項" }
            return c.heard.isEmpty ? "我在聽，請說" : "說完停一下就好"
        case .thinking: return "想一下…"
        case .speaking: return "點一下水珠可以打斷"
        case .paused: return c.pendingCard != nil ? "這件事要你在畫面上確認" : "點一下水珠，換你說"
        case .failed(let message): return message
        }
    }

    private var orbHint: String {
        switch model.conversation.state {
        case .listening: "說完了"
        case .speaking, .thinking: "打斷，換我說"
        default: "開始說話"
        }
    }
}

/// 一輪：你說的、她回的（字、長回答卡片、她丟出來的問題和卡片）。
/// 之前的輪字變淡（顏色慢慢變），卡片照樣可以按，狀態跟著對話更新（確認了就顯示結果）
private struct TurnView: View {
    let turn: VoiceTurn
    let live: Bool
    let onRead: (ReadingCard) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let plain = turn.items.isEmpty && turn.card == nil
        VStack(spacing: 14) {
            if !turn.said.isEmpty {
                Text("「\(turn.said)」")
                    .textRole(.body)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .opacity(live ? 1 : 0.7)
            }
            if let card = turn.card {
                ReplyCard(card: card) { onRead(card) }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if !turn.reply.isEmpty {
                Text(markdown(turn.reply))
                    .textRole(plain ? .lead : .body)
                    .foregroundStyle(live ? Theme.ink : Theme.muted)
                    .multilineTextAlignment(plain ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: plain ? .center : .leading)
            }
            ForEach(turn.items) { item in
                // 之前的輪：用對話裡最新的樣子（確認卡片決定了、問題回答了）
                ChatItemView(item: live ? item : (model.xena.items.first(where: { $0.id == item.id }) ?? item))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.5), value: live)
    }
}

/// 太長的回答：標題、重點（Apple Intelligence 寫的），整段原文收在「全文」裡；下面一顆「念給我聽」
private struct ReplyCard: View {
    let card: ReadingCard
    let onRead: () -> Void
    @State private var full = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !card.title.isEmpty {
                Text(card.title)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
            }
            if card.points.isEmpty {
                fullText
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(card.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                            Text(point)
                                .font(.system(size: 15))
                                .lineSpacing(4)
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if full {
                    Divider().overlay(Theme.line)
                    fullText
                        .transition(.opacity)
                }
            }
            HStack(spacing: 10) {
                Button(action: onRead) {
                    Label { Text("念給我聽") } icon: { HeroIcon("microphone", size: 15) }
                        .font(.brand(14, .semibold))
                }
                .buttonStyle(.brand(.ghost, size: .sm))
                if !card.points.isEmpty {
                    Button(full ? "收起來" : "看全文") {
                        withAnimation(Motion.ease) { full.toggle() }
                    }
                    .font(.brand(14, .medium))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.press)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: Metric.xenaCard, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Metric.xenaCard, style: .continuous).strokeBorder(Theme.line) }
    }

    private var fullText: some View {
        Text(markdown(card.text))
            .font(.system(size: 15))
            .lineSpacing(5)
            .foregroundStyle(Theme.ink)
            .tint(Theme.accent)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
