import SwiftUI

/// 我：帳號、各網站的職能、Xena 怎麼陪你、推播、登出
struct AccountView: View {
    @Environment(AppModel.self) private var model

    @AppStorage("xena.proactive") private var proactive = true
    @AppStorage("xena.nightShift") private var nightShift = true
    @AppStorage("xena.briefHour") private var briefHour = 8
    @AppStorage("push.orders") private var pushOrders = true
    @AppStorage("push.support") private var pushSupport = true
    @AppStorage("push.logistics") private var pushLogistics = true
    @AppStorage("push.digest") private var pushDigest = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        InitialAvatar(name: model.user?.name ?? "我", size: 52, tint: Brand.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.user?.name ?? "")
                                .font(.system(size: 19, weight: .semibold))
                            Text(model.user?.email ?? "")
                                .font(.subheadline)
                                .foregroundStyle(Brand.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("我的網站") {
                    ForEach(model.sites) { site in
                        HStack(spacing: 12) {
                            SiteIcon(site: site, size: 30)
                            Text(site.name)
                            Spacer()
                            Text(site.role.rawValue)
                                .foregroundStyle(Brand.muted)
                        }
                    }
                }

                Section {
                    Toggle("有事主動找我", isOn: $proactive)
                    Toggle("夜班安靜模式（00:00–06:00 只推緊急的）", isOn: $nightShift)
                    Picker("每日摘要", selection: $briefHour) {
                        ForEach(6..<12) { hour in
                            Text("早上 \(hour):00").tag(hour)
                        }
                    }
                    LabeledContent("動手改東西之前", value: "一律先問我")
                } header: {
                    Text("Xena")
                } footer: {
                    Text("Xena 修改任何資料前都會跳確認卡片；刪除、退款要打字確認。網站負責人也可以在後台把 AI 設成只能查詢。")
                }

                Section("手機推播") {
                    Toggle("新訂單、付款", isOn: $pushOrders)
                    Toggle("有人在客服等你", isOn: $pushSupport)
                    Toggle("物流異常（緊急）", isOn: $pushLogistics)
                    Toggle("每日摘要", isOn: $pushDigest)
                }

                Section("關於") {
                    LabeledContent("版本", value: "0.1 雛形")
                    LabeledContent("資料", value: "示範資料")
                    LabeledContent("Console", value: "console.studiox.tw")
                }

                Section {
                    Button("登出", role: .destructive) {
                        model.signOut()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.paper.ignoresSafeArea())
            .navigationTitle("我")
        }
    }
}
