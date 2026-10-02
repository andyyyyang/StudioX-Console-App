import SwiftUI

/// 訂單（網站後台的「訂單管理」）：有商店的網站。預設看「已付款、等出貨」，可以一次選好幾張標記出貨。
/// 改狀態、退款一律先出確認（網站的兩步驟確認），按了才執行。
struct OrdersView: View {
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
        case all = "all"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .toShip: "等出貨"
            case .unpaid: "待付款"
            case .shipped: "已出貨"
            case .all: "全部"
            }
        }
    }

    private var site: SiteSummary? {
        model.site(model.ordersSite ?? "") ?? model.orderSites.first
    }

    private var filter: Filter { Filter(rawValue: model.ordersStatus) ?? .toShip }

    var body: some View {
        NavigationStack(path: Bindable(model).ordersPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    controls
                    if let error {
                        ErrorNote(message: error) { Task { await load() } }
                    }
                    if orders.isEmpty {
                        if loading {
                            LoadingRow().admCard(padding: 0)
                        } else if error == nil {
                            EmptyState(icon: "shopping-bag", title: filter == .toShip ? "沒有等出貨的訂單" : "沒有訂單", message: filter == .toShip ? "已付款的訂單都出貨了。" : nil)
                                .admCard(padding: 0)
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                                if index > 0 { Divider().overlay(Theme.hair).padding(.leading, selecting ? 48 : 14) }
                                row(order)
                            }
                        }
                        .admCard(padding: 0)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 8)
                .padding(.bottom, selecting ? 96 : 32)
            }
            .refreshable { await load() }
            .admPage()
            .navigationTitle("訂單")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if filter == .toShip && !orders.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selecting ? "完成" : "選取") {
                            withAnimation(.smooth) {
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
                        Label { Text("標記已出貨（\(selected.count)）") } icon: { HeroIcon("truck", size: 18) }
                    }
                    .buttonStyle(.adm(.primary, fullWidth: true))
                    .disabled(selected.isEmpty)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
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
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.orderSites.count > 1, let site {
                Menu {
                    ForEach(model.orderSites) { s in
                        Button(s.name) { model.ordersSite = s.id }
                    }
                } label: {
                    HStack(spacing: 8) {
                        SiteIconView(site: site, size: 24)
                        Text(site.name).font(.admCardTitle).foregroundStyle(Theme.ink)
                        HeroIcon("chevron-down", size: 12).foregroundStyle(Theme.faint)
                    }
                }
            } else if let site {
                HStack(spacing: 8) {
                    SiteIconView(site: site, size: 24)
                    Text(site.name).font(.admCardTitle).foregroundStyle(Theme.ink)
                }
            }
            Picker("狀態", selection: Bindable(model).ordersStatus) {
                ForEach(Filter.allCases) { f in
                    Text(f.label).tag(f.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func row(_ order: OrderSummary) -> some View {
        if selecting {
            Button {
                if selected.contains(order.id) { selected.remove(order.id) } else { selected.insert(order.id) }
            } label: {
                HStack(spacing: 10) {
                    HeroIcon(selected.contains(order.id) ? "check-circle" : "stop", size: 22)
                        .foregroundStyle(selected.contains(order.id) ? Theme.primary : Theme.faint)
                        .padding(.leading, 14)
                    OrderRow(order: order)
                }
            }
            .buttonStyle(RowPressStyle())
        } else {
            NavigationLink(value: Route.order(site: order.site, id: order.id)) {
                OrderRow(order: order)
            }
            .buttonStyle(RowPressStyle())
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
                orders = try await model.api.orders(site: site.id, limit: 60)
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

/// 訂單一列
struct OrderRow: View {
    let order: OrderSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(order.customer.isEmpty ? "（沒有名字）" : order.customer)
                        .font(.admCardTitle)
                        .foregroundStyle(Theme.ink)
                    if order.isBankTransfer {
                        StatusBadge("匯款", tone: .neutral)
                    }
                }
                Text("#\(order.number)・\((order.paidAt ?? order.createdAt)?.shortText ?? "")")
                    .font(.system(.footnote).monospacedDigit())
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(order.totalLabel)
                    .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                StatusBadge(order.status.label, tone: order.status.tone)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
