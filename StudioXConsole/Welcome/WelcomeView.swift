import AuthenticationServices
import SwiftUI

/// 歡迎頁＝登入頁：和 console 的網頁登入同一套品牌（atelier-cms 的 auth/AuthScreen.tsx）。
///   上面：大字 StudioX ＋ 3D 玻璃 Logo（studiox.tw 首頁同一份：三塊積木轉著散開又組合，可以用手指抓著玩）
///   下面：透明的玻璃面板，Xena 打招呼；「用 StudioX 帳號登入」打開 console 的登入頁（Apple、Email、邀請都一樣）
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var covered: CGFloat = 320
    @State private var assemble = 0
    @State private var busy = false
    @State private var error: String?

    private var line: String {
        if busy { return "我在等你登入，好了就回來這裡。" }
        if error != nil { return "沒有登入成功，再試一次？" }
        return "嗨，我是 Xena，你的店長。24 小時看著你的每個網站，登入之後我把要你注意的事說給你聽。"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Theme.paper.ignoresSafeArea()
                LogoWebView(coveredBottom: covered, assemble: assemble)
                    .ignoresSafeArea()
                panel
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        covered = height + geo.safeAreaInsets.bottom + 8
                    }
            }
        }
        .onAppear { error = model.loadError }
    }

    private var panel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                XenaOrb(mood: busy ? .thinking : .idle, size: 36)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Xena · 店長")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                    TypewriterText(text: line)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.paperInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Text("登入 StudioX Console")
                .font(.system(size: 17))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 4)

            if let error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dangerFG)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button {
                Task { await signIn() }
            } label: {
                HStack(spacing: 10) {
                    if busy {
                        ProgressView().tint(Theme.paper)
                    } else {
                        BrandMark()
                            .foregroundStyle(Theme.paper)
                            .frame(width: 18, height: 18)
                    }
                    Text(busy ? "登入中…" : "用 StudioX 帳號登入")
                }
            }
            .buttonStyle(AuthButtonStyle())
            .disabled(busy)

            Text("Apple 或 Email 都可以。收到邀請連結的話，直接打開連結就能加入網站。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: 440)
        .glassEffect(.regular.tint(Theme.paper.opacity(0.35)), in: .rect(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .animation(.smooth, value: error)
    }

    private func signIn() async {
        guard !busy else { return }
        busy = true
        error = nil
        assemble += 1
        do {
            try await model.signIn(using: webAuthenticationSession)
        } catch AuthError.cancelled {
            // 使用者自己關掉登入視窗
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}

/// 登入頁的膠囊按鈕（AuthScreen.tsx 的 .au-btn--dark：56 高、全圓角、17 號字）
struct AuthButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.17)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Theme.paper)
            .background(Theme.paperInk, in: .capsule)
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
