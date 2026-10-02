import SwiftUI

/// 一種資料的清單（商品、折價券、橫幅、文章、作品…）：照網站的 list，
/// 商品是格狀的卡片、折價券是票券、橫幅是預覽、有封面的內容是大卡片，其他是細線隔開的列。
/// 點進去是編輯畫面；可以新增的右上角有「＋」。
struct CollectionView: View {
    let site: String
    let entity: String

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var schema: EntitySchema?
    @State private var rows: [RecordSummary] = []
    @State private var raw: JSONValue = .null
    @State private var query = ""
    @State private var filter = "all"
    @State private var loading = true
    @State private var error: String?
    /// 上一次用來讀清單的搜尋字（一樣就不用再讀）
    @State private var loadedQuery = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                if let filters, !filters.isEmpty {
                    FilterBar(items: filters.map(\.0), selection: $filter, title: { key in filters.first { $0.0 == key }?.1 ?? key })
                }
                content
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .searchable(text: $query, prompt: Text("搜尋\(schema?.label ?? "")"))
        .refreshable { await load() }
        .brandPage()
        .navigationTitle(schema?.label ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if schema?.canCreate == true {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.create(site: site, entity: entity)) {
                        HeroIcon("plus", size: 20)
                    }
                    .accessibilityLabel("新增\(schema?.label ?? "")")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
        .task(id: filter) { await load() }
        .task(id: query) {
            // 打字停一下才去網站搜（網站支援搜尋的資料）
            guard serverSearch, query != loadedQuery else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { await load() }
        }
    }

    // MARK: 讀

    /// 網站的 list 支援 query 的資料（其他的在 App 裡篩）
    private var serverSearch: Bool {
        schema?.collection != nil || ["product", "user", "automation"].contains(entity)
    }

    /// 篩選：上架、啟用、已處理…
    private var filters: [(String, String)]? {
        switch entity {
        case "product", "bundle": [("all", "全部"), ("published", "已上架")]
        case "news": [("all", "全部"), ("published", "已發布")]
        case "coupon": [("all", "全部"), ("active", "啟用中")]
        case "user": [("all", "全部"), ("admins", "後台人員")]
        case "mailbox": [("all", "收件匣"), ("done", "已處理")]
        case "automation": [("all", "全部"), ("active", "執行中"), ("paused", "暫停"), ("draft", "草稿")]
        case "automation_run": [("all", "全部"), ("waiting", "等你決定"), ("failed", "失敗")]
        default: schema?.collection != nil && schema?.collection?.singleton == false ? [("all", "全部"), ("published", "已發布")] : nil
        }
    }

    private func load() async {
        if schema == nil {
            schema = await model.schema(for: site)?.entity(entity)
        }
        var args: [String: JSONValue] = ["limit": 200]
        switch filter {
        case "published": args["publishedOnly"] = true
        case "active" where entity == "coupon": args["activeOnly"] = true
        case "admins": args["adminsOnly"] = true
        case "done": args["status"] = "done"
        case "all": break
        default: args["status"] = .string(filter)
        }
        do {
            let sent = query
            let r = try await model.api.list(site: site, entity: entity, query: serverSearch ? sent : nil, filters: args)
            loadedQuery = sent
            withAnimation(Motion.ease) {
                rows = r.rows
                raw = r.raw
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// 網站沒有搜尋的資料：在 App 裡篩
    private var shown: [RecordSummary] {
        var list = rows
        // 「已上架／已發布」：有的資料網站的 list 不支援篩選（例如組合），在 App 裡再篩一次
        if filter == "published" {
            list = list.filter { $0.raw["isPublished"]?.bool != false && ($0.raw["status"]?.string ?? "published") == "published" }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, !serverSearch else { return list }
        return list.filter { [$0.title, $0.subtitle ?? "", $0.detail ?? ""].joined(separator: " ").lowercased().contains(q) }
    }

    // MARK: 頁首

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(model.site(site)?.name ?? site)
            Headline(EntityStyle.headline(entity) ?? "*\(schema?.label ?? entity)*", role: .h1)
            HStack(spacing: 10) {
                if !loading {
                    Text("\(shown.count) 筆")
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                }
                if let note = raw["hint"]?.string ?? schema?.collection?.description {
                    Text(note)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
        }
        .reveal()
    }

    // MARK: 內容

    private var canOpen: Bool { schema.map { $0.canGet || $0.canUpdate } ?? false }

    @ViewBuilder
    private var content: some View {
        if loading {
            SkeletonRows(rows: 6)
        } else if let error {
            ErrorNote(message: error) { Task { await load() } }
        } else if shown.isEmpty {
            EmptyState(title: query.isEmpty ? "還沒有\(schema?.label ?? "資料")" : "找不到「\(query)」", message: schema?.canCreate == true && query.isEmpty ? "右上角的「＋」可以新增。" : nil)
        } else {
            switch entity {
            case "product", "bundle":
                grid
            case "coupon":
                RuledList {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                        link(row) { CouponRow(row: row) }
                            .reveal(i)
                    }
                }
            case "banner":
                VStack(spacing: 28) {
                    ForEach(shown) { row in
                        link(row) {
                            BannerPreview(values: Self.object(row.raw))
                                .allowsHitTesting(false)
                        }
                    }
                }
            default:
                if shown.contains(where: { $0.image != nil }) && shown.count <= 60 && (schema?.collection != nil || entity == "news" || entity == "milestone") {
                    cards
                } else {
                    RuledList {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                            link(row) { RecordRow(row: row) }
                                .reveal(i)
                        }
                    }
                }
            }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: sizeClass == .regular ? 4 : 2)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                link(row) { ProductCard(row: row) }
                    .reveal(i, .scale)
            }
        }
    }

    /// 有封面的內容：大卡片（文章、作品）
    private var cards: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: sizeClass == .regular ? 3 : 1)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                link(row) { CoverCard(row: row) }
                    .reveal(i)
            }
        }
    }

    @ViewBuilder
    private func link<Label: View>(_ row: RecordSummary, @ViewBuilder label: () -> Label) -> some View {
        if canOpen {
            NavigationLink(value: Route.record(site: site, entity: entity, id: row.id)) { label() }
                .buttonStyle(.row)
        } else {
            label()
        }
    }

    static func object(_ v: JSONValue) -> [String: JSONValue] {
        if case .object(let o) = v { return o }
        return [:]
    }
}

/// 一般的列：縮圖、標題、說明、狀態、時間
struct RecordRow: View {
    let row: RecordSummary

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let image = row.image {
                RemoteImage(url: image, aspect: 1, radius: Metric.radiusSm)
                    .frame(width: 52)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
                if let detail = row.detail {
                    Text(detail)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let badge = row.badge { StatusBadge(badge, tone: row.tone) }
                if let date = row.date {
                    Text(date.relativeText)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, 16)
        .contentShape(.rect)
    }
}

/// 折價券的一列：碼、折扣、名稱、用了幾次、到期
struct CouponRow: View {
    let row: RecordSummary

    var body: some View {
        let r = row.raw
        HStack(alignment: .center, spacing: 14) {
            Text(r["discountLabel"]?.string ?? "")
                .font(.brand(18, .semibold))
                .tracking(-0.4)
                .foregroundStyle(Theme.onAccent)
                .frame(width: 72, height: 52)
                .background((r["isActive"]?.bool ?? true) ? Theme.accent : Theme.muted, in: .rect(cornerRadius: Metric.radiusSm))
            VStack(alignment: .leading, spacing: 4) {
                Text(r["code"]?.string ?? "")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                if let name = r["name"]?.string, !name.isEmpty {
                    Text(name)
                        .textRole(.xs)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
                Text(details(r))
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let badge = row.badge { StatusBadge(badge, tone: row.tone) }
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    private func details(_ r: JSONValue) -> String {
        var out: [String] = []
        if let used = r["usageCount"]?.int, let limit = r["usageLimit"]?.int { out.append("用了 \(used)/\(limit)") }
        if let at = r["expiresAt"]?.date { out.append(at < .now ? "已過期" : "\(at.dayText) 到期") }
        if let email = r["assignedUserEmail"]?.string { out.append("給 \(email)") }
        return out.joined(separator: "・")
    }
}

/// 有封面的內容卡（NewsCard：圖、分類、標題、日期）
struct CoverCard: View {
    let row: RecordSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RemoteImage(url: row.image, aspect: 1600 / 840)
                .overlay(alignment: .topLeading) {
                    if let badge = row.badge, row.tone != .active {
                        StatusBadge(badge, tone: row.tone).padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                if let subtitle = row.subtitle {
                    Eyebrow(subtitle)
                }
                Text(row.title)
                    .textRole(.h3)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let date = row.date {
                    Text(date.dayText)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .contentShape(.rect)
    }
}
