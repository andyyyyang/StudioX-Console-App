import Foundation

// Xena 對話的資料型別：和 atelier-cms 的 src/lib/copilot/engine.ts、cards.ts 一致，
// 接上正式的 console 時直接解 /api/copilot/chat 的 SSE 事件。

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
    /// App 這邊的延伸：回答完建議下一句可以問什麼
    case suggestions([String])
    case error(String)
    case done
    /// 看不懂的事件（伺服器比 App 新）：略過
    case unknown

    private nonisolated enum Keys: String, CodingKey {
        case type, id, title, text, call, status, result, ms, card, item, items, message
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
        case "suggestions":
            self = .suggestions(try c.decodeIfPresent([String].self, forKey: .items) ?? [])
        case "error":
            self = .error(try c.decodeIfPresent(String.self, forKey: .message) ?? "發生錯誤，請再試一次")
        case "done":
            self = .done
        default:
            self = .unknown
        }
    }
}

/// 送給 Xena 的一句話
nonisolated struct XenaRequest: Sendable {
    var message: String
    var threadID: String?
    /// 回答 Xena 的提問（ask_user）：那張卡片的 id
    var answering: String?
    /// 從哪個網站的頁面問的（讓 Xena 知道在說哪個網站）
    var siteID: String?
}

/// 確認卡片按下去之後的結果
nonisolated struct DecideResult: Sendable {
    var status: ConfirmStatus
    var result: String?
    /// Xena 接著說的話
    var followUp: String?
}
