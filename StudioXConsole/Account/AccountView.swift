import SwiftUI

/// 我（後台左下角的頭貼選單）：帳號、各網站的職能、Xena、console、登出
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false
    @State private var showingNotifications = false

    private var version: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let b = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        return "\(v)（\(b)）"
    }

    var body: some View {
        NavigationStack(path: Bindable(model).accountPath) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 56) {
                        if let me = model.me {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(spacing: 14) {
                                    Avatar(name: me.name, imageURL: me.imageURL, size: 60)
                                    VStack(alignment: .leading, spacing: 4) {
                                        if me.staff { Eyebrow("StudioX 團隊") } else { Eyebrow("StudioX 帳號") }
                                        Text(me.email)
                                            .textRole(.small)
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                                Headline("Hello, *\(me.name)*", role: .h1)
                            }
                            .reveal()
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("Your *roles*", aside: "職能由網站負責人在 StudioX Console 設定。", role: .h3)
                            RuledList {
                                ForEach(model.sites) { site in
                                    HStack(spacing: 14) {
                                        SiteIconView(site: site, size: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(site.name).textRole(.h4).foregroundStyle(Theme.ink)
                                            Text(site.host).textRole(.xs).foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                        Chip(site.levelLabel)
                                    }
                                    .padding(.vertical, 14)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("*Notifications*", aside: "網站有需要你處理的事，從這裡通知你。", role: .h3)
                            RuledList {
                                row("通知", value: notificationStatus) { showingNotifications = true }
                            }
                        }

                        SecuritySection()

                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("*Xena*", aside: "App 和網頁上是同一個 Xena、同一份對話紀錄。", role: .h3)
                            RuledList {
                                row("跟 Xena 說話") { model.showXena = true }
                                row("動手改東西之前", value: "一律先問你", action: nil)
                                row("退款、刪除", value: "要打字確認", action: nil)
                            }
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("*Console*", aside: "在瀏覽器打開 StudioX Console。", role: .h3)
                            RuledList {
                                row("網站與成員") { openURL(ConsoleConfig.baseURL.appending(path: "sites")) }
                                row("連接外部 AI 的授權") { openURL(ConsoleConfig.baseURL.appending(path: "sites")) }
                                row("版本", value: version, action: nil)
                            }
                            ConnectorCard()
                        }

                        Button {
                            confirmingSignOut = true
                        } label: { Text("登出") }
                        .buttonStyle(.brand(.danger, size: .lg, fullWidth: true))
                    }
                    .frame(maxWidth: Metric.readable + 120, alignment: .leading)
                    .pageWidth()
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Built with care in Tainan.")
                            .font(.serif(18, italic: true))
                            .foregroundStyle(Theme.inverseMuted)
                        Wordmark(color: Theme.onInverse)
                    }
                    .pageWidth()
                    .padding(.top, 48)
                    .padding(.bottom, 24)
                    .background(Theme.inverse)
                    .padding(.top, 72)
                }
            }
            .brandPage()
            .navigationTitle("我")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .navigationDestination(isPresented: $showingNotifications) { NotificationSettingsView() }
            .confirmationDialog("要登出嗎？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("登出", role: .destructive) { Task { await model.signOut() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這台裝置的登入會撤銷、不再收到通知，其他裝置與 AI 連接器不受影響。")
            }
        }
    }

    private var notificationStatus: String {
        let push = model.push
        switch push.permission {
        case .allowed:
            if push.configured == false { return "伺服器還沒設定" }
            guard let device = push.device else { return "登記中" }
            let muted = device.mutedSites.filter { id in model.sites.contains { $0.id == id } }.count
            return muted == 0 ? "開著" : "關掉 \(muted) 個網站"
        case .denied: return "被關掉了"
        case .notDetermined: return "還沒打開"
        case .unknown: return ""
        }
    }

    @ViewBuilder
    private func row(_ title: String, value: String? = nil, action: (() -> Void)?) -> some View {
        let content = HStack(spacing: 12) {
            Text(title)
                .textRole(.h4)
                .foregroundStyle(Theme.ink)
            Spacer()
            if let value {
                Text(value).textRole(.small).foregroundStyle(Theme.muted)
            }
            if action != nil {
                Text("→").font(.brand(18, .medium)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 16)
        .contentShape(.rect)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.row)
        } else {
            content
        }
    }
}

/// 安全：Face ID 鎖住 App、離開多久要解鎖、危險動作前再驗證一次（存在這台裝置）
private struct SecuritySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let lock = model.lock
        VStack(alignment: .leading, spacing: 20) {
            SectionHead("*Security*", aside: lock.available ? "存在這台裝置，換手機要重新設定。" : "這台裝置沒有設定密碼，不能鎖。", role: .h3)
            RuledList {
                ToggleRow(label: "用\(lock.method.name)鎖住 App", help: "打開 App、離開一陣子回來，要先解鎖。切換 App 時畫面會蓋起來。", isOn: Binding(
                    get: { lock.enabled },
                    set: { value in
                        if value {
                            // 先驗證一次，確定解得開
                            Task { _ = await lock.enable() }
                        } else {
                            Task { await lock.turnOff(\.enabled) }
                        }
                    }
                ))
                .padding(.vertical, 10)
                .disabled(!lock.available)

                if lock.enabled && lock.available {
                    HStack {
                        Text("離開多久要解鎖")
                            .textRole(.body)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Picker("離開多久要解鎖", selection: Binding(get: { lock.timeout }, set: { value in Task { await lock.setTimeout(value) } })) {
                            ForEach(AppLock.Timeout.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .labelsHidden()
                        .tint(Theme.ink2)
                    }
                    .padding(.vertical, 12)
                }

                ToggleRow(label: "退款、刪除前再驗證一次", help: "確認執行之前跳\(lock.method.name)，手機借別人看也不會被按下去。", isOn: Binding(
                    get: { lock.confirmDangerous },
                    set: { value in
                        if value {
                            lock.confirmDangerous = true
                        } else {
                            Task { await lock.turnOff(\.confirmDangerous) }
                        }
                    }
                ))
                .padding(.vertical, 10)
                .disabled(!lock.available)
            }
        }
    }
}
