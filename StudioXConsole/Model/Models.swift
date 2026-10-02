import SwiftUI
import UIKit

// 正式資料：/api/app/me 與各網站的工具（MCP，經 console 的閘道）回來的 JSON。
// 欄位名稱照 atelier-cms 與 yellowgirl-website 的 mcp-entities.ts、mcp-tools.ts、analytics.ts、ops-report.ts。
// 金額在資料庫是「分」（1/100 元），*Label 是排好的字串（NT$1,234）。

/// 分 → NT$1,234
func ntd(cents: Int) -> String {
    "NT$" + Int((Double(cents) / 100).rounded()).formatted(.number)
}

// MARK: - 登入的人與網站（GET /api/app/me）

struct Me {
    var id: String
    var name: String
    var email: String
    var imageURL: URL?
    /// StudioX 員工
    var staff: Bool
    var sites: [SiteSummary]

    init(_ json: JSONValue) {
        let u = json["user"] ?? .null
        id = u["id"]?.string ?? ""
        email = u["email"]?.string ?? ""
        name = u["name"]?.string ?? email.split(separator: "@").first.map(String.init) ?? "你"
        imageURL = u["image"]?.string.flatMap(URL.init(string:))
        staff = u["staff"]?.bool ?? false
        sites = (json["sites"]?.array ?? []).map(SiteSummary.init)
    }
}

struct SiteSummary: Identifiable {
    /// 網站代號（呼叫工具時帶的 site，例如 yellowgirl.tw）
    let id: String
    var name: String
    var org: String?
    var url: URL?
    /// 進後台（console 單一登入）
    var adminURL: URL?
    var levelLabel: String
    var iconImage: UIImage?
    var iconFill: Bool
    /// 他在這個網站能用的工具
    var tools: Set<String>
    var stats: SiteStatsSummary?

    init(_ json: JSONValue) {
        id = json["site"]?.string ?? ""
        name = json["name"]?.string ?? id
        org = json["org"]?.string
        url = json["url"]?.string.flatMap(URL.init(string:))
        adminURL = json["adminUrl"]?.string.flatMap(URL.init(string:))
        levelLabel = json["levelLabel"]?.string ?? ""
        let icon = json["icon"]
        iconImage = icon?["src"]?.string.flatMap(SiteSummary.decodeDataURL)
        iconFill = icon?["fill"]?.bool ?? false
        tools = Set((json["tools"]?.array ?? []).compactMap(\.string))
        stats = json["stats"].flatMap { $0.isNull ? nil : SiteStatsSummary($0) }
    }

    var host: String { url?.host() ?? id }
    /// 有商店（訂單、報表）
    var hasOrders: Bool { tools.contains("update_order") || tools.contains("ops_report") }
    /// 有客服信（support_thread、reply_support）
    var hasSupport: Bool { tools.contains("reply_support") }
    var hasTraffic: Bool { tools.contains("traffic_report") }
    var canRefund: Bool { tools.contains("refund_order") }

    /// data:image/png;base64,…（SVG 讀不了：改顯示名稱的第一個字）
    private static func decodeDataURL(_ src: String) -> UIImage? {
        guard src.hasPrefix("data:image/"), !src.hasPrefix("data:image/svg"), let comma = src.firstIndex(of: ",") else { return nil }
        guard let data = Data(base64Encoded: String(src[src.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }
}

struct SiteStatsSummary {
    var live: Int
    var visitors: Int
    var pageviews: Int
    /// 和前一期比（%）
    var change: Double?
    var trend: [Int]

    init(_ json: JSONValue) {
        live = json["live"]?.int ?? 0
        visitors = json["visitors"]?.int ?? 0
        pageviews = json["pageviews"]?.int ?? 0
        change = json["change"]?.double
        trend = (json["trend"]?.array ?? []).map { $0["visitors"]?.int ?? 0 }
    }
}

// MARK: - 訂單

/// 訂單狀態（order-status-labels.ts）
struct OrderStatus: Hashable {
    let raw: String

    static let pending = OrderStatus(raw: "pending")
    static let awaitingPayment = OrderStatus(raw: "awaiting_payment")
    static let paid = OrderStatus(raw: "paid")
    static let shipped = OrderStatus(raw: "shipped")
    static let completed = OrderStatus(raw: "completed")
    static let cancelled = OrderStatus(raw: "cancelled")

    var label: String {
        switch raw {
        case "pending": "待付款"
        case "awaiting_payment": "待繳費"
        case "paid": "已付款"
        case "shipped": "已出貨"
        case "completed": "已完成"
        case "cancelled": "已取消"
        default: raw.isEmpty ? "—" : raw
        }
    }

    var tone: Tone {
        switch raw {
        case "paid": .gold
        case "pending", "awaiting_payment": .warning
        case "shipped": .info
        case "completed": .active
        default: .neutral
        }
    }
}

struct OrderSummary: Identifiable, Hashable {
    let id: String
    var site: String
    var number: String
    var status: OrderStatus
    var totalLabel: String
    var customer: String
    var createdAt: Date?
    var paidAt: Date?
    var trackingNumber: String?
    var refundStatus: String?
    var isBankTransfer: Bool

    init(site: String, _ json: JSONValue) {
        id = json["id"]?.string ?? UUID().uuidString
        self.site = site
        number = json["orderNumber"]?.string ?? ""
        status = OrderStatus(raw: json["status"]?.string ?? "")
        totalLabel = json["totalLabel"]?.string ?? ntd(cents: json["total"]?.int ?? 0)
        customer = json["shippingName"]?.string ?? ""
        createdAt = json["createdAt"]?.date
        paidAt = json["paidAt"]?.date
        trackingNumber = json["trackingNumber"]?.string
        refundStatus = json["refundStatus"]?.string
        isBankTransfer = json["paymentProvider"]?.string == "bank_transfer"
    }
}

struct OrderLine: Identifiable {
    let id: String
    var name: String
    var variant: String?
    var quantity: Int
    var unitCents: Int

    var totalCents: Int { unitCents * quantity }
}

/// 匯款單：客人回報的戶名／後五碼（是客人說的，不是驗證過的）
struct BankTransferInfo {
    var name: String?
    var last5: String?
    var deadline: Date?
    var awaiting: Bool
}

struct OrderDetail {
    var summary: OrderSummary
    var lines: [OrderLine]
    var subtotalCents: Int
    var shippingFeeCents: Int
    var discountCents: Int
    var totalCents: Int
    var refundCents: Int
    var phone: String
    var email: String?
    var address: String
    var shippingMethod: String
    var paymentLabel: String
    var note: String?
    var invoiceNumber: String?
    var trackURL: URL?
    var packingSlipURL: URL?
    var adminURL: URL?
    var bankTransfer: BankTransferInfo?

    init(site: String, _ json: JSONValue) {
        let o = json["order"] ?? .null
        summary = OrderSummary(site: site, o)
        lines = (json["items"]?.array ?? []).enumerated().map { i, item in
            OrderLine(
                id: item["id"]?.string ?? "\(i)",
                name: item["productName"]?.string ?? "商品",
                variant: item["variantName"]?.string,
                quantity: item["quantity"]?.int ?? 1,
                unitCents: item["unitPrice"]?.int ?? 0
            )
        }
        subtotalCents = o["subtotal"]?.int ?? 0
        shippingFeeCents = o["shippingFee"]?.int ?? 0
        discountCents = o["discountAmount"]?.int ?? 0
        totalCents = o["total"]?.int ?? 0
        refundCents = o["refundAmount"]?.int ?? 0
        phone = o["shippingPhone"]?.string ?? ""
        email = o["email"]?.string
        if let store = o["cvsStoreName"]?.string {
            address = "\(store)（門市）"
        } else {
            address = o["shippingAddress"]?.string ?? ""
        }
        shippingMethod = OrderDetail.shippingLabel(o["shippingMethod"]?.string ?? "")
        paymentLabel = OrderDetail.paymentLabel(o["paymentProvider"]?.string ?? "")
        let rawNote = o["note"]?.string ?? ""
        note = rawNote.isEmpty ? nil : rawNote
        invoiceNumber = o["invoiceNumber"]?.string
        trackURL = json["trackUrl"]?.string.flatMap(URL.init(string:))
        packingSlipURL = json["packingSlipUrl"]?.string.flatMap(URL.init(string:))
        adminURL = json["adminUrl"]?.string.flatMap(URL.init(string:))
        if let b = json["bankTransfer"], !b.isNull {
            bankTransfer = BankTransferInfo(
                name: b["customerReportedName"]?.string,
                last5: b["customerReportedLast5"]?.string,
                deadline: b["deadline"]?.date,
                awaiting: b["awaitingConfirmation"]?.bool ?? false
            )
        }
    }

    private static func shippingLabel(_ raw: String) -> String {
        switch raw {
        case "home_tcat_cold": "黑貓宅配・冷藏"
        case "cvs_711": "7-11 取貨"
        case "home": "宅配"
        case "cvs_familymart": "全家取貨"
        default: raw
        }
    }

    private static func paymentLabel(_ raw: String) -> String {
        switch raw {
        case "bank_transfer": "銀行轉帳"
        case "payuni": "統一金流（PAYUNi）"
        case "ecpay": "綠界"
        default: raw
        }
    }
}

// MARK: - 客服信（support_thread）

struct SupportThreadSummary: Identifiable, Hashable {
    let id: String
    var site: String
    var subject: String
    var categoryLabel: String
    var status: String
    var statusLabel: String
    var waitingHours: Double?
    var messageCount: Int
    var orderNumber: String?
    var customer: String

    init(site: String, _ json: JSONValue) {
        id = json["id"]?.string ?? UUID().uuidString
        self.site = site
        subject = json["subject"]?.string ?? "（沒有主旨）"
        categoryLabel = json["categoryLabel"]?.string ?? ""
        status = json["status"]?.string ?? "open"
        statusLabel = json["statusLabel"]?.string ?? ""
        waitingHours = json["waitingHours"]?.double
        messageCount = json["messageCount"]?.int ?? 0
        orderNumber = json["orderNumber"]?.string
        customer = json["customer"]?.string ?? json["contactName"]?.string ?? json["contactEmail"]?.string ?? "客人"
    }

    var tone: Tone {
        switch status {
        case "open": .warning
        case "answered": .active
        default: .neutral
        }
    }
}

struct SupportMessage: Identifiable {
    let id: String
    /// in＝客人、out＝我們
    var fromCustomer: Bool
    var body: String
    var author: String
    var at: Date?
    var attachments: [String]
    var emailError: String?
}

struct CustomerOrder: Identifiable {
    let id: String
    var number: String
    var statusLabel: String
    var totalLabel: String
    var items: String
}

struct SupportThreadDetail {
    var summary: SupportThreadSummary
    var contactEmail: String
    var messages: [SupportMessage]
    var memberName: String?
    var memberTier: String?
    var memberSpend: String?
    var orders: [CustomerOrder]
    var adminURL: URL?

    init(site: String, _ json: JSONValue) {
        let t = json["thread"] ?? .null
        summary = SupportThreadSummary(site: site, t)
        contactEmail = t["contactEmail"]?.string ?? ""
        messages = (t["messages"]?.array ?? []).enumerated().map { i, m in
            SupportMessage(
                id: m["id"]?.string ?? "\(i)",
                fromCustomer: m["direction"]?.string == "in",
                body: m["body"]?.string ?? "",
                author: m["author"]?.string ?? "",
                at: m["createdAt"]?.date,
                attachments: (m["attachments"]?.array ?? []).compactMap { $0["name"]?.string },
                emailError: m["emailError"]?.string
            )
        }
        let c = json["customer"] ?? .null
        let member = c["member"]
        memberName = member?["name"]?.string
        memberTier = member?["tierName"]?.string
        memberSpend = member?["lifetimeSpendLabel"]?.string
        orders = (c["orders"]?.array ?? []).map {
            CustomerOrder(
                id: $0["id"]?.string ?? UUID().uuidString,
                number: $0["orderNumber"]?.string ?? "",
                statusLabel: $0["statusLabel"]?.string ?? "",
                totalLabel: $0["totalLabel"]?.string ?? "",
                items: $0["itemSummary"]?.string ?? ""
            )
        }
        adminURL = json["adminUrl"]?.string.flatMap(URL.init(string:))
    }
}

// MARK: - Xena 的客服對話（assistant_conversation，atelier-cms 的網站）

struct XenaConversationSummary: Identifiable, Hashable {
    let id: String
    var site: String
    var at: Date?
    /// ai（Xena 回答中）/ waiting（等專人）/ human（專人接手）/ closed
    var status: String
    var tags: [String]
    var contactName: String?
    var turns: Int
    var firstQuestion: String?

    init(site: String, _ json: JSONValue) {
        id = json["id"]?.string ?? UUID().uuidString
        self.site = site
        at = json["at"]?.date
        status = json["status"]?.string ?? "ai"
        tags = (json["tags"]?.array ?? []).compactMap(\.string)
        let contact = json["contact"]
        contactName = contact?["name"]?.string ?? contact?["email"]?.string ?? json["signedIn"]?.string
        turns = json["turns"]?.int ?? 0
        firstQuestion = json["questions"]?.array.first?.string
    }

    var statusLabel: String {
        switch status {
        case "ai": "Xena 回答中"
        case "waiting": "等專人"
        case "human": "專人接手"
        case "closed": "已結案"
        default: status
        }
    }

    var tone: Tone {
        switch status {
        case "waiting": .warning
        case "human": .gold
        case "closed": .neutral
        default: .info
        }
    }
}

struct XenaConversationMessage: Identifiable {
    let id: Int
    /// user（訪客）/ assistant（Xena）/ staff（專人）/ event
    var role: String
    var content: String
    var author: String?
    var at: Date?
}

// MARK: - 專案詢問（inquiry，atelier-cms 的網站）

struct InquirySummary: Identifiable, Hashable {
    let id: String
    var site: String
    var at: Date?
    /// new / replied / archived
    var status: String
    var name: String
    var company: String?
    var email: String
    var types: [String]
    var budget: String?
    var message: String?

    init(site: String, _ json: JSONValue) {
        id = json["id"]?.string ?? UUID().uuidString
        self.site = site
        at = json["at"]?.date
        status = json["status"]?.string ?? "new"
        name = json["name"]?.string ?? ""
        company = json["company"]?.string
        email = json["email"]?.string ?? ""
        types = (json["types"]?.array ?? []).compactMap(\.string)
        budget = json["budget"]?.string
        message = json["message"]?.string
    }
}

// MARK: - 報表

struct TrafficPoint: Identifiable {
    var id: String { label }
    let label: String
    let visitors: Int
    let pageviews: Int
}

struct TrafficTop: Identifiable {
    var id: String { key }
    let key: String
    let visitors: Int
}

struct ChannelShare: Identifiable {
    var id: String { name }
    let name: String
    let visits: Int
}

/// 流量（traffic_report）
struct TrafficReport {
    var installed: Bool
    var live: Int
    var visitors: Int
    var pageviews: Int
    var bounceRate: Double?
    var avgDurationMs: Double?
    /// 和前一期比（%）
    var change: Double?
    var trend: [TrafficPoint]
    var pages: [TrafficTop]
    var referrers: [TrafficTop]
    var channels: [ChannelShare]

    init(_ json: JSONValue) {
        installed = json["installed"]?.bool ?? true
        live = json["live"]?.int ?? 0
        visitors = json["visitors"]?.int ?? 0
        pageviews = json["pageviews"]?.int ?? 0
        bounceRate = json["bounceRate"]?.double
        avgDurationMs = json["avgDurationMs"]?.double
        change = json["change"]?["visitors"]?.double
        trend = (json["trend"]?.array ?? []).map {
            TrafficPoint(label: TrafficReport.shortLabel($0["label"]?.string ?? ""), visitors: $0["visitors"]?.int ?? 0, pageviews: $0["pageviews"]?.int ?? 0)
        }
        pages = TrafficReport.tops(json["pages"])
        referrers = TrafficReport.tops(json["referrers"])
        channels = (json["channels"]?.array ?? []).map {
            ChannelShare(name: TrafficReport.channelLabel($0["channel"]?.string ?? ""), visits: $0["visits"]?.int ?? 0)
        }
    }

    /// "2026-10-02" → "10/2"；"2026-10-02T14" → "14時"
    private static func shortLabel(_ raw: String) -> String {
        if raw.contains("T"), let hour = raw.split(separator: "T").last {
            return "\(Int(hour) ?? 0)時"
        }
        let parts = raw.split(separator: "-")
        guard parts.count == 3 else { return raw }
        return "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)"
    }

    private static func tops(_ json: JSONValue?) -> [TrafficTop] {
        (json?.array ?? []).map { TrafficTop(key: $0["key"]?.string ?? "（直接輸入）", visitors: $0["visitors"]?.int ?? 0) }
    }

    private static func channelLabel(_ raw: String) -> String {
        switch raw {
        case "direct": "直接輸入"
        case "search": "搜尋引擎"
        case "social": "社群"
        case "referral": "其他網站"
        case "campaign": "行銷活動"
        default: raw
        }
    }
}

/// 營運報表（ops_report section=orders；days=1 是「昨天」，台北時間）
struct OpsReport {
    var summary: String
    var rangeLabel: String
    var createdTotal: Int
    var paidCount: Int
    var revenueCents: Int
    var awaitingPayment: Int
    var paidButUnfulfilled: Int
    var notificationsOverdue: Int
    var supportAwaiting: Int
    var oldestWaitHours: Int?
    var unmatchedInbound: Int
    var alerts: [String]

    init(_ json: JSONValue) {
        summary = json["summary"]?.string ?? ""
        rangeLabel = json["range"]?["label"]?.string ?? ""
        createdTotal = json["created"]?["total"]?.int ?? 0
        paidCount = json["paid"]?["count"]?.int ?? 0
        revenueCents = json["paid"]?["revenueCents"]?.int ?? 0
        awaitingPayment = json["awaitingPayment"]?.int ?? 0
        paidButUnfulfilled = json["paidButUnfulfilled"]?.int ?? 0
        notificationsOverdue = json["notificationsOverdue"]?.int ?? 0
        let s = json["support"] ?? .null
        supportAwaiting = s["awaitingReply"]?.int ?? 0
        oldestWaitHours = s["oldestWaitHours"]?.int
        unmatchedInbound = s["unmatchedInbound"]?.int ?? 0
        alerts = (json["alerts"]?.array ?? []).compactMap(\.string)
    }
}

// MARK: - 要確認的寫入（兩步驟：第一次回 needsConfirmation，確認後用一樣的參數加 confirmToken 再送）

struct Proposal: Identifiable {
    let id = UUID()
    let tool: String
    let site: String
    let args: [String: JSONValue]
    var title: String
    var detail: String
    var danger: Bool
    /// 要打的字（退款、刪除…）
    var typed: String?
    let confirmToken: String
    /// 店主核准（退款超過門檻）：確認之後才會出現
    var ownerRequestID: String?
    var ownerTitle: String?
    var ownerDetail: String?
}
