import Foundation

/// App 拿資料、跟 Xena 說話的介面。
/// 現在只有 DemoConsole（示範資料）；接上正式的 StudioX Console 要補的伺服器端見 README「接上正式環境」，
/// Xena 的串流協定與登入的準備在 LiveConsole.swift。
protocol ConsoleBackend: AnyObject {
    func signIn(_ method: SignInMethod) async throws -> StaffUser
    func sites() async throws -> [Site]
    func orders() async throws -> [Order]
    func conversations() async throws -> [Conversation]
    func notes() async throws -> [XenaNote]
    func shiftLog() async throws -> [ShiftEntry]

    /// 跟 Xena 說一句話：回傳串流事件（和網頁版 POST /api/copilot/chat 相同）
    func chat(_ request: XenaRequest) -> AsyncThrowingStream<CopilotEvent, any Error>
    /// 確認卡片：確認執行或取消（POST /api/copilot/confirm）
    func decide(_ cardID: String, approve: Bool, typed: String?) async throws -> DecideResult

    func setStatus(_ status: ConversationStatus, conversation id: String) async throws
    func reply(_ text: String, conversation id: String, as staff: String) async throws
}

nonisolated enum ConsoleError: LocalizedError {
    case badCredentials
    case typedMismatch(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .badCredentials: "帳號或密碼不正確"
        case .typedMismatch(let word): "要輸入「\(word)」才能執行"
        case .notConnected: "還沒接上 StudioX Console"
        }
    }
}

extension String {
    /// 切成幾個字一段（模擬串流）
    nonisolated func chunked(_ size: Int) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in self {
            current.append(ch)
            if current.count >= size {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

nonisolated func newID(_ prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
}
