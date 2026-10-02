import SwiftUI

/// 登入的後台人員（console 帳號）
struct StaffUser: Equatable {
    var name: String
    var email: String
}

enum SignInMethod: Equatable {
    case apple
    case email(String, String)
}

/// 在網站上的職能（console 的網站成員）
enum SiteRole: String {
    case owner = "負責人"
    case manager = "管理者"
    case fulfillment = "訂單處理人員"
    case staff = "員工"
}

/// 網站打開的模組（atelier-cms 的 CMS_MODULES）
enum SiteModule: String, Hashable {
    case content, assistant, support, commerce
}

enum SiteIcon: Hashable {
    /// StudioX 的標誌
    case mark
    case letter(String)
}

/// 顏色的語氣：和 Xena 卡片的 tone 相同
enum Tone: String, Hashable {
    case ok, warn, bad, info, muted

    var color: Color {
        switch self {
        case .ok: Brand.success
        case .warn: Brand.accent
        case .bad: Brand.danger
        case .info: XenaPalette.violet
        case .muted: Brand.muted
        }
    }
}

/// +18% / −4%
func percentChange(_ ratio: Double) -> String {
    let n = Int((ratio * 100).rounded())
    return n >= 0 ? "+\(n)%" : "−\(abs(n))%"
}

struct TrafficPoint: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let visitors: Int
    let pageviews: Int
}

struct PageStat: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let title: String
    let visitors: Int
}

/// 流量摘要（console 的 lib/console/site-stats.ts 的 SiteStats）
struct SiteStats: Hashable {
    var live: Int
    var visitors: Int
    var pageviews: Int
    var bounceRate: Double?
    var avgDuration: TimeInterval?
    /// 和前一段時間比：0.18＝多 18%
    var change: Double?
    var trend: [TrafficPoint]
    var pages: [PageStat]
}

struct ContentEntry: Identifiable, Hashable {
    enum PublishState: String, Hashable {
        case draft = "草稿"
        case published = "已發布"
        case scheduled = "排程"

        var tone: Tone {
            switch self {
            case .draft: .muted
            case .published: .ok
            case .scheduled: .info
            }
        }
    }

    let id: String
    var collection: String
    var title: String
    var state: PublishState
    var updatedAt: Date
}

struct Site: Identifiable, Hashable {
    let id: String
    var name: String
    var org: String
    var domain: String
    /// 「開啟後台」：網站後台（從 console 進去會自動登入）
    var adminURL: URL
    var role: SiteRole
    var modules: Set<SiteModule>
    var icon: SiteIcon
    var tint: Color
    var stats: SiteStats
    var content: [ContentEntry]

    var siteURL: URL { URL(string: "https://\(domain)") ?? adminURL }
    var hasCommerce: Bool { modules.contains(.commerce) }
}

// MARK: - 訂單（commerce 模組）

enum OrderStatus: String, CaseIterable, Hashable {
    case pending = "待付款"
    case paid = "已付款"
    case preparing = "備貨中"
    case shipped = "已出貨"
    case completed = "已完成"
    case cancelled = "已取消"
    case refunded = "已退款"

    var tone: Tone {
        switch self {
        case .pending: .muted
        case .paid: .warn
        case .preparing: .info
        case .shipped, .completed: .ok
        case .cancelled, .refunded: .bad
        }
    }

    /// 下一步（給「請 Xena 改成…」用）
    var next: OrderStatus? {
        switch self {
        case .paid: .preparing
        case .preparing: .shipped
        case .shipped: .completed
        default: nil
        }
    }
}

struct OrderLine: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let qty: Int
    let price: Int
}

struct Order: Identifiable, Hashable {
    let id: String
    let number: String
    let siteID: String
    var customer: String
    var phone: String
    var lines: [OrderLine]
    var shippingFee: Int
    var status: OrderStatus
    var payment: String
    var shipping: String
    var placedAt: Date
    var note: String?
    /// 物流狀況（黑貓貨態）
    var logistics: String?

    var subtotal: Int { lines.reduce(0) { $0 + $1.price * $1.qty } }
    var total: Int { subtotal + shippingFee }
    var summary: String {
        lines.map { "\($0.name)×\($0.qty)" }.joined(separator: "、")
    }
}

// MARK: - 客服（support 模組：Xena 轉來的對話）

/// 對話狀態：ai（Xena 回答中）→ waiting（等專人；Xena 繼續幫忙）→ human（專人接手）→ closed
enum ConversationStatus: String, Hashable {
    case ai, waiting, human, closed

    var label: String {
        switch self {
        case .ai: "Xena 處理中"
        case .waiting: "等你回覆"
        case .human: "你接手中"
        case .closed: "已結案"
        }
    }

    var tone: Tone {
        switch self {
        case .ai: .info
        case .waiting: .warn
        case .human: .ok
        case .closed: .muted
        }
    }
}

struct ChatLine: Identifiable, Hashable {
    enum Author: Hashable {
        case visitor
        case xena
        case staff(String)
    }

    let id: String
    var author: Author
    var text: String
    var at: Date
}

struct Conversation: Identifiable, Hashable {
    let id: String
    let siteID: String
    var visitor: String
    var contact: String?
    /// TypeSafe Jev 的分類（費用報價、訂單問題、客訴…）
    var category: String
    /// Jev 判斷要不要找人（0.8 以上才算）
    var humanScore: Double
    var status: ConversationStatus
    var lines: [ChatLine]
    var updatedAt: Date

    var preview: String { lines.last?.text ?? "" }
    /// 最後一句是客人說的（輪到我們回）
    var lastFromVisitor: Bool { lines.last?.author == .visitor }
}

// MARK: - Xena 主動跟你說的事、值班紀錄

struct XenaNote: Identifiable, Hashable {
    enum Kind: Hashable {
        /// 需要你決定
        case attention
        /// Xena 想幫你做（按下去會先出確認卡片）
        case suggestion
        /// Xena 的觀察
        case insight

        var symbol: String {
            switch self {
            case .attention: "exclamationmark.bubble.fill"
            case .suggestion: "hand.raised.fill"
            case .insight: "lightbulb.max.fill"
            }
        }

        var tone: Tone {
            switch self {
            case .attention: .warn
            case .suggestion: .info
            case .insight: .ok
            }
        }
    }

    let id: String
    var kind: Kind
    var siteID: String?
    var title: String
    var body: String
    var at: Date
    /// 要動手改的：兩步驟確認
    var proposal: ConfirmCard?
    /// 要聊的：打開 Xena 接著問這句
    var prompt: String?
    var promptLabel: String?
    /// 處理完了：結果
    var resolution: String?
}

struct ShiftEntry: Identifiable, Hashable {
    let id: String
    var at: Date
    var symbol: String
    var text: String
    var siteID: String?
    var tone: Tone
}
