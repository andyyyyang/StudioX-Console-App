import AuthenticationServices
import Foundation

nonisolated enum APIError: LocalizedError {
    /// 登入過期或被撤銷：要重新登入
    case unauthorized
    case offline
    case http(Int)
    /// JSON-RPC 的錯誤（工具不存在、限流…）
    case rpc(String)
    /// 工具執行失敗（網站回的說明，例如「找不到這張訂單」）
    case tool(String)
    /// 權限不夠（網站關掉了寫入、職能不夠）
    case scope(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "登入已經過期，請重新登入"
        case .offline: "連不上網路，請稍後再試"
        case .http(let code): "伺服器回應 \(code)，請稍後再試"
        case .rpc(let message), .tool(let message): message
        case .scope(let message): message
        }
    }
}

/// 和 StudioX Console 說話：
///   - GET /api/app/me：登入的人、可以管理的網站
///   - POST /api/mcp：各網站的資料與動作（和 AI 連接器同一個閘道，寫入一律兩步驟確認）
///   - /api/copilot/*：Xena
/// 每個請求帶 Bearer token；過期或 401 就用 refresh token 換一次再試，換不到就登出。
final class ConsoleAPI {
    private(set) var tokens: Tokens?
    /// refresh token 也失效了（被撤銷、太久沒用）
    var onSignedOut: (() -> Void)?

    private var refreshing: Task<Tokens, any Error>?
    private var rpcID = 0

    init() {
        tokens = Auth.load()
    }

    var isSignedIn: Bool { tokens != nil }

    func signIn(using session: WebAuthenticationSession) async throws {
        tokens = try await Auth.signIn(using: session)
    }

    func signOut() async {
        let old = tokens
        tokens = nil
        refreshing?.cancel()
        refreshing = nil
        await Auth.signOut(old)
    }

    // MARK: token

    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw APIError.unauthorized }
        if current.isFresh && !forceRefresh { return current.access }
        return try await refresh().access
    }

    /// 同時有好幾個請求過期時只換一次
    private func refresh() async throws -> Tokens {
        if let refreshing { return try await refreshing.value }
        guard let current = tokens else { throw APIError.unauthorized }
        let task = Task { try await Auth.refresh(current) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let next = try await task.value
            tokens = next
            return next
        } catch AuthError.expired {
            expire()
            throw APIError.unauthorized
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw APIError.offline
        }
    }

    private func expire() {
        tokens = nil
        Auth.clear()
        onSignedOut?()
    }

    /// 帶 token 送出；401 就換 token 再試一次
    private func send(_ makeRequest: () throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0..<2 {
            var request = try makeRequest()
            request.setValue("Bearer \(try await accessToken(forceRefresh: attempt > 0))", forHTTPHeaderField: "authorization")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost || error.code == .timedOut {
                throw APIError.offline
            }
            guard let http = response as? HTTPURLResponse else { throw APIError.http(0) }
            if http.statusCode == 401 {
                if attempt == 0 { continue }
                expire()
                throw APIError.unauthorized
            }
            return (data, http)
        }
        throw APIError.unauthorized
    }

    private func json(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    // MARK: 我

    func me() async throws -> Me {
        let (data, http) = try await send { URLRequest(url: ConsoleConfig.baseURL.appending(path: "api/app/me")) }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        return Me(try json(data))
    }

    // MARK: 網站的工具（MCP）

    /// 呼叫某個網站的工具。回傳工具結果的 JSON（site_guide 這種純文字放在 .string）
    func tool(_ name: String, site: String, _ arguments: [String: JSONValue] = [:]) async throws -> JSONValue {
        rpcID += 1
        var args = arguments
        args["site"] = .string(site)
        let body: JSONValue = [
            "jsonrpc": "2.0",
            "id": .number(Double(rpcID)),
            "method": "tools/call",
            "params": ["name": .string(name), "arguments": .object(args)],
        ]
        let payload = try JSONEncoder().encode(body)
        let (data, http) = try await send {
            var r = URLRequest(url: URL(string: ConsoleConfig.mcpURL)!)
            r.httpMethod = "POST"
            r.timeoutInterval = 45
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue("application/json, text/event-stream", forHTTPHeaderField: "accept")
            r.httpBody = payload
            return r
        }
        let reply = (try? json(data)) ?? .null
        if http.statusCode == 403 {
            throw APIError.scope(reply["error_description"]?.string ?? "你在這個網站沒有這個權限")
        }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        if let error = reply["error"], !error.isNull {
            throw APIError.rpc(error["message"]?.string ?? "沒有完成，請再試一次")
        }
        let result = reply["result"] ?? .null
        let text = result["content"]?.array.first?["text"]?.string ?? ""
        if result["isError"]?.bool == true { throw APIError.tool(text) }
        if let parsed = try? json(Data(text.utf8)) { return parsed }
        return .string(text)
    }

    enum WriteOutcome {
        case done(JSONValue)
        case needsConfirmation(Proposal)
    }

    /// 寫入的第一步：網站回「要確認」（標題、內容、要不要打字）時不會執行
    func propose(_ name: String, site: String, _ args: [String: JSONValue]) async throws -> WriteOutcome {
        let r = try await tool(name, site: site, args)
        guard r["needsConfirmation"]?.bool == true, let token = r["confirmToken"]?.string else { return .done(r) }
        return .needsConfirmation(Proposal(
            tool: name, site: site, args: args,
            title: r["title"]?.string ?? "確認",
            detail: r["detail"]?.string ?? "",
            danger: r["danger"]?.bool ?? false,
            typed: r["typedConfirmation"]?.string,
            confirmToken: token
        ))
    }

    enum ConfirmOutcome {
        case done(JSONValue)
        /// 退款超過門檻：要店主的驗證碼（網站會寄給店主）
        case needsOwner(Proposal)
    }

    /// 寫入的第二步：用完全一樣的參數加上確認碼（和要打的字、店主驗證碼）再送一次，這次才執行
    func confirm(_ p: Proposal, typed: String?, ownerCode: String? = nil) async throws -> ConfirmOutcome {
        var args = p.args
        args["confirmToken"] = .string(p.confirmToken)
        if p.typed != nil { args["confirmText"] = .string(typed ?? "") }
        if let request = p.ownerRequestID {
            args["requestId"] = .string(request)
            args["ownerCode"] = .string(ownerCode ?? "")
        }
        let r = try await tool(p.tool, site: p.site, args)
        if r["needsOwnerApproval"]?.bool == true, let request = r["requestId"]?.string {
            var next = p
            next.ownerRequestID = request
            next.ownerTitle = r["title"]?.string
            next.ownerDetail = r["detail"]?.string
            return .needsOwner(next)
        }
        return .done(r)
    }

    // MARK: Xena（/api/copilot）

    private func copilotRequest(_ path: String, method: String = "GET", body: JSONValue? = nil) throws -> URLRequest {
        var r = URLRequest(url: ConsoleConfig.baseURL.appending(path: path))
        r.httpMethod = method
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.httpBody = try JSONEncoder().encode(body)
        }
        return r
    }

    private func copilotError(_ data: Data, _ status: Int) -> APIError {
        if let message = (try? json(data))?["error"]?.string { return .tool(message) }
        return .http(status)
    }

    /// 能不能用、最近的一串（thread＝nil）或指定的一串
    func copilotState(thread: String? = nil) async throws -> CopilotStateDTO {
        var c = URLComponents(url: ConsoleConfig.baseURL.appending(path: "api/copilot"), resolvingAgainstBaseURL: false)!
        if let thread { c.queryItems = [URLQueryItem(name: "thread", value: thread)] }
        let url = c.url!
        let (data, http) = try await send { URLRequest(url: url) }
        guard http.statusCode == 200 else { throw copilotError(data, http.statusCode) }
        return try JSONDecoder().decode(CopilotStateDTO.self, from: data)
    }

    func copilotThreads() async throws -> [ThreadSummaryDTO] {
        let (data, http) = try await send { try copilotRequest("api/copilot/threads") }
        guard http.statusCode == 200 else { throw copilotError(data, http.statusCode) }
        return try JSONDecoder().decode(ThreadListDTO.self, from: data).threads
    }

    func deleteThread(_ id: String) async throws {
        let (data, http) = try await send { try copilotRequest("api/copilot/threads/\(id)", method: "DELETE") }
        guard http.statusCode == 200 else { throw copilotError(data, http.statusCode) }
    }

    /// 確認卡片：確認執行或取消（確認碼只在伺服器，App 只送決定）
    func copilotDecide(card: String, approve: Bool, typed: String?, thread: String?) async throws -> ConfirmResponseDTO {
        var body: [String: JSONValue] = ["id": .string(card), "decision": .string(approve ? "approve" : "reject")]
        if let typed { body["typed"] = .string(typed) }
        if let thread { body["threadId"] = .string(thread) }
        let payload: JSONValue = .object(body)
        let (data, http) = try await send { try copilotRequest("api/copilot/confirm", method: "POST", body: payload) }
        guard http.statusCode == 200 else { throw copilotError(data, http.statusCode) }
        return try JSONDecoder().decode(ConfirmResponseDTO.self, from: data)
    }

    /// 跟 Xena 說一句話：SSE 串流（每個事件一行 data: JSON），和網頁版同一個端點
    func copilotChat(message: String, thread: String?, answering: String?) -> AsyncThrowingStream<CopilotEvent, any Error> {
        var body: [String: JSONValue] = [
            "message": .string(message),
            "page": ["path": "/app", "title": "StudioX App"],
        ]
        if let thread { body["threadId"] = .string(thread) }
        if let answering { body["answering"] = .string(answering) }
        let payload: JSONValue = .object(body)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let bytes = try await openStream(payload)
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if let event = try? decoder.decode(CopilotEvent.self, from: Data(raw.utf8)) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func openStream(_ payload: JSONValue) async throws -> URLSession.AsyncBytes {
        for attempt in 0..<2 {
            var r = try copilotRequest("api/copilot/chat", method: "POST", body: payload)
            r.timeoutInterval = 160
            r.setValue("text/event-stream", forHTTPHeaderField: "accept")
            r.setValue("Bearer \(try await accessToken(forceRefresh: attempt > 0))", forHTTPHeaderField: "authorization")
            let (bytes, response) = try await URLSession.shared.bytes(for: r)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 { continue }
            if status == 401 {
                expire()
                throw APIError.unauthorized
            }
            guard status == 200 else {
                var raw = Data()
                for try await byte in bytes { raw.append(byte) }
                throw copilotError(raw, status)
            }
            return bytes
        }
        throw APIError.unauthorized
    }
}
