import SwiftUI

/// 首頁就是 Xena：24 小時值班的店長。
///   - Hero：studiox.tw 的 Xena 介紹頁開場——置中的 3D 水珠、背後一團紫粉的光；
///     她在跟你說話：招呼一行一行升起，接著一個字一個字說今天的狀況，水珠跟著每個字鼓起來、標點換氣；「問問Xena」
///   - 跑馬燈：各網站現在的數字（在線、昨天的收款、等出貨）
///   - Needs you：客人在等回覆、已付款等出貨、營運異常、轉給專人的對話、新的專案詢問（點了直接去處理）
///   - Yesterday：有商店的網站昨天的營運
///   - This week：各網站最近 7 天的訪客
///   - Ask Xena：常問的幾句
struct XenaHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 「打開通知」的卡片按過「之後再說」
    @AppStorage("push.promptDismissed") private var promptDismissed = false
    /// Xena 說話的聲音（打字機一個字一個字推動水珠）
    @State private var voice = XenaVoice()
    private var settings: AppSettings { .shared }

    var body: some View {
        NavigationStack(path: Bindable(model).homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    if settings.shows(.marquee) && !marqueeItems.isEmpty {
                        Marquee(items: marqueeItems)
                            .padding(.top, 8)
                    }
                    VStack(alignment: .leading, spacing: sizeClass == .regular ? 96 : 64) {
                        if model.push.permission == .notDetermined && !promptDismissed {
                            NotificationPrompt(dismissed: $promptDismissed)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if settings.shows(.attention) { attention }
                        if settings.shows(.yesterday) { yesterday }
                        if settings.shows(.week) { thisWeek }
                        if settings.shows(.asks) { asks }
                    }
                    .pageWidth()
                    .padding(.top, sizeClass == .regular ? 88 : 56)
                    footer
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { [model] in await model.refreshAll() }
            .brandPage()
            .navigationTitle("今天")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    // MARK: Hero

    /// 招呼：三行（第二行是重點，強調詞用品牌橘）
    private var greetingLines: [String] {
        let b = model.briefing
        let hour = Calendar.taipei.component(.hour, from: .now)
        let hello = switch hour {
        case 5..<11: "早安"
        case 11..<14: "午安"
        case 14..<18: "下午好"
        case 18..<23: "晚上好"
        default: "這麼晚還在忙"
        }
        let name = model.me?.name ?? ""
        let first = name.isEmpty ? "\(hello)。" : "\(hello)，\(name)。"
        guard b.updatedAt != nil else { return [first, "我正在看你的網站，", "*等我一下*。"] }
        let count = b.attention(sites: model.sites).count
        if count == 0 { return [first, "現在沒有要你決定的事，", "我*繼續看著*。"] }
        return [first, "今天有 *\(count) 件事*", "等你決定。"]
    }

    /// Xena 的說明：昨天的訂單、現在誰在等你（照真的資料）
    private var report: String {
        let b = model.briefing
        guard b.updatedAt != nil else { return "我在看各網站昨晚到現在的狀況。" }
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
        var text = parts.isEmpty ? "" : parts.joined(separator: "；") + "。"
        text += now.isEmpty ? "其他都很順，有事我會先跟你說。" : "現在" + now.joined(separator: "、") + "。"
        return text
    }

    /// Xena 說話時水珠跟著每個字鼓起來
    private var heroMood: XenaMood {
        voice.speaking ? .speaking : model.xena.mood
    }

    private var hero: some View {
        let regular = sizeClass == .regular
        let orb: CGFloat = regular ? 220 : 156
        let light = orb * 2.6
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Eyebrow("\(Date.now.dayTitle) · \(Date.now.englishDay)")
                Spacer()
                // 設定（iPad 在側欄）：一看就知道的齒輪
                if !regular {
                    Button { model.goToAccount() } label: {
                        HeroIcon("cog-6-tooth", size: 21)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("設定")
                }
            }
            .pageWidth()

            // Xena：置中的 3D 水珠，背後一團紫粉的光（介紹頁的開場）；點她也能問
            Button { model.showXena = true } label: {
                XenaOrb(mood: heroMood, size: orb, pulse: model.xena.pulse, voice: voice, light: light)
                    .background { XenaLight(radius: light) }
                    .contentShape(Circle())
            }
            .buttonStyle(.press)
            .accessibilityLabel("問問Xena")
            .padding(.top, regular ? 36 : 24)
            // 光很大：畫在日期、招呼後面，不蓋到字
            .zIndex(-1)

            presence
                .padding(.top, regular ? 4 : 0)

            // 她說的話：招呼一行一行升起，接著一個字一個字說今天的狀況（水珠跟著說話）
            VStack(spacing: regular ? 24 : 18) {
                RisingHeadline(
                    lines: greetingLines,
                    role: .hero,
                    replayKey: AnyHashable(model.briefing.updatedAt == nil),
                    alignment: .center,
                    iridescent: true
                )
                TypewriterText(
                    text: report,
                    animate: settings.shouldSpeak(report, spoken: model.spokenReport),
                    speed: settings.pace.perCharacter,
                    delay: .milliseconds(model.spokenReport == nil ? 900 : 250),
                    voice: voice
                ) {
                    model.spokenReport = report
                    // 「每天一次」：說完今天的狀況（不是「我在看…」那句）就算說過了
                    if model.briefing.updatedAt != nil { settings.greetedDay = AppSettings.today }
                }
                .textRole(.lead)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                Button("問問Xena") { model.showXena = true }
                    .buttonStyle(.brand(.primary, size: .md, arrow: true))
                    .padding(.top, regular ? 12 : 6)
            }
            .frame(maxWidth: .infinity)
            .pageWidth()
            .padding(.top, regular ? 28 : 20)
        }
        .padding(.top, regular ? 40 : 16)
        .padding(.bottom, regular ? 72 : 48)
    }

    /// Xena 在線（說話時寫「正在跟你說」）
    private var presence: some View {
        HStack(spacing: 8) {
            LiveDot()
            Text("Xena・\(voice.speaking ? "正在跟你說" : model.xena.mood.label)")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .contentTransition(.opacity)
                .animation(.smooth, value: voice.speaking)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 跑馬燈

    private var marqueeItems: [Marquee.Item] {
        var items: [Marquee.Item] = []
        for site in model.sites {
            if let stats = site.stats {
                items.append(.init(text: "\(site.name) 7 天 \(stats.visitors.formatted()) 位訪客"))
                if stats.live > 0 { items.append(.init(text: "\(stats.live) 位在線", serif: true)) }
            }
            if let r = model.briefing.ops[site.id], r.revenueCents > 0 {
                items.append(.init(text: "昨天收款 \(ntd(cents: r.revenueCents))"))
            }
        }
        guard !items.isEmpty else { return [] }
        items.append(.init(text: "Always on", serif: true))
        return items
    }

    // MARK: 需要你看一下

    @ViewBuilder
    private var attention: some View {
        let items = model.briefing.attention(sites: model.sites)
        VStack(alignment: .leading, spacing: 28) {
            SectionHead("Needs *you*", aside: "需要你決定的事，越急的越前面。") {
                if model.briefing.loading {
                    ProgressView().controlSize(.small)
                } else if let at = model.briefing.updatedAt {
                    Text("\(at.clockText) 更新")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
            if items.isEmpty {
                if model.briefing.updatedAt != nil {
                    EmptyState(title: "都處理好了", message: "沒有要你決定的事，我繼續看著。")
                } else {
                    SkeletonRows(rows: 3)
                }
            } else {
                RuledList {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { run(item.action) } label: {
                            AttentionRow(item: item, site: model.site(item.site))
                        }
                        .buttonStyle(.row)
                        .reveal(index)
                    }
                }
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
            VStack(alignment: .leading, spacing: 28) {
                SectionHead("Yesterday, *in numbers*", aside: reports.first?.1.rangeLabel)
                ForEach(reports, id: \.0.id) { site, report in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            SiteIconView(site: site, size: 26)
                            Text(site.name)
                                .textRole(.h4)
                                .foregroundStyle(Theme.ink)
                        }
                        StatGrid {
                            Stat(value: Double(report.createdTotal), label: "筆訂單")
                            Stat(value: Double(report.revenueCents) / 100, label: "收款", format: { "NT$" + Int($0.rounded()).formatted() })
                            Stat(value: Double(report.paidButUnfulfilled), label: "等出貨")
                            Stat(value: Double(report.awaitingPayment), label: "等付款")
                        }
                        if !report.summary.isEmpty {
                            Text(report.summary)
                                .textRole(.small)
                                .foregroundStyle(Theme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: 最近 7 天

    @ViewBuilder
    private var thisWeek: some View {
        let sites = model.sites.filter { $0.stats != nil }
        if !sites.isEmpty {
            VStack(alignment: .leading, spacing: 28) {
                SectionHead("This *week*", aside: "各網站最近 7 天的訪客。")
                RuledList {
                    ForEach(sites) { site in
                        Button { model.open(.site(site.id)) } label: { SiteRow(site: site) }
                            .buttonStyle(.row)
                    }
                }
            }
        }
    }

    // MARK: 問 Xena

    private var asks: some View {
        VStack(alignment: .leading, spacing: 28) {
            SectionHead("Ask *Xena*", aside: "和網頁版同一個 Xena、同一份對話紀錄。")
            RuledList {
                ForEach(XenaSession.starters, id: \.self) { prompt in
                    Button { model.askXena(prompt) } label: {
                        HStack {
                            Text(prompt)
                                .textRole(.h4)
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 12)
                            Text("→")
                                .font(.brand(18, .medium))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 18)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.row)
                }
            }
        }
    }

    // MARK: 頁尾

    private var footer: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Xena 是你的店長，24 小時看著每個網站。")
                .textRole(.small)
                .foregroundStyle(Theme.inverseMuted)
            Wordmark(color: Theme.onInverse)
        }
        .pageWidth()
        .padding(.top, 56)
        .padding(.bottom, 24)
        .background(Theme.inverse)
        .padding(.top, 96)
    }
}

/// 首頁的一件事：狀態方塊、標題、說明、橘色的箭頭
private struct AttentionRow: View {
    let item: AttentionItem
    let site: SiteSummary?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HeroIcon(item.icon, size: 18)
                .foregroundStyle(item.tone.foreground)
                .frame(width: 36, height: 36)
                .background(item.tone.background, in: .rect(cornerRadius: Metric.radiusSm))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(item.detail)
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            ArrowTile(glyph: "→", size: 28)
        }
        .padding(.vertical, 18)
        .contentShape(.rect)
    }
}

/// 網站一列：圖示、名稱、網址、7 天訪客、走勢（console 網站選擇器的 .au-site）
struct SiteRow: View {
    let site: SiteSummary

    var body: some View {
        HStack(spacing: 14) {
            SiteIconView(site: site, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(site.name)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    if let live = site.stats?.live, live > 0 {
                        LiveDot()
                        Text("\(live) 位在線").foregroundStyle(Theme.ink2)
                        Text("·")
                    }
                    Text(site.host)
                }
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let stats = site.stats {
                SparkView(values: stats.trend.map(Double.init))
                    .frame(width: 64, height: 24)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stats.visitors.formatted())
                        .textRole(.number)
                        .foregroundStyle(Theme.ink)
                    ChangeLabel(percent: stats.change)
                }
                .frame(minWidth: 64, alignment: .trailing)
            }
        }
        .padding(.vertical, 16)
        .contentShape(.rect)
    }
}

/// 第一次：請他打開通知（先說清楚會通知什麼，再跳系統的詢問）
private struct NotificationPrompt: View {
    @Binding var dismissed: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("通知")
            Headline("Let me *tap your shoulder*.", role: .h3)
            Text("客人在等回覆、對話轉給專人、有事等你決定時，我第一時間跟你說。哪些事要通知、什麼時候安靜，都可以在「我 → 通知」調整。")
                .textRole(.small)
                .foregroundStyle(Theme.ink2)
            HStack(spacing: 10) {
                Button("打開通知") {
                    Task { await model.push.requestPermission() }
                }
                .buttonStyle(.brand(.accent))
                Button("之後再說") {
                    withAnimation(Motion.ease) { dismissed = true }
                }
                .buttonStyle(.brand(.ghost))
            }
        }
        .panel()
        .reveal()
    }
}
