import SwiftUI

/// 用說的跟 Xena 聊（整個畫面）：中間是會動的 3D 水珠（你說話時跟著你的音量、她說話時跟著每個字），
/// 下面是字幕（你說的、她說的），最下面一個大按鈕。點水珠也可以：她在說就打斷換你說，你在說就當作說完。
struct XenaVoiceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL

    var body: some View {
        let c = model.conversation
        let regular = sizeClass == .regular
        // 她丟出東西（問題、卡片、確認）時水珠縮小，讓位給畫面上的東西
        let busy = !c.turnItems.isEmpty
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

            if XenaMouth.usingCompactVoice && AppSettings.shared.speakReplies {
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

    /// 字幕（你說的、她說的）和她丟出來的東西（問題＋選項、資料卡片、確認卡片：和打字的對話同一個樣子，可以直接按）
    private var conversation: some View {
        let c = model.conversation
        return ScrollView {
            VStack(spacing: 14) {
                if !c.heard.isEmpty {
                    Text("「\(c.heard)」")
                        .textRole(.body)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                if !c.reply.isEmpty {
                    Text(markdown(c.reply))
                        .textRole(c.turnItems.isEmpty ? .lead : .body)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(c.turnItems.isEmpty ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: c.turnItems.isEmpty ? .center : .leading)
                }
                ForEach(c.turnItems) { item in
                    ChatItemView(item: item)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.bottom, 8)
            .animation(.smooth, value: c.heard)
            .animation(.smooth, value: c.reply)
            .animation(.smooth, value: c.turnItems.map(\.id))
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .frame(maxHeight: c.turnItems.isEmpty ? (sizeClass == .regular ? 260 : 200) : .infinity)
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
