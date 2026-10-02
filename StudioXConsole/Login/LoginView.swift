import SwiftUI

/// 登入畫面（和 console 的網頁登入同一套：atelier-cms 的 auth/AuthScreen.tsx、login/LoginPanel.tsx）
///   上半部：大字品牌名＋玻璃標誌（Liquid Glass，三塊積木會散開又組合，可以拖著玩）
///   下半部：玻璃面板：Xena 打招呼、透過 Apple（黑）／用 Email（玻璃），Email 展開成表單
struct LoginView: View {
    @Environment(AppModel.self) private var model

    @State private var panel: Panel = .choose
    @State private var email = ""
    @State private var password = ""
    @State private var pending: Pending?
    @State private var message: String?
    @FocusState private var field: Field?

    private enum Panel {
        case choose, email
    }

    private enum Pending {
        case apple, email
    }

    private enum Field {
        case email, password
    }

    private var mood: XenaMood {
        if pending != nil { return .thinking }
        if message != nil { return .alert }
        if field != nil { return .listening }
        return .idle
    }

    private var xenaLine: String {
        if pending != nil { return "確認身分中，等我一下…" }
        if message != nil { return "好像不太對，再試一次？" }
        if field != nil { return "我在聽。用你的 StudioX 帳號登入就好。" }
        return "嗨，我是 Xena，這裡的店長。我 24 小時幫你看著每個網站，登入之後把昨晚的事說給你聽。"
    }

    var body: some View {
        ZStack {
            Brand.paper.ignoresSafeArea()
            AmbientField().ignoresSafeArea()
            VStack(spacing: 0) {
                hero
                sheet
            }
        }
        .animation(.smooth(duration: 0.35), value: panel)
        .animation(.smooth(duration: 0.35), value: message)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            Wordmark()
                .padding(.horizontal, 18)
                .padding(.top, 8)
            GlassMark()
                .frame(maxWidth: 320)
                .padding(.horizontal, 56)
                .padding(.vertical, 8)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sheet: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                XenaOrb(mood: mood, size: 40)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Xena · 店長")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                    TypewriterText(text: xenaLine, speed: .milliseconds(28))
                        .font(.system(size: 15))
                        .foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 4)

            Text("登入 StudioX Console")
                .font(.system(size: 17))
                .foregroundStyle(Brand.muted)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Brand.danger)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            switch panel {
            case .choose:
                chooseButtons
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .email:
                emailForm
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Text("收到邀請連結的話，直接打開連結就能加入網站。")
                .font(.footnote)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 36))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var chooseButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await signIn(.apple) }
            } label: {
                HStack(spacing: 10) {
                    if pending == .apple {
                        ProgressView().tint(Brand.onInk)
                    } else {
                        Image(systemName: "apple.logo")
                    }
                    Text("透過 Apple 登入")
                }
            }
            .buttonStyle(.pill(.dark))

            Button {
                message = nil
                panel = .email
                field = .email
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                    Text("用 Email 登入")
                }
            }
            .buttonStyle(.pill(.light))
        }
        .disabled(pending != nil)
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Email").font(.footnote).foregroundStyle(Brand.muted)
                TextField("you@studiox.tw", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($field, equals: .email)
                    .onSubmit { field = .password }
                    .fieldChrome(focused: field == .email)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("密碼").font(.footnote).foregroundStyle(Brand.muted)
                SecureField("", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($field, equals: .password)
                    .onSubmit { Task { await signIn(.email(email, password)) } }
                    .fieldChrome(focused: field == .password)
            }
            Button {
                Task { await signIn(.email(email, password)) }
            } label: {
                HStack(spacing: 10) {
                    if pending == .email { ProgressView().tint(Brand.onInk) }
                    Text(pending == .email ? "登入中…" : "登入")
                }
            }
            .buttonStyle(.pill(.dark))
            .padding(.top, 4)

            Button {
                message = nil
                field = nil
                panel = .choose
            } label: {
                Text("其他登入方式")
                    .underline()
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            }
            .buttonStyle(.plain)
        }
        .disabled(pending != nil)
    }

    private func signIn(_ method: SignInMethod) async {
        guard pending == nil else { return }
        if case .apple = method { pending = .apple } else { pending = .email }
        message = nil
        field = nil
        do {
            try await model.signIn(method)
        } catch {
            pending = nil
            message = error.localizedDescription
        }
    }
}

#Preview {
    LoginView()
        .environment(AppModel())
}
