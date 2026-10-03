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

    /// Xena 在網站上的客服對話（atelier-cms 的網站；黃毛丫頭的官網＋LINE。沒有就回空的）
    /// status：open＝等專人＋專人處理中（黃毛丫頭的網站照這個篩；atelier-cms 的網站不認得，回最近的，由呼叫的人自己篩）
    func xenaConversations(site: String, status: String? = "open") async throws -> [XenaConversationSummary] {
        do {
            var args: [String: JSONValue] = ["entity": "assistant_conversation", "limit": 40]
            if let status { args["status"] = .string(status) }
            let r = try await tool("list", site: site, args)
            return (r["items"]?.array ?? []).map { XenaConversationSummary(site: site, $0) }
        } catch let error as APIError {
            // 這個網站沒有這種資料（或不給看）：當作沒有
            switch error {
            case .tool, .rpc, .scope: return []
            default: throw error
            }
        }
    }

    func xenaConversation(site: String, id: String) async throws -> XenaConversationDetail {
        XenaConversationDetail(try await tool("get", site: site, ["entity": "assistant_conversation", "id": .string(id)]))
    }

    /// 專案詢問（只有 atelier-cms 的網站有；沒有就回空的）
    func inquiries(site: String, status: String? = "new") async throws -> [InquirySummary] {
        do {
            var args: [String: JSONValue] = ["entity": "inquiry", "limit": 40]
            if let status { args["status"] = .string(status) }
            let r = try await tool("list", site: site, args)
            return (r["items"]?.array ?? []).map { InquirySummary(site: site, $0) }
        } catch let error as APIError {
            // 這個網站沒有這種資料（或不給看）：當作沒有
            switch error {
            case .tool, .rpc, .scope: return []
            default: throw error
            }
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

    /// Google 搜尋成效（days：往回幾天，預設 28）
    func searchReport(site: String, days: Int = 28) async throws -> SearchReport {
        SearchReport(try await tool("search_report", site: site, ["days": .number(Double(days))]))
    }

    // MARK: 內容與資料（網站後台的 list / get，照 /api/app/schema 的實體）

    /// 一種資料的清單（篩選：query、publishedOnly、activeOnly、status、limit）
    func list(site: String, entity: String, query: String? = nil, filters: [String: JSONValue] = [:]) async throws -> (rows: [RecordSummary], raw: JSONValue) {
        var args = filters
        args["entity"] = .string(entity)
        if let query, !query.isEmpty { args["query"] = .string(query) }
        let r = try await tool("list", site: site, args)
        return (RecordSummary.rows(in: r, entity: entity), r)
    }

    /// 一筆的完整內容（每種資料的形狀不一樣，畫面自己挑）
    func get(site: String, entity: String, id: String?) async throws -> JSONValue {
        var args: [String: JSONValue] = ["entity": .string(entity)]
        if let id { args["id"] = .string(id) }
        return try await tool("get", site: site, args)
    }

    /// 跨訂單、會員、折價券、商品搜尋（有商店的網站）
    func search(site: String, query: String) async throws -> JSONValue {
        try await tool("search", site: site, ["query": .string(query)])
    }

    // MARK: 寫（回提案，確認後才執行）

    /// 修改一筆：只送改過的欄位（網站會列出「舊 → 新」讓你確認）
    func proposeUpdate(site: String, entity: String, id: String?, fields: [String: JSONValue]) async throws -> WriteOutcome {
        var args: [String: JSONValue] = ["entity": .string(entity), "fields": .object(fields)]
        if let id { args["id"] = .string(id) }
        return try await propose("update", site: site, args)
    }

    /// 新增一筆
    func proposeCreate(site: String, entity: String, fields: [String: JSONValue]) async throws -> WriteOutcome {
        try await propose("create", site: site, ["entity": .string(entity), "fields": .object(fields)])
    }

    /// 刪除一筆（要打字確認：刪除、刪除商品…）
    func proposeDelete(site: String, entity: String, id: String) async throws -> WriteOutcome {
        try await propose("delete", site: site, ["entity": .string(entity), "id": .string(id)])
    }

    /// 圖片：移除、換主圖、整體重排（網站會列出前後張數讓你確認）
    func proposeImages(site: String, entity: String, id: String, remove: [String]? = nil, setCover: String? = nil, order: [String]? = nil) async throws -> WriteOutcome {
        var args: [String: JSONValue] = ["entity": .string(entity), "id": .string(id)]
        if let remove { args["remove"] = .array(remove.map { .string($0) }) }
        if let setCover { args["setCover"] = .string(setCover) }
        if let order { args["images"] = .array(order.map { .string($0) }) }
        return try await propose("set_images", site: site, args)
    }

    /// 上傳圖片：先跟網站要一次性的上傳連結（30 分鐘、一次），再把檔案送過去
    func uploadImage(site: String, entity: String, id: String, data: Data, mime: String, position: Int? = nil) async throws -> [String] {
        var args: [String: JSONValue] = ["entity": .string(entity), "id": .string(id), "requestUpload": true]
        if let position { args["position"] = .number(Double(position)) }
        let r = try await tool("set_images", site: site, args)
        guard let link = r["uploadUrl"]?.string.flatMap(URL.init(string:)) else { throw APIError.tool("網站沒有給上傳連結") }
        let ext = mime.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "jpeg", with: "jpg") ?? "jpg"
        return try await upload(to: link, data: data, mime: mime, filename: "studiox-app.\(ext)")
    }

    /// 發折價券給會員（每人一張一次性的券，排入通知）
    func proposeIssueCoupons(site: String, userIDs: [String], fields: [String: JSONValue]) async throws -> WriteOutcome {
        try await propose("issue_coupons", site: site, ["userIds": .array(userIDs.map { .string($0) }), "fields": .object(fields)])
    }

    /// 確認收到匯款（要打「確認收款」；只有看過帳單才能按）
    func proposeConfirmTransfer(site: String, orderID: String) async throws -> WriteOutcome {
        try await propose("confirm_bank_transfer", site: site, ["id": .string(orderID)])
    }

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

    /// Xena 對話的專人動作（reply_xena）：reply（text 必填；官網的出現在客人的 Xena 裡、LINE 的傳到客人的 LINE）、
    /// takeover、release（交還 Xena）、close、reopen
    func proposeXena(site: String, id: String, action: String, text: String? = nil) async throws -> WriteOutcome {
        var args: [String: JSONValue] = ["id": .string(id), "action": .string(action)]
        if let text { args["text"] = .string(text) }
        return try await propose("reply_xena", site: site, args)
    }

    /// 專人回覆：文字＋附的照片、檔案（先上傳好的）、行銷卡片、商品卡片（網站的 reply_xena）
    func proposeXenaReply(site: String, id: String, text: String, attachments: [UploadedAttachment], card: StaffCard?, products: [String]) async throws -> WriteOutcome {
        var args: [String: JSONValue] = ["id": .string(id), "action": "reply"]
        if !text.isEmpty { args["text"] = .string(text) }
        if !attachments.isEmpty { args["attachments"] = .array(attachments.map(\.json)) }
        if let card { args["card"] = card.json }
        if !products.isEmpty { args["products"] = .array(products.map { .string($0) }) }
        return try await propose("reply_xena", site: site, args)
    }

    /// 附件的一次性上傳連結（reply_xena 的 attach：只是上傳，不用確認、不會傳給客人）
    func xenaAttachLink(site: String, id: String, name: String, mime: String, size: Int) async throws -> URL {
        let r = try await tool("reply_xena", site: site, [
            "id": .string(id), "action": "attach", "name": .string(name), "mime": .string(mime), "size": .number(Double(size)),
        ])
        guard let s = r["uploadUrl"]?.string, let url = URL(string: s) else {
            throw APIError.tool(r["message"]?.string ?? "網站沒有給上傳連結（可能還沒更新）")
        }
        return url
    }

    /// 客服信的狀態：open / answered / closed
    func proposeThreadStatus(site: String, id: String, status: String) async throws -> WriteOutcome {
        try await propose("update", site: site, ["entity": "support_thread", "id": .string(id), "fields": ["status": .string(status)]])
    }
}
