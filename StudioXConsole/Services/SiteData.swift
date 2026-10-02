import Foundation

/// 各網站的資料與動作（工具名稱與參數照網站的 mcp-tools.ts、mcp-entities.ts）。
/// 讀取直接回資料；寫入一律先拿到「要確認」的提案（Proposal），使用者在 App 裡確認後才執行。
extension ConsoleAPI {
    // MARK: 讀

    /// 訂單（最新的在前）。status：pending / awaiting_payment / paid / shipped / completed / cancelled
    func orders(site: String, status: String? = nil, limit: Int = 50) async throws -> [OrderSummary] {
        var args: [String: JSONValue] = ["entity": "order", "limit": .number(Double(limit))]
        if let status { args["status"] = .string(status) }
        let r = try await tool("list", site: site, args)
        return (r["orders"]?.array ?? []).map { OrderSummary(site: site, $0) }
    }

    func order(site: String, id: String) async throws -> OrderDetail {
        OrderDetail(site: site, try await tool("get", site: site, ["entity": "order", "id": .string(id)]))
    }

    /// 客服信。status 沒給＝客人已發言、我們還沒回的（等最久的在前）；open / answered / closed
    func supportThreads(site: String, status: String? = nil) async throws -> [SupportThreadSummary] {
        var args: [String: JSONValue] = ["entity": "support_thread", "limit": 50]
        if let status { args["status"] = .string(status) }
        let r = try await tool("list", site: site, args)
        return (r["threads"]?.array ?? []).map { SupportThreadSummary(site: site, $0) }
    }

    func supportThread(site: String, id: String) async throws -> SupportThreadDetail {
        SupportThreadDetail(site: site, try await tool("get", site: site, ["entity": "support_thread", "id": .string(id)]))
    }

    /// Xena 在網站上的客服對話（只有 atelier-cms 的網站有；沒有就回空的）
    func xenaConversations(site: String) async throws -> [XenaConversationSummary] {
        do {
            let r = try await tool("list", site: site, ["entity": "assistant_conversation", "limit": 40])
            return (r["items"]?.array ?? []).map { XenaConversationSummary(site: site, $0) }
        } catch APIError.tool {
            return []
        }
    }

    func xenaConversation(site: String, id: String) async throws -> [XenaConversationMessage] {
        let r = try await tool("get", site: site, ["entity": "assistant_conversation", "id": .string(id)])
        return (r["messages"]?.array ?? []).enumerated().map { i, m in
            XenaConversationMessage(id: i, role: m["role"]?.string ?? "user", content: m["content"]?.string ?? "", author: m["author"]?.string, at: m["at"]?.date)
        }
    }

    /// 專案詢問（只有 atelier-cms 的網站有；沒有就回空的）
    func inquiries(site: String, status: String? = "new") async throws -> [InquirySummary] {
        do {
            var args: [String: JSONValue] = ["entity": "inquiry", "limit": 40]
            if let status { args["status"] = .string(status) }
            let r = try await tool("list", site: site, args)
            return (r["items"]?.array ?? []).map { InquirySummary(site: site, $0) }
        } catch APIError.tool {
            return []
        }
    }

    /// 流量（days：1＝今天）
    func traffic(site: String, days: Int = 7) async throws -> TrafficReport {
        TrafficReport(try await tool("traffic_report", site: site, ["days": .number(Double(days))]))
    }

    /// 營運報表（days：1＝昨天）
    func ops(site: String, days: Int = 1) async throws -> OpsReport {
        OpsReport(try await tool("ops_report", site: site, ["section": "orders", "days": .number(Double(days))]))
    }

    // MARK: 寫（回提案，確認後才執行）

    /// 改一張訂單：狀態、物流單號
    func proposeOrderUpdate(site: String, id: String, status: String? = nil, trackingNumber: String? = nil) async throws -> WriteOutcome {
        var args: [String: JSONValue] = ["id": .string(id)]
        if let status { args["status"] = .string(status) }
        if let trackingNumber { args["trackingNumber"] = .string(trackingNumber) }
        return try await propose("update_order", site: site, args)
    }

    /// 一次改很多張（最多 100）
    func proposeBulkStatus(site: String, ids: [String], status: String) async throws -> WriteOutcome {
        try await propose("bulk_update_orders", site: site, ["ids": .array(ids.map { .string($0) }), "status": .string(status)])
    }

    /// 退款（amountNtd 是「元」；不給＝全額退剩下的）
    func proposeRefund(site: String, id: String, amountNtd: Int?, note: String?) async throws -> WriteOutcome {
        var args: [String: JSONValue] = ["id": .string(id)]
        if let amountNtd { args["amountNtd"] = .number(Double(amountNtd)) }
        if let note, !note.isEmpty { args["note"] = .string(note) }
        return try await propose("refund_order", site: site, args)
    }

    /// 回客服信（寄信給客人；close：回完順便結案）
    func proposeReply(site: String, threadID: String, body: String, close: Bool) async throws -> WriteOutcome {
        var reply: [String: JSONValue] = ["id": .string(threadID), "body": .string(body)]
        if close { reply["close"] = true }
        return try await propose("reply_support", site: site, ["replies": [.object(reply)]])
    }

    /// 客服信的狀態：open / answered / closed
    func proposeThreadStatus(site: String, id: String, status: String) async throws -> WriteOutcome {
        try await propose("update", site: site, ["entity": "support_thread", "id": .string(id), "fields": ["status": .string(status)]])
    }
}
