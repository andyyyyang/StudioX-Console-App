import AVFoundation
import SwiftUI

/// 設定（手機：首頁右上角的齒輪；iPad：側欄）：帳號、外觀、Xena、首頁、通知、安全、各網站的職能、console、登出、刪除帳號。
/// 可以微調的偏好在 AppSettings（存在這台裝置，改了馬上生效）
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var showingNotifications = false

    private var version: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let b = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        return "\(v)（\(b)）"
    }

    var body: some View {
        @Bindable var settings = AppSettings.shared
        NavigationStack(path: Bindable(model).accountPath) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 56) {
                        if let me = model.me {
                            HStack(spacing: 14) {
                                Avatar(name: me.name, imageURL: me.imageURL, size: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(me.name)
                                        .textRole(.h3)
                                        .foregroundStyle(Theme.ink)
                                    Text(me.email)
                                        .textRole(.small)
                                        .foregroundStyle(Theme.muted)
                                    if me.staff { Eyebrow("StudioX 團隊") }
                                }
                            }
                            .reveal()
                        }

                        // 外觀：主題、字的大小、觸覺回饋
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("*Appearance*", role: .h3)
                            RuledList {
                                ChoiceRow(label: "主題", options: AppSettings.Appearance.allCases, selection: $settings.appearance) { $0.label }
                                ChoiceRow(label: "文字大小", options: AppSettings.TextSize.allCases, selection: $settings.textSize) { $0.label }
                                ToggleRow(label: "觸覺回饋", isOn: $settings.haptics)
                                    .padding(.vertical, 10)
                            }
                        }

                        // Xena：首頁開場要不要說話、說多快、水珠會不會動
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("*Xena*", role: .h3)
                            RuledList {
                                ChoiceRow(label: "首頁開場說今天的狀況", help: settings.greeting.help,
                                          options: AppSettings.Greeting.allCases, selection: $settings.greeting) { $0.label }
                                ChoiceRow(label: "說話速度", options: AppSettings.Pace.allCases, selection: $settings.pace) { $0.label }
                                    .disabled(settings.greeting == .quiet)
                                    .opacity(settings.greeting == .quiet ? 0.45 : 1)
                                ToggleRow(label: "水珠會動", help: "關掉比較省電。", isOn: $settings.orbMotion)
                                    .padding(.vertical, 10)
                                row("問問Xena") { model.showXena = true }
                                row("動手改東西之前", value: "一律先問你", action: nil)
                                row("退款、刪除", value: "要打字確認", action: nil)
                            }
                        }

                        // 聲音：用說的時 Xena 用哪個聲音回答（預設 iPhone 內建、免費）
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("*Voice*", role: .h3)
                            RuledList {
                                ToggleRow(label: "用說的時，Xena 開口回答", isOn: $settings.speakReplies)
                                    .padding(.vertical, 10)
                                ChoiceRow(label: "聲音從哪裡來", help: settings.voiceSource == .iphone
                                          ? "iPhone 內建的聲音，不用錢、沒網路也能用。"
                                          : "回答的文字經 StudioX Console 送到 OpenAI（或 Google）轉成聲音，比較像真人；會用到 StudioX 的 AI 額度（大約每說一分鐘不到新台幣 1 元），不會保存。",
                                          options: AppSettings.VoiceSource.allCases, selection: $settings.voiceSource) { $0.label }
                                if settings.voiceSource == .iphone {
                                    HStack(spacing: 12) {
                                        Text("哪個聲音")
                                            .textRole(.body)
                                            .foregroundStyle(Theme.ink)
                                        Spacer()
                                        Picker("哪個聲音", selection: $settings.voiceID) {
                                            Text("自動（Han → Lilian → 最好的）").tag("")
                                            ForEach(XenaMouth.voices, id: \.identifier) { voice in
                                                Text(XenaMouth.label(voice)).tag(voice.identifier)
                                            }
                                        }
                                        .labelsHidden()
                                        .tint(Theme.ink2)
                                    }
                                    .padding(.vertical, 12)
                                    Text(XenaMouth.usingCompactVoice
                                         ? "現在用的是「精簡」版，聽起來比較機械。免費換自然一點的：iPhone 的「設定 → 輔助使用 → 朗讀內容 → 聲音 → 中文」，推薦下載 Han 或 Lilian（挑「加強」或「高品質」），回來這裡選「自動」就會用它。"
                                         : "想換別的聲音：iPhone 的「設定 → 輔助使用 → 朗讀內容 → 聲音 → 中文」可以免費下載更多（推薦 Han、Lilian）。")
                                        .textRole(.xs)
                                        .foregroundStyle(XenaMouth.usingCompactVoice ? Theme.ink2 : Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.vertical, 12)
                                } else {
                                    ChoiceRow(label: "哪個聲音", options: AppSettings.CloudVoice.allCases, selection: $settings.cloudVoice) { $0.label }
                                }
                                row("試聽") { preview() }
                            }
                        }

                        // Apple Intelligence：手機上的模型（離線、資料不出手機）
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("Apple *Intelligence*", aside: XenaLocal.shared.status, role: .h3)
                            RuledList {
                                ToggleRow(label: "寫首頁的開場白", help: "用手機上的模型把今天的狀況寫成她會說的話；數字會一個一個核對，對不上就用原本的句子。", isOn: $settings.aiGreeting)
                                    .padding(.vertical, 10)
                                ToggleRow(label: "用說的時先在手機上聽懂", help: "切頁、念卡片、再說一次、確認、選選項、閒聊，手機上馬上處理；其他的整理好再交給 Xena。太長的回答濃縮成重點、放卡片。", isOn: $settings.aiCommands)
                                    .padding(.vertical, 10)
                            }
                            .disabled(!XenaLocal.shared.available)
                            .opacity(XenaLocal.shared.available ? 1 : 0.45)
                        }

                        // 客服對話：輸入框上面的回覆建議
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("Reply *suggestions*", aside: "回覆客人時，輸入框上面先放幾句可以直接用的", role: .h3)
                            RuledList {
                                ChoiceRow(label: "下一句誰來想", help: settings.replySuggest.help, options: AppSettings.ReplySuggest.allCases, selection: $settings.replySuggest) { $0.label }
                            }
                        }

                        // 首頁：打開 App 先看哪一頁、首頁放哪些
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("*Home*", role: .h3)
                            RuledList {
                                ChoiceRow(label: "打開 App 先看", options: startTabs, selection: $settings.startTab) { $0.label }
                                ForEach(AppSettings.HomeSection.allCases) { section in
                                    ToggleRow(label: section.label, isOn: Binding(
                                        get: { settings.shows(section) },
                                        set: { settings.setShows(section, $0) }
                                    ))
                                    .padding(.vertical, 8)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("*Notifications*", role: .h3)
                            RuledList {
                                row("通知", value: notificationStatus) { showingNotifications = true }
                            }
                        }

                        SecuritySection()

                        VStack(alignment: .leading, spacing: 20) {
                            SectionHead("Your *roles*", role: .h3)
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
                            SectionHead("*Console*", role: .h3)
                            RuledList {
                                row("網站與成員") { openURL(ConsoleConfig.baseURL.appending(path: "sites")) }
                                row("連接外部 AI 的授權") { openURL(ConsoleConfig.baseURL.appending(path: "sites")) }
                                row("版本", value: version, action: nil)
                            }
                            ConnectorCard()
                        }

                        VStack(spacing: 12) {
                            if !settings.isDefault {
                                Button {
                                    withAnimation(Motion.fast) { settings.reset() }
                                } label: { Text("外觀、Xena、首頁回到預設值") }
                                .buttonStyle(.brand(.ghost, size: .lg, fullWidth: true))
                                .transition(.opacity)
                            }
                            if model.isDemo {
                                // 示範模式：沒有真的登入，直接離開回到歡迎頁
                                Button {
                                    Task { await model.signOut() }
                                } label: { Text("離開示範模式") }
                                .buttonStyle(.brand(.danger, size: .lg, fullWidth: true))
                            } else {
                                Button {
                                    confirmingSignOut = true
                                } label: { Text("登出") }
                                .buttonStyle(.brand(.danger, size: .lg, fullWidth: true))
                            }
                            // App Store 要求：App 裡就能刪帳號（示範模式也走一遍，什麼都不會真的刪）
                            Button {
                                confirmingDelete = true
                            } label: {
                                if deleting { ProgressView() } else { Text("刪除帳號") }
                            }
                            .buttonStyle(.brand(.ghost, size: .lg, fullWidth: true))
                            .disabled(deleting)
                        }
                    }
                    .frame(maxWidth: Metric.readable + 120, alignment: .leading)
                    .pageWidth()
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 14) {
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
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 手機是從首頁的齒輪打開的一張卡片：右上角收起來
                if model.showAccount {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { model.showAccount = false }
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .navigationDestination(isPresented: $showingNotifications) { NotificationSettingsView() }
            .confirmationDialog("要登出嗎？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("登出", role: .destructive) { Task { await model.signOut() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這台裝置的登入會撤銷、不再收到通知，其他裝置與 AI 連接器不受影響。")
            }
            .confirmationDialog("要刪除 StudioX 帳號嗎？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("永久刪除帳號", role: .destructive) { Task { await deleteAccount() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text(model.isDemo
                    ? "這是示範模式：會走一遍刪除帳號的流程，然後回到歡迎頁，不會刪掉任何東西。"
                    : "你在每個網站的管理權限、Apple 登入的連結、所有裝置的登入與通知都會刪除，無法復原。網站本身與網站的資料（訂單、客人）不受影響，仍由網站負責人管理。")
            }
            .alert("沒有刪除", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do {
            _ = try await model.deleteAccount()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    /// 試聽：用選好的聲音、語速說一句
    private func preview() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let mouth = model.conversation.mouth
        mouth.stop()
        mouth.say("嗨，我是 Xena。今天有 3 件事等你決定，我們一件一件來。")
    }

    /// 沒有商店的帳號不給選「訂單」
    private var startTabs: [AppSettings.StartTab] {
        AppSettings.StartTab.allCases.filter { $0 != .orders || !model.orderSites.isEmpty }
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

/// 設定裡的單選：標題、一排方形的選項（選到的墨色實心），下面一行說明
private struct ChoiceRow<Option: Identifiable & Hashable>: View {
    let label: String
    var help: String?
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .textRole(.body)
                .foregroundStyle(Theme.ink)
            FlowLayout(spacing: 8) {
                ForEach(options) { option in
                    FilterChip(title: title(option), selected: option == selection) {
                        withAnimation(Motion.fast) { selection = option }
                    }
                    .accessibilityLabel("\(label)：\(title(option))")
                }
            }
            if let help {
                Text(help)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .padding(.vertical, 14)
    }
}

/// 安全：Face ID 鎖住 App、離開多久要解鎖、危險動作前再驗證一次（存在這台裝置）
private struct SecuritySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let lock = model.lock
        VStack(alignment: .leading, spacing: 20) {
            SectionHead("*Security*", aside: lock.available ? nil : "這台裝置沒有設定密碼，不能鎖。", role: .h3)
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
