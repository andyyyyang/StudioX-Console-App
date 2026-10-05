import SwiftUI
import UIKit

/// Face ID 鎖住時的畫面：和歡迎頁同一個語氣（紙色、細線、Xena 的水滴），一個解鎖鈕。
/// 打開 App、回到 App 時會自己跳 Face ID；取消了就按「解鎖」再來一次。
struct LockView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingSignOut = false
    @State private var appeared = false

    var body: some View {
        let lock = model.lock
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark()
                    .foregroundStyle(Theme.ink)
                    .frame(width: 22, height: 22)
                Text("\(Text("studiox").foregroundStyle(Theme.ink))\(Text(".").foregroundStyle(Theme.accent))")
                    .font(.brand(20, .semibold))
                    .tracking(-0.8)
                Spacer()
                LiveDot()
                Text("Xena 值班中")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 22) {
                XenaOrb(mood: .idle, size: 72)
                    .padding(.leading, -12)
                Eyebrow("已鎖定")
                Headline("歡迎回來", role: .hero)
                Text("用\(lock.method.name)解鎖，繼續管理你的網站。")
                    .textRole(.lead)
                    .foregroundStyle(Theme.ink2)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            Spacer(minLength: 40)
            VStack(spacing: 12) {
                Button {
                    Task { await lock.unlock() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: lock.method.symbol)
                            .font(.system(size: 18, weight: .medium))
                        Text("用\(lock.method.name)解鎖")
                    }
                }
                .buttonStyle(.brand(.primary, size: .lg, fullWidth: true))
                .disabled(lock.authenticating)
                Button("登出") { confirmingSignOut = true }
                    .buttonStyle(.brand(.ghost, size: .lg, fullWidth: true))
                    .disabled(lock.authenticating)
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: Metric.readable, maxHeight: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background {
            // 和首頁的 hero 同一個背景：點陣、柔光
            ZStack {
                Theme.page
                DotGrid()
                Glow(size: 380)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 80, y: -40)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(Motion.slow.delay(0.1)) { appeared = true }
        }
        .confirmationDialog("要登出嗎？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("登出", role: .destructive) { Task { await model.signOut() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("這台裝置的登入會撤銷、不再收到通知。")
        }
    }
}

/// 切換 App、拉下通知中心時蓋住畫面（多工畫面看不到訂單、客人資料）
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.page.ignoresSafeArea()
            BrandMark()
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
        }
        .accessibilityHidden(true)
    }
}

/// 鎖定畫面與遮罩放在這個畫面自己的視窗裡：比 sheet（Xena、確認卡片、編輯）還高，才蓋得住。
/// 不需要的時候整個視窗藏起來，不擋觸控。
final class LockWindow {
    /// 這個畫面所在的 scene（iPad 開好幾個視窗時各自蓋）
    var scene: UIWindowScene? {
        didSet {
            guard scene !== oldValue else { return }
            window?.isHidden = true
            window = nil
            apply()
        }
    }

    private var window: UIWindow?
    private var visible = false
    private weak var model: AppModel?

    func show(_ visible: Bool, model: AppModel) {
        self.visible = visible
        self.model = model
        apply()
    }

    private func apply() {
        guard visible else {
            window?.isHidden = true
            return
        }
        if window == nil, let scene, let model {
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1
            w.backgroundColor = .clear
            let host = UIHostingController(rootView: LockOverlay()
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
                .tint(Theme.primary)
                .appSettingsAppearance())
            host.view.backgroundColor = .clear
            w.rootViewController = host
            window = w
        }
        // 正在打字的話把鍵盤收起來（鍵盤在更高的視窗，會露在鎖定畫面上面）
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        window?.isHidden = false
    }
}

private struct LockOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.lock.locked {
                LockView()
                    .transition(.opacity)
            } else {
                PrivacyCover()
                    .transition(.opacity)
            }
        }
        .animation(Motion.ease, value: model.lock.locked)
    }
}

/// 拿到這個畫面所在的 UIWindowScene
struct SceneProbe: UIViewRepresentable {
    let found: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.found = found
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.found = found
    }

    final class ProbeView: UIView {
        var found: ((UIWindowScene) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { found?(scene) }
        }
    }
}
