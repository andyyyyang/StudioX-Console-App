import Foundation
import FoundationModels

/// Apple Intelligence（iPhone 上的語言模型，Foundation Models）：離線、免費、資料不出手機。
/// 用說的時，它是 Xena 在手機上的耳朵和嘴巴，跟雲端的 Xena 一起配合：
///   聽：你說的每一句先在手機上聽懂——切頁、念卡片、再說一次、確認／取消、選選項、閒聊、結束，馬上在手機上處理；
///       其他的整理好（修正聽錯的字、網站名稱）交給雲端的 Xena，她去查之前先回一句「好，我看一下…」
///   說：雲端 Xena 的回答太長，濃縮成兩三句口語的重點，整段放在卡片上（標題＋重點）
/// 另外把首頁今天的數字寫成她會說的話。寫出來的數字都要核對過，對不上就不用。
/// 真正查資料、動手改東西的還是雲端的 Xena（照權限、先問你）。
/// 這台 iPhone 不支援、或 Apple Intelligence 沒打開：全部退回原本的做法（看關鍵字、念到上限）
@Observable
final class XenaLocal {
    static let shared = XenaLocal()

    var available: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// 不能用的原因（設定頁顯示）
    var status: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "可以用：在這台 iPhone 上執行，資料不會離開手機"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "這台 iPhone 不支援 Apple Intelligence（要 iPhone 15 Pro 以後）"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence 沒有打開：iPhone 的「設定 → Apple Intelligence 與 Siri」"
            case .modelNotReady: return "Apple Intelligence 的模型還在下載，好了就會自動用"
            @unknown default: return "現在不能用"
            }
        }
    }

    /// 開始說話前先把模型載進記憶體（第一次回應比較快）
    func prewarm() {
        guard available, AppSettings.shared.aiCommands else { return }
        LanguageModelSession(instructions: Self.listenRules).prewarm()
    }

    // MARK: 聽懂你說的話

    /// 你說的這一句要做什麼（畫面上現在有什麼、她剛剛說了什麼都一起看）。聽不懂、不能用就 nil（照原本的做法）。
    /// 要交給雲端 Xena 的：她針對內容先回的那一句一寫好就 react（不等整個判斷寫完），像真人一樣馬上有反應
    func understand(_ utterance: String, context: VoiceContext, react: (String) -> Void) async -> VoiceIntent? {
        guard available, AppSettings.shared.aiCommands else { return nil }
        let session = LanguageModelSession(instructions: Self.listenRules)
        var lines = ["網站：\(context.sites.isEmpty ? "（沒有）" : context.sites.joined(separator: "、"))"]
        if let card = context.card {
            lines.append("畫面上有一件等老闆確認的事：「\(card)」")
        }
        if let question = context.question {
            let options = context.options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "　")
            lines.append("Xena 剛剛問老闆：「\(question)」" + (options.isEmpty ? "" : "選項：\(options)"))
        }
        if context.hasReadingCard {
            lines.append("畫面上有一張長回答的卡片（還沒念出來）")
        }
        if !context.lastReply.isEmpty {
            lines.append("Xena 剛剛說：「\(String(context.lastReply.prefix(160)))」")
        }
        lines.append("老闆說：「\(utterance)」")
        do {
            let stream = session.streamResponse(to: lines.joined(separator: "\n"), generating: VoiceIntent.self, options: GenerationOptions(sampling: .greedy))
            var reacted = false
            var last: GeneratedContent?
            for try await snapshot in stream {
                last = snapshot.rawContent
                let partial = snapshot.content
                // action 最先寫、接著 say；開始寫 place 就表示 say 寫完了
                if !reacted, partial.action == .ask, partial.place != nil, let line = partial.say {
                    reacted = true
                    react(line)
                }
            }
            guard let last else { return nil }
            return try VoiceIntent(last)
        } catch {
            return nil
        }
    }

    private static let listenRules = """
    你是 Xena 在 iPhone 上的耳朵。老闆用說的跟 Xena（幫他看店的 AI 店長）講話，你先判斷這一句要做什麼，填 action：
    - open：只是要打開 App 的某一頁。place：today（今天、首頁）、sites（網站、某個網站）、orders（訂單）、inbox（收件匣、客服信、詢問）、settings（設定）。在問問題、查數字、要做事都不是 open。
    - read：要把畫面上長回答的卡片念出來（念給我聽、讀一下、說給我聽）。只有畫面上有那張卡片時才選。
    - again：沒聽清楚，要 Xena 把剛剛的話再說一次（再說一次、你說什麼、蛤、沒聽清楚）。
    - approve：同意畫面上等他確認的事（好、確認、可以、做吧、沒問題）。只有有等他確認的事時才選；同意但又加了條件或修改的，選 ask。
    - reject：不要做畫面上等他確認的事（取消、不要、先不要、等一下、算了）。
    - answer：在回答 Xena 剛剛問的問題。answer 填他選的選項，照選項原文（「第二個」就是第 2 個選項）；不是選項就照他說的原文。
    - chat：打招呼、道謝、稱讚、問 Xena 好不好這類閒聊。say 填 Xena 自然的回一句（20 字以內）。不能說任何跟店、訂單、數字、資料有關的事。
    - done：要結束對話（沒事了、先這樣、掰掰、好了謝謝）。
    - ask：其他全部（問問題、查資料、要 Xena 做事、回覆客人、改東西…），交給 Xena。
      say：Xena 馬上針對他說的內容先回一句，像真人聽完會先回的那樣：「好，我查一下昨天的訂單。」「真的嗎？我看看最近的訂單。」「好，我幫你寫回覆。」20 字以內，不要回答內容、不要編數字。
      message：要交給 Xena 的話，照他的原意；只修正聽寫聽錯的字和網站名稱（用網站清單裡的寫法），不要加新的意思、不要改數字。
    不確定就選 ask。site：提到的網站，用清單裡的寫法；沒提到就空字串。用不到的欄位填空字串。
    """

    // MARK: 首頁的開場白

    /// 用 Xena 的口吻把今天的狀況說一次。寫出來的數字都要在原本的事實裡（不能多、不能改），不然回 nil
    func greeting(from facts: String, name: String) async -> String? {
        guard available, AppSettings.shared.aiGreeting else { return nil }
        let session = LanguageModelSession(instructions: Self.greetingRules)
        let prompt = """
        老闆：\(name.isEmpty ? "（沒有名字）" : name)
        現在的狀況：\(facts)
        """
        do {
            let text = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.6)).content
            let cleaned = text
                .replacingOccurrences(of: #"[*#`「」"“”]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard (8...160).contains(cleaned.count), Self.numbers(in: cleaned).isSubset(of: Self.numbers(in: facts)) else { return nil }
            return cleaned
        } catch {
            return nil
        }
    }

    private static let greetingRules = """
    你是 Xena，StudioX 幫老闆 24 小時看店的 AI 店長。用繁體中文、台灣口語，像當面跟老闆報告。
    規則：
    - 只能說「現在的狀況」裡有的事，不要猜、不要補充沒給的事。
    - 數字一律照抄成阿拉伯數字，不能改、不能加總、不能換算。
    - 兩到三句、八十字以內；不要條列、不要表情符號、不要引號。
    - 不用再打招呼（畫面上已經說過早安）。最後一句可以溫和地提醒最要緊的那件事。
    """

    // MARK: 長的回答：說重點、做卡片

    /// 雲端 Xena 的回答太長：濃縮成用說的兩三句重點＋卡片的標題和重點。
    /// alreadySaid：她已經先說出口的開頭（重點不要再說一次）。數字都要在原文裡，不然那一部分不用
    func digest(of text: String, alreadySaid: String) async -> VoiceDigest? {
        guard available, AppSettings.shared.aiCommands else { return nil }
        let session = LanguageModelSession(instructions: Self.digestRules)
        let prompt = """
        老闆已經聽到的開頭：\(alreadySaid.isEmpty ? "（沒有）" : "「\(alreadySaid)」")
        Xena 的回答：
        \(String(text.prefix(2400)))
        """
        do {
            var out = try await session.respond(to: prompt, generating: VoiceDigest.self, options: GenerationOptions(sampling: .greedy)).content
            let facts = Self.numbers(in: text)
            let clean = { (line: String) in
                line.replacingOccurrences(of: #"[*#`「」"“”]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let ok = { (line: String) in Self.numbers(in: line).isSubset(of: facts) }
            out.spoken = clean(out.spoken)
            out.title = clean(out.title)
            out.points = out.points.map(clean).filter { !$0.isEmpty && ok($0) }.prefix(4).map { $0 }
            if !ok(out.spoken) || !(4...120).contains(out.spoken.count) { out.spoken = "" }
            if !ok(out.title) || out.title.count > 20 { out.title = "" }
            return out.spoken.isEmpty && out.points.isEmpty ? nil : out
        } catch {
            return nil
        }
    }

    private static let digestRules = """
    你幫 Xena（幫老闆看店的 AI 店長）把一段太長、不適合用聽的回答，變成用說的重點和一張卡片。繁體中文、台灣口語。
    spoken：用說的重點，兩三句、60 字以內，先講結論；老闆已經聽到的開頭不要再說；不要說「總結」「以下」。
    title：卡片標題，12 字以內。
    points：卡片上的重點，2 到 4 點，每點 24 字以內。
    只能用原文裡有的事；數字一律照抄成阿拉伯數字，不能改、不能加總、不能換算。不要條列符號、不要表情符號。
    """

    /// 一段話裡的數字（拿掉千分位的逗號）
    static func numbers(in text: String) -> Set<String> {
        let plain = text.replacingOccurrences(of: ",", with: "")
        return Set(plain.matches(of: /\d+(?:\.\d+)?/).map { String($0.output) })
    }
}

/// 聽懂一句話時要一起看的：網站、畫面上等你確認的事、她問你的問題、有沒有長回答的卡片、她剛剛說的
nonisolated struct VoiceContext {
    var sites: [String] = []
    var card: String?
    var question: String?
    var options: [String] = []
    var hasReadingCard = false
    var lastReply = ""
}

/// 你說的一句話要做什麼（Foundation Models 照這個格式回答）
@Generable
nonisolated struct VoiceIntent {
    @Guide(description: "這句話要做什麼")
    var action: VoiceAction
    @Guide(description: "action 是 ask 時：Xena 針對內容馬上先回的一句（還沒查，不回答內容）；action 是 chat 時：Xena 回的一句；其他時候空字串")
    var say: String
    @Guide(description: "action 是 open 時要打開的頁面；其他時候填 today")
    var place: VoicePlace
    @Guide(description: "提到的網站名稱，用網站清單裡的寫法；沒提到就空字串")
    var site: String
    @Guide(description: "action 是 answer 時：選的選項（照選項原文），或他說的答案；其他時候空字串")
    var answer: String
    @Guide(description: "action 是 ask 時：要交給 Xena 的話（照原意，只修正聽錯的字和網站名稱）；其他時候空字串")
    var message: String
}

@Generable
nonisolated enum VoiceAction {
    case open, read, again, approve, reject, answer, chat, done, ask
}

@Generable
nonisolated enum VoicePlace {
    case today, sites, orders, inbox, settings
}

/// 太長的回答：用說的重點＋卡片
@Generable
nonisolated struct VoiceDigest {
    @Guide(description: "用說的重點：兩三句口語，60 字以內，先講結論")
    var spoken: String
    @Guide(description: "卡片標題，12 字以內")
    var title: String
    @Guide(description: "卡片上的重點，2 到 4 點，每點 24 字以內")
    var points: [String]
}
