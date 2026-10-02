import SwiftUI

/// 我（後台左下角的頭貼選單）：帳號、各網站的職能、Xena、console、登出
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false

    private var version: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let b = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        return "\(v)（\(b)）"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let me = model.me {
                        HStack(spacing: 14) {
                            Avatar(name: me.name, imageURL: me.imageURL, size: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(me.name)
                                        .font(.admSection)
                                        .foregroundStyle(Theme.ink)
                                    if me.staff { StatusBadge("StudioX", tone: .gold) }
                                }
                                Text(me.email)
                                    .font(.admMeta)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                        }
                        .admCard()
                    }

                    section("我的網站") {
                        ForEach(Array(model.sites.enumerated()), id: \.element.id) { index, site in
                            if index > 0 { Divider().overlay(Theme.hair).padding(.leading, 52) }
                            HStack(spacing: 12) {
                                SiteIconView(site: site, size: 28)
                                Text(site.name)
                                    .font(.admBody)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(site.levelLabel)
                                    .font(.admMeta)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                    Text("職能由網站負責人在 StudioX Console 設定；要調整請聯絡網站負責人或 StudioX。")
                        .font(.admMeta)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 4)

                    section("Xena") {
                        row("sparkles", "跟 Xena 說話") { model.showXena = true }
                        Divider().overlay(Theme.hair).padding(.leading, 44)
                        row("shield-check", "動手改東西之前", value: "一律先問你", action: nil)
                    }
                    Text("Xena 在 App 和網頁上是同一個，對話紀錄也是同一份。修改任何資料前都會先出確認；退款、刪除要打字確認。")
                        .font(.admMeta)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, 4)

                    section("StudioX Console") {
                        row("squares-2x2", "在瀏覽器打開 console") { openURL(ConsoleConfig.baseURL.appending(path: "sites")) }
                        Divider().overlay(Theme.hair).padding(.leading, 44)
                        row("puzzle-piece", "連接外部 AI 的授權") { openURL(ConsoleConfig.baseURL.appending(path: "sites")) }
                        Divider().overlay(Theme.hair).padding(.leading, 44)
                        row("information-circle", "版本", value: version, action: nil)
                    }

                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label { Text("登出") } icon: { HeroIcon("arrow-right-start-on-rectangle", size: 18) }
                    }
                    .buttonStyle(.adm(.danger, fullWidth: true))
                    .padding(.top, 6)
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .admPage()
            .navigationTitle("我")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("要登出嗎？", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("登出", role: .destructive) { Task { await model.signOut() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這台裝置的登入會撤銷，其他裝置與 AI 連接器不受影響。")
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            VStack(spacing: 0) { content() }
                .admCard(padding: 0)
        }
    }

    @ViewBuilder
    private func row(_ icon: String, _ title: String, value: String? = nil, action: (() -> Void)?) -> some View {
        let content = HStack(spacing: 12) {
            HeroIcon(icon, size: 18)
                .foregroundStyle(Theme.icon)
                .frame(width: 20)
            Text(title)
                .font(.admBody)
                .foregroundStyle(Theme.ink)
            Spacer()
            if let value {
                Text(value).font(.admMeta).foregroundStyle(Theme.inkMuted)
            }
            if action != nil {
                HeroIcon("chevron-right", size: 13).foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(RowPressStyle())
        } else {
            content
        }
    }
}
