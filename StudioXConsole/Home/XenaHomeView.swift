import SwiftUI

/// 首頁就是 Xena：24 小時值班的店長。
///   - Hero：studiox.tw 的 Xena 介紹頁開場——置中的 3D 水珠、背後一團紫粉的光；
///     她在跟你說話：招呼一行一行升起，接著一個字一個字說今天的狀況，水珠跟著每個字鼓起來、標點換氣；「問問Xena」
///   - 現在的狀況（StatusDeck）：卡片左右滑——今天的總覽、每個網站一張
///   - Needs you：客人在等回覆、已付款等出貨、營運異常、轉給專人的對話、新的專案詢問（點了直接去處理）
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
                    // 現在的狀況：卡片左右滑
                    if settings.shows(.cards) {
                        StatusDeck()
                    }
                    VStack(alignment: .leading, spacing: sizeClass == .regular ? 72 : 48) {
                        if model.push.permission == .notDetermined && !promptDismissed {
                            NotificationPrompt(dismissed: $promptDismissed)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if settings.shows(.attention) { attention }
                    }
                    .pageWidth()
                    .padding(.top, sizeClass == .regular ? 56 : 40)
                    .padding(.bottom, 64)
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

    /// 招呼：上面一行小字（早安，Andy），下面一行大字只說重點（強調詞用 Xena 的彩虹漸層）
    private var greeting: (hello: String, headline: String) {
        let b = model.briefing
        let hour = Calendar.taipei.component(.hour, from: .now)
        let hello = switch hour {
        case 5..<11: "早安"
        case 11..<14: "午安"
        case 14..<18: "下午好"
        case 18..<23: "晚上好"
        default: "這麼晚還在忙"
        }
        let name = Self.callName(model.me?.name ?? "")
        let first = name.isEmpty ? hello : "\(hello)，\(name)"
        guard b.updatedAt != nil else { return (first, "我在*看你的網站*") }
        let count = b.attention(sites: model.sites).count
        if count == 0 { return (first, "現在*都處理好了*") }
        return (first, "*\(count) 件事*等你決定")
    }

    /// 怎麼叫你：中文叫名字（黃韋豪 → 韋豪）；英文取第一個字、去掉數字（andy111yang111 → Andy）；email 只看 @ 前面
    static func callName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        guard !name.isEmpty else { return "" }
        if name.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            let han = name.filter { !$0.isWhitespace }
            return han.count == 3 ? String(han.suffix(2)) : han
        }
        guard let word = name.split(whereSeparator: { !$0.isLetter }).first, word.count >= 2 else { return "" }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
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

    /// 要不要請 Apple Intelligence 寫開場白（資料到了、設定打開、這台 iPhone 可以用）
    private var wantsWrittenGreeting: Bool {
        model.briefing.updatedAt != nil && settings.aiGreeting && XenaLocal.shared.available
    }

    /// 她要說的話：資料還沒到是「我在看…」；Apple Intelligence 在寫的時候先說「我整理一下」
    private var speech: String {
        guard wantsWrittenGreeting else { return report }
        return model.greetings[report] ?? "我整理一下今天的狀況…"
    }

    /// 是今天真正的狀況（不是過場的那一句）
    private var speechIsFinal: Bool {
        model.briefing.updatedAt != nil && (!wantsWrittenGreeting || model.greetings[report] != nil)
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
                VStack(spacing: regular ? 10 : 6) {
                    RisingHeadline(
                        lines: [greeting.hello],
                        role: .lead,
                        color: Theme.muted,
                        replayKey: AnyHashable(model.briefing.updatedAt == nil),
                        alignment: .center
                    )
                    RisingHeadline(
                        lines: [greeting.headline],
                        role: .h1,
                        replayKey: AnyHashable(model.briefing.updatedAt == nil),
                        alignment: .center,
                        iridescent: true,
                        delay: 0.12
                    )
                }
                TypewriterText(
                    text: speech,
                    animate: settings.shouldSpeak(speech, spoken: model.spokenReport),
                    speed: settings.pace.perCharacter,
                    delay: .milliseconds(model.spokenReport == nil ? 900 : 250),
                    voice: voice
                ) {
                    model.spokenReport = speech
                    // 「每天一次」：說完今天的狀況（不是「我在看…」「我整理一下…」）就算說過了
                    if speechIsFinal { settings.greetedDay = AppSettings.today }
                }
                // Apple Intelligence 把今天的狀況寫成她會說的話（核對過數字；寫不出來就用照資料拼的那句）
                .task(id: report) {
                    guard wantsWrittenGreeting, model.greetings[report] == nil else { return }
                    let written = await XenaLocal.shared.greeting(from: report, name: Self.callName(model.me?.name ?? ""))
                    model.greetings[report] = written ?? report
                }
                .textRole(.lead)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                HStack(spacing: 10) {
                    Button("問問Xena") { model.showXena = true }
                        .buttonStyle(.brand(.primary, size: .md, arrow: true))
                    // 用說的：她用 iPhone 的聲音回答
                    Button { model.showVoice = true } label: {
                        HeroIcon("microphone", size: 20)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 46, height: 46)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("用說的問Xena")
                }
                .padding(.top, regular ? 12 : 6)
            }
            .frame(maxWidth: .infinity)
            .pageWidth()
            .padding(.top, regular ? 28 : 20)
        }
        .padding(.top, regular ? 40 : 16)
        .padding(.bottom, regular ? 72 : 48)
    }

    /// 她在說話、查資料時才寫一行（平常不放字）
    private var presence: some View {
        let active = voice.speaking || model.xena.isBusy
        return Text(voice.speaking ? "正在跟你說" : model.xena.mood.label)
            .textRole(.xs)
            .foregroundStyle(Theme.muted)
            .opacity(active ? 1 : 0)
            .animation(.smooth, value: active)
            .accessibilityHidden(!active)
    }

    // MARK: 需要你看一下

    private var attention: some View {
        AttentionList()
    }
}

/// Needs you：客人在等回覆、已付款等出貨、營運異常…（點了直接去處理）。首頁和「今天」卡片的 sheet 共用
struct AttentionList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.briefing.attention(sites: model.sites)
        VStack(alignment: .leading, spacing: 28) {
            SectionHead("Needs *you*") {
                if model.briefing.loading {
                    ProgressView().controlSize(.small)
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
                        Button { model.handle(item.action) } label: {
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
