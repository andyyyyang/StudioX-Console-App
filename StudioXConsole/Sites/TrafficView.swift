import Charts
import SwiftUI

// 流量與 Google 搜尋（網站後台的「流量」「搜尋成效」；traffic_report、search_report）。

// MARK: - 走勢圖（手指按住可以看每一天的數字）

struct TrafficChart: View {
    enum Measure { case visitors, pageviews }

    let points: [TrafficPoint]
    var metric: Measure = .visitors

    @State private var selected: String?

    var body: some View {
        let value = { (p: TrafficPoint) in metric == .visitors ? p.visitors : p.pageviews }
        let name = metric == .visitors ? "訪客" : "瀏覽"
        let picked = points.first { $0.label == selected }
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("時間", p.label), y: .value(name, value(p)))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("時間", p.label), y: .value(name, value(p)))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let picked {
                RuleMark(x: .value("時間", picked.label))
                    .foregroundStyle(Theme.ink.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(picked.label)
                                .textRole(.xs)
                                .foregroundStyle(Theme.inverseMuted)
                            Text("\(value(picked).formatted()) \(name)")
                                .font(.brand(15, .medium).monospacedDigit())
                                .foregroundStyle(Theme.onInverse)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.inverse, in: .rect(cornerRadius: Metric.radiusSm))
                    }
                PointMark(x: .value("時間", picked.label), y: .value(name, value(picked)))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(60)
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hair)
                AxisValueLabel().foregroundStyle(Theme.muted).font(.brand(11, .regular))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel().foregroundStyle(Theme.muted).font(.brand(11, .regular))
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel("\(name)走勢")
    }
}

// MARK: - 流量的完整報表

struct TrafficView: View {
    let siteID: String
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var days = 7
    @State private var metric: TrafficChart.Measure = .visitors
    @State private var report: TrafficReport?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow(model.site(siteID)?.name ?? siteID)
                    Headline("*Traffic*", role: .h1)
                    Text("訪客以「同一天、同一個瀏覽器」算一位；時間是台北時間。")
                        .textRole(.small)
                        .foregroundStyle(Theme.muted)
                    FilterBar(items: [1, 7, 30, 90, 365], selection: $days, title: { $0 == 1 ? "今天" : $0 == 365 ? "一年" : "\($0) 天" })
                }
                .reveal()

                if let r = report {
                    if !r.installed {
                        EmptyState(title: "還沒有流量資料", message: "網站裝好流量追蹤之後，這裡就看得到。")
                    } else {
                        content(r)
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 4)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await load() }
        .brandPage()
        .navigationTitle("流量")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await load() }
    }

    private func load() async {
        error = nil
        do {
            report = try await model.api.traffic(site: siteID, days: days)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func content(_ r: TrafficReport) -> some View {
        StatGrid(columns: sizeClass == .regular ? 3 : 2) {
            Stat(value: Double(r.visitors), label: "訪客", change: r.change)
            Stat(value: Double(r.pageviews), label: "瀏覽", change: r.pageviewsChange)
            Stat(value: Double(r.visits), label: "造訪")
            Stat(value: r.bounceRate ?? 0, label: "只看一頁就離開", format: { "\(Int($0.rounded()))%" })
            Stat(value: (r.avgDurationMs ?? 0) / 1000, label: "平均停留", format: { s in
                let n = Int(s.rounded())
                return n >= 60 ? "\(n / 60)m\(n % 60)s" : "\(n)s"
            })
            Stat(value: Double(r.live), label: "現在在線")
        }

        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(days == 1 ? "今天每小時" : "每天")
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 6) {
                    FilterChip(title: "訪客", selected: metric == .visitors) { metric = .visitors }
                    FilterChip(title: "瀏覽", selected: metric == .pageviews) { metric = .pageviews }
                }
            }
            TrafficChart(points: r.trend, metric: metric)
                .frame(height: sizeClass == .regular ? 300 : 220)
                .animation(Motion.ease, value: metric)
        }

        if !r.funnel.isEmpty {
            FunnelView(report: r)
        }

        if r.weekHours.count == 7, r.weekHours.contains(where: { $0.contains { $0 > 0 } }) {
            VStack(alignment: .leading, spacing: 20) {
                SectionHead("When they *come*", aside: "一週七天、每個小時的瀏覽次數，顏色越深越多人。", role: .h3)
                WeekHeatmap(grid: r.weekHours)
            }
        }

        let columns = sizeClass == .regular ? [GridItem(.flexible(), spacing: 48), GridItem(.flexible(), spacing: 48)] : [GridItem(.flexible())]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
            Breakdown(title: "熱門頁面", items: r.pages)
            Breakdown(title: "從哪一頁進來", items: r.entries)
            Breakdown(title: "來源網站", items: r.referrers)
            ChannelBreakdown(channels: r.channels)
            Breakdown(title: "國家", items: r.countries, name: TrafficReport.countryName)
            Breakdown(title: "裝置", items: r.devices, name: TrafficReport.deviceLabel)
            Breakdown(title: "瀏覽器", items: r.browsers)
            Breakdown(title: "作業系統", items: r.oses)
            if !r.campaigns.isEmpty {
                Breakdown(title: "行銷活動（utm）", items: r.campaigns)
            }
        }

        if !r.contentPages.isEmpty {
            ContentImpactView(pages: r.contentPages)
        }
    }
}

/// 一種排行（熱門頁面、來源…）：細線隔開、後面一條比例條
struct Breakdown: View {
    let title: String
    let items: [TrafficTop]
    var name: (String) -> String = { $0 }
    var limit = 8

    var body: some View {
        let top = Array(items.prefix(limit))
        let maxValue = max(top.map(\.visitors).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("訪客")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
            if top.isEmpty {
                Text("還沒有資料")
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
            } else {
                RuledList(color: Theme.hair) {
                    ForEach(top) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(name(item.key))
                                    .textRole(.small)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 12)
                                Text(item.visitors.formatted())
                                    .font(.brand(14, .medium).monospacedDigit())
                                    .foregroundStyle(Theme.ink)
                            }
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Theme.accent.opacity(0.55))
                                    .frame(width: max(3, geo.size.width * CGFloat(item.visitors) / CGFloat(maxValue)))
                            }
                            .frame(height: 2)
                        }
                        .padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// 流量來源：一條分段的條＋圖例
struct ChannelBreakdown: View {
    let channels: [ChannelShare]

    var body: some View {
        let total = max(channels.reduce(0) { $0 + $1.visits }, 1)
        VStack(alignment: .leading, spacing: 16) {
            Text("流量來源")
                .textRole(.h4)
                .foregroundStyle(Theme.ink)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(channels.enumerated()), id: \.element.id) { i, c in
                        if c.visits > 0 {
                            Rectangle()
                                .fill(Theme.chart[i % Theme.chart.count])
                                .frame(width: max(2, geo.size.width * CGFloat(c.visits) / CGFloat(total) - 2))
                        }
                    }
                }
            }
            .frame(height: 10)
            .clipShape(.rect(cornerRadius: 2))
            RuledList(color: Theme.hair) {
                ForEach(Array(channels.enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 10) {
                        Rectangle().fill(Theme.chart[i % Theme.chart.count]).frame(width: 8, height: 8)
                        Text(c.name)
                            .textRole(.small)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(Int((Double(c.visits) / Double(total) * 100).rounded()))%")
                            .font(.brand(14, .medium).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                        Text(c.visits.formatted())
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }
}

/// 一週的熱度：7 列（一到日）× 24 小時，顏色越深瀏覽越多
struct WeekHeatmap: View {
    let grid: [[Int]]
    @State private var picked: (day: Int, hour: Int)?

    private let days = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        let top = max(grid.flatMap { $0 }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<7, id: \.self) { d in
                HStack(spacing: 3) {
                    Text(days[d])
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18, alignment: .leading)
                    ForEach(0..<24, id: \.self) { h in
                        let n = grid[safe: d]?[safe: h] ?? 0
                        let on = picked?.day == d && picked?.hour == h
                        RoundedRectangle(cornerRadius: 2)
                            .fill(n == 0 ? Theme.press : Theme.accent.opacity(0.12 + 0.88 * Double(n) / Double(top)))
                            .overlay { if on { RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.ink, lineWidth: 1.5) } }
                            .aspectRatio(1, contentMode: .fit)
                            .onTapGesture { picked = on ? nil : (d, h) }
                    }
                }
            }
            HStack(spacing: 3) {
                Color.clear.frame(width: 18, height: 1)
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text("\(h)")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Group {
                if let picked {
                    Text("星期\(days[picked.day]) \(picked.hour):00–\(picked.hour + 1):00：\(grid[safe: picked.day]?[safe: picked.hour] ?? 0) 次瀏覽")
                } else {
                    Text("點一格看那個時段的數字")
                }
            }
            .textRole(.xs)
            .foregroundStyle(Theme.muted)
        }
        .sensoryFeedback(.selection, trigger: picked.map { $0.day * 24 + $0.hour })
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// 購物漏斗（黃毛丫頭）：進站 → 看商品 → 加入購物車 → 開始結帳 → 送出訂單
struct FunnelView: View {
    let report: TrafficReport

    var body: some View {
        let first = max(report.funnel.first?.visitors ?? 1, 1)
        VStack(alignment: .leading, spacing: 24) {
            SectionHead("The *funnel*", aside: "從進站到下單，每一步還剩多少人。", role: .h3)
            VStack(spacing: 0) {
                ForEach(Array(report.funnel.enumerated()), id: \.element.id) { i, step in
                    let ratio = Double(step.visitors) / Double(first)
                    let prev = i > 0 ? report.funnel[i - 1].visitors : step.visitors
                    Rule()
                    HStack(alignment: .center, spacing: 16) {
                        Text(String(format: "%02d", i + 1))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(step.label)
                                    .textRole(.h4)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(step.visitors.formatted())
                                    .textRole(.number)
                                    .foregroundStyle(Theme.ink)
                            }
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Theme.accent)
                                    .frame(width: max(3, geo.size.width * ratio))
                            }
                            .frame(height: 3)
                            if i > 0, prev > 0 {
                                Text("上一步的 \(Int((Double(step.visitors) / Double(prev) * 100).rounded()))%・進站的 \(String(format: "%.1f", ratio * 100))%")
                                    .textRole(.xs)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
                Rule()
            }
            if let orders = report.funnelPaidOrders {
                Text("付款完成 \(orders) 筆" + (report.funnelRevenueCents.map { "・\(ntd(cents: $0))" } ?? ""))
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
            }
            if !report.funnelProducts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("商品：看的人／加入購物車")
                        .textRole(.small)
                        .foregroundStyle(Theme.muted)
                    RuledList(color: Theme.hair) {
                        ForEach(report.funnelProducts) { p in
                            HStack {
                                Text(p.name)
                                    .textRole(.small)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(p.viewers) ／ \(p.adders)")
                                    .font(.brand(14, .medium).monospacedDigit())
                                    .foregroundStyle(Theme.ink)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }
}

/// 內容頁帶來的生意（黃毛丫頭的 contentPages）
struct ContentImpactView: View {
    let pages: [ContentPageImpact]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHead("Content that *sells*", aside: "看過這頁的人，有多少去看商品、加購物車、下單。", role: .h3)
            RuledList(color: Theme.hair) {
                ForEach(pages.prefix(12)) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.path)
                            .textRole(.small)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 14) {
                            label("訪客", p.visitors)
                            label("看商品", p.viewed)
                            label("加購物車", p.carted)
                            label("下單", p.ordered)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func label(_ title: String, _ n: Int) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(Theme.muted)
            Text("\(n)").foregroundStyle(n > 0 && title == "下單" ? Theme.accentText : Theme.ink).monospacedDigit()
        }
        .textRole(.xs)
    }
}

// MARK: - Google 搜尋成效

struct SearchConsoleView: View {
    let siteID: String
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var days = 28
    @State private var showImpressions = false
    @State private var tab = 0
    @State private var report: SearchReport?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow(model.site(siteID)?.name ?? siteID)
                    Headline("Found on *Google*", role: .h1)
                    Text("Google Search Console 的資料，大約晚 1～2 天。")
                        .textRole(.small)
                        .foregroundStyle(Theme.muted)
                    FilterBar(items: [7, 28, 90, 365], selection: $days, title: { $0 == 365 ? "一年" : "\($0) 天" })
                }
                .reveal()

                if let r = report {
                    switch r.status {
                    case "not_connected":
                        EmptyState(title: "還沒有接上 Google Search Console", message: r.note ?? "在網站後台的「整合」接上之後，這裡就看得到搜尋成效。")
                    case "error":
                        ErrorNote(message: r.note ?? "Google 那邊沒有回應") { Task { await load() } }
                    default:
                        content(r)
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 4)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await load() }
        .brandPage()
        .navigationTitle("Google 搜尋")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await load() }
    }

    private func load() async {
        error = nil
        do {
            report = try await model.api.searchReport(site: siteID, days: days)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func content(_ r: SearchReport) -> some View {
        StatGrid {
            Stat(value: Double(r.clicks), label: "點擊", change: r.clicksChange)
            Stat(value: Double(r.impressions), label: "曝光", change: r.impressionsChange)
            Stat(value: (r.ctr ?? 0) * 100, label: "點閱率", format: { String(format: "%.1f%%", $0) })
            Stat(value: r.position ?? 0, label: "平均排名", format: { String(format: "%.1f", $0) })
        }
        if let range = r.rangeLabel {
            Text("\(range)・\(r.property ?? "")")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }

        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("每天")
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 6) {
                    FilterChip(title: "點擊", selected: !showImpressions) { showImpressions = false }
                    FilterChip(title: "曝光", selected: showImpressions) { showImpressions = true }
                }
            }
            TrafficChart(points: r.trend.map { TrafficPoint(label: $0.label, date: $0.date, visitors: showImpressions ? $0.impressions : $0.clicks, pageviews: 0) }, metric: .visitors)
                .frame(height: sizeClass == .regular ? 280 : 210)
        }

        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                FilterChip(title: "搜尋關鍵字", count: r.queries.count, selected: tab == 0) { tab = 0 }
                FilterChip(title: "頁面", count: r.pages.count, selected: tab == 1) { tab = 1 }
                FilterChip(title: "國家", count: r.countries.count, selected: tab == 2) { tab = 2 }
            }
            SearchRows(rows: tab == 0 ? r.queries : tab == 1 ? r.pages : r.countries, country: tab == 2)
        }
    }
}

/// 搜尋成效的表：關鍵字（或頁面、國家）、點擊、曝光、點閱率、排名
private struct SearchRows: View {
    let rows: [SearchReport.Row]
    var country = false

    var body: some View {
        if rows.isEmpty {
            Text("這段期間沒有資料")
                .textRole(.small)
                .foregroundStyle(Theme.muted)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(country ? "國家" : "").frame(maxWidth: .infinity, alignment: .leading)
                    Text("點擊").frame(width: 52, alignment: .trailing)
                    Text("曝光").frame(width: 60, alignment: .trailing)
                    Text("排名").frame(width: 44, alignment: .trailing)
                }
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 8)
                RuledList(color: Theme.hair) {
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(country ? TrafficReport.countryName(row.key.uppercased()) : row.key)
                                    .textRole(.small)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                if let ctr = row.ctr {
                                    Text(String(format: "點閱率 %.1f%%", ctr * 100))
                                        .textRole(.xs)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.clicks.formatted()).frame(width: 52, alignment: .trailing)
                            Text(row.impressions.formatted()).frame(width: 60, alignment: .trailing)
                            Text(row.position.map { String(format: "%.1f", $0) } ?? "—").frame(width: 44, alignment: .trailing)
                        }
                        .font(.brand(14, .medium).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 11)
                    }
                }
            }
        }
    }
}
