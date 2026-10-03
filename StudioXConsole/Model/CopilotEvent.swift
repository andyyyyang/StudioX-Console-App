import Foundation

// Xena 對話的資料型別：和 atelier-cms 的 src/lib/copilot/engine.ts、cards.ts 一致，
// App 直接解 /api/copilot/chat 的 SSE 事件。

nonisolated enum ConfirmStatus: String, Codable, Sendable {
    case pending, done, failed, cancelled, expired
}

/// 要動手改東西之前的確認卡片。確認碼只在伺服器，App 只送「確認／取消」
nonisolated struct ConfirmCard: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
    var danger: Bool
    /// 需要打字確認的動作（刪除、退款…）：要打的字
    var typed: String?
    var status: ConfirmStatus
    var result: String?
    /// 長文草稿存回網站（apply_draft）：可以先看完整新版、改了哪些
    var draft: DraftInfo?
}

/// 確認卡片附的長文草稿
nonisolated struct DraftInfo: Codable, Hashable, Sendable {
    var id: String
    var title: String
    /// markdown / html / text
    var format: String
    var chars: Int
    var added: Int
    var removed: Int
}

nonisolated enum ToolStatus: String, Codable, Sendable {
    case running, ok, error, proposed
}

/// 一次工具（MCP）呼叫的紀錄
nonisolated struct ToolRecord: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    /// 給人看的一句話：「查詢黃毛丫頭的訂單」
    var label: String
    var args: String
    var status: ToolStatus
    var result: String?
    var ms: Int?
    var confirmed: Bool?
}

nonisolated struct CardBadge: Codable, Hashable, Sendable {
    var label: String
    /// ok | warn | bad | info | muted
    var tone: String
}

nonisolated struct CardField: Codable, Hashable, Sendable {
    var label: String
    var value: String
}

/// Xena 做的卡片（show_cards）：一筆一張，點了到那一頁
nonisolated struct EntityCard: Codable, Hashable, Sendable {
    var entity: String
    var id: String
    var kind: String
    var title: String
    var subtitle: String?
    var badge: CardBadge?
    var fields: [CardField]
    var href: String?
    var image: String?
    var site: String?
}

nonisolated struct CardsItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String?
    var cards: [EntityCard]
}

/// Xena 問你（ask_user）：選項按鈕；回答後記下答了什麼
nonisolated struct AskItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var question: String
    var options: [String]
    var multiple: Bool
    var allowText: Bool
    var answer: String?
}

/// /api/copilot/chat 的串流事件（每個事件一行 data: JSON）
nonisolated enum CopilotEvent: Decodable, Sendable {
    case thread(id: String, title: String)
    case text(String)
    case tool(ToolRecord)
    case toolDone(id: String, status: ToolStatus, result: String?, ms: Int?)
    case confirm(ConfirmCard)
    case cards(CardsItem)
    case ask(AskItem)
    case error(String)
    case done
    /// 看不懂的事件（伺服器比 App 新）：略過
    case unknown

    private nonisolated enum Keys: String, CodingKey {
        case type, id, title, text, call, status, result, ms, card, item, message
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "thread":
            self = .thread(id: try c.decode(String.self, forKey: .id), title: try c.decodeIfPresent(String.self, forKey: .title) ?? "")
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "tool":
            self = .tool(try c.decode(ToolRecord.self, forKey: .call))
        case "tool-done":
            self = .toolDone(
                id: try c.decode(String.self, forKey: .id),
                status: try c.decode(ToolStatus.self, forKey: .status),
                result: try c.decodeIfPresent(String.self, forKey: .result),
                ms: try c.decodeIfPresent(Int.self, forKey: .ms)
            )
        case "confirm":
            self = .confirm(try c.decode(ConfirmCard.self, forKey: .card))
        case "cards":
            self = .cards(try c.decode(CardsItem.self, forKey: .item))
        case "ask":
            self = .ask(try c.decode(AskItem.self, forKey: .item))
        case "error":
            self = .error(try c.decodeIfPresent(String.self, forKey: .message) ?? "發生錯誤，請再試一次")
        case "done":
            self = .done
        default:
            self = .unknown
        }
    }
}

/// 存起來的一串對話（GET /api/copilot 的 thread.view；engine.ts 的 ViewItem）
nonisolated enum ViewItemDTO: Decodable, Sendable {
    case user(String)
    case assistant(String)
    case tool(ToolRecord)
    case confirm(ConfirmCard)
    case cards(CardsItem)
    case ask(AskItem)
    case unknown

    private nonisolated enum Keys: String, CodingKey {
        case kind, text
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decodeIfPresent(String.self, forKey: .kind) ?? "" {
        case "user": self = .user(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "assistant": self = .assistant(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "tool": self = .tool(try ToolRecord(from: decoder))
        case "confirm": self = .confirm(try ConfirmCard(from: decoder))
        case "cards": self = .cards(try CardsItem(from: decoder))
        case "ask": self = .ask(try AskItem(from: decoder))
        default: self = .unknown
        }
    }
}

nonisolated struct ThreadDTO: Decodable, Sendable {
    var id: String
    var title: String
    var view: [ViewItemDTO]
}

/// GET /api/copilot：能不能用、這一串的內容
nonisolated struct CopilotStateDTO: Decodable, Sendable {
    var problem: String?
    var thread: ThreadDTO?
}

/// 對話列表（GET /api/copilot/threads）
nonisolated struct ThreadSummaryDTO: Decodable, Sendable, Identifiable, Hashable {
    var id: String
    var title: String
    var updatedAt: String?
}

nonisolated struct ThreadListDTO: Decodable, Sendable {
    var threads: [ThreadSummaryDTO]
}

/// 確認卡片按下去之後（POST /api/copilot/confirm）：這張卡的結果、要不要接著確認下一張、執行的工具
nonisolated struct ConfirmResponseDTO: Decodable, Sendable {
    var card: ConfirmCard
    var next: ConfirmCard?
    var tool: ToolRecord?
}

// MARK: - 長文草稿（/api/copilot/drafts）

/// 草稿和打開時的原文比較的一段：= 沒變、+ 新增、- 刪掉
nonisolated struct DraftHunk: Codable, Hashable, Sendable {
    var op: String
    var lines: [String]
}

/// 一份草稿的全文（確認卡片的「看完整內容」）
nonisolated struct DraftDocument: Codable, Hashable, Sendable {
    var id: String
    var title: String
    /// markdown / html / text
    var format: String
    var chars: Int
    var text: String
    /// 和原文比較（新寫的、上傳的沒有）
    var hunks: [DraftHunk]?
}

/// 上傳一份文件給 Xena 之後拿到的草稿
nonisolated struct DraftUpload: Codable, Hashable, Sendable {
    var id: String
    var title: String
    var format: String
    var chars: Int
}
