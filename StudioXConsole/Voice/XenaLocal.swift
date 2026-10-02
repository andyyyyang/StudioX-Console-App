import Foundation
import FoundationModels

/// Apple Intelligence（iPhone 上的語言模型，Foundation Models）：離線、免費、資料不出手機。
/// 它不取代 Xena（真正查資料、動手改東西的是 console 上的 Xena，照權限、先問你），只做兩件手機上就做得好的事：
///   1. 聽懂「打開訂單」「看黃毛丫頭」這類 App 裡的指令，馬上切過去，不用等雲端
///   2. 把首頁今天的數字寫成她會說的話（寫完核對數字，對不上就用原本照資料拼的句子）
/// 這台 iPhone 不支援、或 Apple Intelligence 沒打開：兩件事都退回原本的做法
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
        LanguageModelSession(instructions: Self.routerRules).prewarm()
    }

    // MARK: 指令

    /// 這句話是不是「打開某一頁」：是的話回要去哪裡；在問問題、請 Xena 做事就回 nil（交給雲端的 Xena）
    func route(_ utterance: String) async -> VoiceRoute? {
        guard available, AppSettings.shared.aiCommands else { return nil }
        let session = LanguageModelSession(instructions: Self.routerRules)
        do {
            let route = try await session.respond(to: utterance, generating: VoiceRoute.self, options: GenerationOptions(sampling: .greedy)).content
            return route.place == .ask ? nil : route
        } catch {
            return nil
        }
    }

    private static let routerRules = """
    你在 StudioX App 裡分辨老闆說的一句話是不是「只是要打開 App 裡的某一頁」。
    頁面：today（今天、首頁）、sites（網站、某個網站）、orders（訂單）、inbox（收件匣、客服信、詢問）、settings（設定）。
    只有明確要打開、切換、回到某一頁時才選那一頁；在問問題、查數字、要求做事、要回覆客人，一律選 ask。
    例子：
    「打開訂單」→ orders
    「回首頁」→ today
    「看一下黃毛丫頭」→ sites，網站：黃毛丫頭
    「收件匣」→ inbox
    「昨天訂單有幾筆」→ ask
    「幫我回覆那位客人」→ ask
    「黃毛丫頭最近流量怎麼樣」→ ask
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

    // MARK: 長的回答：說重點

    /// 用說的時回答太長：濃縮成一句聽得懂的重點（數字都要在原文裡，不然 nil）
    func outline(of text: String) async -> String? {
        guard available else { return nil }
        let session = LanguageModelSession(instructions: Self.outlineRules)
        do {
            let out = try await session.respond(to: text, options: GenerationOptions(temperature: 0.3)).content
            let cleaned = out
                .replacingOccurrences(of: #"[*#`「」"“”]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard (4...90).contains(cleaned.count), Self.numbers(in: cleaned).isSubset(of: Self.numbers(in: text)) else { return nil }
            return cleaned
        } catch {
            return nil
        }
    }

    private static let outlineRules = """
    把 Xena 的一段回答濃縮成一句口語的重點，讓老闆用聽的就知道大概：繁體中文、台灣口語、40 字以內。
    只能說原文裡有的事，數字照抄成阿拉伯數字，不要加開場白、不要說「總結」、不要條列。
    """

    /// 一段話裡的數字（拿掉千分位的逗號）
    static func numbers(in text: String) -> Set<String> {
        let plain = text.replacingOccurrences(of: ",", with: "")
        return Set(plain.matches(of: /\d+(?:\.\d+)?/).map { String($0.output) })
    }
}

/// 一句話要去的地方（Foundation Models 照這個格式回答）
@Generable
nonisolated struct VoiceRoute {
    @Guide(description: "要打開的頁面；在問問題、查資料、請 Xena 做事就選 ask")
    var place: VoicePlace
    @Guide(description: "提到的網站名稱，照原文；沒提到就空字串")
    var site: String
}

@Generable
nonisolated enum VoicePlace {
    case today, sites, orders, inbox, settings, ask
}
