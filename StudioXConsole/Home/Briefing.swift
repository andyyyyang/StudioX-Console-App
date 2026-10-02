import Observation
import SwiftUI

/// Xena 首頁與收件匣的資料：每個網站同時去拿，拿不到的那個網站就略過（標出來），不影響其他網站。
///   - 昨天的營運報表（有商店的網站：ops_report，昨天的訂單、收款、異常）
///   - 已付款等出貨的訂單
///   - 客人在等回覆的客服信（support_thread）
///   - Xena 轉給專人的網站客服對話（assistant_conversation）、新的專案詢問（inquiry）
@Observable
final class Briefing {
    private(set) var ops: [String: OpsReport] = [:]
    private(set) var toShip: [String: [OrderSummary]] = [:]
    private(set) var awaiting: [SupportThreadSummary] = []
    private(set) var handoffs: [XenaConversationSummary] = []
    private(set) var inquiries: [InquirySummary] = []
    /// 拿不到資料的網站（網站代號 → 原因）
    private(set) var failures: [String: String] = [:]
    private(set) var loading = false
    private(set) var updatedAt: Date?

    @ObservationIgnored private let api: ConsoleAPI
    /// 這一輪要拿的網站、拿回來的結果（同時拿的時候各自寫進來）
    @ObservationIgnored private var plan: [String: SiteSummary] = [:]
    @ObservationIgnored private var collected: [String: SiteResult] = [:]

    init(api: ConsoleAPI) {
        self.api = api
    }

    func reset() {
        ops = [:]
        toShip = [:]
        awaiting = []
        handoffs = []
        inquiries = []
        failures = [:]
        updatedAt = nil
    }

    private struct SiteResult {
        var site: String
        var ops: OpsReport?
        var toShip: [OrderSummary] = []
        var awaiting: [SupportThreadSummary] = []
        var handoffs: [XenaConversationSummary] = []
        var inquiries: [InquirySummary] = []
        var failure: String?
    }

    func refresh(sites: [SiteSummary]) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        plan = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0) })
        collected = [:]
        // 一個網站一個請求序列；網站之間同時跑（結果各自寫回這裡）
        let ids = sites.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { await self.load(id) }
            }
        }
        let results = Array(collected.values)
        ops = Dictionary(uniqueKeysWithValues: results.compactMap { r in r.ops.map { (r.site, $0) } })
        toShip = Dictionary(uniqueKeysWithValues: results.map { ($0.site, $0.toShip) })
        awaiting = results.flatMap(\.awaiting).sorted { ($0.waitingHours ?? 0) > ($1.waitingHours ?? 0) }
        handoffs = results.flatMap(\.handoffs).sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
        inquiries = results.flatMap(\.inquiries).sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
        failures = Dictionary(uniqueKeysWithValues: results.compactMap { r in r.failure.map { (r.site, $0) } })
        updatedAt = .now
    }

    private func load(_ id: String) async {
        guard let site = plan[id] else { return }
        var r = SiteResult(site: site.id)
        do {
            if site.hasOrders {
                r.ops = try? await api.ops(site: site.id, days: 1)
                r.toShip = try await api.orders(site: site.id, status: "paid", limit: 30)
            }
            if site.hasSupport {
                r.awaiting = try await api.supportThreads(site: site.id)
            }
            if site.tools.contains("list") {
                r.handoffs = try await api.xenaConversations(site: site.id).filter { $0.status == "waiting" || $0.status == "human" }
                r.inquiries = try await api.inquiries(site: site.id, status: "new")
            }
        } catch {
            r.failure = error.localizedDescription
        }
        collected[id] = r
    }

    /// 需要你看一下的事（越急的越前面）
    func attention(sites: [SiteSummary]) -> [AttentionItem] {
        var out: [AttentionItem] = []
        let name = { (id: String) in sites.first { $0.id == id }?.name ?? id }
        for (site, threads) in Dictionary(grouping: awaiting, by: \.site).sorted(by: { $0.key < $1.key }) {
            let oldest = threads.compactMap(\.waitingHours).max()
            out.append(AttentionItem(
                id: "support-\(site)", site: site, icon: "chat-bubble-left-right", tone: .warning,
                title: "\(threads.count) 位客人在等回覆",
                detail: "\(name(site))・" + (oldest.map { "最久等了 \(Self.hours($0))" } ?? "還沒回覆"),
                action: .inbox
            ))
        }
        for (site, orders) in toShip.sorted(by: { $0.key < $1.key }) where !orders.isEmpty {
            out.append(AttentionItem(
                id: "ship-\(site)", site: site, icon: "truck", tone: .gold,
                title: "\(orders.count) 筆訂單已付款、等出貨",
                detail: "\(name(site))・最早的是 \(orders.last?.paidAt?.shortText ?? orders.last?.createdAt?.shortText ?? "")",
                action: .orders(site: site, status: "paid")
            ))
        }
        for (site, report) in ops.sorted(by: { $0.key < $1.key }) {
            for (i, alert) in report.alerts.enumerated() {
                out.append(AttentionItem(id: "alert-\(site)-\(i)", site: site, icon: "exclamation-triangle", tone: .danger, title: alert, detail: name(site), action: .askXena("\(name(site))的異常：「\(alert)」，怎麼處理？")))
            }
        }
        if !handoffs.isEmpty {
            out.append(AttentionItem(
                id: "handoffs", site: handoffs[0].site, icon: "chat-bubble-oval-left-ellipsis", tone: .warning,
                title: "Xena 轉給專人的對話 \(handoffs.count) 段",
                detail: handoffs.prefix(2).map { $0.contactName ?? $0.firstQuestion ?? "訪客" }.joined(separator: "、"),
                action: .inbox
            ))
        }
        if !inquiries.isEmpty {
            out.append(AttentionItem(
                id: "inquiries", site: inquiries[0].site, icon: "envelope", tone: .info,
                title: "\(inquiries.count) 筆新的專案詢問",
                detail: inquiries.prefix(2).map { [$0.name, $0.company].compactMap { $0 }.joined(separator: "・") }.joined(separator: "、"),
                action: .inbox
            ))
        }
        return out
    }

    static func hours(_ h: Double) -> String {
        h < 1 ? "\(max(1, Int(h * 60))) 分鐘" : h < 48 ? "\(Int(h.rounded())) 小時" : "\(Int((h / 24).rounded())) 天"
    }
}

/// 首頁上的一件事
struct AttentionItem: Identifiable {
    enum Action {
        case inbox
        case orders(site: String, status: String)
        case askXena(String)
    }

    let id: String
    var site: String
    var icon: String
    var tone: Tone
    var title: String
    var detail: String
    var action: Action
}
