import SwiftUI

/// 營運報表（網站後台首頁的數字）：選一段時間看訂單、收款、等出貨、客服待辦、異常；
/// 會員：總數、這個月新加入、累積消費、各等級人數、消費最多的五位（點進會員頁）。
struct OpsReportView: View {
    let siteID: String

    @Environment(AppModel.self) private var model
    @State private var days = 7
    @State private var report: JSONValue?
    @State private var members: JSONValue?
    @State private var error: String?
    @State private var loading = false

    private var site: SiteSummary? { model.site(siteID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(site?.name ?? siteID)
                    Headline("Store *report*", role: .h1)
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
                if let m = members {
                    memberSection(m)
                }
            }
            .frame(maxWidth: Metric.readable + 160, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await load() }.value }
        .brandPage()
        .navigationTitle("營運報表")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: days) { await load() }
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
            SectionHead("Orders, *\(ops.rangeLabel.isEmpty ? (days == 1 ? "昨天" : "\(days) 天") : ops.rangeLabel)*", role: .h3) {
                MoreLink("看訂單") {
                    model.ordersSite = siteID
                    model.ordersStatus = "all"
                    model.tab = .orders
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
            SectionHead("Right *now*", role: .h3)
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

    // MARK: 會員

    @ViewBuilder
    private func memberSection(_ m: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHead("*Members*", role: .h3)
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
