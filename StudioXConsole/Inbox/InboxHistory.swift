import SwiftUI

/// 收件匣的「全部紀錄」：所有網站、所有管道過去的客服（Xena 的官網與 LINE 對話、客服信、專案詢問），
/// 結束了的也在，最近有動靜的在前；可以搜尋、只看某個管道，捲到底自動載入更早的。
///
/// 每個網站的每一種各自往前翻頁（網站的 list：before＝上一頁回的 next；舊版網站沒給 next 就是只有最新一頁），
/// 合在一起照時間排。某一種還有更早的沒載入時，比它載到的最舊那一筆還舊的先不放
/// （不然翻到下一頁時，更早的會插進已經看過的中間）；捲到底先翻卡住的那一種。
@MainActor @Observable
final class InboxHistory {
    enum Channel: Hashable, CaseIterable {
        case all, web, line, email, form

        var title: String {
            switch self {
            case .all: "全部"
            case .web: "官網"
            case .line: "LINE"
            case .email: "Email"
            case .form: "表單"
            }
        }

        var kind: Kind? {
            switch self {
            case .all: nil
            case .web, .line: .xena
            case .email: .thread
            case .form: .inquiry
            }
        }
    }

    enum Kind: Hashable { case xena, thread, inquiry }

    private struct Feed {
        let site: String
        let kind: Kind
        var next: String?
        var done = false
        /// 載到的最舊一筆（還沒載過是 nil）
        var oldest: Date?
    }

    private(set) var channel: Channel = .all
    private(set) var query = ""
    private(set) var items: [InboxItem] = []
    /// 第一頁還在載
    private(set) var loading = false
    /// 正在載更早的
    private(set) var loadingMore = false
    /// 讀不到的網站（名字）
    private(set) var failed: [String] = []
    /// 讀得到的種類：管道的篩選只放有的
    private(set) var kinds: Set<Kind> = []
    /// 載過了（第一次打開「全部紀錄」才載）
    private(set) var loaded = false
    private var feeds: [Feed] = []
    private var generation = 0
    @ObservationIgnored private let api: ConsoleAPI
    @ObservationIgnored private var names: [String: String] = [:]
    /// 第一頁同時拿的時候先收在這裡
    @ObservationIgnored private var batch: [InboxItem] = []

    init(api: ConsoleAPI) { self.api = api }

    /// 可以放出來的：還有更早沒載入的那幾種，各自載到的最舊一筆裡最新的那個，比它舊的先不放
    var shown: [InboxItem] {
        let open = feeds.filter { !$0.done }
        guard !open.isEmpty else { return items }
        let floor = open.map { $0.oldest ?? .distantFuture }.max() ?? .distantPast
        return items.filter { ($0.at ?? .distantPast) >= floor }
    }

    var hasMore: Bool { feeds.contains { !$0.done } }

    func reset() {
        generation += 1
        items = []
        feeds = []
        failed = []
        kinds = []
        loaded = false
        loading = false
        loadingMore = false
        query = ""
        channel = .all
    }

    /// 從頭載（換管道、換搜尋、下拉重新整理）
    func restart(sites: [SiteSummary], channel: Channel? = nil, query: String? = nil) async {
        if let channel { self.channel = channel }
        if let query { self.query = query.trimmingCharacters(in: .whitespacesAndNewlines) }
        generation += 1
        let round = generation
        names = Dictionary(sites.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let want = self.channel.kind
        feeds = sites.flatMap { site -> [Feed] in
            var f: [Feed] = []
            let canList = site.tools.contains("list")
            if canList, want == nil || want == .xena { f.append(Feed(site: site.id, kind: .xena)) }
            if site.hasSupport, want == nil || want == .thread { f.append(Feed(site: site.id, kind: .thread)) }
            if canList, want == nil || want == .inquiry { f.append(Feed(site: site.id, kind: .inquiry)) }
            return f
        }
        failed = []
        batch = []
        loading = true
        loadingMore = false
        // 每一種的第一頁同時拿（結果各自收進 batch），都回來了再一起放出來
        let indices = Array(feeds.indices)
        await withTaskGroup(of: Void.self) { group in
            for i in indices {
                group.addTask { await self.first(i, round: round) }
            }
        }
        guard round == generation else { return }
        withAnimation(Motion.ease) {
            items = Self.merge([], batch)
            loading = false
            loaded = true
        }
        batch = []
    }

    private func first(_ i: Int, round: Int) async {
        guard let page = await fetch(i, round: round), round == generation else { return }
        batch.append(contentsOf: page)
    }

    /// 捲到底：先翻卡住的那一種（還有更早的、載到的最舊一筆最新的），放出來的多了 15 筆以上或沒有更早的就停
    func loadMore() async {
        guard !loading, !loadingMore, hasMore else { return }
        let round = generation
        loadingMore = true
        defer { if round == generation { loadingMore = false } }
        let before = shown.count
        for _ in 0..<6 {
            guard let i = feeds.indices.filter({ !feeds[$0].done }).max(by: { (feeds[$0].oldest ?? .distantFuture) < (feeds[$1].oldest ?? .distantFuture) }) else { break }
            let page = await fetch(i, round: round)
            guard round == generation else { return }
            if let page {
                withAnimation(Motion.ease) { items = Self.merge(items, page) }
            }
            if shown.count - before >= 15 || !hasMore { break }
        }
    }

    /// 一種的下一頁：寫回這一種的 next、最舊的時間；這個網站沒有這種資料（或不給看）就當作沒有
    private func fetch(_ i: Int, round: Int) async -> [InboxItem]? {
        guard i < feeds.count else { return nil }
        let feed = feeds[i]
        let q = query.isEmpty ? nil : query
        do {
            var rows: [InboxItem]
            let next: String?
            let paged: Bool
            switch feed.kind {
            case .xena:
                let channel: String? = switch self.channel {
                case .web: "web"
                case .line: "line"
                default: nil
                }
                let page = try await api.xenaConversationPage(site: feed.site, channel: channel, query: q, before: feed.next)
                // 舊版網站不認得 channel：這裡再篩一次
                rows = page.items
                    .filter { channel == nil || ($0.channel == .line) == (channel == "line") }
                    .map { InboxItem(history: $0) }
                next = page.next
                paged = page.paged
            case .thread:
                let page = try await api.supportThreadPage(site: feed.site, query: q, before: feed.next)
                rows = page.items.map { InboxItem(history: $0) }
                next = page.next
                paged = page.paged
            case .inquiry:
                let page = try await api.inquiryPage(site: feed.site, query: q, before: feed.next)
                rows = page.items.map { InboxItem(history: $0) }
                next = page.next
                paged = page.paged
            }
            guard round == generation, i < feeds.count else { return nil }
            // 舊版網站不認得搜尋（回來的是沒篩過的）：在這裡照名字和看得到的字篩
            if !paged, let q {
                rows = rows.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.text.localizedCaseInsensitiveContains(q) }
            }
            kinds.insert(feed.kind)
            feeds[i].next = next
            feeds[i].done = next == nil || rows.isEmpty
            if let oldest = rows.compactMap(\.at).min() { feeds[i].oldest = oldest }
            return rows
        } catch {
            guard round == generation, i < feeds.count else { return nil }
            feeds[i].done = true
            // 這個網站沒有這種資料（黃毛丫頭沒有專案詢問）或不給看：當作沒有；連不上、出錯才說
            if let error = error as? APIError {
                switch error {
                case .tool, .rpc, .scope: return nil
                default: break
                }
            }
            let name = names[feed.site] ?? feed.site
            if !failed.contains(name) { failed.append(name) }
            return nil
        }
    }

    /// 合在一起、同一筆留新的，最近的在前
    private static func merge(_ old: [InboxItem], _ new: [InboxItem]) -> [InboxItem] {
        var byID: [String: InboxItem] = [:]
        for item in old + new { byID[item.id] = item }
        return byID.values.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
    }
}

extension InboxItem {
    /// 紀錄裡的 Xena 對話：狀態照實寫（Xena 回答中、等專人、專人接手、已結案）
    init(history c: XenaConversationSummary) {
        self.init(c)
        status = (text: c.statusLabel, tone: c.tone)
    }

    /// 紀錄裡的客服信：最後一封的時間、開頭，狀態照實寫
    init(history t: SupportThreadSummary) {
        self.init(t)
        at = t.at ?? at
        since = at
        if let last = t.lastMessage { text = "\(t.subject)・\(last)" }
        status = (text: t.statusLabel.isEmpty ? "客服信" : t.statusLabel, tone: t.tone)
    }

    /// 紀錄裡的專案詢問
    init(history q: InquirySummary) {
        self.init(q)
        status = (text: InquiryView.statusLabel(q.status), tone: q.status == "new" ? Tone.gold : Tone.neutral)
    }
}

/// 「全部紀錄」的內容：搜尋、管道、照日子分段的清單、捲到底載更早的
struct InboxHistoryList<Row: View>: View {
    let history: InboxHistory
    @Binding var search: String
    /// 一列（點了怎麼開由收件匣決定：手機推下一頁、iPad 在右邊打開）
    @ViewBuilder let row: (InboxItem) -> Row

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                SearchField(text: $search, prompt: "搜尋客人、Email、對話內容")
                if channels.count > 2 {
                    FilterBar(
                        items: channels,
                        selection: Binding(get: { history.channel }, set: { c in
                            Task { await history.restart(sites: model.sites, channel: c) }
                        }),
                        title: \.title
                    )
                }
            }
            if !history.failed.isEmpty {
                ErrorNote(message: "\(history.failed.joined(separator: "、")) 這次沒讀到") {
                    Task { await history.restart(sites: model.sites) }
                }
            }
            if history.loading && history.items.isEmpty {
                SkeletonRows(rows: 6)
            } else if history.shown.isEmpty && !history.hasMore {
                EmptyState(
                    title: history.query.isEmpty ? "還沒有紀錄" : "找不到「\(history.query)」",
                    message: history.query.isEmpty
                        ? "客人在官網、LINE、Email 或聯絡表單找過你，都會留在這裡。"
                        : "試試客人的名字、Email，或對話裡的一句話。"
                )
            } else {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(day.title)
                        RuledList {
                            ForEach(day.items) { item in row(item) }
                        }
                    }
                }
                footer
            }
        }
    }

    /// 管道：只放讀得到的（沒有客服信的網站不放 Email，沒有詢問的不放表單）
    private var channels: [InboxHistory.Channel] {
        var c: [InboxHistory.Channel] = [.all]
        if history.kinds.contains(.xena) || history.channel == .web || history.channel == .line { c += [.web, .line] }
        if history.kinds.contains(.thread) || history.channel == .email { c.append(.email) }
        if history.kinds.contains(.inquiry) || history.channel == .form { c.append(.form) }
        return c
    }

    private struct Day: Identifiable {
        let title: String
        var items: [InboxItem]
        var id: String { title }
    }

    /// 照台北的日子分段：今天、昨天、10月2日 星期五
    private var days: [Day] {
        var out: [Day] = []
        for item in history.shown {
            let title = item.at.map(Self.dayTitle) ?? "更早"
            if out.last?.title == title {
                out[out.count - 1].items.append(item)
            } else {
                out.append(Day(title: title, items: [item]))
            }
        }
        return out
    }

    private static func dayTitle(_ date: Date) -> String {
        if Calendar.taipei.isDateInToday(date) { return "今天" }
        if Calendar.taipei.isDateInYesterday(date) { return "昨天" }
        let thisYear = Calendar.taipei.isDate(date, equalTo: .now, toGranularity: .year)
        return thisYear ? date.dayTitle : "\(date.dayText)"
    }

    @ViewBuilder
    private var footer: some View {
        if history.hasMore {
            LoadingRow(text: "載入更早的…")
                .onAppear { Task { await history.loadMore() } }
        } else if history.shown.count > 8 {
            Text(history.query.isEmpty ? "沒有更早的了" : "就這些")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }
}
