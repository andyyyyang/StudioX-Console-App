import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// console 的網址與 App 的 OAuth client（atelier-cms 的 src/lib/oauth.ts 的 APP_CLIENT_ID）
enum ConsoleConfig {
    static let baseURL = URL(string: "https://console.studiox.tw")!
    static let clientID = "studiox-app"
    static let callbackScheme = "studiox-console"
    static let redirectURI = "studiox-console://oauth"
    static let mcpURL = "https://console.studiox.tw/api/mcp"
}

/// 登入的憑證：存在 Keychain（這台裝置、解鎖後才讀得到）
nonisolated struct Tokens: Codable, Sendable {
    var access: String
    var refresh: String
    var expiresAt: Date

    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

nonisolated enum AuthError: LocalizedError {
    case cancelled
    case denied(String)
    case expired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "登入取消了"
        case .denied(let why): why
        case .expired: "登入已經過期，請重新登入"
        case .server(let why): why
        }
    }
}

/// 用 StudioX 帳號登入：系統的登入視窗打開 console 的登入頁（Apple、Email、邀請都一樣），
/// 回到 studiox-console://oauth 帶授權碼，再用 PKCE 換 token。token 一小時、refresh 30 天輪替。
enum Auth {
    private static let keychainAccount = "console-tokens"

    static func signIn(using session: WebAuthenticationSession) async throws -> Tokens {
        let verifier = randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomURLSafe(16)

        var c = URLComponents(url: ConsoleConfig.baseURL.appending(path: "api/oauth/authorize"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: ConsoleConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: ConsoleConfig.redirectURI),
            URLQueryItem(name: "scope", value: "admin:read admin:write admin:refund"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "resource", value: ConsoleConfig.mcpURL),
        ]

        let callback: URL
        do {
            // 和 Safari 共用登入狀態：已經在 Safari 登入過 console 就不用再打密碼
            callback = try await session.authenticate(using: c.url!, callbackURLScheme: ConsoleConfig.callbackScheme, preferredBrowserSession: .shared)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw AuthError.cancelled
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw AuthError.denied(value("error_description") ?? (error == "access_denied" ? "這個帳號沒有可以管理的網站" : "登入沒有完成，請再試一次"))
        }
        guard value("state") == state, let code = value("code") else { throw AuthError.denied("登入沒有完成，請再試一次") }

        let tokens = try await tokenRequest([
            "grant_type": "authorization_code",
            "client_id": ConsoleConfig.clientID,
            "code": code,
            "redirect_uri": ConsoleConfig.redirectURI,
            "code_verifier": verifier,
        ])
        save(tokens)
        return tokens
    }

    /// 用 refresh token 換新的一組（舊的 refresh token 同時作廢）
    static func refresh(_ tokens: Tokens) async throws -> Tokens {
        let next = try await tokenRequest([
            "grant_type": "refresh_token",
            "client_id": ConsoleConfig.clientID,
            "refresh_token": tokens.refresh,
        ])
        save(next)
        return next
    }

    /// 登出：撤銷 token、清掉 Keychain（網路不通也照樣登出）
    static func signOut(_ tokens: Tokens?) async {
        clear()
        guard let tokens else { return }
        for token in [tokens.refresh, tokens.access] {
            var req = URLRequest(url: ConsoleConfig.baseURL.appending(path: "api/oauth/revoke"))
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
            req.httpBody = formBody(["token": token])
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private static func tokenRequest(_ form: [String: String]) async throws -> Tokens {
        var req = URLRequest(url: ConsoleConfig.baseURL.appending(path: "api/oauth/token"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        req.httpBody = formBody(form)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        guard status == 200, let access = json?["access_token"]?.string, let refresh = json?["refresh_token"]?.string else {
            if json?["error"]?.string == "invalid_grant" { throw AuthError.expired }
            throw AuthError.server(json?["error_description"]?.string ?? "登入沒有完成（\(status)），請再試一次")
        }
        let ttl = json?["expires_in"]?.double ?? 3600
        return Tokens(access: access, refresh: refresh, expiresAt: Date().addingTimeInterval(ttl))
    }

    private static func formBody(_ form: [String: String]) -> Data {
        var c = URLComponents()
        c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents 不會編碼 +，token 裡可能有
        let encoded = (c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        return Data(encoded.utf8)
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        if SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer) != errSecSuccess {
            buffer = (0..<bytes).map { _ in UInt8.random(in: .min ... .max) }
        }
        return Data(buffer).base64URL
    }

    // MARK: Keychain

    static func load() -> Tokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "tw.studiox.console",
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    static func save(_ tokens: Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        clear()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "tw.studiox.console",
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "tw.studiox.console",
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
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
