import CryptoKit
import Foundation
import Security

// 接上正式的 StudioX Console 的準備（雛形還沒用到，App 現在跑 DemoConsole）。
// console 那邊要先補的東西見 README「接上正式環境」：
//   1. 給 App 用的公開 OIDC client（沒有密鑰、PKCE、回傳網址 studiox-console://oauth）
//   2. /api/copilot/* 接受 Bearer token（現在只認瀏覽器的登入 cookie＋同網域的 Origin）
//   3. App 用的清單 API（網站、訂單、客服）與 APNs 推播

enum ConsoleConfig {
    static let baseURL = URL(string: "https://console.studiox.tw")!
    static let clientID = "studiox-ios"
    static let callbackScheme = "studiox-console"
    static let redirectURI = "studiox-console://oauth"
}

/// 登入用的 PKCE（S256）：console 的 /api/console/oidc/authorize 一定要
struct PKCE {
    let verifier: String
    let challenge: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        verifier = Data(bytes).base64URL
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }
}

extension Data {
    nonisolated var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// 用 StudioX 帳號登入：在 App 內的瀏覽器打開 console 的授權頁，拿授權碼換 token
struct ConsoleSignIn {
    let pkce = PKCE()
    let state = UUID().uuidString

    var authorizeURL: URL {
        var c = URLComponents(url: ConsoleConfig.baseURL.appending(path: "api/console/oidc/authorize"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: ConsoleConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: ConsoleConfig.redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return c.url!
    }

    /// 授權頁轉回 studiox-console://oauth?code=…&state=… 之後：換成 token
    func exchange(callback: URL) async throws -> ConsoleToken {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else { throw ConsoleError.notConnected }
        var req = URLRequest(url: ConsoleConfig.baseURL.appending(path: "api/console/oidc/token"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: ConsoleConfig.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: ConsoleConfig.redirectURI),
            URLQueryItem(name: "code_verifier", value: pkce.verifier),
        ]
        req.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ConsoleError.notConnected }
        return try JSONDecoder().decode(ConsoleToken.self, from: data)
    }
}

nonisolated struct ConsoleToken: Decodable, Sendable {
    let accessToken: String
    let idToken: String?
    let expiresIn: Int?

    private nonisolated enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}

/// Xena 的串流：和網頁版同一個端點與格式（POST /api/copilot/chat，回 SSE，每個事件一行 data: JSON）
struct XenaStreamClient {
    var token: String
    var baseURL = ConsoleConfig.baseURL

    private struct Body: Encodable {
        struct Page: Encodable {
            var path: String
            var title: String
        }
        var message: String
        var threadId: String?
        var answering: String?
        var page: Page
    }

    func chat(_ request: XenaRequest) -> AsyncThrowingStream<CopilotEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: baseURL.appending(path: "api/copilot/chat"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "accept")
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
                    req.httpBody = try JSONEncoder().encode(Body(
                        message: request.message,
                        threadId: request.threadID,
                        answering: request.answering,
                        page: Body.Page(path: "/app", title: "StudioX iOS")
                    ))
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ConsoleError.notConnected }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if let event = try? decoder.decode(CopilotEvent.self, from: Data(json.utf8)) {
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
}
