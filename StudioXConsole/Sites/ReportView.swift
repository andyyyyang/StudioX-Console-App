import SwiftUI

/// 營運報表（網站後台首頁的數字）：選一段時間看訂單、收款、等出貨、客服待辦、異常；
/// 會員：總數、這個月新加入、累積消費、各等級人數、消費最多的五位（點進會員頁）；
/// 哪裡的人最常訂購：付款的訂單照收件的地方分縣市（網站的 ops_report section=regions，只有總數、沒有客人的資料）；
/// 現場排隊 → 線上成交：取號、掃 QR 看叫號、當天看商品／加購物車／下單、排隊帶來的訂單（section=queue）。
struct OpsReportView: View {
    let siteID: String

    @Environment(AppModel.self) private var model
    @State private var days = 7
    @State private var report: JSONValue?
    @State private var members: JSONValue?
    @State private var regions: JSONValue?
    /// 地區看比較長的時間才有意義：自己的區間（預設 90 天）
    @State private var regionDays = 90
    @State private var queue: JSONValue?
    /// 現場排隊也有自己的區間（預設 30 天）：上面的「昨天」對排隊沒有意義
    @State private var queueDays = 30
    @State private var error: String?
    @State private var loading = false

    private var site: SiteSummary? { model.site(siteID) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    VStack(alignment: .leading, spacing: 18) {
                        PageHeader("營運報表", eyebrow: site?.name ?? siteID)
                        FilterBar(items: [1, 7, 30, 90], selection: $days, title: { $0 == 1 ? "昨天" : "\($0) 天" })
                    }
                    if let error {
                        ErrorNote(message: error) { Task { await load() } }
                    }
                    if let r = report {
                        orders(r)
                    } else if loading {
                        SkeletonRows(rows: 4)
                    }
                    if let q = queue {
                        queueSection(q)
                            .id("queue")
                    }
                    if let m = members {
                        memberSection(m)
                    }
                    if let r = regions {
                        regionSection(r)
                            .id("regions")
                    }
                }
                .frame(maxWidth: Metric.readable + 160, alignment: .leading)
                .pageWidth()
                .padding(.top, 16)
                .padding(.bottom, 64)
            }
            // UI 截圖（-demoScroll regions／queue）：捲到「哪裡的人最常訂購」／「現場排隊 → 線上成交」
            .task(id: regions != nil && queue != nil) {
                guard DemoServer.screenshots, regions != nil, queue != nil,
                      let target = UserDefaults.standard.string(forKey: "demoScroll"), ["regions", "queue"].contains(target) else { return }
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo(target, anchor: .top)
            }
        }
        .refreshable {
            await Task {
                await load()
                await loadQueue()
                await loadRegions()
            }.value
        }
        .brandPage()
        .pageTitle("營運報表")
        .task(id: days) { await load() }
        .task(id: regionDays) { await loadRegions() }
        .task(id: queueDays) { await loadQueue() }
    }

    /// 網站有現場排隊的報表才放（沒有叫號的網站、舊版網站不顯示）；換區間時讀不到就留著上一次的
    private func loadQueue() async {
        guard let q = try? await model.api.tool("ops_report", site: siteID, ["section": "queue", "days": .number(Double(queueDays))]),
              q["tickets"] != nil else { return }
        withAnimation(Motion.ease) { queue = q }
    }

    /// 網站有地區報表才放（舊版網站回錯誤就不顯示）；換區間時讀不到就留著上一次的
    private func loadRegions() async {
        guard let r = try? await model.api.tool("ops_report", site: siteID, ["section": "regions", "days": .number(Double(regionDays))]),
              r["cities"] != nil else { return }
        withAnimation(Motion.ease) { regions = r }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            report = try await model.api.tool("ops_report", site: siteID, ["section": "orders", "days": .number(Double(days))])
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        // 會員的數字不隨時間區間變：第一次拿就好（沒有權限看會員就不放）
        if members == nil {
            members = try? await model.api.tool("ops_report", site: siteID, ["section": "members"])
        }
    }

    // MARK: 訂單與收款

    @ViewBuilder
    private func orders(_ r: JSONValue) -> some View {
        let ops = OpsReport(r)
        VStack(alignment: .leading, spacing: 24) {
            SectionHead("訂單與收款・\(ops.rangeLabel.isEmpty ? (days == 1 ? "昨天" : "最近 \(days) 天") : ops.rangeLabel)", role: .h3) {
                MoreLink("看訂單") {
                    model.openOrders(site: siteID, status: "all")
                }
            }
            StatGrid {
                Stat(value: Double(ops.revenueCents) / 100, label: "收款", format: { "NT$" + Int($0.rounded()).formatted() }, compact: { ntdShort(cents: Int(($0 * 100).rounded())) })
                Stat(value: Double(ops.paidCount), label: "付款的訂單")
                Stat(value: Double(ops.createdTotal), label: "新訂單")
                Stat(value: ops.paidCount > 0 ? Double(ops.revenueCents) / 100 / Double(ops.paidCount) : 0, label: "平均客單", format: { "NT$" + Int($0.rounded()).formatted() }, compact: { ntdShort(cents: Int(($0 * 100).rounded())) })
            }
            // 新訂單現在是什麼狀態
            let byStatus = (r["created"]?["byStatus"]?.array ?? []).compactMap { s -> (OrderStatus, Int)? in
                guard let raw = s["status"]?.string, let n = s["count"]?.int, n > 0 else { return nil }
                return (OrderStatus(raw: raw), n)
            }
            if !byStatus.isEmpty {
                Bars(title: "新訂單現在的狀態", rows: byStatus.map { ($0.0.label, $0.1) })
            }
        }
        VStack(alignment: .leading, spacing: 18) {
            SectionHead("現在", role: .h3)
            StatGrid {
                Stat(value: Double(ops.paidButUnfulfilled), label: "等出貨")
                Stat(value: Double(ops.awaitingPayment), label: "等付款")
                Stat(value: Double(ops.supportAwaiting), label: "客人等回覆", note: ops.oldestWaitHours.map { "最久 \($0) 小時" })
                Stat(value: Double(ops.notificationsOverdue), label: "通知逾時")
            }
            if ops.alerts.isEmpty {
                Text("沒有偵測到異常。")
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("要注意的")
                    ForEach(ops.alerts, id: \.self) { alert in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            HeroIcon("exclamation-triangle", size: 15)
                                .foregroundStyle(Theme.warningFG)
                            Text(alert)
                                .textRole(.small)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .panel(padding: 16)
            }
        }
    }

    // MARK: 現場排隊

    @ViewBuilder
    private func queueSection(_ q: JSONValue) -> some View {
        let same = q["sameDay"] ?? .null
        let orders = q["orders"] ?? .null
        let gift = q["gift"] ?? .null
        let steps: [(String, Int, Int?)] = [
            ("取號", q["tickets"]?.int ?? 0, nil),
            ("掃 QR 看叫號", q["scanned"]?.int ?? 0, q["scanRatePercent"]?.int),
            ("當天看商品", same["viewed"]?.int ?? 0, same["viewRatePercent"]?.int),
            ("當天加購物車", same["carted"]?.int ?? 0, same["cartRatePercent"]?.int),
            ("當天下單", same["ordered"]?.int ?? 0, same["orderRatePercent"]?.int),
        ]
        VStack(alignment: .leading, spacing: 20) {
            SectionHead("現場排隊 → 線上成交", role: .h3)
            FilterBar(items: [7, 30, 90, 365], selection: $queueDays, title: { $0 == 365 ? "一年" : "\($0) 天" })
            if let summary = q["summary"]?.string {
                Text(summary)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let top = max(1, steps.map(\.1).max() ?? 1)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps.indices, id: \.self) { i in
                    QueueStepRow(label: steps[i].0, count: steps[i].1, rate: steps[i].2, maxCount: top, first: i == 0)
                }
            }
            StatGrid {
                Stat(value: Double(orders["count"]?.int ?? 0), label: "排隊帶來的訂單", format: { "\(Int($0)) 張" })
                Stat(value: 0, label: "營收（占比）", format: { _ in
                    orders["count"]?.int == 0 ? "—" : "\(orders["revenueLabel"]?.string ?? "—")（\(orders["revenueSharePercent"]?.int ?? 0)%）"
                })
                Stat(value: orders["avgDaysToOrder"]?.double ?? 0, label: "排隊後幾天下單", format: { _ in
                    orders["avgDaysToOrder"]?.double.map { "平均 \($0.formatted(.number.precision(.fractionLength(0...1)))) 天" } ?? "—"
                })
                Stat(value: Double(gift["claimed"]?.int ?? 0), label: "領會員禮", format: { _ in
                    let claimed = gift["claimed"]?.int ?? 0
                    return claimed == 0 ? "0 位" : "\(claimed) 位・用掉 \(gift["used"]?.int ?? 0)"
                })
            }
            Text(queueNote(q))
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 排隊帶來的訂單是怎麼認的、「當天」只算得到同一天
    private func queueNote(_ q: JSONValue) -> String {
        var parts: [String] = []
        if let e = q["orders"]?["byEvidence"], (q["orders"]?["count"]?.int ?? 0) > 0 {
            parts.append("排隊帶來的訂單：用了會員禮的券 \(e["coupon"]?.int ?? 0) 張、領過會員禮的會員 \(e["member"]?.int ?? 0) 張、這支手機排過隊 \(e["device"]?.int ?? 0) 張。")
        }
        parts.append("「當天」看的是流量（同一天、同一個瀏覽器）；之後幾天才下的單，要用了會員禮、領過會員禮，或用同一支手機下單（60 天內）才算得到。")
        return parts.joined()
    }

    // MARK: 地區

    @ViewBuilder
    private func regionSection(_ r: JSONValue) -> some View {
        let cities = r["cities"]?.array ?? []
        VStack(alignment: .leading, spacing: 20) {
            SectionHead("哪裡的人最常訂購", role: .h3)
            FilterBar(items: [30, 90, 365, 3650], selection: $regionDays, title: { $0 == 365 ? "一年" : $0 == 3650 ? "全部" : "\($0) 天" })
            if let summary = r["summary"]?.string {
                Text(summary)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !cities.isEmpty {
                let top = max(1, cities.compactMap { $0["orders"]?.int }.max() ?? 1)
                RuledList {
                    ForEach(cities.prefix(12).indices, id: \.self) { i in
                        RegionRow(rank: i + 1, city: cities[i], maxOrders: top)
                    }
                }
            }
            Text(regionNote(r))
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 這份數字有多少代表性：認得出地區的比例、7-11 舊單沒有門市地址
    private func regionNote(_ r: JSONValue) -> String {
        var parts = ["照收件的地方算（宅配看地址、7-11 看取貨門市；送禮的算收件人那裡）。"]
        if let located = r["located"]?.int, let total = r["orders"]?.int, total > 0 {
            parts.append("認得出地區 \(located) / \(total) 張（\(r["coveragePercent"]?.int ?? 0)%）。")
        }
        if let old = r["unknown"]?["pickupWithoutAddress"]?.int, old > 0 {
            parts.append("7-11 取貨的舊單 \(old) 張沒有門市地址，10/8 起會記下來。")
        }
        return parts.joined()
    }

    // MARK: 會員

    @ViewBuilder
    private func memberSection(_ m: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHead("會員", role: .h3)
            StatGrid(columns: 3) {
                Stat(value: Double(m["total"]?.int ?? 0), label: "會員")
                Stat(value: Double(m["newThisMonth"]?.int ?? 0), label: "這個月新加入")
                Stat(value: Double(m["total"]?.int ?? 0), label: "累積消費", format: { _ in m["totalSpendLabel"]?.string ?? "—" })
            }
            let tiers = (m["tiers"]?.array ?? []).compactMap { t -> (String, Int)? in
                guard let name = t["name"]?.string, let n = t["count"]?.int else { return nil }
                return (name, n)
            }
            if !tiers.isEmpty {
                Bars(title: "各等級的人數", rows: tiers.sorted { $0.1 > $1.1 })
            }
            if let top = m["topSpenders"]?.array, !top.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("消費最多的")
                    RuledList {
                        ForEach(top.indices, id: \.self) { i in
                            let t = top[i]
                            Button {
                                if let id = t["id"]?.string { model.open(.member(site: siteID, id: id)) }
                            } label: {
                                HStack {
                                    Text("\(i + 1)")
                                        .font(.brand(13, .medium).monospacedDigit())
                                        .foregroundStyle(Theme.muted)
                                        .frame(width: 22, alignment: .leading)
                                    Text(t["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? t["email"]?.string ?? "會員")
                                        .textRole(.small)
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(t["spendLabel"]?.string ?? "")
                                        .font(.brand(15, .medium).monospacedDigit())
                                        .foregroundStyle(Theme.ink)
                                }
                                .padding(.vertical, 12)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.row)
                        }
                    }
                }
            }
        }
    }
}

/// 現場排隊的一步：名稱、人數（橫條）、占上一步幾 %
private struct QueueStepRow: View {
    let label: String
    let count: Int
    let rate: Int?
    let maxCount: Int
    let first: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .textRole(.small)
                .foregroundStyle(Theme.ink)
                .frame(width: 104, alignment: .leading)
                .lineLimit(1)
            GeometryReader { g in
                Capsule()
                    .fill(first ? Theme.ink.opacity(0.35) : Theme.accent)
                    .frame(width: max(4, g.size.width * CGFloat(count) / CGFloat(maxCount)))
            }
            .frame(height: 8)
            Text("\(count)")
                .font(.brand(13, .medium).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 32, alignment: .trailing)
            Text(rate.map { "\($0)%" } ?? "")
                .font(.brand(12, .regular).monospacedDigit())
                .foregroundStyle(Theme.muted)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rate.map { "\(label) \(count)，上一步的 \($0)%" } ?? "\(label) \(count)")
    }
}

/// 一個縣市：名次、訂單（橫條）、買家、營收與占比、客單價、回購率、最多的區
private struct RegionRow: View {
    let rank: Int
    let city: JSONValue
    let maxOrders: Int

    var body: some View {
        let orders = city["orders"]?.int ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.brand(13, .medium).monospacedDigit())
                    .foregroundStyle(rank == 1 ? Theme.accentText : Theme.muted)
                    .frame(width: 22, alignment: .leading)
                Text(city["city"]?.string ?? "")
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 64, alignment: .leading)
                GeometryReader { g in
                    Capsule()
                        .fill(rank == 1 ? Theme.accent : Theme.ink.opacity(0.75))
                        .frame(width: max(4, g.size.width * CGFloat(orders) / CGFloat(maxOrders)))
                }
                .frame(height: 8)
                Text("\(orders) 張")
                    .font(.brand(13, .medium).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            Text(detail)
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .padding(.leading, 34)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = ["\(city["buyers"]?.int ?? 0) 位買家"]
        if let revenue = city["revenueLabel"]?.string { parts.append("\(revenue)（\(city["revenueSharePercent"]?.int ?? 0)%）") }
        if let avg = city["avgOrderLabel"]?.string { parts.append("客單 \(avg)") }
        parts.append("回購 \(city["repeatRatePercent"]?.int ?? 0)%")
        let districts = (city["topDistricts"]?.array ?? []).prefix(3).compactMap { d -> String? in
            guard let name = d["district"]?.string, let n = d["orders"]?.int else { return nil }
            return "\(name) \(n)"
        }
        if !districts.isEmpty { parts.append("最多：" + districts.joined(separator: "、")) }
        return parts.joined(separator: "・")
    }
}

/// 一組橫條（各狀態、各等級的數量）
private struct Bars: View {
    let title: String
    let rows: [(String, Int)]

    var body: some View {
        let top = max(1, rows.map(\.1).max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    let row = rows[i]
                    HStack(spacing: 12) {
                        Text(row.0)
                            .textRole(.small)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 96, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { g in
                            Capsule()
                                .fill(Theme.ink.opacity(0.75))
                                .frame(width: max(4, g.size.width * CGFloat(row.1) / CGFloat(top)))
                        }
                        .frame(height: 8)
                        Text("\(row.1)")
                            .font(.brand(13, .medium).monospacedDigit())
                            .foregroundStyle(Theme.ink2)
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.0) \(row.1)")
                }
            }
        }
    }
}
