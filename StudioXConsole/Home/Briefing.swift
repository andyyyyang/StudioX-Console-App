import Observation
import SwiftUI

/// Xena 首頁與收件匣的資料：每個網站同時去拿，拿不到的那個網站就略過（標出來），不影響其他網站。
///   - 昨天的營運報表（有商店的網站：ops_report，昨天的訂單、收款、異常）
///   - 已付款等出貨的訂單
///   - 客人在等回覆的客服信（support_thread）
///   - Xena 轉給專人的網站客服對話（assistant_conversation）、她正在回答的對話、新的專案詢問（inquiry）
///   - 信箱裡還沒分的信（mailbox）
///   - 平台管理者：console 的待辦（服務申請、帳單、同步失敗…）
@Observable
final class Briefing {
    private(set) var ops: [String: OpsReport] = [:]
    private(set) var toShip: [String: [OrderSummary]] = [:]
    private(set) var awaiting: [SupportThreadSummary] = []
    /// 等專人、專人接手中的 Xena 對話
    private(set) var handoffs: [XenaConversationSummary] = []
    /// Xena 正在回答的對話（24 小時內有動靜的）
    private(set) var live: [XenaConversationSummary] = []
    private(set) var inquiries: [InquirySummary] = []
    /// 寄到網站信箱、還沒分的信
    private(set) var mail: [MailSummary] = []
    /// 等你決定：console 看數據找到的優化（要處理的事是 attention）
    private(set) var decisions: [Decision] = []
    /// StudioX Console 的待辦（平台管理者才有）
    private(set) var platform: [ConsoleTodo] = []
    /// 要不要拿 console 的待辦（AppModel 照登入的人有沒有平台管理權限設）
    @ObservationIgnored var loadsPlatform = false
    /// 拿不到資料的網站（網站代號 → 原因）
    private(set) var failures: [String: String] = [:]
    private(set) var loading = false
    private(set) var updatedAt: Date?

    @ObservationIgnored private let api: ConsoleAPI
    /// 這一輪要拿的網站、拿回來的結果（同時拿的時候各自寫進來）
    @ObservationIgnored private var plan: [String: SiteSummary] = [:]
    @ObservationIgnored private var collected: [String: SiteResult] = [:]
    /// 拿資料的途中又被要求重新整理（例如 Xena 剛改了東西）：這一輪結束後再跑一輪
    @ObservationIgnored private var rerun: [SiteSummary]?

    init(api: ConsoleAPI) {
        self.api = api
    }

    func reset() {
        ops = [:]
        toShip = [:]
        awaiting = []
        handoffs = []
        live = []
        inquiries = []
        mail = []
        decisions = []
        platform = []
        failures = [:]
        updatedAt = nil
    }

    private struct SiteResult {
        var site: String
        var ops: OpsReport?
        var toShip: [OrderSummary] = []
        var awaiting: [SupportThreadSummary] = []
        var handoffs: [XenaConversationSummary] = []
        var live: [XenaConversationSummary] = []
        var inquiries: [InquirySummary] = []
        var mail: [MailSummary] = []
        var failure: String?
    }

    func refresh(sites: [SiteSummary]) async {
        guard !loading else {
            rerun = sites
            return
        }
        loading = true
        defer { loading = false }
        var next: [SiteSummary]? = sites
        while let round = next {
            rerun = nil
            await collect(round)
            next = rerun
        }
    }

    private func collect(_ sites: [SiteSummary]) async {
        plan = Dictionary(sites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        collected = [:]
        // 等你決定：console 第一次看一個網站的數據要幾秒，不等它（拿到了再出現）；拿不到就留著上一次的
        Task { [api] in
            if let found = try? await api.decisions() {
                withAnimation(Motion.ease) { self.decisions = found }
            }
        }
        // console 的待辦：一樣不等；拿不到就留著上一次的
        if loadsPlatform {
            Task { [api] in
                if let todos = try? await api.consoleTodos() {
                    withAnimation(Motion.ease) { self.platform = todos }
                }
            }
        } else if !platform.isEmpty {
            platform = []
        }
        // 一個網站一個請求序列；網站之間同時跑（結果各自寫回這裡）
        let ids = sites.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { await self.load(id) }
            }
        }
        let results = Array(collected.values)
        ops = Dictionary(results.compactMap { r in r.ops.map { (r.site, $0) } }, uniquingKeysWith: { first, _ in first })
        toShip = Dictionary(results.map { ($0.site, $0.toShip) }, uniquingKeysWith: { first, _ in first })
        awaiting = results.flatMap(\.awaiting).sorted { ($0.waitingHours ?? 0) > ($1.waitingHours ?? 0) }
        handoffs = results.flatMap(\.handoffs).sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
        live = results.flatMap(\.live).sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
        inquiries = results.flatMap(\.inquiries).sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
        mail = results.flatMap(\.mail).sorted { ($0.row.date ?? .distantPast) > ($1.row.date ?? .distantPast) }
        failures = Dictionary(results.compactMap { r in r.failure.map { (r.site, $0) } }, uniquingKeysWith: { first, _ in first })
        updatedAt = .now
    }

    private func load(_ id: String) async {
        guard let site = plan[id] else { return }
        var r = SiteResult(site: site.id)
        // 每一段各自拿：一段失敗不影響同一個網站的其他段（失敗的原因記第一個）
        func note(_ error: any Error) {
            if r.failure == nil { r.failure = error.localizedDescription }
        }
        if site.hasOrders {
            r.ops = try? await api.ops(site: site.id, days: 1)
            do { r.toShip = try await api.orders(site: site.id, status: "paid", limit: 30) } catch { note(error) }
        }
        if site.hasSupport {
            do { r.awaiting = try await api.supportThreads(site: site.id) } catch { note(error) }
            // 信箱：沒有（或不給看）就是沒有
            if let box = try? await api.list(site: site.id, entity: "mailbox", filters: ["limit": 30]) {
                r.mail = box.rows.map { MailSummary(site: site.id, row: $0) }
            }
        }
        if site.tools.contains("list") {
            do { r.handoffs = try await api.xenaConversations(site: site.id).filter { $0.status == "waiting" || $0.status == "human" } } catch { note(error) }
            // Xena 正在回答的（黃毛丫頭的網站不認得 ai，回全部：這裡再篩）；太久沒動靜的不算
            let since = Date.now.addingTimeInterval(-24 * 3600)
            if let live = try? await api.xenaConversations(site: site.id, status: "ai") {
                r.live = live.filter { $0.status == "ai" && ($0.at ?? .distantPast) > since }
            }
            do { r.inquiries = try await api.inquiries(site: site.id, status: "new") } catch { note(error) }
        }
        collected[id] = r
    }

    /// 交給 Xena 了（真的送出了才叫，見 AppModel.decide）／不用了／之後再說：先從清單拿掉，再告訴 console（失敗也不放回來，下次重新整理會照 console 的）
    func decide(_ decision: Decision, _ action: Decision.Action) {
        withAnimation(Motion.ease) { decisions.removeAll { $0.id == decision.id } }
        Task { [api] in try? await api.decide(decision.id, action: action) }
    }

    /// 要你處理的事（越急的越前面）：出貨、回覆客人、異常…本來就得做的。可做可不做的優化在 decisions。
    /// 點了直接去處理：好幾件的打開收件匣的「要你處理」、訂單的「等出貨」；只有一件的直接打開那一段、那一張
    func attention(sites: [SiteSummary]) -> [AttentionItem] {
        var out: [AttentionItem] = []
        let name = { (id: String) in sites.first { $0.id == id }?.name ?? id }
        for (site, threads) in Dictionary(grouping: awaiting, by: \.site).sorted(by: { $0.key < $1.key }) {
            let oldest = threads.compactMap(\.waitingHours).max()
            let action: AttentionItem.Action = threads.count == 1 ? .open(Route.thread(site: site, id: threads[0].id)) : .inbox
            out.append(AttentionItem(
                id: "support-\(site)", site: site, icon: "chat-bubble-left-right", tone: .warning,
                title: "\(threads.count) 位客人在等回覆",
                detail: "\(name(site))・" + (oldest.map { "最久等了 \(Self.hours($0))" } ?? "還沒回覆"),
                action: action
            ))
        }
        for (site, orders) in toShip.sorted(by: { $0.key < $1.key }) where !orders.isEmpty {
            let action: AttentionItem.Action = orders.count == 1 ? .open(Route.order(site: site, id: orders[0].id)) : .orders(site: site, status: "paid")
            out.append(AttentionItem(
                id: "ship-\(site)", site: site, icon: "truck", tone: .gold,
                title: "\(orders.count) 筆訂單已付款、等出貨",
                detail: "\(name(site))・最早的是 \(orders.last?.paidAt?.shortText ?? orders.last?.createdAt?.shortText ?? "")",
                action: action
            ))
        }
        for (site, report) in ops.sorted(by: { $0.key < $1.key }) {
            for (i, alert) in report.alerts.enumerated() {
                out.append(AttentionItem(id: "alert-\(site)-\(i)", site: site, icon: "exclamation-triangle", tone: .danger, title: alert, detail: name(site), action: .askXena("\(name(site))的異常：「\(alert)」，怎麼處理？")))
            }
        }
        if let first = handoffs.first {
            let action: AttentionItem.Action = handoffs.count == 1 ? .open(Route.xenaConversation(site: first.site, id: first.id)) : .inbox
            out.append(AttentionItem(
                id: "handoffs", site: first.site, icon: "chat-bubble-oval-left-ellipsis", tone: .warning,
                title: "Xena 轉給專人的對話 \(handoffs.count) 段",
                detail: handoffs.prefix(2).map { $0.contactName ?? $0.firstQuestion ?? "訪客" }.joined(separator: "、"),
                action: action
            ))
        }
        // StudioX Console 的待辦（服務申請、帳單、同步失敗…）：點了打開平台管理的那一頁
        for todo in platform {
            out.append(AttentionItem(
                id: "console-\(todo.key)", site: "", icon: todo.icon, tone: todo.tone,
                title: todo.title, detail: "StudioX Console・\(todo.detail)",
                action: .open(Route.console(todo.page))
            ))
        }
        if let first = inquiries.first {
            let action: AttentionItem.Action = inquiries.count == 1 ? .open(Route.inquiry(site: first.site, id: first.id)) : .inbox
            out.append(AttentionItem(
                id: "inquiries", site: first.site, icon: "envelope", tone: .info,
                title: "\(inquiries.count) 筆新的專案詢問",
                detail: inquiries.prefix(2).map { [$0.name, $0.company].compactMap { $0 }.joined(separator: "・") }.joined(separator: "、"),
                action: action
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
        /// 收件匣的「要你處理」
        case inbox
        /// 訂單清單（那個網站、那個狀態）
        case orders(site: String, status: String)
        /// 只有一件：直接打開那一段對話、那一張訂單
        case open(Route)
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

/// 信箱裡的一封信（寄到網站信箱、還沒轉成客服對話也還沒收起來的）
struct MailSummary: Identifiable {
    var site: String
    var row: RecordSummary
    var id: String { "\(site)|\(row.id)" }
}
