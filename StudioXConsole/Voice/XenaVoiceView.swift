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
        let orb: CGFloat = regular ? 240 : 190
        let light = orb * 2.4
        VStack(spacing: 0) {
            header

            Spacer(minLength: 12)

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

            Spacer(minLength: 12)

            subtitles
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)

            if let confirm = c.pendingConfirm {
                confirmPrompt(confirm)
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            mainButton
                .padding(.top, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Theme.page.ignoresSafeArea() }
        .animation(Motion.ease, value: c.pendingConfirm)
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

    @ViewBuilder
    private var subtitles: some View {
        let c = model.conversation
        ScrollView {
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
                        .textRole(.lead)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .animation(.smooth, value: c.heard)
            .animation(.smooth, value: c.reply)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .frame(maxHeight: sizeClass == .regular ? 260 : 200)
    }

    private func confirmPrompt(_ title: String) -> some View {
        Button {
            model.showVoice = false
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                model.showXena = true
            }
        } label: {
            HStack(spacing: 10) {
                HeroIcon("hand-raised", size: 18)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("要你確認")
                        .font(.brand(12, .medium))
                        .foregroundStyle(Theme.muted)
                    Text(title)
                        .font(.brand(15, .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text("去確認 →")
                    .font(.brand(14, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line) }
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
        case .listening: return c.heard.isEmpty ? "我在聽，請說" : "說完停一下就好"
        case .thinking: return "想一下…"
        case .speaking: return "點一下水珠可以打斷"
        case .paused: return c.pendingConfirm != nil ? "這件事要你在畫面上確認" : "點一下水珠，換你說"
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
