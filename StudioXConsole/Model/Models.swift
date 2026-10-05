import SwiftUI
import UIKit

// 正式資料：/api/app/me 與各網站的工具（MCP，經 console 的閘道）回來的 JSON。
// 欄位名稱照 atelier-cms 與 yellowgirl-website 的 mcp-entities.ts、mcp-tools.ts、analytics.ts、ops-report.ts。
// 金額在資料庫是「分」（1/100 元），*Label 是排好的字串（NT$1,234）。

/// 分 → NT$1,234
func ntd(cents: Int) -> String {
    "NT$" + Int((Double(cents) / 100).rounded()).formatted(.number)
}

/// 分 → 窄的地方用的短寫法：NT$9,860、NT$1.3萬、NT$12萬（一萬以上用「萬」）
func ntdShort(cents: Int) -> String {
    let amount = Double(cents) / 100
    guard abs(amount) >= 10_000 else { return ntd(cents: cents) }
    let wan = amount / 10_000
    return "NT$" + wan.formatted(.number.precision(.fractionLength(0...(abs(wan) < 10 ? 1 : 0)))) + "萬"
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
    /// Xena 的客服對話可以在 App 裡回覆、接手（reply_xena；官網＋LINE）
    var hasXenaDesk: Bool { tools.contains("reply_xena") }
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

/// 配送進度（和客人的追蹤頁同一份）：黑貓宅配四站走到哪、目前的貨態、時間軸
struct Shipment {
    /// tcat＝黑貓宅配；其他是網站的運送方式代號（超商取貨…）
    var carrier: String?
    var trackingNumber: String?
    /// 到黑貓查詢
    var carrierTrackURL: URL?
    /// 新的在前
    var events: [ShipmentEvent]

    init(_ json: JSONValue) {
        carrier = json["carrier"]?.string
        trackingNumber = json["trackingNumber"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        carrierTrackURL = json["carrierTrackUrl"]?.string.flatMap(URL.init(string:))
        events = (json["events"]?.array ?? []).enumerated().map { ShipmentEvent(index: $0.offset, $0.element) }
    }

    /// 黑貓的四站
    static let steps = ["黑貓收件", "轉運中", "配送中", "已送達"]

    var isTcat: Bool { carrier == "tcat" }

    /// 走到第幾站（-1＝黑貓還沒收件）；訂單已完成就是最後一站
    func step(completed: Bool) -> Int {
        if completed { return Self.steps.count - 1 }
        return events.reduce(-1) { max($0, $1.step) }
    }

    /// 最新的一筆是異常（不在家、退回、暫置…）
    var exception: Bool {
        guard let current = events.first, current.stage != "delivered", current.stage != "picked_up" else { return false }
        return current.stage == "exception" || ["退回", "不在", "異常", "拒收", "暫置", "地址不明", "破損"].contains { current.status.contains($0) }
    }
}

struct ShipmentEvent: Identifiable {
    let id: Int
    /// 物流商的原文（「已集貨」）；括號裡的營業所拆到 office
    var status: String
    var office: String?
    /// accepted／in_transit／out_for_delivery／delivered／in_store／picked_up／exception
    var stage: String?
    var at: Date?

    init(index: Int, _ json: JSONValue) {
        id = index
        let text = (json["status"]?.string ?? "").trimmingCharacters(in: .whitespaces)
        // 「已集貨（新竹營業所）」→ 已集貨、新竹營業所
        if let open = text.lastIndex(of: "（"), text.hasSuffix("）"), open > text.startIndex {
            status = String(text[..<open])
            office = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
        } else {
            status = text.isEmpty ? "貨態更新" : text
        }
        stage = json["stage"]?.string
        at = json["at"]?.date
    }

    /// 這一筆代表黑貓走到第幾站（看不出來的算收件）
    var step: Int {
        switch stage {
        case "in_transit": 1
        case "out_for_delivery", "in_store": 2
        case "delivered", "picked_up": 3
        default: 0
        }
    }
}

/// 匯款單：客人回報的戶名／後五碼（是客人說的，不是驗證過的）
struct BankTransferInfo {
    var name: String?
    var last5: String?
    var deadline: Date?
    var awaiting: Bool
}

/// 訂單上的一筆折扣：用了哪張券（碼、名稱、優惠）、折了多少（網站 order.get 的 discounts）
struct OrderDiscount: Identifiable {
    let id: String
    var couponID: String?
    var code: String?
    var name: String?
    var note: String?
    /// fixed | percentage | free_shipping；對不上的差額是 other
    var type: String
    /// 網站的 AI 依客人的購物車給的專屬券
    var personalized: Bool
    /// 免運、9 折、88 折、折 NT$100
    var offer: String
    var cents: Int

    init(index: Int, _ json: JSONValue) {
        couponID = json["couponId"]?.string
        id = "\(index)-\(couponID ?? "other")"
        code = json["code"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        name = json["name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        note = json["description"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        type = json["type"]?.string ?? ""
        personalized = json["personalized"]?.bool ?? false
        offer = json["offer"]?.string ?? ""
        cents = json["amount"]?.int ?? 0
    }

    /// 這筆折扣叫什麼：券的名稱；沒取名的照種類
    var title: String {
        if let name { return name }
        if personalized { return "專屬優惠" }
        return switch type {
        case "free_shipping": "免運券"
        case "other": "其他折扣"
        default: "折價券"
        }
    }

    /// 小字：折價碼・優惠・AI 專屬券
    var detail: String {
        [code, offer.isEmpty || offer == title ? nil : offer, personalized ? "AI 專屬券" : nil]
            .compactMap { $0 }
            .joined(separator: "・")
    }
}

/// 下單的會員（訪客結帳沒有）
struct OrderMember {
    var id: String
    var name: String?
    var email: String?
    var tier: String?
    /// 付款完成的訂單數（含這張，如果這張已付款）
    var paidOrderCount: Int
    var lifetimeSpendCents: Int

    init?(_ json: JSONValue?) {
        guard let json, let id = json["id"]?.string else { return nil }
        self.id = id
        name = json["name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        email = json["email"]?.string
        tier = json["tier"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        paidOrderCount = json["paidOrderCount"]?.int ?? 0
        lifetimeSpendCents = json["lifetimeSpendCents"]?.int ?? 0
    }
}

struct OrderDetail {
    var summary: OrderSummary
    var lines: [OrderLine]
    var subtotalCents: Int
    var shippingFeeCents: Int
    var discountCents: Int
    /// 每一筆折扣的名目；舊版網站沒有這欄時是空的，只顯示總折扣
    var discounts: [OrderDiscount]
    /// 下單的會員；nil 是訪客結帳（isGuest）或網站還沒提供
    var member: OrderMember?
    /// 訪客結帳（沒有登入會員）
    var isGuest: Bool
    var totalCents: Int
    var refundCents: Int
    var phone: String
    var email: String?
    var address: String
    var shippingMethod: String
    var paymentLabel: String
    var note: String?
    var invoiceNumber: String?
    /// 發票：個人（載具）／公司（統編、抬頭）／捐贈（愛心碼）
    var invoiceText: String?
    var trackingNumber: String?
    /// 貨態（黑貓的「順利送達」或 PAYUNi 的代碼）與更新時間
    var logisticsStatus: String?
    var logisticsUpdatedAt: Date?
    /// 7-11 取貨單號（客人到店出示）
    var cvsPaymentNo: String?
    var refundNote: String?
    var waybillURL: URL?
    var trackURL: URL?
    var packingSlipURL: URL?
    var adminURL: URL?
    var bankTransfer: BankTransferInfo?
    /// 最後一次改狀態的時間（進度條上「現在這一站」的時間）
    var updatedAt: Date?
    /// 配送進度：物流商回報的貨態（網站的 get order 有 logistics 才有）
    var shipment: Shipment?

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
        discounts = (json["discounts"]?.array ?? []).enumerated()
            .map { OrderDiscount(index: $0, $1) }
            .filter { $0.cents > 0 }
        member = OrderMember(json["member"])
        isGuest = o["userId"].map(\.isNull) ?? false
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
        invoiceText = OrderDetail.invoiceText(o)
        trackingNumber = o["trackingNumber"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        logisticsStatus = o["logisticsStatus"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        logisticsUpdatedAt = o["logisticsStatusUpdatedAt"]?.date
        cvsPaymentNo = o["cvsPaymentNo"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        refundNote = o["refundNote"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        waybillURL = o["waybillPdfUrl"]?.string.flatMap(URL.init(string:))
        trackURL = json["trackUrl"]?.string.flatMap(URL.init(string:))
        packingSlipURL = json["packingSlipUrl"]?.string.flatMap(URL.init(string:))
        adminURL = json["adminUrl"]?.string.flatMap(URL.init(string:))
        updatedAt = o["updatedAt"]?.date
        if let l = json["logistics"], !l.isNull {
            shipment = Shipment(l)
        }
        if let b = json["bankTransfer"], !b.isNull {
            bankTransfer = BankTransferInfo(
                name: b["customerReportedName"]?.string,
                last5: b["customerReportedLast5"]?.string,
                deadline: b["deadline"]?.date,
                awaiting: b["awaitingConfirmation"]?.bool ?? false
            )
        }
    }

    private static func invoiceText(_ o: JSONValue) -> String? {
        let v = { (k: String) in o[k]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        switch v("invoiceType") {
        case "company":
            return ["公司戶", v("invoiceTaxId").map { "統編 \($0)" }, v("invoiceTitle")].compactMap { $0 }.joined(separator: "・")
        case "donation":
            return "捐贈" + (v("invoiceDonationCode").map { "・愛心碼 \($0)" } ?? "")
        case "personal":
            let carrier: String? = switch v("invoiceCarrierType") {
            case "mobile": "手機條碼"
            case "natural": "自然人憑證"
            case "email": "Email 載具"
            case "payuni": "PAYUNi 會員載具"
            default: nil
            }
            return ["個人", carrier, v("invoiceCarrierCode")].compactMap { $0 }.joined(separator: "・")
        default:
            return nil
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
    /// 好幾個網站放在一起的清單用（id 只在同一個網站裡不重複）
    var key: String { "\(site)|\(id)" }
    var subject: String
    var categoryLabel: String
    var status: String
    var statusLabel: String
    var waitingHours: Double?
    var messageCount: Int
    var orderNumber: String?
    var customer: String
    /// 最後一封的時間（紀錄照這個排；舊版網站沒給就是建立時間）
    var at: Date?
    /// 最後一封的開頭（客人寫的照原樣，我們寫的前面標「我們：」）
    var lastMessage: String?

    init(site: String, _ json: JSONValue) {
        id = json["id"]?.string ?? UUID().uuidString
        self.site = site
        at = json["lastMessageAt"]?.date ?? json["lastMessage"]?["at"]?.date ?? json["createdAt"]?.date
        if let last = json["lastMessage"], let text = last["text"]?.string, !text.isEmpty {
            lastMessage = last["fromCustomer"]?.bool == false ? "我們：\(text)" : text
        }
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

// MARK: - Xena 的客服對話（assistant_conversation：atelier-cms 的網站、黃毛丫頭的官網＋LINE）

/// 對話從哪裡來：官網右下角的 Xena，或網站的 LINE 官方帳號（黃毛丫頭）
enum XenaChannel: String, Hashable, Sendable {
    case web, line

    init(_ raw: String?) { self = raw == "line" ? .line : .web }

    var label: String { self == .line ? "LINE" : "官網" }
    /// 專人的回覆會送到哪裡（對話頁的說明）
    var replyHint: String {
        self == .line ? "回覆會從官方帳號照原樣傳到客人的 LINE；第一次回覆前客人會看到「你的名字 接手了這段對話」" : "回覆會出現在客人網站上的 Xena 裡"
    }
}

struct XenaConversationSummary: Identifiable, Hashable {
    let id: String
    var site: String
    var key: String { "\(site)|\(id)" }
    var at: Date?
    /// ai（Xena 回答中）/ waiting（等專人）/ human（專人接手）/ closed
    var status: String
    var channel: XenaChannel
    /// 需要專人看（等人接手、接手後客人又說話還沒看）；網站沒給就照狀態算
    var attention: Bool
    var tags: [String]
    var contactName: String?
    /// LINE 好友的頭像
    var picture: URL?
    var turns: Int
    var firstQuestion: String?
    /// 最新的一句（收件匣的預覽）：客人說的照原樣，Xena、專人說的前面標出是誰
    var preview: String?

    init(site: String, _ json: JSONValue) {
        id = json["id"]?.string ?? UUID().uuidString
        self.site = site
        at = json["at"]?.date
        status = json["status"]?.string ?? "ai"
        channel = XenaChannel(json["channel"]?.string)
        attention = json["attention"]?.bool ?? (status == "waiting")
        tags = (json["tags"]?.array ?? []).compactMap(\.string)
        let contact = json["contact"]
        contactName = contact?["name"]?.string ?? contact?["email"]?.string ?? json["signedIn"]?.string ?? json["line"]?["name"]?.string
        picture = json["line"]?["picture"]?.string.flatMap(URL.init(string:))
        turns = json["turns"]?.int ?? 0
        let questions = (json["questions"]?.array ?? []).compactMap(\.string)
        firstQuestion = questions.first.map(VisitorPreview.text)
        if let last = json["last"], let text = last["text"]?.string, !text.isEmpty {
            switch last["role"]?.string {
            case "assistant": preview = "Xena：\(text)"
            case "staff": preview = "專人：\(text)"
            default: preview = VisitorPreview.text(text)
            }
        } else {
            preview = questions.last.map(VisitorPreview.text)
        }
    }

    /// 收件匣的分類：Jev 最近替這段對話判斷的類別（有別的類別時不用「閒聊」「其他」）
    var topic: String? {
        tags.last { !["閒聊", "其他"].contains($0) } ?? tags.last
    }

    /// 為什麼要專人看（要你處理的那一列）
    var attentionLabel: String {
        switch status {
        case "waiting": "等專人"
        case "human": "客人又傳了訊息"
        default: "留了聯絡資料"
        }
    }

    var statusLabel: String { XenaConversationSummary.label(status) }
    var tone: Tone { XenaConversationSummary.tone(status) }

    static func label(_ status: String) -> String {
        switch status {
        case "ai": "Xena 回答中"
        case "waiting": "等專人"
        case "human": "專人接手"
        case "closed": "已結案"
        default: status
        }
    }

    static func tone(_ status: String) -> Tone {
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
    /// Jev 的分類（「訂單查詢」…）
    var tag: String?
    /// Jev 判斷這一句要不要找人（機率 0–1）
    var jevHuman: (yes: Bool, confidence: Double)?
    /// Jev 判斷專人回這一句要不要 Xena 查資料：xena（請 Xena 分析）／quick（手機上的 Apple Intelligence 就夠）；舊的網站沒有
    var jevAssist: String?
    /// Xena 這一輪帶客人去的頁面（客人看到的是一顆按鈕）
    var navigate: (path: String, title: String)?
    /// 專人附的行銷卡片（LINE 上是品牌樣式的 Flex 卡片）
    var card: StaffCard?
    /// 專人推薦的商品（黃毛丫頭：LINE 上是左右滑的商品卡片）
    var products: [(name: String, slug: String)]
    /// role 是 event 的種類：handoff / takeover / release / closed / reopened / contact / login / logout（舊的網站沒有）
    var event: String?
    /// 專人回覆時也寄了信給客人
    var emailed: Bool

    init(id: Int, _ m: JSONValue) {
        self.id = id
        role = m["role"]?.string ?? "user"
        content = m["content"]?.string ?? ""
        author = m["author"]?.string
        at = m["at"]?.date
        tag = m["tag"]?.string
        if let jev = m["jev"], let yes = jev["human"]?.bool {
            jevHuman = (yes, jev["confidence"]?.double ?? 0)
        }
        jevAssist = m["jev"]?["assist"]?.string
        if let nav = m["navigate"], let path = nav["path"]?.string, !path.isEmpty {
            navigate = (path, nav["title"]?.string ?? path)
        }
        card = m["card"].flatMap(StaffCard.init)
        products = (m["products"]?.array ?? []).compactMap { p in
            guard let name = p["name"]?.string else { return nil }
            return (name, p["slug"]?.string ?? "")
        }
        event = m["event"]?.string
        emailed = m["emailed"]?.bool ?? false
    }

    /// 只是卡片的那一行字（「［卡片］標題」）：畫了卡片就不用再畫這行
    var isOnlyCardLabel: Bool {
        guard card != nil else { return false }
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.hasPrefix("［卡片］") || t.hasPrefix("[卡片]")
    }
}

/// Xena 想的回覆建議（console 的 /api/app/reply-suggest）：這位客人的分析、回覆用得到的事實、三種下一句
struct XenaReplySuggestion: Equatable {
    var brief: String
    var facts: [String]
    var replies: [String]
    /// 客人同一句話之後已經分析過（這次不算額度）
    var cached: Bool

    init(brief: String, facts: [String], replies: [String], cached: Bool = false) {
        self.brief = brief
        self.facts = facts
        self.replies = replies
        self.cached = cached
    }

    init(_ json: JSONValue) {
        brief = json["brief"]?.string ?? ""
        facts = (json["facts"]?.array ?? []).compactMap(\.string)
        replies = (json["replies"]?.array ?? []).compactMap(\.string).filter { !$0.isEmpty }
        cached = json["cached"]?.bool ?? false
    }
}

/// 專人回覆附的行銷卡片（網站的 lib/ai/staff-card.ts）
struct StaffCard {
    var title: String
    var body: String?
    var imageURL: URL?
    var couponCode: String?
    var buttonLabel: String?
    var url: URL?

    init?(_ json: JSONValue) {
        guard let title = json["title"]?.string, !title.isEmpty else { return nil }
        self.title = title
        body = json["body"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        imageURL = json["imageUrl"]?.string.flatMap(URL.init(string:))
        couponCode = json["couponCode"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        buttonLabel = json["buttonLabel"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        url = json["url"]?.string.flatMap(URL.init(string:))
    }

    init(title: String, body: String? = nil, imageURL: URL? = nil, couponCode: String? = nil, buttonLabel: String? = nil, url: URL? = nil) {
        self.title = title
        self.body = body
        self.imageURL = imageURL
        self.couponCode = couponCode
        self.buttonLabel = buttonLabel
        self.url = url
    }

    /// 送給網站的 reply_xena 的 card（空的欄位不送）
    var json: JSONValue {
        var o: [String: JSONValue] = ["title": .string(title)]
        if let body, !body.isEmpty { o["body"] = .string(body) }
        if let imageURL { o["imageUrl"] = .string(imageURL.absoluteString) }
        if let couponCode, !couponCode.isEmpty { o["couponCode"] = .string(couponCode) }
        if let buttonLabel, !buttonLabel.isEmpty { o["buttonLabel"] = .string(buttonLabel) }
        if let url { o["url"] = .string(url.absoluteString) }
        return .object(o)
    }
}

/// 傳到網站儲存的附件（reply_xena 的 attach → /api/upload/<token>），回覆時放進 attachments
struct UploadedAttachment: Hashable, Sendable {
    /// image | file
    var kind: String
    var url: String
    var name: String
    var size: Int
    var mime: String

    var json: JSONValue {
        ["kind": .string(kind), "url": .string(url), "name": .string(name), "size": .number(Double(size)), "mime": .string(mime)]
    }
}

/// 網站讓專人附照片、檔案的上限（get assistant_conversation 的 attach；網站還沒有檔案空間是 nil）
struct AttachLimits {
    var max: Int
    var imageBytes: Int
    var fileBytes: Int

    init?(_ json: JSONValue?) {
        guard let json, !json.isNull else { return nil }
        max = json["max"]?.int ?? 4
        imageBytes = json["imageBytes"]?.int ?? 1_048_576
        fileBytes = json["fileBytes"]?.int ?? 20_971_520
    }
}

/// 同一位 LINE 好友之前的一段對話
struct EarlierConversation: Identifiable {
    let id: String
    var startedAt: Date?
    var lastAt: Date?
    var statusLabel: String?
    var firstQuestion: String?
}

/// 一段 Xena 對話的全貌（網站有給的才有：還沒更新的網站只有訊息）
struct XenaConversationDetail {
    var status: String?
    var channel: XenaChannel
    var who: String?
    /// LINE 好友的頭像
    var picture: URL?
    var lineBlocked: Bool
    /// 客人現在開著網站（官網的對話）
    var visitorOnline: Bool
    var assignee: String?
    var handoffReason: String?
    var handoffAt: Date?
    var startedAt: Date?
    /// Jev 替這段對話分的類別
    var topics: [String]
    /// 回覆會送到哪裡（網站說的；沒有就照來源）
    var replyGoesTo: String?
    var messages: [XenaConversationMessage]
    var earlier: [EarlierConversation]
    /// 會員最近的訂單（黃毛丫頭：登入的會員、綁了 LINE 的客人）
    var orders: [CustomerOrder]
    var adminURL: URL?
    /// 專人回覆除了文字還能附什麼：card（行銷卡片）、products（商品卡片）、attachments（照片、檔案）
    var replyWith: Set<String>
    /// 照片、檔案的上限（網站還沒有檔案空間是 nil）
    var attach: AttachLimits?
    /// 登入的會員（黃毛丫頭）：可以點進會員頁、發專屬折價券
    var memberID: String?

    init(_ json: JSONValue) {
        status = json["status"]?.string
        channel = XenaChannel(json["channel"]?.string)
        // 會員（黃毛丫頭）或用 StudioX 登入的訪客（studiox.tw 的 identity）、LINE 好友、留過聯絡資料的
        let member = json["member"] ?? json["identity"]
        who = member?["name"]?.string ?? member?["email"]?.string ?? json["line"]?["name"]?.string ?? json["contact"]?["name"]?.string
        picture = json["line"]?["picture"]?.string.flatMap(URL.init(string:))
        lineBlocked = json["line"]?["following"]?.bool == false
        visitorOnline = json["visitorOnline"]?.bool ?? false
        assignee = json["assignee"]?.string
        handoffReason = json["handoff"]?["reason"]?.string ?? json["handoffReason"]?.string
        handoffAt = json["handoff"]?["at"]?.date
        startedAt = json["startedAt"]?.date
        // atelier-cms：tags 是代號、tagLabels 是中文；黃毛丫頭的 tags 就是中文
        topics = (json["tagLabels"]?.array ?? json["tags"]?.array ?? []).compactMap(\.string)
        replyGoesTo = json["replyGoesTo"]?.string
        messages = (json["messages"]?.array ?? []).enumerated().map { XenaConversationMessage(id: $0, $1) }
        earlier = (json["earlier"]?.array ?? []).compactMap { e in
            guard let id = e["id"]?.string else { return nil }
            return EarlierConversation(id: id, startedAt: e["startedAt"]?.date, lastAt: e["lastAt"]?.date, statusLabel: e["statusLabel"]?.string, firstQuestion: e["firstQuestion"]?.string)
        }
        orders = (json["orders"]?.array ?? []).compactMap { o in
            guard let id = o["id"]?.string else { return nil }
            return CustomerOrder(
                id: id,
                number: o["orderNumber"]?.string ?? "",
                statusLabel: o["statusLabel"]?.string ?? "",
                totalLabel: o["totalLabel"]?.string ?? "",
                items: o["itemSummary"]?.string ?? ""
            )
        }
        adminURL = json["adminUrl"]?.string.flatMap(URL.init(string:))
        // 還沒更新的網站沒有 replyWith：只確定能附行銷卡片
        replyWith = Set((json["replyWith"]?.array ?? ["card"]).compactMap(\.string))
        attach = AttachLimits(json["attach"])
        memberID = json["member"]?["id"]?.string
    }
}

// MARK: - 專案詢問（inquiry，atelier-cms 的網站）

struct InquirySummary: Identifiable, Hashable {
    let id: String
    var site: String
    var key: String { "\(site)|\(id)" }
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
    var id: String { key }
    /// 網站給的原始標籤（2026-10-02、2026-10-02T14）：一年的走勢裡 M/d 會重複，用這個當 id 與圖上的位置
    let key: String
    /// 10/2、14時
    let label: String
    let date: Date?
    let visitors: Int
    let pageviews: Int
}

struct TrafficTop: Identifiable {
    var id: String { key }
    let key: String
    let visitors: Int
    let pageviews: Int
}

struct ChannelShare: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let visits: Int
}

/// 購物漏斗（黃毛丫頭：進站 → 看商品 → 加入購物車 → 開始結帳 → 送出訂單）
struct FunnelStep: Identifiable {
    var id: String { step }
    let step: String
    let label: String
    let visitors: Int
}

struct FunnelProduct: Identifiable {
    var id: String { slug }
    let name: String
    let slug: String
    let viewers: Int
    let adders: Int
}

/// 內容頁帶來的生意（黃毛丫頭的 contentPages：看了這頁的人有多少去看商品、加購物車、下單）
struct ContentPageImpact: Identifiable {
    var id: String { path }
    let path: String
    let visitors: Int
    let viewed: Int
    let carted: Int
    let ordered: Int
}

/// 流量（traffic_report；atelier-cms 與 yellowgirl-website 的 lib/analytics.ts）
struct TrafficReport {
    var installed: Bool
    var days: Int
    var live: Int
    var visitors: Int
    var pageviews: Int
    var visits: Int
    /// 只看一頁就離開（%）
    var bounceRate: Double?
    var avgDurationMs: Double?
    /// 和前一期比（%）
    var change: Double?
    var pageviewsChange: Double?
    var trend: [TrafficPoint]
    var pages: [TrafficTop]
    var entries: [TrafficTop]
    var referrers: [TrafficTop]
    var countries: [TrafficTop]
    var devices: [TrafficTop]
    var browsers: [TrafficTop]
    var oses: [TrafficTop]
    var campaigns: [TrafficTop]
    var channels: [ChannelShare]
    /// [星期一…星期日][0…23 時] 的瀏覽次數（台北時間，isodow）
    var weekHours: [[Int]]
    var funnel: [FunnelStep]
    var funnelPaidOrders: Int?
    var funnelRevenueCents: Int?
    var funnelProducts: [FunnelProduct]
    var contentPages: [ContentPageImpact]

    init(_ json: JSONValue) {
        installed = json["installed"]?.bool ?? true
        days = json["days"]?.int ?? 7
        live = json["live"]?.int ?? 0
        visitors = json["visitors"]?.int ?? 0
        pageviews = json["pageviews"]?.int ?? 0
        visits = json["visits"]?.int ?? 0
        bounceRate = json["bounceRate"]?.double
        avgDurationMs = json["avgDurationMs"]?.double
        change = json["change"]?["visitors"]?.double
        pageviewsChange = json["change"]?["pageviews"]?.double
        trend = (json["trend"]?.array ?? []).map {
            let raw = $0["label"]?.string ?? ""
            return TrafficPoint(key: raw, label: TrafficReport.shortLabel(raw), date: TrafficReport.day(raw), visitors: $0["visitors"]?.int ?? 0, pageviews: $0["pageviews"]?.int ?? 0)
        }
        pages = TrafficReport.tops(json["pages"])
        entries = TrafficReport.tops(json["entries"])
        referrers = TrafficReport.tops(json["referrers"])
        countries = TrafficReport.tops(json["countries"])
        devices = TrafficReport.tops(json["devices"])
        browsers = TrafficReport.tops(json["browsers"])
        oses = TrafficReport.tops(json["oses"])
        campaigns = TrafficReport.tops(json["campaigns"])
        channels = (json["channels"]?.array ?? []).map {
            let key = $0["channel"]?.string ?? ""
            return ChannelShare(key: key, name: TrafficReport.channelLabel(key), visits: $0["visits"]?.int ?? 0)
        }
        weekHours = (json["weekHours"]?.array ?? []).map { $0.array.map { $0.int ?? 0 } }
        let f = json["funnel"] ?? .null
        funnel = (f["steps"]?.array ?? []).map { FunnelStep(step: $0["step"]?.string ?? "", label: $0["label"]?.string ?? "", visitors: $0["visitors"]?.int ?? 0) }
        funnelPaidOrders = f["paid"]?["orders"]?.int
        funnelRevenueCents = f["paid"]?["revenueCents"]?.int
        funnelProducts = (f["products"]?.array ?? []).map {
            FunnelProduct(name: $0["name"]?.string ?? "", slug: $0["slug"]?.string ?? UUID().uuidString, viewers: $0["viewers"]?.int ?? 0, adders: $0["adders"]?.int ?? 0)
        }
        contentPages = (json["contentPages"]?.array ?? []).map {
            ContentPageImpact(path: $0["path"]?.string ?? "", visitors: $0["visitors"]?.int ?? 0, viewed: $0["viewed"]?.int ?? 0, carted: $0["carted"]?.int ?? 0, ordered: $0["ordered"]?.int ?? 0)
        }
    }

    /// 平均停留：1 分 23 秒
    var durationText: String? {
        guard let ms = avgDurationMs else { return nil }
        let s = Int((ms / 1000).rounded())
        return s >= 60 ? "\(s / 60) 分 \(s % 60) 秒" : "\(s) 秒"
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

    private static func day(_ raw: String) -> Date? {
        let parts = raw.split(separator: "T").first?.split(separator: "-").compactMap { Int($0) } ?? []
        guard parts.count == 3 else { return nil }
        var c = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        if raw.contains("T"), let h = raw.split(separator: "T").last.flatMap({ Int($0) }) { c.hour = h }
        return Calendar.taipei.date(from: c)
    }

    private static func tops(_ json: JSONValue?) -> [TrafficTop] {
        (json?.array ?? []).map { TrafficTop(key: $0["key"]?.string ?? "（直接輸入）", visitors: $0["visitors"]?.int ?? 0, pageviews: $0["pageviews"]?.int ?? 0) }
    }

    static func channelLabel(_ raw: String) -> String {
        switch raw {
        case "direct": "直接輸入"
        case "search": "搜尋引擎"
        case "social": "社群"
        case "referral": "其他網站"
        case "campaign": "行銷活動"
        default: raw
        }
    }

    static func deviceLabel(_ raw: String) -> String {
        switch raw {
        case "mobile": "手機"
        case "desktop": "電腦"
        case "tablet": "平板"
        default: raw
        }
    }

    /// TW → 台灣（系統的地區名稱）
    static func countryName(_ code: String) -> String {
        Locale(identifier: "zh_Hant_TW").localizedString(forRegionCode: code) ?? code
    }
}

/// Google 搜尋成效（search_report；lib/search-console.ts）
struct SearchReport {
    struct Row: Identifiable {
        var id: String { key }
        let key: String
        let clicks: Int
        let impressions: Int
        /// 0…1
        let ctr: Double?
        let position: Double?
    }

    struct Point: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let date: Date?
        let clicks: Int
        let impressions: Int
    }

    /// not_connected / ok / error
    var status: String
    var note: String?
    var property: String?
    var rangeLabel: String?
    var clicks: Int
    var impressions: Int
    var ctr: Double?
    var position: Double?
    var clicksChange: Double?
    var impressionsChange: Double?
    var trend: [Point]
    var queries: [Row]
    var pages: [Row]
    var countries: [Row]

    init(_ json: JSONValue) {
        if json["connected"]?.bool == false {
            status = "not_connected"
        } else {
            status = json["status"]?.string ?? "ok"
        }
        note = json["note"]?.string ?? json["error"]?.string
        property = json["property"]?.string
        if let start = json["range"]?["start"]?.string, let end = json["range"]?["end"]?.string {
            rangeLabel = "\(start.replacingOccurrences(of: "-", with: "/")) – \(end.replacingOccurrences(of: "-", with: "/"))"
        }
        let t = json["totals"] ?? .null
        clicks = t["clicks"]?.int ?? 0
        impressions = t["impressions"]?.int ?? 0
        ctr = t["ctr"]?.double
        position = t["position"]?.double
        clicksChange = json["change"]?["clicks"]?.double
        impressionsChange = json["change"]?["impressions"]?.double
        trend = (json["trend"]?.array ?? []).map {
            let raw = $0["label"]?.string ?? ""
            let parts = raw.split(separator: "-").compactMap { Int($0) }
            let date = parts.count == 3 ? Calendar.taipei.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) : nil
            let label = parts.count == 3 ? "\(parts[1])/\(parts[2])" : raw
            return Point(key: raw, label: label, date: date, clicks: $0["clicks"]?.int ?? 0, impressions: $0["impressions"]?.int ?? 0)
        }
        let rows = { (v: JSONValue?) in
            (v?.array ?? []).map { Row(key: $0["key"]?.string ?? "", clicks: $0["clicks"]?.int ?? 0, impressions: $0["impressions"]?.int ?? 0, ctr: $0["ctr"]?.double, position: $0["position"]?.double) }
        }
        queries = rows(json["queries"])
        pages = rows(json["pages"])
        countries = rows(json["countries"])
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

// MARK: - 等你決定（console 看數據找到的優化，/api/app/decisions）

/// 等你決定的一件事：StudioX 看網站的數據找到、做了會更好的優化（不是出貨、回覆這種本來就要做的事）。
/// 「交給 Xena」就把 prompt 交給她：她先查、給方案，真的要改時照樣要你確認。
struct Decision: Identifiable, Hashable {
    enum Action: String {
        /// 交給 Xena 了（30 天內不再出現）
        case accept
        /// 不用了（90 天）
        case dismiss
        /// 之後再說（7 天）
        case later
    }

    let id: String
    var site: String
    var icon: String
    var title: String
    /// 看到了什麼（附數字）
    var detail: String
    /// 做了大概會怎樣
    var impact: String
    /// 交代 Xena 的話
    var prompt: String

    init?(_ json: JSONValue) {
        guard let id = json["id"]?.string, let site = json["site"]?.string, let title = json["title"]?.string, let prompt = json["prompt"]?.string else { return nil }
        self.id = id
        self.site = site
        icon = json["icon"]?.string ?? "light-bulb"
        self.title = title
        detail = json["detail"]?.string ?? ""
        impact = json["impact"]?.string ?? ""
        self.prompt = prompt
    }
}

/// 清單上一則訪客訊息的樣子：「［圖片］網址」這類行換成一句話（傳了 2 張照片、傳了語音：…），網址和系統的附註不顯示
enum VisitorPreview {
    static func text(_ raw: String) -> String {
        var parts: [String] = []
        var photos = 0
        func flushPhotos() {
            if photos > 0 { parts.append(photos == 1 ? "傳了一張照片" : "傳了 \(photos) 張照片") }
            photos = 0
        }
        let lines = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var i = 0
        while i < lines.count {
            // 網址、舊版留下的系統附註（「（沒有存下來：…）」）不顯示
            let line = lines[i]
                .replacingOccurrences(of: #"\s*https?://\S+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"（沒有存下來[^）]*）"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            i += 1
            if line.hasPrefix("[圖片]") {
                photos += 1
                continue
            }
            flushPhotos()
            if let m = line.wholeMatch(of: /\[貼圖(?:：(.+))?\]/) {
                parts.append(m.1.map { "傳了貼圖（\($0)）" } ?? "傳了貼圖")
            } else if line.hasPrefix("[影片") {
                parts.append("傳了一段影片")
            } else if line.hasPrefix("[語音") {
                // 語音轉成的文字在下一行
                if i < lines.count, let said = lines[i].wholeMatch(of: /（語音內容：(.+)）/) {
                    parts.append("語音：\(said.1)")
                    i += 1
                } else {
                    parts.append("傳了一段語音")
                }
            } else if let m = line.wholeMatch(of: /\[檔案\]\s*(.*?)(?:（[^）]*）)?/) {
                let name = m.1.trimmingCharacters(in: .whitespaces)
                parts.append(name.isEmpty ? "傳了檔案" : "傳了檔案「\(name)」")
            } else if let m = line.wholeMatch(of: /\[位置\]\s*(.*)/) {
                let place = m.1.trimmingCharacters(in: .whitespaces)
                parts.append(place.isEmpty ? "傳了位置" : "傳了位置：\(place)")
            } else if let said = line.wholeMatch(of: /（語音內容：(.+)）/) {
                parts.append("語音：\(said.1)")
            } else {
                parts.append(line)
            }
        }
        flushPhotos()
        return parts.joined(separator: "，")
    }
}

