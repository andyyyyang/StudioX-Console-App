import SwiftUI

/// 訂單（網站後台的「訂單管理」）：有商店的網站。預設看「已付款、等出貨」，可以一次選好幾張標記出貨。
/// 改狀態、退款一律先出確認（網站的兩步驟確認），按了才執行。
/// iPad：左邊清單、右邊訂單內容。
struct OrdersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                OrdersList(picked: Bindable(model).ordersPicked)
                    .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 480)
                    .splitListColumn()
            } detail: {
                NavigationStack(path: Bindable(model).ordersPath) {
                    Group {
                        if let picked = model.ordersPicked, let site = model.ordersSite ?? model.orderSites.first?.id {
                            OrderDetailView(site: site, orderID: picked)
                                .id(picked)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Headline("Pick an *order*", role: .h2)
                                Text("從左邊選一張訂單。")
                                    .textRole(.small)
                                    .foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .brandPage()
                        }
                    }
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .brandSplitView()
            }
        } else {
            NavigationStack(path: Bindable(model).ordersPath) {
                OrdersList(picked: nil)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        }
    }
}

/// 訂單清單（手機是一頁；iPad 是左邊那欄）
struct OrdersList: View {
    /// iPad：點了在右邊打開（nil＝手機，點了推下一頁）
    var picked: Binding<String?>?

    @Environment(AppModel.self) private var model
    @State private var orders: [OrderSummary] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var proposal: Proposal?
    /// 搜尋框裡的字；query 是停下來之後真的拿去搜的
    @State private var search = ""
    @State private var query = ""
    /// 下一頁（更早的訂單）的 before；nil＝沒有更早的了
    @State private var next: String?
    @State private var loadingMore = false

    enum Filter: String, CaseIterable, Identifiable {
        case toShip = "paid"
        case unpaid = "unpaid"
        case shipped = "shipped"
        case completed = "completed"
        case cancelled = "cancelled"
        case all = "all"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .toShip: "等出貨"
            case .unpaid: "待付款"
            case .shipped: "已出貨"
            case .completed: "已完成"
            case .cancelled: "已取消"
            case .all: "全部"
            }
        }
    }

    private var site: SiteSummary? {
        model.site(model.ordersSite ?? "") ?? model.orderSites.first
    }

    private var filter: Filter { Filter(rawValue: model.ordersStatus) ?? .toShip }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    SearchField(text: $search, prompt: "訂單編號、收件人、電話、Email")
                    // 搜尋是找全部狀態的
                    if query.isEmpty {
                        FilterBar(items: Filter.allCases, selection: Binding(get: { filter }, set: { model.ordersStatus = $0.rawValue }), title: \.label)
                    }
                }
                if let error {
                    ErrorNote(message: error) { Task { await load() } }
                }
                if orders.isEmpty {
                    if loading {
                        SkeletonRows(rows: 5)
                    } else if error == nil {
                        if !query.isEmpty {
                            EmptyState(title: "找不到「\(query)」", message: "試試訂單編號、收件人的名字、電話或 Email。")
                        } else {
                            EmptyState(title: filter == .toShip ? "沒有等出貨的訂單" : "沒有訂單", message: filter == .toShip ? "已付款的訂單都出貨了。" : nil)
                        }
                    }
                } else {
                    RuledList {
                        ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                            row(order)
                                .reveal(min(index, 12))
                        }
                    }
                    if next != nil {
                        LoadingRow(text: "載入更早的訂單…")
                            .onAppear { Task { await loadMore() } }
                    }
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, selecting ? 110 : 48)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await Task { await load() }.value }
        .brandPage()
        .navigationTitle("訂單")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // iPad 的分欄沒有導覽列：「選取」放在大標旁邊
            if picked == nil, canSelect {
                ToolbarItem(placement: .topBarTrailing) { selectButton }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                Button {
                    Task { await bulkUpdate() }
                } label: {
                    Text("\(bulkTarget == "completed" ? "標記已完成" : "標記已出貨")（\(selected.count)）")
                }
                .buttonStyle(.brand(.accent, size: .lg, fullWidth: true, arrow: true))
                .disabled(selected.isEmpty)
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, 10)
                .background(.bar)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            let n = result["updated"]?.int ?? selected.count
            model.show("已標記 \(n) 張訂單\(bulkTarget == "completed" ? "完成" : "出貨")")
            selecting = false
            selected = []
            Task {
                await load()
                await model.refreshAll()
            }
        }
        .task(id: "\(site?.id ?? "")|\(filter.rawValue)|\(query)") { await load() }
        // 搜尋：打字停 0.35 秒才去搜
        .task(id: search) {
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q != query else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            selecting = false
            selected = []
            query = q
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.orderSites.count > 1, let site {
                Menu {
                    ForEach(model.orderSites) { s in
                        Button(s.name) {
                            model.ordersSite = s.id
                            picked?.wrappedValue = nil
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        SiteIconView(site: site, size: 22)
                        Text(site.name).textRole(.small).foregroundStyle(Theme.ink)
                        HeroIcon("chevron-down", size: 12).foregroundStyle(Theme.muted)
                    }
                }
            } else if let site {
                Eyebrow(site.name)
            }
            HStack(alignment: .firstTextBaseline) {
                Headline("*Orders*", role: .h1)
                Spacer(minLength: 12)
                if picked != nil, canSelect {
                    selectButton
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
            }
        }
    }

    /// 等出貨的可以一次選幾張標出貨；已出貨的一次標完成
    private var canSelect: Bool { query.isEmpty && (filter == .toShip || filter == .shipped) && !orders.isEmpty }

    private var bulkTarget: String { filter == .shipped ? "completed" : "shipped" }

    private var selectButton: some View {
        Button(selecting ? "完成" : "選取") {
            withAnimation(Motion.ease) {
                selecting.toggle()
                selected = []
            }
        }
    }

    @ViewBuilder
    private func row(_ order: OrderSummary) -> some View {
        if selecting {
            Button {
                if selected.contains(order.id) { selected.remove(order.id) } else { selected.insert(order.id) }
            } label: {
                HStack(spacing: 12) {
                    let on = selected.contains(order.id)
                    Rectangle()
                        .fill(on ? Theme.accent : .clear)
                        .frame(width: 20, height: 20)
                        .overlay { Rectangle().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: 1.5) }
                        .overlay { if on { Text("✓").font(.brand(13, .bold)).foregroundStyle(Theme.onAccent) } }
                    OrderRow(order: order)
                }
            }
            .buttonStyle(.row)
            .haptic(.selection, trigger: selected.contains(order.id))
        } else if let picked {
            Button {
                picked.wrappedValue = order.id
                model.ordersPath = []
            } label: {
                OrderRow(order: order)
                    .padding(.horizontal, 10)
                    .background(picked.wrappedValue == order.id ? Theme.accentSoft : .clear)
            }
            .buttonStyle(.row)
        } else {
            NavigationLink(value: Route.order(site: order.site, id: order.id)) {
                OrderRow(order: order)
            }
            .buttonStyle(.row)
        }
    }

    /// 這一頁現在是什麼（網站、篩選、搜尋）：翻頁回來時還是同一個才接上去
    private var listKey: String { "\(site?.id ?? "")|\(filter.rawValue)|\(query)" }

    /// 一頁要拿的狀態（搜尋是全部狀態）
    private var pageStatus: String? { query.isEmpty && filter != .all ? filter.rawValue : nil }

    private func load() async {
        guard let site else { return }
        let key = listKey
        loading = true
        defer { loading = false }
        error = nil
        // 換了篩選、搜尋：上一張清單的下一頁不能接到這裡
        next = nil
        do {
            if query.isEmpty && filter == .unpaid {
                let pending = try await model.api.orders(site: site.id, status: "pending")
                let awaiting = try await model.api.orders(site: site.id, status: "awaiting_payment")
                guard key == listKey else { return }
                orders = (pending + awaiting).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                next = nil
            } else {
                let page = try await model.api.orderPage(site: site.id, status: pageStatus, query: query.isEmpty ? nil : query, before: nil, limit: 60)
                guard key == listKey else { return }
                orders = page.paged || query.isEmpty ? page.items : Self.matching(page.items, query)
                next = page.next
            }
        } catch {
            guard key == listKey else { return }
            self.error = error.localizedDescription
        }
    }

    /// 捲到底：接上更早的一頁
    private func loadMore() async {
        guard let site, let before = next, !loadingMore, !loading else { return }
        let key = listKey
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await model.api.orderPage(site: site.id, status: pageStatus, query: query.isEmpty ? nil : query, before: before, limit: 60)
            guard key == listKey else { return }
            let have = Set(orders.map(\.id))
            orders += page.items.filter { !have.contains($0.id) }
            next = page.items.isEmpty ? nil : page.next
        } catch {
            guard key == listKey else { return }
            next = nil
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    /// 舊版網站不認得搜尋：照單號和收件人篩
    private static func matching(_ orders: [OrderSummary], _ q: String) -> [OrderSummary] {
        orders.filter { $0.number.localizedCaseInsensitiveContains(q) || $0.customer.localizedCaseInsensitiveContains(q) }
    }

    private func bulkUpdate() async {
        guard let site, !selected.isEmpty else { return }
        let numbers = orders.filter { selected.contains($0.id) }.map(\.number)
        do {
            let outcome = try await model.api.proposeBulkStatus(site: site.id, ids: numbers, status: bulkTarget)
            switch outcome {
            case .needsConfirmation(let p): proposal = p
            case .done: await load()
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }
}

/// 訂單一列：客人、單號、時間、金額、狀態
struct OrderRow: View {
    let order: OrderSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(order.customer.isEmpty ? "（沒有名字）" : order.customer)
                        .textRole(.h4)
                        .foregroundStyle(Theme.ink)
                    if order.isBankTransfer {
                        StatusBadge("匯款", tone: .neutral)
                    }
                    if let refund = order.refundStatus, !refund.isEmpty {
                        StatusBadge("退款", tone: .danger)
                    }
                }
                Text("#\(order.number)・\((order.paidAt ?? order.createdAt)?.shortText ?? "")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(order.totalLabel)
                    .font(.brand(16, .medium).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                StatusBadge(order.status.label, tone: order.status.tone)
            }
        }
        .padding(.vertical, 16)
        .contentShape(.rect)
    }
}
