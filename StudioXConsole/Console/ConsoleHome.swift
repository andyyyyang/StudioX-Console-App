import SwiftUI

/// 平台管理：StudioX Console 自己的管理後台（客戶與網站、服務、金鑰、計費、人員、紀錄、Xena）。
/// 和網頁後台同一支 API、同一張權限表（console 認 App 的 token）；看得到哪些頁照 /api/app/me 的 consoleCaps。
/// 手機從「網站」分頁進來；iPad 在側欄的「平台管理」。
struct ConsoleHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                PageHeader("平台管理", eyebrow: "StudioX Console", subtitle: subtitle)
                    .reveal()
                ForEach(Array(ConsoleSection.groups.enumerated()), id: \.offset) { index, group in
                    let items = group.items.filter { $0.visible(model) }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(group.title)
                            RuledList {
                                ForEach(items) { item in
                                    NavigationLink(value: Route.console(item.page)) {
                                        ConsoleSectionRow(section: item)
                                    }
                                    .buttonStyle(.row)
                                }
                            }
                        }
                        .reveal(index + 1)
                    }
                }
            }
            .pageWidth()
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
        .brandPage()
        .pageTitle("平台管理")
    }

    private var subtitle: String {
        let level = model.me?.consoleLevelLabel.map { "你是 StudioX 的\($0)。" } ?? ""
        return level + "和網頁版的 console 是同一份資料，改了馬上生效。"
    }
}

/// 平台管理的一頁：標題、說明、圖示、要什麼能力才看得到
struct ConsoleSection: Identifiable, Hashable {
    var id: ConsolePage { page }
    let page: ConsolePage
    let title: String
    let detail: String
    let icon: String
    /// 有其中一項能力就看得到
    let caps: [String]

    func visible(_ model: AppModel) -> Bool { caps.contains { model.can($0) } }

    static let customers = ConsoleSection(page: .customers, title: "客戶與網站", detail: "網站、成員、邀請、登入設定", icon: "briefcase", caps: ["console.read"])
    static let requests = ConsoleSection(page: .requests, title: "申請", detail: "客戶申請的方案與服務", icon: "inbox-stack", caps: ["platform.read"])
    static let services = ConsoleSection(page: .services, title: "網站服務", detail: "每個網站用哪把金鑰、開了哪些服務", icon: "puzzle-piece", caps: ["platform.read"])
    static let keys = ConsoleSection(page: .keys, title: "金鑰庫", detail: "AI、寄信、簡訊、金流…的金鑰", icon: "key", caps: ["platform.manage"])
    static let usage = ConsoleSection(page: .usage, title: "用量", detail: "寄信、簡訊、AI 的用量與成本", icon: "chart-bar", caps: ["platform.read"])
    static let billing = ConsoleSection(page: .billing, title: "帳單", detail: "每個客戶每個月的帳單", icon: "banknotes", caps: ["platform.read"])
    static let plans = ConsoleSection(page: .plans, title: "方案", detail: "客戶訂的方案與加購", icon: "rectangle-stack", caps: ["platform.read"])
    static let pricing = ConsoleSection(page: .pricing, title: "價目", detail: "匯率、AI 加成、簡訊與 Email 單價", icon: "tag", caps: ["platform.read"])
    static let team = ConsoleSection(page: .team, title: "後台人員", detail: "誰能進 console、是什麼職能", icon: "users", caps: ["users.level"])
    static let audit = ConsoleSection(page: .audit, title: "操作紀錄", detail: "誰在什麼時候改了什麼", icon: "clipboard-document-check", caps: ["audit.read"])
    static let xena = ConsoleSection(page: .xena, title: "Xena AI", detail: "開關、外部 AI 連接器、呼叫紀錄", icon: "sparkles", caps: ["console.read", "platform.read", "users.level", "mcp.manage"])

    static let groups: [(title: String, items: [ConsoleSection])] = [
        ("客戶", [customers, requests, services]),
        ("計費", [usage, billing, plans, pricing]),
        ("系統", [keys, team, audit, xena]),
    ]
    static var all: [ConsoleSection] { groups.flatMap(\.items) }
}

struct ConsoleSectionRow: View {
    let section: ConsoleSection
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            HeroIcon(section.icon, size: 20)
                .foregroundStyle(Theme.ink2)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                Text(section.detail)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HeroIcon("chevron-right", size: 13)
                .foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

/// 從哪裡打開都一樣：平台管理的每一頁
struct ConsolePageView: View {
    let page: ConsolePage

    var body: some View {
        switch page {
        case .home: ConsoleHomeView()
        case .customers: CustomersView()
        case .site(let id): ConsoleSiteView(siteID: id)
        case .requests: RequestsView()
        case .services: ServicesMatrixView()
        case .siteServices(let id): SiteServicesView(siteID: id)
        case .keys: KeysView()
        case .usage: UsageView()
        case .billing: BillingView()
        case .plans: PlansView()
        case .pricing: PricingView()
        case .team: TeamView()
        case .audit: AuditView()
        case .xena: XenaAdminView()
        }
    }
}

/// iPad 側欄的「平台管理」：左邊選一頁、右邊是那一頁（往下點的在右邊疊上去）。
/// 選哪一頁記在 AppModel.consoleSection：通知、深連結（open(.console(…))）打開的也選在左邊對應的那一項
struct ConsoleWorkspace: View {
    @Environment(AppModel.self) private var model
    @State private var visibility: NavigationSplitViewVisibility = .all

    /// 左邊點了別的一頁：右邊從那一頁開始（不帶著上一頁點進去的）
    private var selection: Binding<ConsolePage?> {
        Binding(get: { model.consoleSection }, set: { page in
            guard let page, page != model.consoleSection else { return }
            model.consoleSection = page
            model.consolePath = []
        })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(selection: selection) {
                ForEach(Array(ConsoleSection.groups.enumerated()), id: \.offset) { _, group in
                    let items = group.items.filter { $0.visible(model) }
                    if !items.isEmpty {
                        Section(group.title) {
                            ForEach(items) { item in
                                Label {
                                    Text(item.title)
                                } icon: {
                                    HeroIcon(item.icon, size: 17)
                                }
                                .tag(item.page)
                            }
                        }
                    }
                }
            }
            .navigationTitle("平台管理")
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            NavigationStack(path: Bindable(model).consolePath) {
                ConsolePageView(page: model.consoleSection)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .id(model.consoleSection)
            .brandSplitView()
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // 沒有「客戶與網站」權限的人：選第一個看得到的
            let visible = ConsoleSection.all.filter { $0.visible(model) }
            let current = model.consoleSection
            if !visible.contains(where: { $0.page == current }), let first = visible.first {
                model.consoleSection = first.page
            }
        }
    }
}

// MARK: - 共用

extension AppModel {
    /// 收不回來的動作（刪除金鑰、重新產生密鑰、作廢帳單、移除成員、撤銷連接器）：
    /// 畫面先出確認選單寫清楚後果（Face ID 掃臉時不會顯示要做什麼，不能只靠它），
    /// 按了確認再驗證一次（Face ID；2 分鐘內驗證過、沒離開 App 就不再跳）才做
    func verified(_ reason: String, then work: () async -> Void) async {
        guard await lock.verify(reason) else { return }
        await work()
    }

    /// 平台管理的寫入：成功顯示 done、失敗顯示原因。回傳有沒有成功
    @discardableResult
    func adminRun(_ done: String?, _ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            if let done { show(done) }
            return true
        } catch {
            show(error.localizedDescription, tone: .danger)
            return false
        }
    }
}

/// 平台管理各頁的狀態：載入中、錯誤、資料
@Observable
final class AdminLoad<Value> {
    var value: Value?
    var error: String?
    var loading = false

    func run(_ fetch: () async throws -> Value) async {
        loading = true
        defer { loading = false }
        do {
            value = try await fetch()
            error = nil
        } catch {
            if value == nil { self.error = error.localizedDescription }
        }
    }
}

/// 頁首右邊的「＋」（Menu 的 label 用；和 SquareIconButtonStyle 同樣的方框）
struct AddIconLabel: View {
    var body: some View {
        HeroIcon("plus", size: 18)
            .foregroundStyle(Theme.ink)
            .frame(width: 40, height: 40)
            .overlay { RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(Theme.line, lineWidth: 1) }
            .contentShape(.rect)
    }
}

/// 一行「標籤：值」（設定、登入資訊）
struct InfoRow: View {
    let label: String
    let value: String
    var mono = false
    var copy = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .textRole(.small)
                .foregroundStyle(Theme.muted)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 13, design: .monospaced) : .brand(15, .regular, relativeTo: .body))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if copy {
                CopyButton(text: value)
            }
        }
        .padding(.vertical, 10)
    }
}

/// 複製（按了變「已複製」兩秒）
struct CopyButton: View {
    let text: String
    var title = "複製"
    @State private var copied = false

    var body: some View {
        Button(copied ? "已複製" : title) {
            UIPasteboard.general.string = text
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
        .buttonStyle(.brand(.ghost, size: .sm))
        .haptic(.success, trigger: copied) { _, now in now }
    }
}

/// 一個月一個月往前選（帳單、用量）：YYYY-MM（台北時間）
struct PeriodPicker: View {
    @Binding var period: String
    var count = 12

    nonisolated static var current: String { months(1)[0] }

    nonisolated static func months(_ n: Int) -> [String] {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        let now = Date.now
        return (0..<n).compactMap { i in
            guard let d = c.date(byAdding: .month, value: -i, to: now) else { return nil }
            let y = c.component(.year, from: d)
            let m = c.component(.month, from: d)
            return String(format: "%04d-%02d", y, m)
        }
    }

    nonisolated static func label(_ p: String) -> String {
        let parts = p.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return p }
        return p == current ? "這個月（\(m) 月）" : "\(y) 年 \(m) 月"
    }

    var body: some View {
        Menu {
            Picker("月份", selection: $period) {
                ForEach(Self.months(count), id: \.self) { Text(Self.label($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(Self.label(period))
                HeroIcon("chevron-down", size: 12)
            }
            .font(.brand(15, .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
        }
    }
}

/// 平台管理的表單外框：標題、內容、底部的主要按鈕（送出中會轉圈、不能重按）
struct AdminSheet<Content: View>: View {
    let title: String
    var subtitle: String?
    var action: String
    var danger = false
    var disabled = false
    let onSubmit: () async -> Bool
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Headline(title, role: .h2)
                        if let subtitle {
                            Text(subtitle)
                                .textRole(.small)
                                .foregroundStyle(Theme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        working = true
                        let ok = await onSubmit()
                        working = false
                        if ok { dismiss() }
                    }
                } label: {
                    if working { ProgressView().tint(Theme.page) } else { Text(action) }
                }
                .buttonStyle(.brand(danger ? .danger : .accent, size: .lg, fullWidth: true))
                .disabled(disabled || working)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .background(Theme.sheet)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 一個文字欄位（FieldBlock＋TextField）
struct AdminTextField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var hint: String?
    var required = false
    var secure = false
    var keyboard: UIKeyboardType = .default
    var multiline = false
    @FocusState private var focused: Bool

    var body: some View {
        FieldBlock(label: label, hint: hint, required: required, focused: focused) {
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else if multiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(3...10)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .default && !secure ? .sentences : .never)
            .autocorrectionDisabled(keyboard != .default || secure)
            .focused($focused)
            .fieldText()
        }
    }
}

/// 選一個（職能、方案…）：Menu 做的下拉
struct AdminPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var hint: String?

    var body: some View {
        FieldBlock(label: label, hint: hint) {
            Menu {
                Picker(label, selection: $selection) {
                    ForEach(options.indices, id: \.self) { i in
                        Text(options[i].label).tag(options[i].value)
                    }
                }
            } label: {
                HStack {
                    Text(options.first { $0.value == selection }?.label ?? "請選擇")
                        .fieldText()
                    Spacer()
                    HeroIcon("arrows-up-down", size: 13)
                        .foregroundStyle(Theme.muted)
                }
                .contentShape(.rect)
            }
        }
    }
}

/// 開關（說明在下面）
struct AdminToggle: View {
    let label: String
    @Binding var isOn: Bool
    var hint: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                if let hint {
                    Text(hint)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// 只有這一次看得到的密鑰（建立網站、重新產生密鑰）：複製、分享，提醒放進網站的環境變數
struct SiteSecretSheet: View {
    let secret: SiteSecret
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Headline("「\(secret.siteName)」的登入設定", role: .h2)
                    Text("把這三行放進網站後台的環境變數（Railway），網站就能用 StudioX 登入。密鑰只會出現這一次，關掉之後就看不到了；弄丟了可以重新產生。")
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(secret.env)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.ink.opacity(0.05), in: .rect(cornerRadius: Metric.radius))
                    HStack(spacing: 10) {
                        CopyButton(text: secret.env, title: "複製三行")
                        ShareLink(item: secret.env) {
                            Text("分享")
                        }
                        .buttonStyle(.brand(.ghost, size: .sm))
                    }
                }
                .padding(24)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("我存好了") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}
