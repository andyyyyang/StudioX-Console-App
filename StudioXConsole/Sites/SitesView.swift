import Charts
import SwiftUI
import UIKit

/// 網站選擇器（console 的 /sites）：每個網站一張卡，7 天訪客＋走勢；點進去是那個網站的儀表板
struct SitesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.sitesPath) {
            ScrollView {
                VStack(spacing: 12) {
                    summary
                    ForEach(model.sites) { site in
                        NavigationLink(value: Route.site(site.id)) {
                            SiteRow(site: site)
                        }
                        .buttonStyle(.plain)
                    }
                    ConnectorBox()
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Brand.paper.ignoresSafeArea())
            .navigationTitle("網站")
            .refreshable { await model.refresh() }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private var summary: some View {
        let visitors = model.sites.reduce(0) { $0 + $1.stats.visitors }
        let live = model.sites.reduce(0) { $0 + $1.stats.live }
        return HStack(alignment: .firstTextBaseline) {
            Text("\(model.sites.count) 個網站 · 7 天訪客 \(Text(visitors.formatted()).bold().foregroundStyle(Brand.ink))")
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text("\(live) 人在線")
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(Brand.muted)
        .padding(.horizontal, 4)
    }
}

private struct SiteRow: View {
    let site: Site

    var body: some View {
        HStack(spacing: 14) {
            SiteIcon(site: site)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                Text("\(site.domain) · \(site.role.rawValue)")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(site.stats.visitors.formatted())
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Brand.ink)
                Sparkline(values: site.stats.trend.map { Double($0.visitors) })
                    .stroke(site.icon == .mark ? Brand.accent : site.tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 64, height: 18)
                ChangeLabel(change: site.stats.change)
            }
        }
        .raisedCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// 連接外部 AI（console 一個網址管所有網站）
private struct ConnectorBox: View {
    @State private var copied = false
    private let url = "https://console.studiox.tw/api/mcp"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("連接 Claude／ChatGPT")
                .font(.system(size: 15, weight: .semibold))
            Text("在 AI 的「連接器」貼上這個網址，用 StudioX 帳號登入就能操作你所有的網站；修改一律要你確認。")
                .font(.footnote)
                .foregroundStyle(Brand.muted)
            Button {
                UIPasteboard.general.string = url
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                HStack(spacing: 10) {
                    Text(url)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Brand.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(copied ? "已複製" : "複製")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.onInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Brand.ink, in: .capsule)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .background(Brand.raised, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.line))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: copied) { _, now in now }
        }
        .padding(.horizontal, 4)
    }
}

/// 一個網站的儀表板：流量、熱門頁面、訂單（有商店的話）、最近的內容
struct SiteDetailView: View {
    let siteID: String
    @Environment(AppModel.self) private var model

    var body: some View {
        if let site = model.site(siteID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(site)
                    kpis(site)
                    chart(site)
                    pages(site)
                    if site.hasCommerce { orders(site) }
                    content(site)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Brand.paper.ignoresSafeArea())
            .navigationTitle(site.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.askXena("幫我看一下\(site.name)最近怎麼樣", site: site.id)
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("問 Xena")
                }
            }
        } else {
            ContentUnavailableView("找不到這個網站", systemImage: "questionmark.square.dashed")
        }
    }

    private func header(_ site: Site) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SiteIcon(site: site, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.4)
                    Text("\(site.domain) · \(site.role.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(Brand.muted)
                }
            }
            HStack(spacing: 10) {
                Link(destination: site.adminURL) {
                    Label("開啟後台", systemImage: "rectangle.stack")
                }
                .buttonStyle(.pill(.dark, compact: true))
                Link(destination: site.siteURL) {
                    Label("看網站", systemImage: "safari")
                }
                .buttonStyle(.pill(.light, compact: true))
            }
        }
        .padding(.top, 8)
    }

    private func kpis(_ site: Site) -> some View {
        let s = site.stats
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Kpi(title: "現在在線", value: "\(s.live)", live: true)
                Kpi(title: "7 天訪客", value: s.visitors.formatted(), change: s.change)
            }
            GridRow {
                Kpi(title: "瀏覽次數", value: s.pageviews.formatted())
                Kpi(title: "平均停留", value: s.avgDuration.map { "\(Int($0) / 60) 分 \(Int($0) % 60) 秒" } ?? "—")
            }
        }
    }

    private func chart(_ site: Site) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "訪客", trailing: "最近 7 天")
            Chart(site.stats.trend) { point in
                AreaMark(x: .value("日期", point.label), y: .value("訪客", point.visitors))
                    .foregroundStyle(LinearGradient(colors: [Brand.accent.opacity(0.28), Brand.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", point.label), y: .value("訪客", point.visitors))
                    .foregroundStyle(Brand.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Brand.line)
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
            .raisedCard(cornerRadius: 22, padding: 16)
        }
    }

    private func pages(_ site: Site) -> some View {
        let top = site.stats.pages.sorted { $0.visitors > $1.visitors }
        let maxVisitors = max(top.first?.visitors ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "熱門頁面")
            VStack(spacing: 12) {
                ForEach(top) { page in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(page.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(page.visitors.formatted())
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        GeometryReader { geo in
                            Capsule()
                                .fill(Brand.accent.opacity(0.18))
                                .frame(width: geo.size.width * CGFloat(page.visitors) / CGFloat(maxVisitors))
                        }
                        .frame(height: 5)
                    }
                }
            }
            .raisedCard(cornerRadius: 22, padding: 16)
        }
    }

    private func orders(_ site: Site) -> some View {
        let list = model.orders(for: site.id)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "訂單", trailing: "\(list.filter { $0.status == .paid }.count) 筆等備貨")
            VStack(spacing: 0) {
                ForEach(Array(list.prefix(6).enumerated()), id: \.element.id) { index, order in
                    if index > 0 { Divider().padding(.leading, 14) }
                    NavigationLink(value: Route.order(order.id)) {
                        OrderRow(order: order)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Brand.raised, in: .rect(cornerRadius: 22))
        }
    }

    private func content(_ site: Site) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "最近的內容")
            VStack(spacing: 0) {
                ForEach(Array(site.content.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 14) }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text("\(entry.collection) · \(entry.updatedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                        }
                        Spacer()
                        StatusPill(text: entry.state.rawValue, tone: entry.state.tone)
                    }
                    .padding(14)
                }
            }
            .background(Brand.raised, in: .rect(cornerRadius: 22))
        }
    }
}

private struct Kpi: View {
    let title: String
    let value: String
    var change: Double?
    var live = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if live {
                    Circle()
                        .fill(Brand.success)
                        .frame(width: 6, height: 6)
                        .phaseAnimator([1.0, 0.3]) { content, phase in
                            content.opacity(phase)
                        } animation: { _ in
                            .easeInOut(duration: 1)
                        }
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ChangeLabel(change: change)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedCard(cornerRadius: 18, padding: 14)
    }
}

struct OrderRow: View {
    let order: Order

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(order.customer)
                        .font(.subheadline.weight(.semibold))
                    Text(order.number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Brand.muted)
                }
                Text(order.summary)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(order.total.ntd)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                StatusPill(text: order.status.rawValue, tone: order.status.tone)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

/// 一筆訂單：品項、配送、付款；要改狀態或退款，交給 Xena（她會先出確認卡片）
struct OrderDetailView: View {
    let orderID: String
    @Environment(AppModel.self) private var model

    var body: some View {
        if let order = model.order(orderID) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(order.number)
                                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                            Spacer()
                            StatusPill(text: order.status.rawValue, tone: order.status.tone)
                        }
                        Text("\(order.customer) · \(order.phone)")
                            .font(.subheadline)
                            .foregroundStyle(Brand.muted)
                        Text(order.placedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                    .padding(.vertical, 4)
                }

                Section("品項") {
                    ForEach(order.lines) { line in
                        HStack {
                            Text(line.name)
                            Text("×\(line.qty)")
                                .foregroundStyle(Brand.muted)
                            Spacer()
                            Text((line.price * line.qty).ntd)
                                .monospacedDigit()
                        }
                    }
                    LabeledContent("運費", value: order.shippingFee == 0 ? "免運" : order.shippingFee.ntd)
                    LabeledContent("合計") {
                        Text(order.total.ntd)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(Brand.ink)
                    }
                }

                Section("配送與付款") {
                    LabeledContent("配送", value: order.shipping)
                    LabeledContent("付款", value: order.payment)
                    if let logistics = order.logistics {
                        LabeledContent("貨態", value: logistics)
                    }
                    if let note = order.note {
                        LabeledContent("備註", value: note)
                    }
                }

                Section {
                    if let next = order.status.next {
                        Button {
                            model.askXena("把 \(order.number) 改成\(next.rawValue)", site: order.siteID)
                        } label: {
                            Label("請 Xena 改成「\(next.rawValue)」", systemImage: "sparkles")
                        }
                    }
                    Button {
                        model.askXena("\(order.number) 現在怎麼樣？", site: order.siteID)
                    } label: {
                        Label("問 Xena 這筆訂單", systemImage: "text.bubble")
                    }
                    if order.status != .pending && order.status != .refunded && order.status != .cancelled {
                        Button(role: .destructive) {
                            model.askXena("幫 \(order.number) 退款", site: order.siteID)
                        } label: {
                            Label("退款…", systemImage: "arrow.uturn.left")
                        }
                    }
                } footer: {
                    Text("Xena 動手之前會先跳確認卡片；退款要打字確認。")
                }
            }
            .navigationTitle("訂單")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("找不到這筆訂單", systemImage: "shippingbox")
        }
    }
}
