import SwiftUI

/// 首頁就是 Xena：24 小時值班的店長。
///   - 水滴＋她跟你打招呼（照真的資料說：昨天的訂單、現在誰在等你）
///   - 需要你看一下：客人在等回覆、已付款等出貨、營運異常、Xena 轉給專人的對話、新的專案詢問（點了直接去處理）
///   - 昨天：有商店的網站各自的營運報表
///   - 最近 7 天：每個網站的訪客
struct XenaHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack(path: Bindable(model).homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    presence
                    attention
                    yesterday
                    traffic
                    asks
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .refreshable { [model] in await model.refreshAll() }
            .admPage()
            .navigationTitle(Date.now.dayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    // MARK: 招呼

    private var greeting: String {
        let b = model.briefing
        guard b.updatedAt != nil else { return "我正在看你的網站昨晚到現在的狀況，等我一下…" }
        let hour = Calendar.current.component(.hour, from: .now)
        let hello = switch hour {
        case 5..<11: "早安"
        case 11..<14: "午安"
        case 14..<18: "下午好"
        case 18..<23: "晚上好"
        default: "這麼晚還在忙"
        }
        var parts: [String] = []
        for site in model.orderSites {
            if let r = b.ops[site.id] {
                parts.append(r.createdTotal > 0 ? "昨天\(site.name)有 \(r.createdTotal) 筆訂單、收款 \(ntd(cents: r.revenueCents))" : "昨天\(site.name)沒有新訂單")
            }
        }
        var now: [String] = []
        if !b.awaiting.isEmpty { now.append("\(b.awaiting.count) 位客人在等回覆") }
        let ship = b.toShip.values.reduce(0) { $0 + $1.count }
        if ship > 0 { now.append("\(ship) 筆訂單等出貨") }
        if !b.handoffs.isEmpty { now.append("\(b.handoffs.count) 段對話轉給專人") }
        if !b.inquiries.isEmpty { now.append("\(b.inquiries.count) 筆新的專案詢問") }
        var text = "\(hello)，\(model.me?.name ?? "")。"
        if !parts.isEmpty { text += parts.joined(separator: "；") + "。" }
        text += now.isEmpty ? "現在沒有要你決定的事，我繼續看著 ☕️" : "現在" + now.joined(separator: "、") + "，我列在下面。"
        return text
    }

    private var presence: some View {
        VStack(spacing: 14) {
            Button {
                model.showXena = true
            } label: {
                XenaOrb(mood: model.xena.mood, size: 112, pulse: model.xena.pulse)
            }
            .buttonStyle(PressScale())
            .accessibilityHint("打開對話")

            VStack(spacing: 3) {
                Text("Xena")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.successFG)
                        .frame(width: 7, height: 7)
                    Text("店長・\(model.xena.mood.label)・24 小時在線")
                }
                .font(.admMeta)
                .foregroundStyle(Theme.inkMuted)
            }

            TypewriterText(text: greeting, animate: !model.greeted) {
                if model.briefing.updatedAt != nil { model.greeted = true }
            }
            .font(.system(size: 16))
            .lineSpacing(4)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .admCard()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: 需要你看一下

    @ViewBuilder
    private var attention: some View {
        let items = model.briefing.attention(sites: model.sites)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "需要你看一下") {
                if model.briefing.loading { ProgressView().controlSize(.small) } else if let at = model.briefing.updatedAt { Text("\(at.clockText) 更新") }
            }
            if items.isEmpty {
                if model.briefing.updatedAt != nil {
                    EmptyState(icon: "check-circle", title: "都處理好了", message: "沒有要你決定的事，我繼續看著。")
                        .admCard(padding: 0)
                } else {
                    LoadingRow(text: "Xena 正在看各網站…")
                        .admCard(padding: 0)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.hair).padding(.leading, 56) }
                        Button { run(item.action) } label: { AttentionRow(item: item, site: model.site(item.site)) }
                            .buttonStyle(RowPressStyle())
                    }
                }
                .admCard(padding: 0)
            }
            ForEach(model.briefing.failures.sorted(by: { $0.key < $1.key }), id: \.key) { site, message in
                ErrorNote(message: "\(model.site(site)?.name ?? site)：\(message)") {
                    Task { await model.refreshAll() }
                }
            }
        }
    }

    private func run(_ action: AttentionItem.Action) {
        switch action {
        case .inbox:
            model.tab = .inbox
        case .orders(let site, let status):
            model.ordersSite = site
            model.ordersStatus = status
            model.tab = .orders
        case .askXena(let prompt):
            model.askXena(prompt)
        }
    }

    // MARK: 昨天

    @ViewBuilder
    private var yesterday: some View {
        let reports = model.orderSites.compactMap { site in model.briefing.ops[site.id].map { (site, $0) } }
        if !reports.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "昨天") { Text(reports.first?.1.rangeLabel ?? "") }
                ForEach(reports, id: \.0.id) { site, report in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            SiteIconView(site: site, size: 28)
                            Text(site.name)
                                .font(.admCardTitle)
                                .foregroundStyle(Theme.ink)
                        }
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                MetricTile(label: "訂單", value: "\(report.createdTotal)")
                                MetricTile(label: "收款", value: ntd(cents: report.revenueCents))
                            }
                            GridRow {
                                MetricTile(label: "等付款", value: "\(report.awaitingPayment)")
                                MetricTile(label: "等出貨", value: "\(report.paidButUnfulfilled)", tone: report.paidButUnfulfilled > 0 ? .gold : nil)
                            }
                        }
                        if !report.summary.isEmpty {
                            Text(report.summary)
                                .font(.admMeta)
                                .foregroundStyle(Theme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .admCard()
                }
            }
        }
    }

    // MARK: 最近 7 天

    @ViewBuilder
    private var traffic: some View {
        let sites = model.sites.filter { $0.stats != nil }
        if !sites.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "最近 7 天") { Text("訪客") }
                VStack(spacing: 0) {
                    ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                        if index > 0 { Divider().overlay(Theme.hair).padding(.leading, 56) }
                        Button { model.open(.site(site.id)) } label: { SiteStatRow(site: site) }
                            .buttonStyle(RowPressStyle())
                    }
                }
                .admCard(padding: 0)
            }
        }
    }

    private var asks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("問 Xena")
            ChipFlow(items: XenaSession.starters) { model.askXena($0) }
        }
    }
}

/// 首頁的一件事
private struct AttentionRow: View {
    let item: AttentionItem
    let site: SiteSummary?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HeroIcon(item.icon, size: 18)
                .foregroundStyle(item.tone.foreground)
                .frame(width: 32, height: 32)
                .background(item.tone.background, in: .rect(cornerRadius: Metric.radiusMd, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.admCardTitle)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(item.detail)
                    .font(.admMeta)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            HeroIcon("chevron-right", size: 14)
                .foregroundStyle(Theme.faint)
                .padding(.top, 9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// 網站一列：圖示、名稱、7 天訪客、走勢（console 網站選擇器的 .au-site）
struct SiteStatRow: View {
    let site: SiteSummary

    var body: some View {
        HStack(spacing: 12) {
            SiteIconView(site: site, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(site.name)
                    .font(.admCardTitle)
                    .foregroundStyle(Theme.ink)
                Text([site.org, site.host].compactMap { $0 }.joined(separator: " · "))
                    .font(.admMeta)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let stats = site.stats {
                Sparkline(values: stats.trend.map(Double.init))
                    .stroke(Theme.chart[0], style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 56, height: 18)
                    .opacity(0.8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(stats.visitors.formatted())
                        .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    ChangeLabel(percent: stats.change)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// 一個數字＋標籤
struct MetricTile: View {
    let label: String
    let value: String
    var tone: Tone?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FieldLabel(label)
            Text(value)
                .font(.system(.title3, weight: .semibold).monospacedDigit())
                .foregroundStyle(tone?.foreground ?? Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 清單的一列：按下有淡淡的底（--adm-hover）
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.hover : .clear)
    }
}
