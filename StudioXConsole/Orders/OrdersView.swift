import SwiftUI

/// 訂單（網站後台的「訂單管理」）：有商店的網站。預設看「已付款、等出貨」，可以一次選好幾張標記出貨。
/// 改狀態、退款一律先出確認（網站的兩步驟確認），按了才執行。
/// iPad：左邊清單、右邊訂單內容。
struct OrdersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var picked: String?

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                OrdersList(picked: $picked)
                    .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 480)
            } detail: {
                NavigationStack(path: Bindable(model).ordersPath) {
                    Group {
                        if let picked, let site = model.ordersSite ?? model.orderSites.first?.id {
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

    enum Filter: String, CaseIterable, Identifiable {
        case toShip = "paid"
        case unpaid = "unpaid"
        case shipped = "shipped"
        case completed = "completed"
        case all = "all"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .toShip: "等出貨"
            case .unpaid: "待付款"
            case .shipped: "已出貨"
            case .completed: "已完成"
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
                FilterBar(items: Filter.allCases, selection: Binding(get: { filter }, set: { model.ordersStatus = $0.rawValue }), title: \.label)
                if let error {
                    ErrorNote(message: error) { Task { await load() } }
                }
                if orders.isEmpty {
                    if loading {
                        SkeletonRows(rows: 5)
                    } else if error == nil {
                        EmptyState(title: filter == .toShip ? "沒有等出貨的訂單" : "沒有訂單", message: filter == .toShip ? "已付款的訂單都出貨了。" : nil)
                    }
                } else {
                    RuledList {
                        ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                            row(order)
                                .reveal(index)
                        }
                    }
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, selecting ? 110 : 48)
        }
        .refreshable { await load() }
        .brandPage()
        .navigationTitle("訂單")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if filter == .toShip && !orders.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "選取") {
                        withAnimation(Motion.ease) {
                            selecting.toggle()
                            selected = []
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                Button {
                    Task { await bulkShip() }
                } label: {
                    Text("標記已出貨（\(selected.count)）")
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
            model.show("已標記 \(n) 張訂單出貨")
            selecting = false
            selected = []
            Task {
                await load()
                await model.refreshAll()
            }
        }
        .task(id: "\(site?.id ?? "")|\(filter.rawValue)") { await load() }
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
            Headline("*Orders*", role: .h1)
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
                        .overlay(Rectangle().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: 1.5))
                        .overlay { if on { Text("✓").font(.brand(13, .bold)).foregroundStyle(Theme.onAccent) } }
                    OrderRow(order: order)
                }
            }
            .buttonStyle(.row)
            .sensoryFeedback(.selection, trigger: selected.contains(order.id))
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

    private func load() async {
        guard let site else { return }
        loading = true
        defer { loading = false }
        error = nil
        do {
            switch filter {
            case .unpaid:
                let pending = try await model.api.orders(site: site.id, status: "pending")
                let awaiting = try await model.api.orders(site: site.id, status: "awaiting_payment")
                orders = (pending + awaiting).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            case .all:
                orders = try await model.api.orders(site: site.id, limit: 100)
            default:
                orders = try await model.api.orders(site: site.id, status: filter.rawValue)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func bulkShip() async {
        guard let site, !selected.isEmpty else { return }
        let numbers = orders.filter { selected.contains($0.id) }.map(\.number)
        do {
            let outcome = try await model.api.proposeBulkStatus(site: site.id, ids: numbers, status: "shipped")
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
