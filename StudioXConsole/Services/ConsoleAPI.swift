import AuthenticationServices
import Foundation
import SwiftUI

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
    /// 還沒同意 Xena 使用雲端 AI（CloudAIConsentSheet）：資料不送出去
    case needsAIConsent

    var errorDescription: String? {
        switch self {
        case .unauthorized: "登入已經過期，請重新登入"
        case .offline: "連不上網路，請稍後再試"
        case .http(let code): "伺服器回應 \(code)，請稍後再試"
        case .rpc(let message), .tool(let message): message
        case .scope(let message): message
        case .needsAIConsent: "要先同意 Xena 使用雲端 AI（設定 → AI 與隱私）"
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
        // 示範模式（UI 截圖）：不用登入，所有請求由 DemoServer 回答
        if DemoServer.enabled { tokens = Self.demoTokens }
    }

    private static let demoTokens = Tokens(access: "demo", refresh: "demo", expiresAt: .distantFuture)

    /// 歡迎頁的「先看看示範」：不用登入，所有請求由 DemoServer 用假資料回答（登出就結束）
    func enterDemo() {
        DemoServer.enabled = true
        tokens = Self.demoTokens
    }

    var isSignedIn: Bool { tokens != nil }

    func signIn(using session: WebAuthenticationSession) async throws {
        tokens = try await Auth.signIn(using: session)
    }

    func signOut() async {
        if DemoServer.enabled {
            DemoServer.enabled = false
            tokens = nil
            return
        }
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

    /// 帶 token 送出；401 就換 token 再試一次。
    /// 讀資料的請求（GET、查詢的工具）連線斷了、逾時：多半是 App 放著一陣子、舊的連線已經死了（下拉重新整理第一次逾時、第二次才好）——
    /// 第一次只等 15 秒，換一條新的連線馬上再試一次，不讓你看到錯誤。寫入的不重送（避免做兩次）。
    private func send(retryable: Bool? = nil, _ makeRequest: () throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        if DemoServer.enabled { return DemoServer.respond(to: try makeRequest()) }
        var refreshedToken = false
        var reconnected = false
        while true {
            var request = try makeRequest()
            let canRetry = retryable ?? ((request.httpMethod ?? "GET") == "GET")
            if canRetry && !reconnected { request.timeoutInterval = min(request.timeoutInterval, 15) }
            request.setValue("Bearer \(try await accessToken(forceRefresh: refreshedToken))", forHTTPHeaderField: "authorization")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where Self.stale.contains(error.code) || error.code == .notConnectedToInternet {
                if canRetry && !reconnected && Self.stale.contains(error.code) {
                    reconnected = true
                    await freshConnections()
                    continue
                }
                throw APIError.offline
            }
            guard let http = response as? HTTPURLResponse else { throw APIError.http(0) }
            if http.statusCode == 401 {
                if !refreshedToken {
                    refreshedToken = true
                    continue
                }
                expire()
                throw APIError.unauthorized
            }
            return (data, http)
        }
    }

    /// 連線死掉的樣子（換一條新的連線通常就好）
    private static let stale: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .secureConnectionFailed]

    /// 之後的請求都開新的連線（App 從背景回來、下拉重新整理：舊的連線可能已經被網路斷掉了）
    func freshConnections() async {
        await URLSession.shared.flush()
    }

    /// 只是查資料的工具：連線斷了可以放心重送（寫入一律要確認，不重送）
    private static let readTools: Set<String> = ["list", "get", "search", "ops_report", "traffic_report", "search_report", "site_guide", "list_sites"]

    private func json(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    // MARK: Xena 的雲端聲音

    /// 一句話 → 聲音（console 用金鑰庫的 OpenAI／Google 轉，mp3 或 wav）
    func speech(_ text: String, voice: String) async throws -> Data {
        try requireCloudAI()
        let body = try JSONEncoder().encode(["text": text, "voice": voice])
        let (data, http) = try await send {
            var r = URLRequest(url: ConsoleConfig.baseURL.appending(path: "api/app/tts"))
            r.httpMethod = "POST"
            r.timeoutInterval = 25
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.httpBody = body
            return r
        }
        guard http.statusCode == 200, http.value(forHTTPHeaderField: "content-type")?.hasPrefix("audio") == true else {
            throw APIError.http(http.statusCode)
        }
        return data
    }

    /// 雲端聲音能不能用（設定頁）
    func speechAvailable() async -> Bool {
        guard let (data, http) = try? await send({ URLRequest(url: ConsoleConfig.baseURL.appending(path: "api/app/tts")) }),
              http.statusCode == 200 else { return false }
        return (try? json(data))?["available"]?.bool == true
    }

    // MARK: 我

    func me() async throws -> Me {
        let (data, http) = try await send { URLRequest(url: ConsoleConfig.baseURL.appending(path: "api/app/me")) }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        return Me(try json(data))
    }

    /// 刪除自己的帳號（console 的 /api/app/account）：網站的權限、Apple 的連結、所有登入與推播裝置一起刪掉。
    /// 平台管理者不能在 App 刪（console 回 403 和說明）
    func deleteAccount() async throws {
        let (data, http) = try await send(retryable: false) {
            var r = URLRequest(url: ConsoleConfig.baseURL.appending(path: "api/app/account"))
            r.httpMethod = "DELETE"
            return r
        }
        guard http.statusCode == 200 else {
            if let message = (try? json(data))?["message"]?.string { throw APIError.tool(message) }
            throw APIError.http(http.statusCode)
        }
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
        let (data, http) = try await send(retryable: Self.readTools.contains(name)) {
            var r = URLRequest(url: URL(string: ConsoleConfig.mcpURL)!)
            r.httpMethod = "POST"
            r.timeoutInterval = 45
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue("application/json, text/event-stream", forHTTPHeaderField: "accept")
            r.httpBody = payload
            return r
        }
        let reply = rpcReply(data, contentType: http.value(forHTTPHeaderField: "content-type"))
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

    /// JSON-RPC 的回覆：一般是 JSON；伺服器用 SSE 回的話（data: 一行一個訊息）取最後一個
    private func rpcReply(_ data: Data, contentType: String?) -> JSONValue {
        if contentType?.contains("text/event-stream") == true {
            let text = String(decoding: data, as: UTF8.self)
            let messages = text.split(whereSeparator: \.isNewline)
                .filter { $0.hasPrefix("data:") }
                .compactMap { try? json(Data($0.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)) }
            return messages.last { $0["result"] != nil || $0["error"] != nil } ?? .null
        }
        return (try? json(data)) ?? .null
    }

    // MARK: 欄位定義、現在的值、換圖（/api/app/schema、/api/app/record、網站的上傳連結）

    /// 網站的資料與欄位定義（網站的 lib/mcp-schema.ts）
    func schema(site: String) async throws -> SiteSchema {
        var c = URLComponents(url: ConsoleConfig.baseURL.appending(path: "api/app/schema"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "site", value: site)]
        let url = c.url!
        let (data, http) = try await send { URLRequest(url: url) }
        let body = (try? json(data)) ?? .null
        guard http.statusCode == 200 else {
            if http.statusCode == 404, body["error"]?.string == "not_found" { throw APIError.tool("console 還沒更新到支援 App 編輯的版本") }
            throw APIError.tool(body["message"]?.string ?? "拿不到這個網站的欄位定義（\(http.statusCode)）")
        }
        return SiteSchema(body)
    }

    /// 一筆資料現在的欄位值（和 update 比對新舊的同一份；金額是「分」）
    func record(site: String, entity: String, id: String?) async throws -> RecordValues {
        var c = URLComponents(url: ConsoleConfig.baseURL.appending(path: "api/app/record"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "site", value: site), URLQueryItem(name: "entity", value: entity)] + (id.map { [URLQueryItem(name: "id", value: $0)] } ?? [])
        let url = c.url!
        let (data, http) = try await send { URLRequest(url: url) }
        let body = (try? json(data)) ?? .null
        guard http.statusCode == 200 else { throw APIError.tool(body["message"]?.string ?? "拿不到這筆資料（\(http.statusCode)）") }
        return RecordValues(body)
    }

    /// 換圖：網站給的一次性上傳連結（set_images 的 requestUpload），直接把檔案送到網站
    /// （和手機上點連結上傳是同一條路：存恢復點、通知店主、稽核）。回傳新的圖片清單
    func upload(to link: URL, data: Data, mime: String, filename: String) async throws -> [String] {
        let result = try await postUpload(to: link, data: data, mime: mime, filename: filename)
        return result["images"]?.array.compactMap(\.string) ?? []
    }

    /// 對話的附件：用 reply_xena 給的一次性連結把檔案送到網站（存進網站的儲存），回存好的網址
    func uploadAttachment(to link: URL, data: Data, mime: String, filename: String) async throws -> UploadedAttachment {
        if DemoServer.enabled {
            try? await Task.sleep(for: .milliseconds(600))
            let kind = mime.hasPrefix("image/") ? "image" : "file"
            return UploadedAttachment(kind: kind, url: "https://demo.studiox.tw/xena/staff/\(UUID().uuidString.prefix(8)).\(kind == "image" ? "jpg" : "pdf")", name: filename, size: data.count, mime: mime)
        }
        let result = try await postUpload(to: link, data: data, mime: mime, filename: filename)
        guard let url = result["url"]?.string else { throw APIError.tool("網站沒有回存好的網址") }
        return UploadedAttachment(
            kind: result["kind"]?.string ?? (mime.hasPrefix("image/") ? "image" : "file"),
            url: url,
            name: result["name"]?.string ?? filename,
            size: result["size"]?.int ?? data.count,
            mime: result["mime"]?.string ?? mime
        )
    }

    private func postUpload(to link: URL, data: Data, mime: String, filename: String) async throws -> JSONValue {
        let token = link.lastPathComponent
        guard var c = URLComponents(url: link, resolvingAgainstBaseURL: false), !token.isEmpty else { throw APIError.tool("上傳連結不正確") }
        c.path = "/api/upload/\(token)"
        c.query = nil
        guard let url = c.url else { throw APIError.tool("上傳連結不正確") }
        let boundary = "studiox-\(UUID().uuidString)"
        var body = Data()
        // 檔名放在標頭裡：拿掉引號、換行（中文檔名照原樣，網站收得到）
        let safeName = filename.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 120
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        let reply: Data
        let response: URLResponse
        do {
            (reply, response) = try await URLSession.shared.upload(for: r, from: body)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost || error.code == .timedOut {
            throw APIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let result = (try? json(reply)) ?? .null
        guard status == 200, result["ok"]?.bool == true else { throw APIError.tool(result["error"]?.string ?? "上傳失敗（\(status)）") }
        return result
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

    // MARK: 通知（/api/app/devices、/api/app/notifications）

    private func appRequest(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: JSONValue? = nil) throws -> URLRequest {
        var c = URLComponents(url: ConsoleConfig.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        var r = URLRequest(url: c.url!)
        r.httpMethod = method
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.httpBody = try JSONEncoder().encode(body)
        }
        return r
    }

    private func appReply(_ data: Data, _ http: HTTPURLResponse, fallback: String) throws -> JSONValue {
        let body = (try? json(data)) ?? .null
        guard http.statusCode == 200 else {
            if http.statusCode == 404, body["error"]?.string == "not_found", body["message"] == nil { throw APIError.tool("console 還沒更新到支援 App 通知的版本") }
            throw APIError.tool(body["message"]?.string ?? "\(fallback)（\(http.statusCode)）")
        }
        return body
    }

    /// 登記這台裝置（Apple 給的 token；sandbox＝Xcode 直接裝，production＝TestFlight、App Store）
    func registerDevice(token: String, environment: String, name: String) async throws -> PushRegistration {
        let payload: JSONValue = ["token": .string(token), "environment": .string(environment), "name": .string(name)]
        let (data, http) = try await send { try appRequest("api/app/devices", method: "POST", body: payload) }
        return PushRegistration(try appReply(data, http, fallback: "通知登記失敗"))
    }

    /// 關掉哪些網站的通知（網站代號）
    func setMutedSites(token: String, sites: [String]) async throws -> PushRegistration {
        let payload: JSONValue = ["token": .string(token), "mutedSites": .array(sites.map { .string($0) })]
        let (data, http) = try await send { try appRequest("api/app/devices", method: "PATCH", body: payload) }
        return PushRegistration(try appReply(data, http, fallback: "沒有存起來"))
    }

    /// 登出前：這台裝置不要再收到通知
    func removeDevice(token: String) async {
        _ = try? await send { try appRequest("api/app/devices", method: "DELETE", query: [URLQueryItem(name: "token", value: token)]) }
    }

    /// 送一則測試通知給這台裝置。失敗丟網站（console）寫的原因
    func testPush(token: String) async throws {
        let payload: JSONValue = ["token": .string(token)]
        let (data, http) = try await send { try appRequest("api/app/devices/test", method: "POST", body: payload) }
        let body = (try? json(data)) ?? .null
        guard http.statusCode == 200, body["ok"]?.bool == true else {
            throw APIError.tool(body["message"]?.string ?? "測試通知沒有送出（\(http.statusCode)）")
        }
    }

    /// 他在某個網站的個人通知設定（網站沒有的話 supported＝false）；帶 set 就是改
    func notificationPrefs(site: String, set: JSONValue? = nil) async throws -> NotificationPrefs {
        let (data, http): (Data, HTTPURLResponse)
        if let set {
            let payload: JSONValue = ["site": .string(site), "prefs": set]
            (data, http) = try await send { try appRequest("api/app/notifications", method: "PUT", body: payload) }
        } else {
            (data, http) = try await send { try appRequest("api/app/notifications", query: [URLQueryItem(name: "site", value: site)]) }
        }
        return NotificationPrefs(try appReply(data, http, fallback: "拿不到通知設定"))
    }

    // MARK: 等你決定（/api/app/decisions）

    /// console 看各網站的數據找到、值得做的優化。console 還沒更新到有這個（404）就是沒有
    func decisions() async throws -> [Decision] {
        let (data, http) = try await send { try appRequest("api/app/decisions") }
        if http.statusCode == 404 { return [] }
        return (try appReply(data, http, fallback: "拿不到建議")["decisions"]?.array ?? []).compactMap(Decision.init)
    }

    /// 交給 Xena 了／不用了／之後再說：那一則一段時間內不再出現（跟著帳號走）
    func decide(_ id: String, action: Decision.Action) async throws {
        let payload: JSONValue = ["id": .string(id), "action": .string(action.rawValue)]
        let (data, http) = try await send { try appRequest("api/app/decisions", method: "POST", body: payload) }
        _ = try appReply(data, http, fallback: "沒有存起來")
    }

    // MARK: 客服對話的「Xena 擬回覆／潤飾」（/api/app/reply-draft）

    /// console 的 Xena 讀整段對話寫一段回覆（draft：notes 是專人交代的重點；polish：text 是要潤飾的那段）。只回草稿，不會送出。
    /// kind：conversation＝Xena 對話（官網、LINE）、thread＝Email 客服信
    func replyDraft(site: String, id: String, polish: Bool, text: String, kind: String = "conversation") async throws -> String {
        try requireCloudAI()
        let payload: JSONValue = ["site": .string(site), "id": .string(id), "mode": .string(polish ? "polish" : "draft"), "text": .string(text), "kind": .string(kind)]
        let (data, http) = try await send { try appRequest("api/app/reply-draft", method: "POST", body: payload) }
        if http.statusCode == 404, (try? json(data))?["message"] == nil { throw APIError.tool("console 還沒更新到有這個功能") }
        guard let draft = try appReply(data, http, fallback: "Xena 寫不出來")["text"]?.string, !draft.isEmpty else {
            throw APIError.tool("Xena 這次沒有寫出東西，再試一次")
        }
        return draft
    }

    /// 回覆建議（Xena 的那一半）：這位客人的分析＋三種下一句。客人同一句話之後再叫拿的是快取，不再算額度
    func replySuggest(site: String, id: String, refresh: Bool = false) async throws -> XenaReplySuggestion {
        try requireCloudAI()
        let payload: JSONValue = ["site": .string(site), "id": .string(id), "refresh": .bool(refresh)]
        let (data, http) = try await send { try appRequest("api/app/reply-suggest", method: "POST", body: payload) }
        if http.statusCode == 404, (try? json(data))?["message"] == nil { throw APIError.tool("console 還沒更新到有這個功能") }
        let suggestion = XenaReplySuggestion(try appReply(data, http, fallback: "Xena 想不出建議"))
        guard !suggestion.replies.isEmpty else { throw APIError.tool("Xena 這次沒有想出建議，再試一次") }
        return suggestion
    }

    // MARK: Xena（/api/copilot）

    /// 會把資料交給雲端 AI 的請求，送出前再檢查一次有沒有同意（畫面上漏問了也不會送出去）
    private func requireCloudAI() throws {
        guard AppSettings.cloudAIAllowedNow else { throw APIError.needsAIConsent }
    }

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

    /// 上傳一份文件給 Xena（App 在對話裡附上 .md／.txt）：存成草稿，對話裡帶草稿編號
    func uploadDraft(text: String, name: String) async throws -> DraftUpload {
        try requireCloudAI()
        let payload: JSONValue = ["text": .string(text), "name": .string(name)]
        let (data, http) = try await send { try copilotRequest("api/copilot/drafts", method: "POST", body: payload) }
        guard http.statusCode == 200 else { throw copilotError(data, http.statusCode) }
        return try JSONDecoder().decode(DraftUpload.self, from: data)
    }

    /// 一份草稿的全文與「改了哪些」（確認卡片的「看完整內容」）
    func draftDocument(_ id: String) async throws -> DraftDocument {
        let (data, http) = try await send { try copilotRequest("api/copilot/drafts/\(id)") }
        guard http.statusCode == 200 else { throw copilotError(data, http.statusCode) }
        return try JSONDecoder().decode(DraftDocument.self, from: data)
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
        // 示範模式：Xena 用示範的回答（不連 AI）
        if DemoServer.enabled {
            let reply = DemoServer.copilotReply(message)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    continuation.yield(.text(reply))
                    continuation.yield(.done)
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
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
        try requireCloudAI()
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
