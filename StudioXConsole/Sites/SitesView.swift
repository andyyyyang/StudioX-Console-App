import SwiftUI
import UIKit

/// 網站（手機的分頁）：後台人員最上面是「平台管理」；每個網站一列，7 天訪客＋走勢；點進去是那個網站（概況＋所有可以管理的內容）。
/// iPad 上網站直接列在側欄（MainView 的 TabSection），每個網站是一個 SiteWorkspace。AI 連接器的網址在「設定」。
struct SitesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack(path: Bindable(model).sitesPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    PageHeader("網站", subtitle: summary)
                        .reveal()
                    // 後台人員：平台管理放第一個（iPad 在側欄的「StudioX」）
                    if model.canManageConsole {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow("StudioX Console")
                            RuledList {
                                NavigationLink(value: Route.console(.home)) {
                                    ConsoleSectionRow(section: ConsoleSection(page: .home, title: "平台管理", detail: "客戶與網站、服務、金鑰、計費、人員、紀錄", icon: "briefcase", caps: []))
                                }
                                .buttonStyle(.row)
                            }
                        }
                    }
                    if model.sites.isEmpty {
                        EmptyState(title: "目前沒有可以管理的網站", message: "收到邀請連結的話，直接打開連結就能加入網站。")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            if model.canManageConsole { Eyebrow("你的網站") }
                            RuledList {
                                ForEach(Array(model.sites.enumerated()), id: \.element.id) { index, site in
                                    NavigationLink(value: Route.site(site.id)) {
                                        SiteRow(site: site)
                                    }
                                    .buttonStyle(.row)
                                    .reveal(index + 1)
                                }
                            }
                        }
                    }
                }
                .pageWidth()
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .refreshable { [model] in await Task { await model.refreshAll() }.value }
            .brandPage()
            .pageTitle("網站")
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private var summary: String {
        let visitors = model.sites.reduce(0) { $0 + ($1.stats?.visitors ?? 0) }
        return "\(model.sites.count) 個網站・最近 7 天 \(visitors.formatted()) 位訪客。"
    }
}

/// 連接 Claude／ChatGPT（console 一個網址管所有網站；studiox-cms 的「AI → 連接外部 AI」）。放在「設定 → Console」
struct ConnectorCard: View {
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("AI 連接器")
            Text("在 Claude 或 ChatGPT 的「連接器」貼上這個網址，用 StudioX 帳號登入，就能用聊天操作你所有的網站；修改一律要你確認。")
                .textRole(.small)
                .foregroundStyle(Theme.ink2)
            HStack(spacing: 10) {
                Text(ConsoleConfig.mcpURL)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button(copied ? "已複製" : "複製") {
                    UIPasteboard.general.string = ConsoleConfig.mcpURL
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
        .panel()
    }
}

// MARK: - 一個網站（手機：概況＋可以管理的內容；iPad：側欄＋內容）

/// 網站的首頁（手機）：名稱、概況（流量、昨天的營運）、可以管理的所有內容
struct SiteHomeView: View {
    let siteID: String
    @Environment(AppModel.self) private var model

    var body: some View {
        if let site = model.site(siteID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 56) {
                    SiteHeader(site: site)
                    SiteOverview(site: site)
                    SiteSections(site: site, style: .ruled)
                }
                .pageWidth()
                .padding(.top, 16)
                .padding(.bottom, 56)
            }
            .brandPage()
            .pageTitle(site.name)
            .xenaFocus("site-\(site.id)", prompt: "幫我看一下「\(site.name)」（\(site.id)）最近怎麼樣")
            .toolbar { AskXenaToolbar(model: model) }
        } else {
            EmptyState(title: "找不到這個網站", message: "你可能已經不是這個網站的成員。")
                .pageWidth()
                .brandPage()
        }
    }
}

/// iPad：一個網站一個工作區。左邊是這個網站可以管理的東西，右邊是內容（各自一疊頁面）
struct SiteWorkspace: View {
    let siteID: String
    @Environment(AppModel.self) private var model
    @State private var section: SiteSection? = .overview
    @State private var visibility: NavigationSplitViewVisibility = .all

    var body: some View {
        if let site = model.site(siteID) {
            NavigationSplitView(columnVisibility: $visibility) {
                SiteSectionSidebar(site: site, selection: $section)
                    .navigationTitle(site.name)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            } detail: {
                NavigationStack(path: path) {
                    sectionView(site)
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .id(section)
                .brandSplitView()
            }
            .navigationSplitViewStyle(.balanced)
            .onChange(of: section) { model.sitePaths[siteID] = [] }
        } else {
            EmptyState(title: "找不到這個網站", message: "你可能已經不是這個網站的成員。")
                .pageWidth()
                .brandPage()
        }
    }

    private var path: Binding<[Route]> {
        Binding(get: { model.sitePaths[siteID] ?? [] }, set: { model.sitePaths[siteID] = $0 })
    }

    @ViewBuilder
    private func sectionView(_ site: SiteSummary) -> some View {
        switch section ?? .overview {
        case .overview:
            ScrollView {
                VStack(alignment: .leading, spacing: 64) {
                    SiteHeader(site: site)
                    SiteOverview(site: site)
                }
                .pageWidth()
                .padding(.top, 24)
                .padding(.bottom, 64)
            }
            .brandPage()
            .pageTitle(site.name)
            .xenaFocus("site-\(site.id)", prompt: "幫我看一下「\(site.name)」（\(site.id)）最近怎麼樣")
            .toolbar { AskXenaToolbar(model: model) }
        case .traffic:
            TrafficView(siteID: site.id)
        case .search:
            SearchConsoleView(siteID: site.id)
        case .report:
            OpsReportView(siteID: site.id)
        case .entity(let key):
            EntityRoot(site: site.id, entity: key)
        }
    }
}

/// iPad 側欄的一項
enum SiteSection: Hashable {
    case overview, report, traffic, search
    case entity(String)
}

/// iPad 的側欄：概況、營運報表、流量、Google 搜尋（和手機網站頁的「管理」同一組），以及照網站欄位定義分好組的內容
private struct SiteSectionSidebar: View {
    let site: SiteSummary
    @Binding var selection: SiteSection?
    @Environment(AppModel.self) private var model
    @State private var schema: SiteSchema?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label { Text("概況") } icon: { HeroIcon("squares-2x2", size: 18) }
                    .tag(SiteSection.overview)
                if site.tools.contains("ops_report") {
                    Label { Text("營運報表") } icon: { HeroIcon("presentation-chart-line", size: 18) }
                        .tag(SiteSection.report)
                }
                if site.hasTraffic {
                    Label { Text("流量") } icon: { HeroIcon("chart-bar", size: 18) }
                        .tag(SiteSection.traffic)
                }
                if site.tools.contains("search_report") {
                    Label { Text("Google 搜尋") } icon: { HeroIcon("magnifying-glass", size: 18) }
                        .tag(SiteSection.search)
                }
            }
            if let schema {
                ForEach(EntityStyle.groups(for: schema), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.entities) { entity in
                            Label { Text(entity.label) } icon: { HeroIcon(EntityStyle.icon(entity.key), size: 18) }
                                .tag(SiteSection.entity(entity.key))
                        }
                    }
                }
            } else if let error = model.schemaErrors[site.id] {
                Section {
                    Text(error)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .listStyle(.sidebar)
        .brandPage()
        .task { schema = await model.schema(for: site.id) }
    }
}

/// 網站的頁首：圖示、名稱、網址、職能；開啟後台、看網站
struct SiteHeader: View {
    let site: SiteSummary
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                SiteIconView(site: site, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    // 公司名稱和網站名稱一樣時不重複寫（大標就是網站名稱）
                    Eyebrow([site.org == site.name ? nil : site.org, site.levelLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    Text(site.host)
                        .textRole(.small)
                        .foregroundStyle(Theme.muted)
                }
            }
            PageHeader(site.name)
            HStack(spacing: 10) {
                if let url = site.adminURL {
                    Button { openURL(url) } label: { Text("開啟後台") }
                        .buttonStyle(.brand(.primary, arrow: true))
                }
                if let url = site.url {
                    Button { openURL(url) } label: { Text("看網站 ↗") }
                        .buttonStyle(.brand(.ghost))
                }
            }
        }
        .reveal()
    }
}

// MARK: - 概況（流量＋昨天的營運）

struct SiteOverview: View {
    let site: SiteSummary
    @Environment(AppModel.self) private var model
    @State private var days = 7
    @State private var report: TrafficReport?
    @State private var ops: OpsReport?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 56) {
            if site.hasTraffic {
                traffic
            }
            if site.hasOrders, let ops {
                store(ops)
            }
            if let error {
                ErrorNote(message: error) { Task { await load() } }
            }
        }
        .task(id: days) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            if site.hasTraffic { report = try await model.api.traffic(site: site.id, days: days) }
            if site.hasOrders, ops == nil { ops = try await model.api.ops(site: site.id, days: 1) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var traffic: some View {
        VStack(alignment: .leading, spacing: 28) {
            SectionHead("流量") {
                // 在哪一疊頁面裡就往下推（首頁卡片的 sheet 裡也是）
                NavigationLink(value: Route.traffic(site: site.id)) { MoreLinkLabel(title: "完整報表") }
                    .buttonStyle(.press)
            }
            FilterBar(items: [1, 7, 30, 90], selection: $days, title: { $0 == 1 ? "今天" : "\($0) 天" })
            if let r = report {
                if !r.installed {
                    EmptyState(title: "還沒有流量資料", message: "網站裝好流量追蹤之後，這裡就看得到。")
                } else {
                    StatGrid {
                        Stat(value: Double(r.live), label: "現在在線")
                        Stat(value: Double(r.visitors), label: "訪客", change: r.change)
                        Stat(value: Double(r.pageviews), label: "瀏覽", change: r.pageviewsChange)
                        Stat(value: (r.avgDurationMs ?? 0) / 1000, label: "平均停留", format: { s in
                            let n = Int(s.rounded())
                            return n >= 60 ? "\(n / 60)m\(n % 60)s" : "\(n)s"
                        })
                    }
                    TrafficChart(points: r.trend, metric: .visitors)
                        .frame(height: 220)
                }
            } else if loading {
                SkeletonRows(rows: 2)
            }
        }
    }

    private func store(_ ops: OpsReport) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            SectionHead("昨天的商店") {
                NavigationLink(value: Route.report(site: site.id)) { MoreLinkLabel(title: "完整報表") }
                    .buttonStyle(.press)
            }
            StatGrid {
                Stat(value: Double(ops.createdTotal), label: "新訂單")
                Stat(value: Double(ops.revenueCents) / 100, label: "收款", format: { "NT$" + Int($0.rounded()).formatted() }, compact: { ntdShort(cents: Int(($0 * 100).rounded())) })
                Stat(value: Double(ops.paidButUnfulfilled), label: "等出貨")
                Stat(value: Double(ops.supportAwaiting), label: "客人等回覆")
            }
            if !ops.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ops.alerts, id: \.self) { alert in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.dangerFG).frame(width: 6, height: 6)
                            Text(alert)
                                .textRole(.small)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 可以管理的內容（照網站的欄位定義）

struct SiteSections: View {
    enum Style { case ruled }
    let site: SiteSummary
    var style: Style = .ruled
    @Environment(AppModel.self) private var model
    @State private var schema: SiteSchema?

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            SectionHead("管理")
            RuledList {
                if site.tools.contains("ops_report") {
                    sectionRow(icon: "presentation-chart-line", title: "營運報表", detail: "訂單、收款、等出貨、會員、異常", route: .report(site: site.id))
                }
                if site.hasTraffic {
                    sectionRow(icon: "chart-bar", title: "流量", detail: "訪客、熱門頁面、來源、時段", route: .traffic(site: site.id))
                }
                if site.tools.contains("search_report") {
                    sectionRow(icon: "magnifying-glass", title: "Google 搜尋", detail: "點擊、曝光、搜尋關鍵字", route: .searchConsole(site: site.id))
                }
            }
            if let schema {
                ForEach(EntityStyle.groups(for: schema), id: \.title) { group in
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(group.title)
                        RuledList {
                            ForEach(group.entities) { entity in
                                sectionRow(
                                    icon: EntityStyle.icon(entity.key),
                                    title: entity.label,
                                    detail: EntityStyle.detail(entity),
                                    route: entity.singleton ? .record(site: site.id, entity: entity.key, id: nil) : .collection(site: site.id, entity: entity.key)
                                )
                            }
                        }
                    }
                }
            } else if let error = model.schemaErrors[site.id] {
                ErrorNote(message: error) { Task { schema = await model.schema(for: site.id, reload: true) } }
            } else {
                SkeletonRows(rows: 4)
            }
        }
        .task { schema = await model.schema(for: site.id) }
    }

    private func sectionRow(icon: String, title: String, detail: String?, route: Route) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 16) {
                HeroIcon(icon, size: 20)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .overlay { RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(Theme.line, lineWidth: 1) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .textRole(.h4)
                        .foregroundStyle(Theme.ink)
                    if let detail {
                        Text(detail)
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 8)
                Text("→")
                    .font(.brand(18, .medium))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.row)
    }
}

/// 一種資料在 App 裡的樣子：圖示、分組、英文的大標
enum EntityStyle {
    struct Group {
        let title: String
        let entities: [EntitySchema]
    }

    /// 這些有自己的分頁或收件匣，不重複列
    static let hidden: Set<String> = ["order", "support_thread", "unmatched_inbound", "assistant_conversation", "inquiry"]

    static func group(_ key: String) -> String {
        switch key {
        case "product", "category", "bundle", "coupon", "stall_menu", "membership_tier", "shipping_settings", "bank_transfer":
            "商店"
        case "campaign", "line_campaign", "line_marketing", "line_theme":
            "行銷"
        case "user", "mailbox", "pending_notification":
            "顧客"
        case "page_seo", "business_info", "site_settings", "notifications_config", "personalized_config", "assistant_settings", "integration", "service":
            "網站設定"
        case "automation", "automation_run":
            "自動化"
        default:
            "內容"
        }
    }

    static let groupOrder = ["內容", "商店", "行銷", "顧客", "自動化", "網站設定"]

    /// 有「發送優惠」（send_promotion：簡訊和 LINE 一起發）的網站，簡訊活動和 LINE 推播合成一項（EntityListView 打開 PromotionsView）
    static let promotionEntities: Set<String> = ["line_campaign", "campaign"]
    static let promotionLabel = "發送優惠"

    static func groups(for schema: SiteSchema) -> [Group] {
        var shown = schema.entities.filter { !hidden.contains($0.key) && ($0.canList || $0.singleton || $0.canGet) }
        if schema.tools.contains("send_promotion"), let i = shown.firstIndex(where: { promotionEntities.contains($0.key) }) {
            shown[i].label = promotionLabel
            let kept = shown[i].key
            shown.removeAll { promotionEntities.contains($0.key) && $0.key != kept }
        }
        let byGroup = Dictionary(grouping: shown, by: { group($0.key) })
        return groupOrder.compactMap { title in byGroup[title].map { Group(title: title, entities: $0) } }
    }

    static func icon(_ key: String) -> String {
        switch key {
        case "product": "cube"
        case "category": "tag"
        case "bundle": "gift"
        case "coupon": "ticket"
        case "news", "content_news": "newspaper"
        case "banner": "photo"
        case "faq", "content_faq": "question-mark-circle"
        case "milestone": "trophy"
        case "membership_tier": "star"
        case "campaign": "megaphone"
        case "line_campaign": "paper-airplane"
        case "line_marketing": "arrow-path"
        case "line_theme": "swatch"
        case "user": "users"
        case "mailbox": "envelope"
        case "pending_notification": "bell"
        case "shipping_settings": "truck"
        case "site_settings": "cog-6-tooth"
        case "bank_transfer": "banknotes"
        case "notifications_config": "bell-alert"
        case "personalized_config": "sparkles"
        case "stall_menu": "queue-list"
        case "projects": "briefcase"
        case "services": "squares-2x2"
        case "engagements": "document-duplicate"
        case "home": "home"
        case "about": "book-open"
        case "contact": "phone"
        case "assistant": "chat-bubble-oval-left-ellipsis"
        case "assistant_settings": "adjustments-horizontal"
        case "page_seo": "magnifying-glass"
        case "business_info": "identification"
        case "automation": "bolt"
        case "automation_run": "clock"
        case "service": "puzzle-piece"
        case "integration": "link"
        default: "rectangle-stack"
        }
    }

    /// 清單上的一句說明
    static func detail(_ entity: EntitySchema) -> String? {
        if let d = entity.collection?.description { return d }
        if promotionEntities.contains(entity.key), entity.label == promotionLabel { return "LINE、簡訊一起發・發送紀錄" }
        var can: [String] = []
        if entity.canCreate { can.append("新增") }
        if entity.canUpdate { can.append("修改") }
        if entity.images != nil { can.append("換圖") }
        if entity.canDelete { can.append("刪除") }
        return can.isEmpty ? "只能查看" : can.joined(separator: "・")
    }
}

/// iPad 側欄點到一種資料：單一頁面直接打開，其他是清單
struct EntityRoot: View {
    let site: String
    let entity: String
    @Environment(AppModel.self) private var model
    @State private var schema: EntitySchema?

    var body: some View {
        Group {
            if let schema {
                if schema.singleton {
                    RecordView(site: site, entity: entity, id: nil)
                } else {
                    EntityListView(site: site, entity: entity)
                }
            } else {
                SkeletonRows(rows: 5).pageWidth().brandPage()
            }
        }
        .task(id: entity) { schema = await model.schema(for: site)?.entity(entity) }
    }
}
