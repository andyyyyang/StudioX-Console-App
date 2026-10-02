import SwiftUI

/// 首頁「現在的狀況」：一張一張的卡片，左右滑著看（像一手牌：旁邊的稍微小一點、斜一點、淡一點）。
/// 第一張是今天的總覽，後面每個網站一張；點網站的卡片打開那個網站。
struct StatusDeck: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var current: String?

    private var cards: [StatusCard] {
        [StatusCard(id: "today", site: nil)] + model.sites.map { StatusCard(id: $0.id, site: $0) }
    }

    var body: some View {
        let regular = sizeClass == .regular
        let all = cards
        VStack(spacing: 16) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(all) { card in
                        Group {
                            if let site = card.site {
                                Button { model.open(.site(site.id)) } label: { SiteStatusCard(site: site) }
                                    .buttonStyle(PressScale(scale: 0.97))
                            } else {
                                TodayCard()
                            }
                        }
                        .containerRelativeFrame(.horizontal, count: regular ? 3 : 1, span: 1, spacing: 12)
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(1 - abs(phase.value) * 0.08)
                                .rotationEffect(.degrees(phase.value * 5), anchor: .bottom)
                                .offset(y: abs(phase.value) * 14)
                                .opacity(1 - abs(phase.value) * 0.35)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 18)
            }
            .safeAreaPadding(.horizontal, regular ? Metric.gutterWide : 34)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $current)

            if all.count > 1 && !regular {
                PageDots(count: all.count, index: all.firstIndex { $0.id == (current ?? "today") } ?? 0)
            }
        }
    }
}

struct StatusCard: Identifiable {
    let id: String
    let site: SiteSummary?
}

/// 卡片的底：圓角、細框、淡淡的影子
private struct CardFace<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210, alignment: .topLeading)
            .background(Theme.surface, in: .rect(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.line) }
            .shadow(color: .black.opacity(0.07), radius: 18, y: 10)
    }
}

/// 第一張：今天要你決定幾件事、現在多少人在線、昨天收了多少、幾筆等出貨
private struct TodayCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let b = model.briefing
        let count = b.attention(sites: model.sites).count
        let live = model.sites.reduce(0) { $0 + ($1.stats?.live ?? 0) }
        let revenue = b.ops.values.reduce(0) { $0 + $1.revenueCents }
        let ship = b.toShip.values.reduce(0) { $0 + $1.count }
        CardFace {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("今天")
                        .textRole(.h3)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if b.loading { ProgressView().controlSize(.small) }
                }
                Spacer(minLength: 8)
                if b.updatedAt == nil {
                    Text("…")
                        .textRole(.stat)
                        .foregroundStyle(Theme.faint)
                } else if count == 0 {
                    Text("都處理好了")
                        .textRole(.h1)
                        .foregroundStyle(Theme.ink)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(count)")
                            .textRole(.stat)
                            .foregroundStyle(Theme.accent)
                        Text("件事等你決定")
                            .textRole(.h4)
                            .foregroundStyle(Theme.ink)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    DeckFigure(value: "\(live)", label: "在線", live: live > 0)
                    if !model.orderSites.isEmpty {
                        DeckFigure(value: ntd(cents: revenue), label: "昨天收款")
                        DeckFigure(value: "\(ship)", label: "等出貨")
                    }
                }
            }
        }
    }
}

/// 一個網站一張：在線、7 天訪客和走勢、昨天的訂單、等出貨、客人在等
private struct SiteStatusCard: View {
    let site: SiteSummary
    @Environment(AppModel.self) private var model

    var body: some View {
        let b = model.briefing
        let report = b.ops[site.id]
        let ship = b.toShip[site.id]?.count ?? 0
        let waiting = b.awaiting.filter { $0.site == site.id }.count
        CardFace {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    SiteIconView(site: site, size: 28)
                    Text(site.name)
                        .textRole(.h4)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let live = site.stats?.live, live > 0 {
                        HStack(spacing: 6) {
                            LiveDot()
                            Text("\(live) 在線")
                                .textRole(.xs)
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                }
                Spacer(minLength: 6)
                if let stats = site.stats {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(stats.visitors.formatted())
                            .textRole(.number)
                            .foregroundStyle(Theme.ink)
                        Text("7 天訪客")
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                        ChangeLabel(percent: stats.change)
                    }
                    SparkView(values: stats.trend.map(Double.init))
                        .frame(height: 40)
                        .padding(.top, 6)
                }
                Spacer(minLength: 6)
                HStack(spacing: 0) {
                    if let report {
                        DeckFigure(value: "\(report.createdTotal)", label: "昨天訂單")
                        DeckFigure(value: ntd(cents: report.revenueCents), label: "昨天收款")
                    }
                    if site.hasOrders { DeckFigure(value: "\(ship)", label: "等出貨", highlight: ship > 0) }
                    if site.hasSupport { DeckFigure(value: "\(waiting)", label: "在等回覆", highlight: waiting > 0) }
                }
            }
        }
    }
}

/// 卡片底下的一格數字
private struct DeckFigure: View {
    let value: String
    let label: String
    var live = false
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if live { LiveDot() }
                Text(value)
                    .font(.brand(17, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(highlight ? Theme.accent : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 第幾張（手機）
private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.ink : Theme.line)
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.smooth, value: index)
        .accessibilityElement()
        .accessibilityLabel("第 \(index + 1) 張，共 \(count) 張")
    }
}
