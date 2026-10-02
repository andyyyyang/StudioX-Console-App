import Charts
import SwiftUI
import UIKit

/// 網站選擇器（console 的 /sites）：每個網站一列，7 天訪客＋走勢；點進去是那個網站的儀表板
struct SitesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack(path: Bindable(model).sitesPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PageTitle(title: "我的網站", subtitle: summary)
                    if model.sites.isEmpty {
                        EmptyState(icon: "globe-alt", title: "目前沒有可以管理的網站", message: "收到邀請連結的話，直接打開連結就能加入網站。")
                            .admCard(padding: 0)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.sites.enumerated()), id: \.element.id) { index, site in
                                if index > 0 { Divider().overlay(Theme.hair).padding(.leading, 56) }
                                NavigationLink(value: Route.site(site.id)) {
                                    SiteStatRow(site: site)
                                }
                                .buttonStyle(RowPressStyle())
                            }
                        }
                        .admCard(padding: 0)
                    }
                    ConnectorCard()
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable { [model] in await model.refreshAll() }
            .admPage()
            .navigationTitle("網站")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private var summary: String {
        let visitors = model.sites.reduce(0) { $0 + ($1.stats?.visitors ?? 0) }
        return "\(model.sites.count) 個網站・最近 7 天 \(visitors.formatted()) 位訪客"
    }
}

/// 連接 Claude／ChatGPT（console 一個網址管所有網站；atelier-cms 的「AI → 連接外部 AI」）
private struct ConnectorCard: View {
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HeroIcon("puzzle-piece", size: 18).foregroundStyle(Theme.icon)
                Text("連接 Claude／ChatGPT")
                    .font(.admCardTitle)
                    .foregroundStyle(Theme.ink)
            }
            Text("在 AI 的「連接器」貼上這個網址，用 StudioX 帳號登入就能操作你所有的網站；修改一律要你確認。")
                .font(.admMeta)
                .foregroundStyle(Theme.inkMuted)
            HStack(spacing: 10) {
                Text(ConsoleConfig.mcpURL)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
                .buttonStyle(.adm(.secondary, size: .sm))
                .sensoryFeedback(.success, trigger: copied) { _, now in now }
            }
            .padding(10)
            .background(Theme.ink.opacity(0.04), in: .rect(cornerRadius: Metric.radiusMd, style: .continuous))
        }
        .admCard()
    }
}

/// 一個網站的儀表板（網站後台的「流量」＋「概況」）：在線、訪客、走勢、熱門頁面、來源；有商店的再加昨天的營運
struct SiteDetailView: View {
    let siteID: String
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var days = 7
    @State private var report: TrafficReport?
    @State private var ops: OpsReport?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        if let site = model.site(siteID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(site)
                    if site.hasTraffic {
                        trafficSection
                    }
                    if site.hasOrders {
                        opsSection(site)
                    }
                    if let error {
                        ErrorNote(message: error) { Task { await load(site) } }
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 32)
            }
            .refreshable { await load(site) }
            .admPage()
            .navigationTitle(site.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.askXena("幫我看一下「\(site.name)」（\(site.id)）最近怎麼樣") } label: { HeroIcon("sparkles") }
                        .accessibilityLabel("問 Xena")
                }
            }
            .task(id: days) { await load(site) }
        } else {
            EmptyState(icon: "globe-alt", title: "找不到這個網站", message: "你可能已經不是這個網站的成員。")
                .admPage()
        }
    }

    private func load(_ site: SiteSummary) async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            if site.hasTraffic { report = try await model.api.traffic(site: site.id, days: days) }
            if site.hasOrders { ops = try await model.api.ops(site: site.id, days: 1) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func header(_ site: SiteSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SiteIconView(site: site, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                        .font(.admTitle)
                        .tracking(-0.33)
                        .foregroundStyle(Theme.ink)
                    Text([site.org, site.host, site.levelLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.admMeta)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            HStack(spacing: 10) {
                if let url = site.adminURL {
                    Button { openURL(url) } label: { Label { Text("開啟後台") } icon: { HeroIcon("arrow-top-right-on-square", size: 16) } }
                        .buttonStyle(.adm(.primary, size: .lg))
                }
                if let url = site.url {
                    Button { openURL(url) } label: { Label { Text("看網站") } icon: { HeroIcon("globe-alt", size: 16) } }
                        .buttonStyle(.adm(.secondary, size: .lg))
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var trafficSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("流量")
                    .font(.admSection)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Picker("期間", selection: $days) {
                    Text("今天").tag(1)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, 4)

            if let r = report {
                if !r.installed {
                    EmptyState(icon: "cursor-arrow-rays", title: "還沒有流量資料", message: "網站裝好流量追蹤之後，這裡就看得到。")
                        .admCard(padding: 0)
                } else {
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow {
                            KpiTile(label: "現在在線", value: "\(r.live)", live: true)
                            KpiTile(label: "訪客", value: r.visitors.formatted(), percent: r.change)
                        }
                        GridRow {
                            KpiTile(label: "瀏覽", value: r.pageviews.formatted())
                            KpiTile(label: "平均停留", value: r.avgDurationMs.map { Self.duration($0) } ?? "—")
                        }
                    }
                    chart(r)
                    topList("熱門頁面", r.pages)
                    topList("從哪裡來", r.referrers)
                    channels(r)
                }
            } else if loading {
                LoadingRow().admCard(padding: 0)
            }
        }
    }

    private static func duration(_ ms: Double) -> String {
        let s = Int(ms / 1000)
        return s >= 60 ? "\(s / 60) 分 \(s % 60) 秒" : "\(s) 秒"
    }

    private func chart(_ r: TrafficReport) -> some View {
        Chart(r.trend) { p in
            AreaMark(x: .value("時間", p.label), y: .value("訪客", p.visitors))
                .foregroundStyle(LinearGradient(colors: [Theme.chart[0].opacity(0.25), Theme.chart[0].opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("時間", p.label), y: .value("訪客", p.visitors))
                .foregroundStyle(Theme.chart[0])
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.hair)
                AxisValueLabel().foregroundStyle(Theme.inkMuted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel().foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(height: 170)
        .admCard()
    }

    @ViewBuilder
    private func topList(_ title: String, _ items: [TrafficTop]) -> some View {
        if !items.isEmpty {
            let top = Array(items.prefix(6))
            let maxValue = max(top.map(\.visitors).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.admCardTitle)
                    .foregroundStyle(Theme.ink)
                ForEach(top) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.key)
                                .font(.admMeta)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.visitors.formatted())
                                .font(.system(.footnote, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                        }
                        GeometryReader { geo in
                            Capsule()
                                .fill(Theme.chart[0].opacity(0.22))
                                .frame(width: max(4, geo.size.width * CGFloat(item.visitors) / CGFloat(maxValue)))
                        }
                        .frame(height: 4)
                    }
                }
            }
            .admCard()
        }
    }

    @ViewBuilder
    private func channels(_ r: TrafficReport) -> some View {
        let total = max(r.channels.reduce(0) { $0 + $1.visits }, 1)
        if r.channels.contains(where: { $0.visits > 0 }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("流量來源")
                    .font(.admCardTitle)
                    .foregroundStyle(Theme.ink)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(r.channels.enumerated()), id: \.element.id) { i, c in
                            if c.visits > 0 {
                                Rectangle()
                                    .fill(Theme.chart[i % Theme.chart.count])
                                    .frame(width: max(2, geo.size.width * CGFloat(c.visits) / CGFloat(total) - 2))
                            }
                        }
                    }
                    .clipShape(.capsule)
                }
                .frame(height: 8)
                FlowLayout(spacing: 12) {
                    ForEach(Array(r.channels.enumerated()), id: \.element.id) { i, c in
                        HStack(spacing: 5) {
                            Circle().fill(Theme.chart[i % Theme.chart.count]).frame(width: 7, height: 7)
                            Text("\(c.name) \(Int((Double(c.visits) / Double(total) * 100).rounded()))%")
                                .font(.admMeta)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
            .admCard()
        }
    }

    @ViewBuilder
    private func opsSection(_ site: SiteSummary) -> some View {
        if let ops {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "昨天的營運") { Text(ops.rangeLabel) }
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            MetricTile(label: "新訂單", value: "\(ops.createdTotal)")
                            MetricTile(label: "收款", value: ntd(cents: ops.revenueCents))
                        }
                        GridRow {
                            MetricTile(label: "等出貨", value: "\(ops.paidButUnfulfilled)", tone: ops.paidButUnfulfilled > 0 ? .gold : nil)
                            MetricTile(label: "客人等回覆", value: "\(ops.supportAwaiting)", tone: ops.supportAwaiting > 0 ? .warning : nil)
                        }
                    }
                    ForEach(ops.alerts, id: \.self) { alert in
                        Label { Text(alert) } icon: { HeroIcon("exclamation-triangle", size: 15) }
                            .font(.admMeta)
                            .foregroundStyle(Theme.dangerFG)
                    }
                    Button {
                        model.ordersSite = site.id
                        model.ordersStatus = "paid"
                        model.tab = .orders
                    } label: {
                        Label { Text("看訂單") } icon: { HeroIcon("shopping-bag", size: 16) }
                    }
                    .buttonStyle(.adm(.secondary, size: .lg, fullWidth: true))
                }
                .admCard()
            }
        }
    }
}

/// 儀表板上的數字（網站後台的 KPI 卡）
struct KpiTile: View {
    let label: String
    let value: String
    var percent: Double?
    var live = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if live {
                    Circle()
                        .fill(Theme.successFG)
                        .frame(width: 6, height: 6)
                        .phaseAnimator([1.0, 0.3]) { content, phase in
                            content.opacity(phase)
                        } animation: { _ in
                            .easeInOut(duration: 1)
                        }
                }
                FieldLabel(label)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(.title3, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ChangeLabel(percent: percent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .admCard(padding: 14)
    }
}
