import SwiftUI

/// 搜尋（分頁列右邊的放大鏡）：一次搜所有網站。
///   - 有商店的網站：網站的 search 工具（訂單編號、收件人、電話；會員姓名、email、電話；折價碼；商品）
///   - 內容網站：每個內容集合的 list（關鍵字）
/// 結果照網站分組，點了直接打開那一筆。
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var groups: [ResultGroup] = []
    @State private var searching = false
    @State private var searched = ""

    struct Hit: Identifiable, Hashable {
        let id: String
        let kind: String
        let title: String
        let detail: String?
        let badge: (String, Tone)?
        let route: Route

        static func == (a: Hit, b: Hit) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    struct ResultGroup: Identifiable {
        let id: String
        let site: SiteSummary
        let hits: [Hit]
    }

    var body: some View {
        NavigationStack(path: Bindable(model).searchPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        intro
                    } else if searching && groups.isEmpty {
                        SkeletonRows(rows: 4)
                    } else if groups.isEmpty && searched == query {
                        EmptyState(title: "找不到「\(query)」", message: "試試訂單編號、客人的名字或電話、折價碼、商品或文章的名稱。")
                        historyLink
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 10) {
                                    SiteIconView(site: group.site, size: 22)
                                    Text(group.site.name).textRole(.h4).foregroundStyle(Theme.ink)
                                    Text("\(group.hits.count)").textRole(.xs).foregroundStyle(Theme.muted)
                                }
                                RuledList {
                                    ForEach(group.hits) { hit in
                                        NavigationLink(value: hit.route) { HitRow(hit: hit) }
                                            .buttonStyle(.row)
                                    }
                                }
                            }
                        }
                        historyLink
                    }
                }
                .pageWidth()
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.immediately)
            .brandPage()
            .navigationTitle("搜尋")
            .searchable(text: $query, prompt: Text("訂單、客人、折價碼、商品、文章…"))
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard q.count >= 2 else {
                    groups = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await run(q)
            }
        }
    }

    /// 客服的對話、信、詢問在收件匣的全部紀錄裡搜（內容多，不在這裡一起搜）
    private var historyLink: some View {
        Button {
            model.openInboxHistory(search: query.trimmingCharacters(in: .whitespaces))
        } label: {
            HStack(spacing: 12) {
                HeroIcon("inbox-stack", size: 20)
                    .foregroundStyle(Theme.ink2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("在客服紀錄找「\(query.trimmingCharacters(in: .whitespaces))」")
                        .textRole(.h4)
                        .foregroundStyle(Theme.ink)
                    Text("官網、LINE 的對話，客服信和專案詢問，結束了的也找得到")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                HeroIcon("chevron-right", size: 14)
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .overlay { RoundedRectangle(cornerRadius: Metric.radius).strokeBorder(Theme.line, lineWidth: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Headline("Find *anything*", role: .h1)
            Text("一次搜你所有的網站：訂單編號、收件人、電話、會員、折價碼、商品，以及每個網站的文章、作品、服務、FAQ。")
                .textRole(.lead)
                .foregroundStyle(Theme.ink2)
        }
        .reveal()
    }

    // MARK: 搜

    private func run(_ q: String) async {
        searching = true
        defer { searching = false }
        var out: [ResultGroup] = []
        for site in model.sites {
            var hits: [Hit] = []
            if site.tools.contains("search") {
                do {
                    hits += Self.commerceHits(try await model.api.search(site: site.id, query: q), site: site.id)
                } catch {
                    // 這個網站搜不到（或暫時連不上）：略過
                }
            }
            if let schema = await model.schema(for: site.id) {
                for entity in schema.entities where entity.collection != nil && !entity.singleton && entity.canList {
                    guard !Task.isCancelled else { return }
                    do {
                        let r = try await model.api.list(site: site.id, entity: entity.key, query: q, filters: ["limit": 8])
                        hits += r.rows.prefix(8).map { row in
                            Hit(id: "\(site.id)/\(entity.key)/\(row.id)", kind: entity.label, title: row.title, detail: row.subtitle, badge: row.badge.map { ($0, row.tone) }, route: .record(site: site.id, entity: entity.key, id: row.id))
                        }
                    } catch {
                        continue
                    }
                }
            }
            if !hits.isEmpty { out.append(ResultGroup(id: site.id, site: site, hits: hits)) }
        }
        guard !Task.isCancelled else { return }
        withAnimation(Motion.ease) {
            groups = out
            searched = query
        }
    }

    /// 商店網站的 search：訂單、會員、折價券、商品
    static func commerceHits(_ r: JSONValue, site: String) -> [Hit] {
        var hits: [Hit] = []
        for o in r["orders"]?.array ?? [] {
            guard let id = o["id"]?.string else { continue }
            let status = OrderStatus(raw: o["status"]?.string ?? "")
            hits.append(Hit(id: "\(site)/order/\(id)", kind: "訂單", title: "#\(o["orderNumber"]?.string ?? "")・\(o["shippingName"]?.string ?? "")", detail: o["totalLabel"]?.string, badge: (status.label, status.tone), route: .order(site: site, id: id)))
        }
        for u in r["users"]?.array ?? [] {
            guard let id = u["id"]?.string else { continue }
            hits.append(Hit(id: "\(site)/user/\(id)", kind: "會員", title: u["name"]?.string ?? u["email"]?.string ?? "會員", detail: [u["email"]?.string, u["phone"]?.string].compactMap { $0 }.joined(separator: "・"), badge: nil, route: .member(site: site, id: id)))
        }
        for c in r["coupons"]?.array ?? [] {
            guard let id = c["id"]?.string else { continue }
            let active = c["isActive"]?.bool ?? false
            hits.append(Hit(id: "\(site)/coupon/\(id)", kind: "折價券", title: c["code"]?.string ?? "", detail: c["name"]?.string, badge: (active ? "啟用" : "停用", active ? .active : .neutral), route: .record(site: site, entity: "coupon", id: id)))
        }
        for p in r["products"]?.array ?? [] {
            guard let id = p["id"]?.string else { continue }
            let published = p["isPublished"]?.bool ?? false
            hits.append(Hit(id: "\(site)/product/\(id)", kind: "商品", title: p["nameZh"]?.string ?? "", detail: p["priceLabel"]?.string, badge: (published ? "已上架" : "未上架", published ? .active : .neutral), route: .record(site: site, entity: "product", id: id)))
        }
        return hits
    }
}

/// 搜尋結果的一列：種類、標題、說明、狀態
private struct HitRow: View {
    let hit: SearchView.Hit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(hit.kind)
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let detail = hit.detail, !detail.isEmpty {
                    Text(detail)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let badge = hit.badge { StatusBadge(badge.0, tone: badge.1) }
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}
