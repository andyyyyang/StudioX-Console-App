import Foundation

/// 示範模式：歡迎頁按「先看看示範」（或啟動參數 `-demo`）時不連 console，所有請求在這裡用假資料回答，
/// 走的是 App 原本的程式（ConsoleAPI.send 這一個入口），所以每個畫面都會照真的樣子畫出來。
/// 給還沒有帳號的人、App Store 的審核看（不會碰到任何真的網站和客人），也用在 UI 截圖（.github/workflows/ui-screenshots.yml）；
/// 網站（晨麥手作、木白設計）、客人的名字、訂單都是編的。寫入（回覆、改狀態…）照樣跳確認、回「已完成」，但什麼都不會真的發生。
///
/// 其他啟動參數：
///   -demoTab sites|orders|inbox|account|search   打開哪個分頁
///   -demoRoute site|traffic|order|member|thread|line|products|product|xena   打開哪一頁（line：LINE 來的 Xena 對話）
///   -demoSheet today|chenmai.studiox.tw   首頁卡片打開的 sheet
///   -demoLock YES   顯示 Face ID 的鎖定畫面
///   -demoTools YES   對話頁打開輸入列的「＋」選單（配 -demoRoute line）
nonisolated enum DemoServer {
    /// 現在是示範模式（歡迎頁按了「先看看示範」，登出就結束）
    nonisolated(unsafe) static var enabled = screenshots
    /// UI 截圖（啟動參數 -demo）：水珠不動、照參數打開指定的畫面
    static let screenshots = ProcessInfo.processInfo.arguments.contains("-demo")

    /// 示範模式裡跟 Xena 說話：照關鍵字回一段示範的回答（不連 AI）
    static func copilotReply(_ message: String) -> String {
        let m = message
        if m.contains("訂單") || m.contains("出貨") {
            return "晨麥手作目前有 **6 筆等出貨**、2 筆待付款。最早的一筆是昨天下午的 #20260602-1042（手工蛋捲禮盒 ×2）。\n\n要我把已付款的 6 筆一起標成「已出貨」嗎？（示範模式不會真的改）"
        }
        if m.contains("客人") || m.contains("回覆") || m.contains("客服") {
            return "有 **2 位客人**在等回覆：\n- 陳小姐問蛋捲禮盒的保存期限（等了 3 小時）\n- LINE 上的 Kevin 想訂 20 盒當公司禮品\n\n要我先幫你擬回覆嗎？"
        }
        if m.contains("流量") || m.contains("訪客") {
            return "這週晨麥手作有 **3,820 位訪客**，比上週多 12%。從 Instagram 來的最多，其次是 Google 搜尋「蛋捲禮盒」。"
        }
        if m.contains("賣") || m.contains("營收") || m.contains("收款") {
            return "這週晨麥手作有 **64 筆訂單**、收款 NT$102,300，比上週多 18%。賣最好的是手工蛋捲禮盒（41 盒），庫存剩 38 盒，照這個速度大約 6 天賣完。"
        }
        return "這是示範模式：我用假的網站資料回答。你可以問我「今天有什麼要注意的？」「有誰在等回覆？」「這週賣得怎麼樣？」，或打開各個分頁看看。登入 StudioX 帳號後，我就會看你自己的網站。"
    }

    static func respond(to request: URLRequest) -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://console.studiox.tw")!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let q = { (name: String) in items.first { $0.name == name }?.value }
        var status = 200
        let body: JSONValue
        switch url.path() {
        case "/api/app/me": body = parse(me)
        case "/api/app/schema": body = parse(schema(site: q("site") ?? ""))
        case "/api/app/record": body = parse(record(entity: q("entity") ?? "", id: q("id")))
        case "/api/mcp": body = mcp(request.httpBody)
        case "/api/copilot": body = screenshots ? parse(copilotThread) : ["thread": .null]
        case "/api/copilot/confirm": body = parse(confirmed(request.httpBody))
        case "/api/copilot/threads": body = ["threads": []]
        case "/api/copilot/drafts": body = ["id": "d_demo_upload_0001", "title": "上傳的文件", "format": "markdown", "chars": 1200]
        case let path where path.hasPrefix("/api/copilot/drafts/"): body = parse(draftDocument)
        case "/api/app/devices": body = ["configured": false, "device": .null]
        case "/api/app/notifications": body = ["supported": false]
        case "/api/app/account": body = ["ok": true, "demo": true]
        case "/api/app/decisions": body = request.httpMethod == "POST" ? ["ok": true] : parse(decisions)
        case "/api/app/reply-draft": body = ["text": .string(replyDraft(request.httpBody))]
        case "/api/app/reply-suggest": body = parse(replySuggestion)
        case "/api/app/signature": body = ["name": "示範帳號", "title": "店長", "phone": ""]
        case let path where path.hasPrefix("/api/admin/") || path == "/api/copilot/settings":
            let reply = admin(path: path, method: request.httpMethod ?? "GET", body: request.httpBody)
            status = reply.0
            body = reply.1
        default:
            status = 404
            body = ["error": "not_found", "message": "示範模式沒有這個資料"]
        }
        let data = (try? JSONEncoder().encode(body)) ?? Data()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["content-type": "application/json"])!
        return (data, response)
    }

    // MARK: 平台管理（console 的 /api/admin/*）

    /// 示範模式的平台管理：讀的回固定的資料，寫的一律回「示範模式不會真的改」
    private static func admin(path: String, method: String, body: Data?) -> (Int, JSONValue) {
        let p = path.replacingOccurrences(of: "/api/admin/", with: "")
        if method != "GET" {
            if p == "console/sites" {
                return (200, ["site": ["id": "s_demo_new", "name": "新網站", "clientId": "site_demo"], "secret": "demo",
                              "env": "CONSOLE_URL=https://console.studiox.tw\nCONSOLE_CLIENT_ID=site_demo\nCONSOLE_CLIENT_SECRET=（示範模式）"])
            }
            if p.hasSuffix("/invites") { return (200, ["url": "https://console.studiox.tw/invite/demo", "expiresAt": .string(ago(hours: -168)), "sent": false, "sendError": .null]) }
            if p.hasSuffix("/test") { return (200, ["ok": true, "message": "示範模式：金鑰可以用"]) }
            if p.hasSuffix("/line") { return (200, parse(lineConnect)) }
            return (400, ["error": "示範模式不會真的修改；登入你的 StudioX 帳號就能操作。"])
        }
        switch p {
        case "console": return (200, parse(adminOrgs))
        case "console/stats":
            return (200, parse(#"{"days":7,"sites":{"s1":{"visitors":1843,"pageviews":6120,"change":18,"live":12},"s2":{"visitors":412,"pageviews":1380,"change":-4,"live":3},"s3":{"visitors":96,"pageviews":240,"change":7,"live":1}}}"#))
        case let x where x.hasPrefix("console/sites/"): return (200, parse(adminSite))
        case "platform/requests": return (200, parse(adminRequests))
        case "platform/services": return (200, parse(adminServices))
        case let x where x.hasPrefix("platform/services/") && x.hasSuffix("/assistant"): return (200, parse(adminAssistant))
        case let x where x.hasPrefix("platform/services/"): return (200, parse(adminSiteServices))
        case "platform/keys": return (200, parse(adminKeys))
        case let x where x.hasPrefix("platform/keys/"):
            return (200, parse(#"{"id":"k1","provider":"anthropic","label":"StudioX 主帳號","orgId":null,"disabled":false,"values":{"apiKey":""},"filled":{"apiKey":true}}"#))
        case "platform/usage": return (200, parse(adminUsage))
        case "platform/ai-usage": return (200, parse(adminAiUsage))
        case "platform/billing": return (200, parse(adminBilling))
        case "platform/plans": return (200, parse(adminPlans))
        case "platform/pricing": return (200, parse(adminPricing))
        case "team": return (200, parse(adminTeam))
        case "audit": return (200, parse(adminAudit))
        case "mcp-connectors": return (200, parse(adminConnectors))
        case "ai-records": return (200, parse(adminAiRecords))
        case "/api/copilot/settings": return (200, parse(adminCopilot))
        default: return (404, ["error": "示範模式沒有這個資料"])
        }
    }

    private static var adminOrgs: String { """
    {"orgs":[
     {"id":"o1","name":"晨麥手作","note":"台南手工蛋捲","createdAt":"2026-03-02T08:00:00.000Z","updatedAt":"2026-09-30T08:00:00.000Z",
      "sites":[{"id":"s1","orgId":"o1","name":"晨麥手作","siteUrl":"https://chenmai.studiox.tw","cmsUrl":"https://admin.chenmai.studiox.tw","status":"active","lastSyncAt":"\(ago(hours: 2))","lastSyncError":null,"members":4}]},
     {"id":"o2","name":"StudioX","note":null,"createdAt":"2026-01-10T08:00:00.000Z","updatedAt":"2026-09-30T08:00:00.000Z",
      "sites":[{"id":"s2","orgId":"o2","name":"StudioX.tw","siteUrl":"https://studiox.tw","cmsUrl":"https://cms.studiox.tw","status":"active","lastSyncAt":"\(ago(hours: 5))","lastSyncError":null,"members":3}]},
     {"id":"o3","name":"木白設計","note":"室內設計工作室","createdAt":"2026-06-18T08:00:00.000Z","updatedAt":"2026-09-30T08:00:00.000Z",
      "sites":[{"id":"s3","orgId":"o3","name":"木白設計","siteUrl":"https://mubai.studiox.tw","cmsUrl":"https://admin.mubai.studiox.tw","status":"active","lastSyncAt":"\(ago(hours: 30))","lastSyncError":"網站回應 502","members":2}]}
    ]}
    """ }

    private static var adminSite: String { """
    {"site":{"id":"s1","orgId":"o1","name":"晨麥手作","siteUrl":"https://chenmai.studiox.tw","cmsUrl":"https://admin.chenmai.studiox.tw","clientId":"site_chenmai","status":"active","supportDesk":false,"lastSyncAt":"\(ago(hours: 2))","lastSyncError":null,"createdAt":"2026-03-02T08:00:00.000Z","updatedAt":"2026-09-30T08:00:00.000Z"},
     "org":{"id":"o1","name":"晨麥手作"},
     "login":{"issuer":"https://console.studiox.tw","clientId":"site_chenmai","redirectUri":"https://admin.chenmai.studiox.tw/api/auth/callback/studiox","env":"CONSOLE_URL=https://console.studiox.tw"},
     "members":[
      {"userId":"u_a","email":"owner@chenmai.example","name":"晨麥店長","signature":{"title":"店長"},"level":"owner","since":"2026-03-02T08:00:00.000Z","appleLinked":true},
      {"userId":"u_b","email":"ops@chenmai.example","name":"出貨小幫手","signature":null,"level":"fulfillment","since":"2026-05-11T08:00:00.000Z","appleLinked":true},
      {"userId":"u_c","email":"cs@chenmai.example","name":"客服","signature":null,"level":"staff","since":"2026-07-20T08:00:00.000Z","appleLinked":false},
      {"userId":"demo","email":"demo@studiox.tw","name":"Andy","signature":{"title":"StudioX"},"level":"manager","since":"2026-03-02T08:00:00.000Z","appleLinked":true}],
     "invites":[{"id":"i1","email":"new@chenmai.example","level":"staff","expiresAt":"\(ago(hours: -120))","createdAt":"\(ago(hours: 48))"}]}
    """ }

    private static var adminRequests: String { """
    {"requests":[
     {"id":"r1","siteId":"s3","site":"木白設計","org":"木白設計","service":"plan:growth","label":"方案：成長","note":"想開 AI 客服跟 LINE","status":"pending","reply":null,"requestedByEmail":"owner@mubai.example","requestedByName":"木白","handledByEmail":null,"handledAt":null,"createdAt":"\(ago(hours: 6))"},
     {"id":"r2","siteId":"s1","site":"晨麥手作","org":"晨麥手作","service":"line","label":"LINE 官方帳號","note":null,"status":"approved","reply":"已經接好了","requestedByEmail":"owner@chenmai.example","requestedByName":"晨麥店長","handledByEmail":"demo@studiox.tw","handledAt":"\(ago(hours: 200))","createdAt":"\(ago(hours: 230))"}
    ]}
    """ }

    private static let adminServices = #"""
    {"services":[{"id":"llm.anthropic","label":"Claude"},{"id":"email","label":"Email"},{"id":"sms","label":"簡訊"},{"id":"payment","label":"金流"},{"id":"line","label":"LINE"},{"id":"search","label":"Google 搜尋成效"},{"id":"assistant","label":"AI 客服"}],
     "sites":[
      {"id":"s1","name":"晨麥手作","org":"晨麥手作","orgId":"o1","status":"active","cmsUrl":"https://admin.chenmai.studiox.tw","services":{"llm.anthropic":{"enabled":true,"billable":true,"keyLabel":"StudioX 主帳號","own":false,"capNtd":3000},"email":{"enabled":true,"billable":true,"keyLabel":"Resend","own":false,"capNtd":null},"sms":{"enabled":true,"billable":true,"keyLabel":"三竹","own":false,"capNtd":null},"payment":{"enabled":true,"billable":false,"keyLabel":"晨麥金流","own":true,"capNtd":null},"line":{"enabled":true,"billable":false,"keyLabel":"晨麥 LINE","own":true,"capNtd":null},"assistant":{"enabled":true,"billable":true,"keyLabel":null,"own":false,"capNtd":null}}},
      {"id":"s2","name":"StudioX.tw","org":"StudioX","orgId":"o2","status":"active","cmsUrl":"https://cms.studiox.tw","services":{"llm.anthropic":{"enabled":true,"billable":false,"keyLabel":"StudioX 主帳號","own":false,"capNtd":null},"email":{"enabled":true,"billable":false,"keyLabel":"Resend","own":false,"capNtd":null},"search":{"enabled":true,"billable":false,"keyLabel":"Search Console","own":false,"capNtd":null}}},
      {"id":"s3","name":"木白設計","org":"木白設計","orgId":"o3","status":"active","cmsUrl":"https://admin.mubai.studiox.tw","services":{"email":{"enabled":true,"billable":true,"keyLabel":"Resend","own":false,"capNtd":null}}}
     ]}
    """#

    private static let adminSiteServices = #"""
    {"site":{"id":"s1","name":"晨麥手作","orgId":"o1","org":"晨麥手作","cmsUrl":"https://admin.chenmai.studiox.tw","status":"active"},
     "services":[
      {"id":"llm.anthropic","label":"Claude","description":"Xena、AI 客服用的模型","provider":"anthropic","providerLabel":"Anthropic（Claude）","via":"gateway","metering":"llm","settingsFields":[],"configured":true,"enabled":true,"keyId":"k1","billable":true,"capNtd":3000,"settings":{},"monthToDateNtd":842,"keys":[{"id":"k1","provider":"anthropic","label":"StudioX 主帳號","hint":"sk-ant-…a1b2","orgId":null,"disabled":false,"own":false}]},
      {"id":"email","label":"Email","description":"訂單通知、客服信","provider":"resend","providerLabel":"Resend（Email）","via":"gateway","metering":"each","settingsFields":[{"key":"fromEmail","label":"寄件地址"},{"key":"fromName","label":"寄件人名稱","optional":true},{"key":"inboundWebhookSecret","label":"收信 Webhook 密鑰","secret":true,"optional":true}],"configured":true,"enabled":true,"keyId":"k2","billable":true,"capNtd":null,"settings":{"fromEmail":"hello@chenmai.example","fromName":"晨麥手作","inboundWebhookSecret":"••••（已設定）"},"monthToDateNtd":126,"keys":[{"id":"k2","provider":"resend","label":"Resend","hint":"re_…9f0c","orgId":null,"disabled":false,"own":false}]},
      {"id":"sms","label":"簡訊","description":"行銷簡訊、通知","provider":"mitake","providerLabel":"三竹簡訊","via":"gateway","metering":"each","settingsFields":[],"configured":true,"enabled":true,"keyId":"k3","billable":true,"capNtd":null,"settings":{},"monthToDateNtd":318,"keys":[{"id":"k3","provider":"mitake","label":"三竹","hint":"…","orgId":null,"disabled":false,"own":false}]},
      {"id":"line","label":"LINE 官方帳號","description":"客人在 LINE 問 Xena","provider":"line","providerLabel":"LINE 官方帳號","via":"site","metering":"none","settingsFields":[],"configured":true,"enabled":true,"keyId":"k4","billable":false,"capNtd":null,"settings":{},"monthToDateNtd":null,"keys":[{"id":"k4","provider":"line","label":"晨麥 LINE","hint":"…3a91","orgId":"o1","disabled":false,"own":true}]},
      {"id":"search","label":"Google 搜尋成效","description":"Search Console 的點擊、曝光","provider":"gsc","providerLabel":"Google 服務帳戶（Search Console）","via":"gateway","metering":"none","settingsFields":[{"key":"property","label":"資源"}],"configured":false,"enabled":false,"keyId":null,"billable":true,"capNtd":null,"settings":{},"monthToDateNtd":null,"keys":[{"id":"k5","provider":"gsc","label":"Search Console","hint":"…","orgId":null,"disabled":false,"own":false}]}
     ]}
    """#

    private static let adminAssistant = #"""
    {"site":{"id":"s1","name":"晨麥手作"},"configured":true,"enabled":true,
     "settings":{"provider":"anthropic","modelMode":"latest","model":"","family":"claude-haiku","includePreview":false,"maxOutputTokens":1200,"fastReplies":true,"followUps":true,"temperature":null,"instructions":"語氣親切，蛋捲的保存方式要講清楚。","rateLimit":20,"allowedOrigins":[],"logConversations":true,"retentionDays":180},
     "providers":[{"id":"anthropic","name":"Anthropic","provisioned":true,"families":[{"family":"claude-haiku","latest":"Claude Haiku"},{"family":"claude-sonnet","latest":"Claude Sonnet"}]},{"id":"openai","name":"OpenAI","provisioned":false,"families":[]}],
     "fromSite":null}
    """#

    private static let lineConnect = #"""
    {"ok":true,"webhook":"https://admin.chenmai.studiox.tw/api/line/webhook","account":{"name":"晨麥手作","id":"@chenmai","picture":null},
     "steps":[{"key":"key","label":"金鑰","ok":true},{"key":"token","label":"換 token","ok":true},{"key":"webhook","label":"設定 Webhook","ok":true},{"key":"test","label":"LINE 打一次測試","ok":true},{"key":"autoreply","label":"關掉官方帳號的自動回應","ok":null,"detail":"LINE 沒有 API，要到官方帳號後台點一下"}]}
    """#

    private static var adminKeys: String { """
    {"keys":[
      {"id":"k1","provider":"anthropic","label":"StudioX 主帳號","hint":"sk-ant-…a1b2","orgId":null,"org":null,"disabled":false,"lastUsedAt":"\(ago(hours: 0.2))","createdAt":"2026-02-01T08:00:00.000Z","updatedAt":"2026-02-01T08:00:00.000Z","sites":3},
      {"id":"k6","provider":"openai","label":"OpenAI 備援","hint":"sk-…7d2e","orgId":null,"org":null,"disabled":false,"lastUsedAt":"\(ago(hours: 20))","createdAt":"2026-04-01T08:00:00.000Z","updatedAt":"2026-04-01T08:00:00.000Z","sites":1},
      {"id":"k2","provider":"resend","label":"Resend","hint":"re_…9f0c","orgId":null,"org":null,"disabled":false,"lastUsedAt":"\(ago(hours: 1))","createdAt":"2026-02-01T08:00:00.000Z","updatedAt":"2026-02-01T08:00:00.000Z","sites":3},
      {"id":"k4","provider":"line","label":"晨麥 LINE","hint":"…3a91","orgId":"o1","org":"晨麥手作","disabled":false,"lastUsedAt":"\(ago(hours: 4))","createdAt":"2026-08-01T08:00:00.000Z","updatedAt":"2026-08-01T08:00:00.000Z","sites":1}],
     "providers":{"anthropic":{"label":"Anthropic（Claude）","fields":[{"key":"apiKey","label":"API 金鑰","secret":true,"placeholder":"sk-ant-…"}]},
                  "openai":{"label":"OpenAI","fields":[{"key":"apiKey","label":"API 金鑰","secret":true,"placeholder":"sk-…"}]},
                  "resend":{"label":"Resend（Email）","fields":[{"key":"apiKey","label":"API 金鑰","secret":true,"placeholder":"re_…"}]},
                  "line":{"label":"LINE 官方帳號","fields":[{"key":"channelId","label":"Messaging API：Channel ID","optional":true},{"key":"channelSecret","label":"Messaging API：Channel secret","secret":true}]}},
     "orgs":[{"id":"o1","name":"晨麥手作"},{"id":"o2","name":"StudioX"},{"id":"o3","name":"木白設計"}]}
    """ }

    private static var adminUsage: String {
        let daily = (0..<7).map { (i: Int) -> String in
            let cost: Int = 180_000_000 + i * 22_000_000
            let price: Int = 260_000_000 + i * 31_000_000
            return "{\"day\":\"\(day(6 - i))\",\"costMicros\":\(cost),\"priceMicros\":\(price)}"
        }.joined(separator: ",")
        return """
        {"period":"2026-10","rows":[
          {"orgId":"o1","org":"晨麥手作","siteId":"s1","site":"晨麥手作","service":"llm.anthropic","model":"Claude Haiku","billable":true,"calls":1820,"quantity":1820,"costMicros":612000000,"priceMicros":842000000},
          {"orgId":"o1","org":"晨麥手作","siteId":"s1","site":"晨麥手作","service":"sms","model":null,"billable":true,"calls":420,"quantity":420,"costMicros":294000000,"priceMicros":378000000},
          {"orgId":"o1","org":"晨麥手作","siteId":"s1","site":"晨麥手作","service":"email","model":null,"billable":true,"calls":1260,"quantity":1260,"costMicros":63000000,"priceMicros":126000000},
          {"orgId":"o3","org":"木白設計","siteId":"s3","site":"木白設計","service":"email","model":null,"billable":true,"calls":84,"quantity":84,"costMicros":4200000,"priceMicros":8400000}],
         "daily":[\(daily)],"totals":{"costMicros":973200000,"priceMicros":1354400000,"calls":3584}}
        """
    }

    private static let adminAiUsage = #"""
    {"period":"2026-10","sites":[{"id":"s1","name":"晨麥手作"}],"features":["assistant","copilot"],
     "rows":[{"siteId":"s1","site":"晨麥手作","feature":"assistant","service":"llm.anthropic","model":"Claude Haiku","calls":1640,"input":2840000,"output":412000,"cacheRead":1900000,"costMicros":540000000,"priceMicros":742000000},
             {"siteId":"s1","site":"晨麥手作","feature":"copilot","service":"llm.anthropic","model":"Claude Sonnet","calls":180,"input":620000,"output":88000,"cacheRead":410000,"costMicros":72000000,"priceMicros":100000000}],
     "recent":[],"daily":[]}
    """#

    private static let adminBilling = #"""
    {"period":"2026-10","statements":[
     {"orgId":"o1","org":"晨麥手作","statement":{"id":"b1","status":"issued","note":null,"issuedAt":"2026-10-01T02:00:00.000Z","paidAt":null},
      "lines":[{"siteId":null,"site":"—","service":"plan","label":"方案：成長","quantity":1,"unit":"月","amountMicros":2980000000},{"siteId":"s1","site":"晨麥手作","service":"sms","label":"簡訊（超過內含的 300 則）","quantity":120,"unit":"則","amountMicros":108000000},{"siteId":"s1","site":"晨麥手作","service":"llm","label":"AI 用量","quantity":1820,"unit":"次","amountMicros":842000000}],
      "subtotalMicros":3930000000,"adjustmentMicros":0,"totalMicros":3930000000},
     {"orgId":"o3","org":"木白設計","statement":null,
      "lines":[{"siteId":null,"site":"—","service":"plan","label":"方案：入門","quantity":1,"unit":"月","amountMicros":990000000}],
      "subtotalMicros":990000000,"adjustmentMicros":0,"totalMicros":990000000}
    ]}
    """#

    private static let adminPlans = #"""
    {"catalog":{"plans":[
      {"id":"starter","name":"入門","tagline":"一個網站、基本的後台","price":990,"lines":["Xena 每月 300 則","Email 1,000 封"]},
      {"id":"growth","name":"成長","tagline":"AI 客服、LINE、行銷","price":2980,"lines":["Xena 每月 2,000 則","AI 客服","簡訊 300 則","Email 5,000 封"]}],
     "addons":[{"id":"seats","name":"多 3 個座位","description":"後台人員多 3 位","price":300,"public":true,"effect":{"kind":"seats","seats":3}}]},
     "models":{},
     "orgs":[{"id":"o1","name":"晨麥手作","sites":1,"subscription":{"planId":"growth","addons":[{"id":"seats","qty":1}],"note":null},"monthlyFeeNtd":3280},
             {"id":"o3","name":"木白設計","sites":1,"subscription":{"planId":"starter","addons":[],"note":null},"monthlyFeeNtd":990},
             {"id":"o2","name":"StudioX","sites":1,"subscription":null,"monthlyFeeNtd":null}]}
    """#

    private static let adminPricing = #"""
    {"pricing":{"fxUsdTwd":32.5,"llmMarkup":1.3,"email":{"cost":0.05,"price":0.1},"sms":{"cost":0.7,"price":0.9},"orgs":{"o1":{"smsPrice":0.85}}},
     "orgs":[{"id":"o1","name":"晨麥手作"},{"id":"o2","name":"StudioX"},{"id":"o3","name":"木白設計"}]}
    """#

    private static let adminTeam = #"""
    {"managedBy":null,"members":[
     {"id":"demo","email":"demo@studiox.tw","name":"Andy","level":"owner","createdAt":"2026-01-10T08:00:00.000Z","hasPassword":false},
     {"id":"t2","email":"design@studiox.example","name":"設計","level":"manager","createdAt":"2026-05-03T08:00:00.000Z","hasPassword":true}]}
    """#

    private static var adminAudit: String { """
    {"entries":[
     {"id":"a1","action":"console.member","actionLabel":"網站成員","actorName":"Andy","actorEmail":"demo@studiox.tw","actorLevel":"owner","entityType":null,"entityId":null,"entityLabel":null,"summary":"「晨麥手作」成員職能：員工 → 訂單處理人員","detail":null,"source":"app","ok":true,"createdAt":"\(ago(hours: 1))"},
     {"id":"a2","action":"platform.service","actionLabel":"平台：網站服務","actorName":"Andy","actorEmail":"demo@studiox.tw","actorLevel":"owner","entityType":null,"entityId":null,"entityLabel":null,"summary":"「晨麥手作」的 Claude：每月上限 NT$3,000","detail":null,"source":"admin","ok":true,"createdAt":"\(ago(hours: 26))"},
     {"id":"a3","action":"console.invite","actionLabel":"邀請","actorName":"Andy","actorEmail":"demo@studiox.tw","actorLevel":"owner","entityType":null,"entityId":null,"entityLabel":null,"summary":"產生「晨麥手作」的邀請（員工）並寄出","detail":null,"source":"app","ok":true,"createdAt":"\(ago(hours: 48))"},
     {"id":"a4","action":"platform.key","actionLabel":"平台：金鑰","actorName":"Andy","actorEmail":"demo@studiox.tw","actorLevel":"owner","entityType":null,"entityId":null,"entityLabel":null,"summary":"新增金鑰「OpenAI 備援」","detail":null,"source":"admin","ok":true,"createdAt":"\(ago(hours: 140))"}]}
    """ }

    private static var adminConnectors: String { """
    {"clients":[{"clientId":"c1","clientName":"Claude","lastUsedAt":"\(ago(hours: 3))","isEnabled":true,"activeTokens":2,"createdAt":"\(ago(hours: 400))"},
                {"clientId":"c2","clientName":"ChatGPT","lastUsedAt":"\(ago(hours: 50))","isEnabled":true,"activeTokens":1,"createdAt":"\(ago(hours: 900))"}]}
    """ }

    private static var adminAiRecords: String { """
    {"all":true,"who":"all","page":1,"total":3,"more":false,"stats":{"calls":1240,"copilot":980,"failed":12,"writes":64,"external":260},
     "records":[
      {"id":"m1","tool":"chenmai.studiox.tw:update_order","site":"chenmai.studiox.tw","label":"更新訂單","args":null,"ok":true,"proposal":false,"approvedVia":"chat","approvedViaLabel":"對話確認","xena":true,"source":"Xena AI（Console）","actorEmail":"demo@studiox.tw","error":null,"durationMs":820,"createdAt":"\(ago(hours: 0.5))"},
      {"id":"m2","tool":"chenmai.studiox.tw:traffic_report","site":"chenmai.studiox.tw","label":"看流量","args":null,"ok":true,"proposal":false,"approvedVia":null,"approvedViaLabel":null,"xena":false,"source":"Claude","actorEmail":"demo@studiox.tw","error":null,"durationMs":1420,"createdAt":"\(ago(hours: 3))"},
      {"id":"m3","tool":"chenmai.studiox.tw:issue_coupons","site":"chenmai.studiox.tw","label":"發折價券","args":null,"ok":true,"proposal":true,"approvedVia":"proposal","approvedViaLabel":"提案（還沒執行）","xena":true,"source":"Xena AI（Console）","actorEmail":"demo@studiox.tw","error":null,"durationMs":210,"createdAt":"\(ago(hours: 5))"}]}
    """ }

    private static let adminCopilot = #"""
    {"settings":{"enabled":true},"plan":null,"ceiling":{"tier":"flagship","label":"旗艦"},"auto":true,
     "tiers":[{"tier":"light","label":"輕量","allowed":true,"models":["Anthropic · Claude Haiku"]},{"tier":"standard","label":"標準","allowed":true,"models":["Anthropic · Claude Sonnet"]}],
     "fallback":{"provider":"OpenAI","model":"GPT","tierLabel":"標準"},"jev":{"ready":true,"source":"vault","vault":null},"problem":null,
     "providers":[{"id":"anthropic","name":"Anthropic","hasKey":true,"source":"vault","vault":null},{"id":"openai","name":"OpenAI","hasKey":true,"source":"vault","vault":null},{"id":"google","name":"Google","hasKey":false,"source":null,"vault":null}],
     "platform":true,"vault":null}
    """#

    // MARK: 回覆建議（Xena 分析過這位客人）

    private static let replySuggestion = #"""
    {"brief":"老客（買過 2 次蛋捲禮盒），這次收到的禮盒壓扁、有兩條碎掉，想換一盒；語氣還算客氣但很失望。",
     "facts":["#CM-24100607 已送達・原味蛋捲禮盒 × 3","上次用了 3 盒 9 折券"],
     "replies":["小雯真的很抱歉！壓壞的那盒我們直接幫你換一盒新的，這兩天寄出，舊的不用寄回。","不好意思讓你收到這樣的禮盒！方便拍一張盒子和蛋捲的照片給我嗎？我馬上幫你安排換貨。","真的很抱歉！我請同事今天就補寄一盒新的給你，到貨後再跟我說一聲，有任何問題我都在。"],
     "at":null,"cached":false}
    """#

    // MARK: 長文草稿（確認卡片的「看完整內容」）

    private static let draftDocument = #"""
    {"id":"d_demo_draft_0001","title":"手工蛋捲怎麼保存才不會軟掉","format":"markdown","chars":420,
     "text":"# 手工蛋捲怎麼保存才不會軟掉\n\n蛋捲最怕**濕氣**。開封後照下面的方法放，可以多脆好幾天。\n\n## 開封前\n\n- 放在陰涼、不會曬到太陽的地方\n- 常溫可以放 **30 天**\n\n## 開封後\n\n1. 用夾子把袋口夾緊\n2. 放進密封罐，放一包乾燥劑\n3. 一週內吃完最好吃\n\n> 軟掉了也別丟：烤箱 150°C 烤 3 分鐘，放涼就會恢復酥脆。\n\n| 放法 | 可以放多久 |\n| --- | --- |\n| 未開封常溫 | 30 天 |\n| 開封後密封 | 7 天 |\n",
     "hunks":[
      {"op":"=","lines":["# 手工蛋捲怎麼保存才不會軟掉","","蛋捲最怕**濕氣**。開封後照下面的方法放，可以多脆好幾天。","","## 開封前",""]},
      {"op":"-","lines":["- 放在陰涼處"]},
      {"op":"+","lines":["- 放在陰涼、不會曬到太陽的地方","- 常溫可以放 **30 天**"]},
      {"op":"=","lines":["","## 開封後",""]},
      {"op":"+","lines":["1. 用夾子把袋口夾緊","2. 放進密封罐，放一包乾燥劑","3. 一週內吃完最好吃","","> 軟掉了也別丟：烤箱 150°C 烤 3 分鐘，放涼就會恢復酥脆。"]},
      {"op":"=","lines":["","| 放法 | 可以放多久 |","| --- | --- |","| 未開封常溫 | 30 天 |","| 開封後密封 | 7 天 |"]}
     ]}
    """#

    // MARK: 等你決定（console 看數據找到的優化）

    private static let decisions = #"""
    {"decisions":[
     {"id":"chenmai.studiox.tw:checkout","site":"chenmai.studiox.tw","kind":"checkout","icon":"shopping-bag",
      "title":"開始結帳的人，大多沒有送出訂單","detail":"過去 28 天有 46 位開始結帳，只有 15 位送出訂單（33%）。",
      "impact":"結帳這一步每多留住一位就是多一筆訂單，平均一筆 NT$1,280。",
      "prompt":"晨麥手作過去 28 天有 46 位開始結帳、只有 15 位送出訂單。請幫我找出結帳時最可能讓人放棄的地方，列出最可能的原因和改法，我決定要改哪些。"},
     {"id":"chenmai.studiox.tw:seo-page:/products/egg-roll","site":"chenmai.studiox.tw","kind":"seo-page","icon":"globe-alt",
      "title":"/products/egg-roll 在 Google 常出現，但很少人點進來","detail":"過去 28 天在 Google 出現 4,210 次、平均第 5.8 名，只有 0.7% 的人點進來（這個名次一般有 4% 左右）。",
      "impact":"把搜尋結果上的標題和描述改得更吸引人，每個月大約可以多 70 次點擊。",
      "prompt":"幫我優化晨麥手作的頁面 /products/egg-roll 在 Google 搜尋結果上的標題和描述。先讀這一頁現在的內容，給我 2～3 組新的標題和描述，我選好再幫我改。"},
     {"id":"mubai.studiox.tw:seo-query:室內設計 費用","site":"mubai.studiox.tw","kind":"seo-query","icon":"magnifying-glass",
      "title":"很多人搜「室內設計 費用」，網站排在第 8 名左右","detail":"過去 28 天這個搜尋讓網站出現 1,320 次，只有 9 次點進來（0.7%）。擠進前三名，點的人會多很多。",
      "impact":"把相關的內容寫得更完整、標題更貼近這個字，每個月可能多 55 次點擊。",
      "prompt":"木白設計在 Google 搜尋「室內設計 費用」時排在第 8 名左右、點閱率很低。請先查是哪一頁在這個搜尋上出現，再給我方案，我決定之後再做。"}
    ]}
    """#

    // MARK: 和 Xena 的對話（UI 截圖：交代她做事、等你確認）

    private static let copilotThread = #"""
    {"thread":{"id":"demo-thread","title":"標出貨","view":[
     {"kind":"user","text":"已付款的訂單幫我全部標成已出貨"},
     {"kind":"tool","id":"demo-tool","name":"list","label":"查詢晨麥手作的訂單","args":"{}","status":"ok","ms":420},
     {"kind":"assistant","text":"晨麥手作有 **6 筆已付款**、還沒出貨的訂單：\n\n| 訂單 | 客人 | 金額 |\n| --- | --- | --- |\n| CM-24100612 | 林小涵 | NT$1,280 |\n| CM-24100611 | 陳柏宇 | NT$860 |\n| CM-24100610 | 王怡君 | NT$2,140 |\n\n另外 3 筆是今天早上的。我會把這 6 筆一起標成「已出貨」，客人會收到出貨通知。確認一下："},
     {"kind":"confirm","id":"demo-confirm","title":"6 筆訂單標成已出貨","detail":"晨麥手作・CM-24100607～CM-24100612\n標好後寄出貨通知給 6 位客人","danger":false,"status":"pending"}
    ]}}
    """#

    /// 確認卡片按下去：示範模式什麼都不會真的改
    private static func confirmed(_ body: Data?) -> String {
        let req = body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        let id = req["id"]?.string ?? "demo-confirm"
        let approve = req["decision"]?.string == "approve"
        // 卡片整張換掉：標題、內容照原本那張（示範只有這一張）
        return #"{"card":{"id":"\#(id)","title":"6 筆訂單標成已出貨","detail":"晨麥手作・CM-24100607～CM-24100612\n標好後寄出貨通知給 6 位客人","danger":false,"status":"\#(approve ? "done" : "cancelled")","result":"\#(approve ? "完成（示範模式不會真的改）" : "已取消")"},"next":null,"tool":null}"#
    }

    // MARK: 工具（/api/mcp 的 tools/call）

    private static func mcp(_ body: Data?) -> JSONValue {
        let rpc = body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        let name = rpc["params"]?["name"]?.string ?? ""
        let args = rpc["params"]?["arguments"] ?? .null
        let site = args["site"]?.string ?? ""
        let entity = args["entity"]?.string ?? ""
        let result: JSONValue
        if let text = tool(name, site: site, entity: entity, args: args) {
            result = ["content": [["type": "text", "text": .string(text)]]]
        } else {
            result = ["isError": true, "content": [["type": "text", "text": "示範模式沒有這個資料"]]]
        }
        return ["jsonrpc": "2.0", "id": rpc["id"] ?? 1, "result": result]
    }

    /// 只是查資料的工具；其他都是寫入（示範模式：先跳確認，確認後回「已完成」，什麼都不會真的改）
    private static let readTools: Set<String> = ["list", "get", "search", "ops_report", "traffic_report", "search_report", "site_guide", "list_sites", "email_signature"]

    private static func tool(_ name: String, site: String, entity: String, args: JSONValue) -> String? {
        // 附件的上傳連結（只是上傳，不用確認；示範模式的上傳不會真的送出去）
        if name == "reply_xena", args["action"]?.string == "attach" {
            return #"{"uploadUrl":"https://demo.studiox.tw/u/img/demo-upload-token","expiresInMinutes":30}"#
        }
        // 試算人數（不發送、不用確認）
        if args["dryRun"]?.bool == true {
            switch name {
            case "send_campaign": return #"{"recipientCount":186,"usedToday":0,"cap":500,"capRemaining":500,"isQuietHour":false}"#
            case "send_line_campaign":
                let kind = args["audience"]?["kind"]?.string
                return #"{"recipients":\#(kind == "members" ? 214 : kind == "inactive" ? 57 : kind == "bought" ? 33 : 642)}"#
            default: break
            }
        }
        if !readTools.contains(name) {
            if args["confirmToken"]?.string != nil { return #"{"ok":true,"demo":true}"# }
            return #"{"needsConfirmation":true,"title":"確認（示範模式）","detail":"這是示範模式：按確認會顯示完成，但不會真的送出或修改任何資料。","confirmToken":"demo"}"#
        }
        switch (name, entity) {
        case ("email_signature", _): return #"{"lines":["示範帳號｜店長","晨麥手作","02 2345 6789 · hello@chenmai.tw · chenmai.studiox.tw"]}"#
        case ("ops_report", _):
            guard site == "chenmai.studiox.tw" else { return nil }
            return args["section"]?.string == "members" ? membersReport : ops(days: args["days"]?.int ?? 1)
        case ("traffic_report", _): return traffic(site: site, days: args["days"]?.int ?? 7)
        case ("search_report", _): return search
        case ("list", "order"): return orders(status: args["status"]?.string)
        case ("get", "order"): return order(id: args["id"]?.string ?? "o1")
        case ("get", "user"): return member(id: args["id"]?.string ?? "u1")
        case ("list", "coupon"): return coupons
        case ("list", "support_thread"):
            guard site == "chenmai.studiox.tw" else { return #"{"threads":[]}"# }
            // 全部紀錄（status: all）：連已回覆、已結案的一起
            return args["status"]?.string == "all" ? history(threadHistory, key: "threads", args: args) : threads
        case ("get", "support_thread"): return thread
        case ("list", "assistant_conversation"):
            // 和網站一樣照 status 篩：open＝等專人＋專人接手、ai＝Xena 回答中
            let all = site == "studiox.tw" ? conversations : site == "chenmai.studiox.tw" ? shopConversations : nil
            if args["status"]?.string == "all" {
                // 全部紀錄：現在的加上結束了的
                let past = site == "chenmai.studiox.tw" ? shopHistory : site == "studiox.tw" ? studioHistory : nil
                return all.map { history(merged($0, past), key: "items", args: args) }
            }
            return all.map { filtered($0, status: args["status"]?.string) }
        case ("get", "assistant_conversation"): return args["id"]?.string == "yc1" ? lineConversation : conversation
        case ("list", "inquiry"):
            guard site == "studiox.tw" else { return nil }
            return args["status"]?.string == "all" ? history(inquiryHistory, key: "items", args: args) : inquiries
        case ("get", "inquiry"): return inquiryDetail
        case ("list", "mailbox"): return site == "chenmai.studiox.tw" ? mailbox : #"{"items":[]}"#
        case ("list", "product"): return products
        case ("list", "campaign"): return campaigns
        case ("get", "campaign"): return campaign(id: args["id"]?.string ?? "sc1")
        case ("list", "line_campaign"): return lineCampaigns
        // 顏色是 "#…"：要用 ## 的原始字串
        case ("get", "line_theme"): return ##"{"name":"晨麥手作","primary":"#B5651D","accent":"#B5651D","text":"#2B2118"}"##
        case ("list", "pending_notification"): return pendingNotifications
        case ("list", "integration"): return integrations
        case ("list", _): return #"{"items":[]}"#
        default: return nil
        }
    }

    private static func parse(_ json: String) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null
    }

    // MARK: 時間

    // ISO8601DateFormatter 不是 Sendable，但建好之後只讀
    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()
    private static func ago(hours: Double) -> String { iso.string(from: Date.now.addingTimeInterval(-hours * 3600)) }
    private static func day(_ offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let date = calendar.date(byAdding: .day, value: -offset, to: .now)!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    private static func trend(_ values: [Int]) -> String {
        values.enumerated().map { i, v in #"{"label":"\#(day(values.count - 1 - i))","visitors":\#(v),"pageviews":\#(v * 3)}"# }.joined(separator: ",")
    }

    // MARK: 我與網站

    private static let shopTools = #"["list","get","search","update","create","delete","set_images","update_order","bulk_update_orders","refund_order","confirm_bank_transfer","ops_report","reply_support","reply_xena","traffic_report","search_report","issue_coupons","send_campaign","send_line_campaign","manage_notification","recompute_tiers","test_integration"]"#
    private static let studioTools = #"["list","get","search","update","create","delete","set_images","traffic_report","search_report","reply_support","reply_xena"]"#
    private static let basicTools = #"["list","get","search","update","traffic_report"]"#

    private static var me: String { """
    {"user":{"id":"demo","name":"Andy","email":"demo@studiox.tw","staff":true,"consoleLevel":"owner","consoleLevelLabel":"負責人","consoleCaps":["console.read","console.manage","platform.read","platform.manage","users.level","audit.read","mcp.manage"]},
     "sites":[
      {"site":"chenmai.studiox.tw","name":"晨麥手作","org":"晨麥手作","url":"https://chenmai.studiox.tw","adminUrl":"https://chenmai.studiox.tw/login?sso=studiox","level":"owner","levelLabel":"負責人","icon":null,"tools":\(shopTools),
       "stats":{"live":12,"visitors":1843,"pageviews":6120,"change":0.18,"trend":[\(trend([210, 245, 232, 268, 301, 287, 300]))]}},
      {"site":"studiox.tw","name":"StudioX.tw","org":"StudioX","url":"https://studiox.tw","adminUrl":"https://studiox.tw/login?sso=studiox","level":"owner","levelLabel":"負責人","icon":null,"tools":\(studioTools),
       "stats":{"live":3,"visitors":412,"pageviews":1380,"change":-0.04,"trend":[\(trend([62, 55, 71, 58, 60, 49, 57]))]}},
      {"site":"mubai.studiox.tw","name":"木白設計","org":"木白設計","url":"https://mubai.studiox.tw","adminUrl":"https://mubai.studiox.tw/login?sso=studiox","level":"owner","levelLabel":"負責人","icon":null,"tools":\(basicTools),
       "stats":{"live":1,"visitors":96,"pageviews":240,"change":0.07,"trend":[\(trend([11, 14, 12, 15, 13, 16, 15]))]}}
     ]}
    """ }

    // MARK: 營運、訂單

    private static func ops(days: Int) -> String {
        let k = days == 1 ? 1 : days
        let created = days == 1 ? 14 : 13 * k
        let paid = days == 1 ? 12 : 11 * k
        let revenue = days == 1 ? 1286000 : 1104000 * k
        return """
    {"summary":"\(days == 1 ? "昨天 14 筆訂單、收款 NT$12,860" : "")","range":{"label":"\(days == 1 ? "昨天" : "最近 \(days) 天")"},
     "created":{"total":\(created),"byStatus":[{"status":"completed","count":\(created * 6 / 10)},{"status":"shipped","count":\(created * 2 / 10)},{"status":"paid","count":\(created / 10)},{"status":"awaiting_payment","count":\(max(1, created / 20))},{"status":"cancelled","count":\(max(1, created / 30))}]},
     "paid":{"count":\(paid),"revenueCents":\(revenue)},
     "awaitingPayment":2,"paidButUnfulfilled":5,"notificationsOverdue":0,
     "support":{"awaitingReply":2,"oldestWaitHours":5,"unmatchedInbound":1},
     "alerts":["1 筆物流異常：包裹退回（CM-24100612）"]}
    """
    }

    private static var membersReport: String { """
    {"total":1286,"newThisMonth":48,"totalSpendLabel":"NT$2,418,600",
     "tiers":[{"name":"一般會員","count":1012},{"name":"銀卡會員","count":203},{"name":"金卡會員","count":71}],
     "topSpenders":[{"id":"u1","name":"林小涵","spendLabel":"NT$28,400"},{"id":"u3","name":"陳柏宇","spendLabel":"NT$24,960"},{"id":"u4","name":"王怡君","spendLabel":"NT$19,320"},{"id":"u5","name":"張家豪","spendLabel":"NT$16,880"},{"id":"u6","name":"李思妤","spendLabel":"NT$15,200"}]}
    """ }


    private static let customers = ["林小涵", "陳柏宇", "王怡君", "張家豪", "李思妤", "黃冠廷", "吳佩珊"]

    private static func orders(status: String?) -> String {
        let s = status ?? "paid"
        let rows = (0..<6).map { i -> String in
            let total = [1120, 860, 2140, 640, 1590, 990][i]
            return #"{"id":"o\#(i + 1)","orderNumber":"CM-2410\#(String(format: "%04d", 612 - i))","status":"\#(s)","total":\#(total * 100),"totalLabel":"NT$\#(total.formatted())","shippingName":"\#(customers[i])","createdAt":"\#(ago(hours: Double(3 + i * 5)))","paidAt":"\#(ago(hours: Double(2 + i * 5)))","paymentProvider":"\#(i == 2 ? "bank_transfer" : "payuni")"}"#
        }
        return #"{"orders":[\#(rows.joined(separator: ","))]}"#
    }

    private static func order(id: String) -> String {
        // o3：已出貨、黑貓配送中（訂單進度、配送進度的示範）
        let shipped = id == "o3"
        let logistics = shipped ? """
     "logistics":{"carrier":"tcat","trackingNumber":"9050-1234-5678","carrierTrackUrl":"https://www.t-cat.com.tw/inquire/trace.aspx",
      "events":[{"status":"配送中（台南中西營業所）","stage":"out_for_delivery","at":"\(ago(hours: 2))"},
                {"status":"到著（台南中西營業所）","stage":"in_transit","at":"\(ago(hours: 9))"},
                {"status":"轉運中（台中轉運中心）","stage":"in_transit","at":"\(ago(hours: 16))"},
                {"status":"已集貨（新竹營業所）","stage":"accepted","at":"\(ago(hours: 22))"}]},
    """ : #""logistics":{"carrier":"tcat","trackingNumber":null,"carrierTrackUrl":null,"events":[]},"#
        return """
    {\(logistics)
     "order":{"id":"\(id)","orderNumber":"CM-24100612","status":"\(shipped ? "shipped" : "paid")","updatedAt":"\(ago(hours: shipped ? 22 : 2))",\(shipped ? #""trackingNumber":"9050-1234-5678","# : "")"total":112000,"totalLabel":"NT$1,120","subtotal":118000,"shippingFee":10000,"discountAmount":16000,"userId":"u1","couponId":"cp1",
      "shippingName":"林小涵","shippingPhone":"0912-000-000","email":"demo-customer@example.com","shippingMethod":"home","shippingAddress":"台南市中西區民族路二段 1 號",
      "paymentProvider":"payuni","createdAt":"\(ago(hours: shipped ? 30 : 3))","paidAt":"\(ago(hours: shipped ? 29 : 2))","note":"請下午送達，謝謝"},
     "items":[{"id":"i1","productName":"手工蛋捲禮盒","variantName":"原味・12 入","quantity":2,"unitPrice":45000},
              {"id":"i2","productName":"芝麻薄餅","variantName":"罐裝","quantity":1,"unitPrice":28000}],
     "discounts":[{"couponId":"cp1","code":"MOON10","name":"中秋禮盒 9 折","type":"percentage","personalized":false,"offer":"9 折","amount":11800,"amountLabel":"NT$118"},
                  {"couponId":"cp2","code":"YG-K7Q2M9","name":"林小涵 專屬折價","type":"percentage","personalized":true,"offer":"85 折","amount":4200,"amountLabel":"NT$42"}],
     "member":{"id":"u1","name":"林小涵","email":"demo-customer@example.com","tier":"金卡會員","paidOrderCount":4,"lifetimeSpendCents":684000,"lifetimeSpendLabel":"NT$6,840"},
     "trackUrl":null}
    """
    }

    private static func member(id: String) -> String { """
    {"user":{"id":"\(id)","name":"\(id == "u2" ? "小雯" : "林小涵")","email":"demo-customer@example.com","phone":"0912-000-000","phoneVerified":"\(ago(hours: 2000))","role":"customer","tier":"金卡會員",
      "lifetimeSpendCents":684000,"lifetimeSpendLabel":"NT$6,840","invitedCount":2,"createdAt":"\(ago(hours: 4300))"},
     "rfm":{"segment":"loyal","orderCount":4,"recencyDays":0,"frequency90d":2,"monetaryCents":236000},
     "recentOrders":[{"id":"o1","orderNumber":"CM-24100612","status":"paid","total":112000,"totalLabel":"NT$1,120","createdAt":"\(ago(hours: 3))"},
                     {"id":"o9","orderNumber":"CM-24090388","status":"completed","total":124000,"totalLabel":"NT$1,240","createdAt":"\(ago(hours: 900))"},
                     {"id":"o10","orderNumber":"CM-24061205","status":"completed","total":228000,"totalLabel":"NT$2,280","createdAt":"\(ago(hours: 2600))"}],
     "coupons":[]}
    """ }

    // MARK: 客服、Xena、詢問

    private static var threads: String { """
    {"threads":[
     {"id":"t1","subject":"訂單什麼時候會出貨？","categoryLabel":"訂單與物流","status":"open","statusLabel":"等回覆","waitingHours":5.2,"messageCount":3,"orderNumber":"CM-24100607","customer":"陳柏宇"},
     {"id":"t2","subject":"可以改成超商取貨嗎","categoryLabel":"訂單與物流","status":"open","statusLabel":"等回覆","waitingHours":1.4,"messageCount":1,"customer":"王怡君"}
    ]}
    """ }

    private static var thread: String { """
    {"thread":{"id":"t1","subject":"訂單什麼時候會出貨？","categoryLabel":"訂單與物流","status":"open","statusLabel":"等回覆","waitingHours":5.2,"messageCount":3,
      "orderNumber":"CM-24100607","customer":"陳柏宇","contactEmail":"demo-customer@example.com",
      "messages":[
       {"id":"m1","direction":"in","body":"你好，我前天下的訂單還沒收到出貨通知，想問大概什麼時候會寄出？","author":"陳柏宇","createdAt":"\(ago(hours: 30))"},
       {"id":"m2","direction":"out","body":"您好，這批蛋捲今天出爐，明天上午會寄出，寄出後會再通知您。","author":"Andy","createdAt":"\(ago(hours: 26))"},
       {"id":"m3","direction":"in","body":"好的謝謝！可以順便加一罐芝麻薄餅嗎？","author":"陳柏宇","createdAt":"\(ago(hours: 5.2))"}
      ]},
     "customer":{"member":{"name":"陳柏宇","tierName":"金卡會員","lifetimeSpendLabel":"NT$8,420"},
      "orders":[{"id":"o2","orderNumber":"CM-24100607","statusLabel":"已付款","totalLabel":"NT$860","itemSummary":"手工蛋捲禮盒 ×1"}]}}
    """ }

    private static var conversations: String { """
    {"items":[
     {"id":"c1","at":"\(ago(hours: 0.6))","status":"waiting","attention":true,"tags":["費用報價"],"contact":{"name":"Sarah"},"turns":6,"questions":["想做一個品牌官網，大概的費用與時程？","sarah@example.com，謝謝"],"last":{"role":"user","text":"sarah@example.com，謝謝"}},
     {"id":"c2","at":"\(ago(hours: 7))","status":"human","attention":false,"tags":["服務內容"],"contact":null,"signedIn":"Daniel","turns":4,"questions":["你們有做電商網站嗎？"],"last":{"role":"staff","text":"有的，我把幾個電商案例整理給你。"}},
     {"id":"c3","at":"\(ago(hours: 0.02))","status":"ai","attention":false,"channel":"line","line":{"name":"Ivy"},"tags":["合作流程"],"turns":3,"questions":["官網從開始到上線大概要多久？"],"last":{"role":"user","text":"官網從開始到上線大概要多久？"}}
    ]}
    """ }

    private static var shopConversations: String { """
    {"items":[
     {"id":"yc1","at":"\(ago(hours: 0.2))","status":"waiting","channel":"line","line":{"name":"小雯"},"attention":true,"tags":["收貨問題"],"contact":{"name":"小雯"},"turns":3,"questions":["蛋捲禮盒收到的時候盒子壓扁了"]},
     {"id":"yc2","at":"\(ago(hours: 3))","status":"human","channel":"web","attention":false,"tags":["改單退款"],"contact":{"name":"王先生"},"turns":5,"questions":["可以改收件地址嗎？"],"last":{"role":"staff","text":"已經幫你改好了，明天出貨。"}},
     {"id":"yc3","at":"\(ago(hours: 0.03))","status":"ai","channel":"line","line":{"name":"阿凱"},"attention":false,"tags":["商品詢問"],"contact":{"name":"阿凱"},"turns":2,"questions":["芝麻薄餅還有貨嗎？想訂三盒"],"last":{"role":"assistant","text":"芝麻薄餅還有貨！三盒一起買可以用組合價，要幫你放進購物車嗎？"}},
     {"id":"yc4","at":"\(ago(hours: 1.5))","status":"ai","channel":"web","attention":false,"tags":["訂單查詢"],"contact":{"name":"林小姐"},"turns":4,"questions":["我的訂單到哪了？"],"last":{"role":"assistant","text":"你的訂單已經出貨，預計明天送達。"}}
    ]}
    """ }

    /// LINE 上的一位客人：前天問禮盒（Xena 帶她看商品、專人給了優惠卡片），今天收到時盒子壓扁了（Jev 判斷要找人、她也傳了語音）
    private static var lineConversation: String { """
    {"id":"yc1","status":"waiting","channel":"line","line":{"name":"小雯","following":true},"member":{"id":"u2","name":"小雯"},
     "replyWith":["card","products","attachments"],"attach":{"max":4,"imageBytes":1048576,"fileBytes":20971520},
     "startedAt":"\(ago(hours: 50))","tagLabels":["商品詢問","優惠","收貨問題"],
     "orders":[{"id":"o1","orderNumber":"CM-24100607","statusLabel":"已送達","totalLabel":"NT$1,134","itemSummary":"原味蛋捲禮盒 × 3"}],
     "handoff":{"at":"\(ago(hours: 0.3))","reason":"客人說蛋捲禮盒收到時盒子壓扁、有兩條碎掉，想換一盒"},
     "replyGoesTo":"回覆會從官方帳號照原樣傳到客人的 LINE",
     "messages":[
      {"role":"user","content":"請問蛋捲禮盒可以放多久？想寄給台北的朋友","at":"\(ago(hours: 50))","tag":"商品詢問","jev":{"human":false,"confidence":0.02}},
      {"role":"assistant","content":"原味蛋捲禮盒常溫可以放 **30 天**，開封後建議一週內吃完。寄台北隔天就到，盒子附提袋，送禮很方便。","at":"\(ago(hours: 50))","navigate":{"path":"/products/egg-roll-gift","title":"原味蛋捲禮盒"}},
      {"role":"user","content":"訂 3 盒有優惠嗎？","at":"\(ago(hours: 49.9))","tag":"優惠","jev":{"human":true,"confidence":0.71}},
      {"role":"assistant","content":"我請專人幫你看看，稍等一下喔。","at":"\(ago(hours: 49.9))"},
      {"role":"event","content":"已經通知專人，專人會在這裡回覆你。","at":"\(ago(hours: 49.9))","event":"handoff"},
      {"role":"event","content":"Andy 接手了這段對話，接下來由我在這裡回覆你。","at":"\(ago(hours: 49.6))","event":"takeover","author":"Andy"},
      {"role":"staff","content":"小雯你好！3 盒以上可以用這張 9 折券，結帳時輸入就好 🙌","at":"\(ago(hours: 49.6))","author":"Andy"},
      {"role":"staff","content":"［卡片］蛋捲禮盒 3 盒 9 折","at":"\(ago(hours: 49.6))","author":"Andy",
       "card":{"title":"蛋捲禮盒 3 盒 9 折","body":"中秋前下單，3 盒以上結帳輸入優惠碼就打 9 折，寄台北隔天到。","couponCode":"MOON10","buttonLabel":"去訂購","url":"https://chenmai.studiox.tw/products/egg-roll-gift"}},
      {"role":"user","content":"太好了，謝謝！","at":"\(ago(hours: 49.5))","tag":"閒聊","jev":{"human":false,"confidence":0}},
      {"role":"event","content":"這段對話已經結束。還有問題的話，直接再問就好。","at":"\(ago(hours: 49.4))","event":"closed"},
      {"role":"user","content":"蛋捲禮盒收到的時候盒子壓扁了","at":"\(ago(hours: 0.32))","tag":"收貨問題","jev":{"human":true,"confidence":0.93,"assist":"xena"}},
      {"role":"user","content":"[語音 6 秒] https://chenmai.studiox.tw/api/line/media/demo-voice?s=demo\\n（語音內容：裡面有兩條碎掉了，可以換一盒嗎？）","at":"\(ago(hours: 0.31))","tag":"收貨問題","jev":{"human":true,"confidence":0.9,"assist":"xena"}},
      {"role":"assistant","content":"真的很抱歉讓你收到壓壞的禮盒！我已經請專人來處理，方便的話可以拍一張照片傳給我們。","at":"\(ago(hours: 0.3))"},
      {"role":"event","content":"已經通知專人，專人會在這裡回覆你。","at":"\(ago(hours: 0.3))","event":"handoff"}
     ]}
    """ }

    private static var conversation: String { """
    {"messages":[
     {"role":"user","content":"想做一個品牌官網，大概的費用與時程？","at":"\(ago(hours: 0.9))"},
     {"role":"assistant","content":"品牌官網通常 6–10 週。費用依頁數與功能而定，我先幫你請專人聯絡，方便留下 Email 嗎？","at":"\(ago(hours: 0.85))"},
     {"role":"user","content":"sarah@example.com，謝謝","at":"\(ago(hours: 0.6))"}
    ]}
    """ }

    /// 照 status 篩對話清單（示範資料）
    private static func filtered(_ json: String, status: String?) -> String {
        guard let status, case .object(var o) = parse(json), let items = o["items"]?.array else { return json }
        let keep: (String) -> Bool = status == "open" ? { $0 == "waiting" || $0 == "human" } : { $0 == status }
        o["items"] = .array(items.filter { keep($0["status"]?.string ?? "") })
        guard let data = try? JSONEncoder().encode(JSONValue.object(o)) else { return json }
        return String(decoding: data, as: UTF8.self)
    }

    /// 全部紀錄的篩選（照網站：channel、query 找名字和內容；示範只有一頁，next 是 null）
    private static func history(_ json: String, key: String, args: JSONValue) -> String {
        guard case .object(var o) = parse(json), let rows = o[key]?.array else { return json }
        let channel = args["channel"]?.string
        let query = (args["query"]?.string ?? "").lowercased()
        let kept = rows.filter { row in
            if let channel, (row["channel"]?.string ?? "web") != channel { return false }
            guard !query.isEmpty else { return true }
            guard let data = try? JSONEncoder().encode(row) else { return false }
            return String(decoding: data, as: UTF8.self).lowercased().contains(query)
        }
        o[key] = .array(kept)
        o["next"] = .null
        guard let data = try? JSONEncoder().encode(JSONValue.object(o)) else { return json }
        return String(decoding: data, as: UTF8.self)
    }

    private static func merged(_ now: String, _ past: String?) -> String {
        guard let past, case .object(var o) = parse(now), let a = o["items"]?.array, let b = parse(past)["items"]?.array else { return now }
        o["items"] = .array(a + b)
        guard let data = try? JSONEncoder().encode(JSONValue.object(o)) else { return now }
        return String(decoding: data, as: UTF8.self)
    }

    /// 晨麥手作結束了的對話（全部紀錄）
    private static var shopHistory: String { """
    {"items":[
     {"id":"yh1","at":"\(ago(hours: 27))","status":"closed","channel":"web","attention":false,"tags":["訂單查詢"],"contact":{"name":"陳太太"},"turns":6,"questions":["上週訂的禮盒還沒到"],"last":{"role":"staff","text":"幫你查好了，物流明天上午送達，謝謝耐心等候！"}},
     {"id":"yh2","at":"\(ago(hours: 75))","status":"closed","channel":"line","line":{"name":"Mia"},"attention":false,"tags":["商品詢問"],"contact":{"name":"Mia"},"turns":4,"questions":["芝麻薄餅素食可以吃嗎？"],"last":{"role":"assistant","text":"芝麻薄餅是奶素，蛋奶素的朋友可以放心吃。"}},
     {"id":"yh3","at":"\(ago(hours: 150))","status":"closed","channel":"web","attention":false,"tags":["改單退款"],"contact":{"name":"張先生"},"turns":7,"questions":["訂錯口味可以換嗎？"],"last":{"role":"staff","text":"已經幫你換成原味，差額退回原付款方式。"}},
     {"id":"yh4","at":"\(ago(hours: 330))","status":"ai","channel":"line","line":{"name":"小蘋"},"attention":false,"tags":["優惠"],"contact":{"name":"小蘋"},"turns":3,"questions":["中秋有優惠嗎？"],"last":{"role":"assistant","text":"中秋禮盒 3 盒以上 9 折，結帳輸入 MOON10 就可以。"}}
    ]}
    """ }

    /// StudioX.tw 結束了的對話（全部紀錄）
    private static var studioHistory: String { """
    {"items":[
     {"id":"sh1","at":"\(ago(hours: 52))","status":"closed","channel":"web","attention":false,"tags":["費用報價"],"contact":{"name":"Leo"},"turns":5,"questions":["品牌改版大概多少預算？"],"last":{"role":"staff","text":"已經把報價單寄到你的信箱，有問題隨時找我。"}},
     {"id":"sh2","at":"\(ago(hours: 200))","status":"closed","channel":"line","line":{"name":"Joy"},"attention":false,"tags":["服務內容"],"turns":3,"questions":["有做 App 嗎？"],"last":{"role":"assistant","text":"有的，我們做過 iOS 與 Android 的會員 App，作品在這裡。"}}
    ]}
    """ }

    /// 晨麥手作的客服信（全部紀錄：等回覆、已回覆、已結案）
    private static var threadHistory: String { """
    {"threads":[
     {"id":"t1","subject":"訂單什麼時候會出貨？","categoryLabel":"訂單與物流","status":"open","statusLabel":"等回覆","waitingHours":5.2,"messageCount":3,"orderNumber":"CM-24100607","customer":"陳柏宇","lastMessageAt":"\(ago(hours: 5.2))","lastMessage":{"text":"好的謝謝！可以順便加一罐芝麻薄餅嗎？","fromCustomer":true}},
     {"id":"t2","subject":"可以改成超商取貨嗎","categoryLabel":"訂單與物流","status":"open","statusLabel":"等回覆","waitingHours":1.4,"messageCount":1,"customer":"王怡君","lastMessageAt":"\(ago(hours: 1.4))","lastMessage":{"text":"我下午不在家，可以改到 7-11 嗎？","fromCustomer":true}},
     {"id":"t3","subject":"發票可以開統編嗎","categoryLabel":"其他","status":"answered","statusLabel":"已回覆","messageCount":2,"customer":"李思妤","lastMessageAt":"\(ago(hours: 46))","lastMessage":{"text":"可以的，結帳時在備註寫統編就好。","fromCustomer":false}},
     {"id":"t4","subject":"禮盒可以附卡片嗎","categoryLabel":"商品","status":"closed","statusLabel":"已結案","messageCount":4,"orderNumber":"CM-24092288","customer":"黃冠廷","lastMessageAt":"\(ago(hours: 220))","lastMessage":{"text":"收到了，卡片很漂亮，謝謝！","fromCustomer":true}}
    ]}
    """ }

    /// StudioX.tw 的專案詢問（全部紀錄）
    private static var inquiryHistory: String { """
    {"items":[
     {"id":"q1","at":"\(ago(hours: 20))","status":"new","name":"Kevin","company":"小路咖啡","email":"demo-inquiry@example.com","types":["品牌官網","電商"],"budget":"30–60 萬","message":"我們想把門市的訂購搬到線上，需要會員與訂閱制。"},
     {"id":"q2","at":"\(ago(hours: 98))","status":"replied","name":"Emma","company":"青田花藝","email":"demo-inquiry@example.com","types":["品牌官網"],"budget":"15–30 萬","message":"想做一個可以預約花藝課的網站。"},
     {"id":"q3","at":"\(ago(hours: 720))","status":"archived","name":"Ken","company":"山下工作室","email":"demo-inquiry@example.com","types":["SEO"],"message":"想了解 SEO 顧問的服務內容。"}
    ]}
    """ }

    private static var mailbox: String { """
    {"box":"inbox","items":[
     {"id":"mb1","from":"好日子選物 <buyer@example.com>","subject":"團購合作邀約：中秋禮盒 200 組","receivedAt":"\(ago(hours: 26))","unread":true,"preview":"您好，我們是好日子選物，想洽談中秋禮盒團購…","attachmentCount":1}
    ]}
    """ }

    private static var inquiryDetail: String { """
    {"id":"q1","createdAt":"\(ago(hours: 20))","status":"new","name":"Kevin","company":"小路咖啡","email":"demo-inquiry@example.com","types":["品牌官網","電商"],"budget":"30–60 萬",
     "message":"我們想把門市的訂購搬到線上，需要會員與訂閱制。目前每月大約 800 筆外帶訂單，希望明年第一季上線。","sourcePath":"/contact"}
    """ }

    private static var inquiries: String { """
    {"items":[
     {"id":"q1","at":"\(ago(hours: 20))","status":"new","name":"Kevin","company":"小路咖啡","email":"demo-inquiry@example.com","types":["品牌官網","電商"],"budget":"30–60 萬","message":"我們想把門市的訂購搬到線上，需要會員與訂閱制。"}
    ]}
    """ }

    // MARK: 流量、搜尋

    private static func dailyVisitors(base: Int, day i: Int) -> Int {
        let wave: Double = Double(base) * 0.25 * sin(Double(i) * 1.3)
        let bump: Int = (i % 3) * base / 10
        return base + Int(wave) + bump
    }

    private static func hourRow(base: Int, day d: Int) -> String {
        var cells: [String] = []
        for h in 0..<24 {
            let busy: Double = (h > 9 && h < 23) ? 1.5 : 0.3
            let jitter: Double = Double((d * 7 + h) % 5)
            let value: Double = Double(base) / 12 * busy + jitter
            cells.append(String(max(0, Int(value))))
        }
        return "[" + cells.joined(separator: ",") + "]"
    }

    private static var searchTrend: String {
        (0..<28).map { (i: Int) -> String in
            let clicks: Int = 12 + i % 7 * 3
            let impressions: Int = 380 + i % 5 * 40
            return #"{"label":"\#(day(28 - i))","clicks":\#(clicks),"impressions":\#(impressions)}"#
        }.joined(separator: ",")
    }

    private static func traffic(site: String, days: Int) -> String {
        let base = site == "chenmai.studiox.tw" ? 260 : site == "studiox.tw" ? 58 : 14
        let values: [Int] = (0..<max(days, 1)).map { (i: Int) -> Int in dailyVisitors(base: base, day: i) }
        let hours: String = (0..<7).map { (d: Int) -> String in hourRow(base: base, day: d) }.joined(separator: ",")
        return """
        {"installed":true,"days":\(days),"live":\(base / 20 + 1),"visitors":\(values.reduce(0, +)),"pageviews":\(values.reduce(0, +) * 3),"visits":\(values.reduce(0, +) * 5 / 4),
         "bounceRate":0.38,"avgDurationMs":94000,"change":{"visitors":0.18,"pageviews":0.12},
         "trend":[\(trend(values))],
         "pages":[{"key":"/","name":"首頁","visitors":\(base * 3),"pageviews":\(base * 5)},{"key":"/shop","name":"商店","visitors":\(base * 2),"pageviews":\(base * 4)},{"key":"/shop/egg-rolls","name":"原味手工蛋捲禮盒","visitors":\(base),"pageviews":\(base * 2)},{"key":"/about","name":"關於我們","visitors":\(base / 2),"pageviews":\(base / 2 + 3)}],
         "entries":[{"key":"/","name":"首頁","visitors":\(base * 2),"pageviews":\(base * 2)},{"key":"/shop/egg-rolls","name":"原味手工蛋捲禮盒","visitors":\(base / 2),"pageviews":\(base / 2)},{"key":"/qr","name":"找不到的頁面","missing":true,"visitors":\(base / 6 + 1),"pageviews":\(base / 6 + 1)}],
         "referrers":[{"key":"l.instagram.com","name":"Instagram","visitors":\(base),"pageviews":\(base * 2)},{"key":"google.com","name":"Google 搜尋","visitors":\(base / 2),"pageviews":\(base)},{"key":"line.me","name":"LINE","visitors":\(base / 3),"pageviews":\(base / 2)},{"key":"chatgpt.com","name":"ChatGPT","visitors":\(base / 8 + 1),"pageviews":\(base / 8 + 1)}],
         "countries":[{"key":"TW","visitors":\(base * 4),"pageviews":\(base * 9)},{"key":"HK","visitors":\(base / 5),"pageviews":\(base / 3)}],
         "devices":[{"key":"mobile","visitors":\(base * 3),"pageviews":\(base * 7)},{"key":"desktop","visitors":\(base),"pageviews":\(base * 3)}],
         "browsers":[{"key":"Safari","visitors":\(base * 2),"pageviews":\(base * 5)}],"oses":[{"key":"iOS","visitors":\(base * 2),"pageviews":\(base * 5)}],"campaigns":[],
         "channels":[{"channel":"social","visits":\(base * 2)},{"channel":"organic","visits":\(base)},{"channel":"direct","visits":\(base / 2)}],
         "weekHours":[\(hours)],
         "funnel":{"steps":[{"step":"visit","label":"進站","visitors":\(base * 4)},{"step":"product","label":"看商品","visitors":\(base * 2)},{"step":"cart","label":"加購物車","visitors":\(base / 2)},{"step":"checkout","label":"結帳","visitors":\(base / 4)},{"step":"order","label":"下單","visitors":\(base / 6)}],"products":[]},
         "contentPages":[]}
        """
    }

    private static var search: String { """
    {"status":"ok","property":"sc-domain:chenmai.studiox.tw","range":{"start":"\(day(28))","end":"\(day(1))"},
     "totals":{"clicks":482,"impressions":12840,"ctr":0.0375,"position":8.4},"change":{"clicks":0.11,"impressions":0.06},
     "trend":[\(searchTrend)],
     "queries":[{"key":"台南 蛋捲","clicks":96,"impressions":1820,"ctr":0.052,"position":3.1},{"key":"手工蛋捲 禮盒","clicks":71,"impressions":1430,"ctr":0.049,"position":4.6}],
     "pages":[{"key":"/","name":"首頁","clicks":210,"impressions":4100,"ctr":0.051,"position":5.2},{"key":"/shop/egg-rolls","name":"原味手工蛋捲禮盒","clicks":118,"impressions":2650,"ctr":0.045,"position":6.3}],"countries":[{"key":"twn","clicks":460,"impressions":12100,"ctr":0.038,"position":8.1}]}
    """ }

    // MARK: 內容（商品）

    private static var products: String { """
    {"items":[
     {"id":"p1","title":"手工蛋捲禮盒","priceLabel":"NT$450","category":"禮盒","isPublished":true,"stock":38,"updatedAt":"\(ago(hours: 20))"},
     {"id":"p2","title":"芝麻薄餅","priceLabel":"NT$280","category":"餅乾","isPublished":true,"stock":4,"updatedAt":"\(ago(hours: 50))"},
     {"id":"p3","title":"中秋限定綜合禮盒","priceLabel":"NT$980","category":"禮盒","isPublished":false,"stock":0,"updatedAt":"\(ago(hours: 90))"},
     {"id":"p4","title":"海苔蛋捲","priceLabel":"NT$320","category":"蛋捲","isPublished":true,"stock":21,"updatedAt":"\(ago(hours: 120))"}
    ]}
    """ }

    private static func schema(site: String) -> String {
        let product = #"""
        {"key":"product","label":"商品","ops":{"list":true,"get":true,"update":true,"create":true,"delete":true\#(screenshots ? "" : #","images":"multiple""#)},
         "fields":[{"key":"title","label":"名稱","type":"string","required":true,"maxLen":80},
                   {"key":"price","label":"價格","type":"ntd","required":true,"min":0},
                   {"key":"stock","label":"庫存","type":"int","min":0},
                   {"key":"isPublished","label":"上架","type":"bool"},
                   {"key":"category","label":"分類","type":"enum","values":["禮盒","餅乾","蛋捲"]},
                   {"key":"description","label":"商品說明","type":"text","maxLen":2000}],
         "createFields":[]}
        """#
        let simple = { (key: String, label: String) in #"{"key":"\#(key)","label":"\#(label)","ops":{"list":true,"get":true,"update":true},"fields":[]}"# }
        let entities: [String]
        switch site {
        case "chenmai.studiox.tw":
            entities = [product, simple("coupon", "折價券"), simple("banner", "商店橫幅"), simple("news", "公告"), simple("faq", "常見問題"), simple("user", "會員"),
                        simple("membership_tier", "會員等級規則"), simple("campaign", "行銷簡訊活動"), simple("line_campaign", "LINE 優惠推播"),
                        simple("pending_notification", "待發通知"), simple("integration", "整合狀態")]
        case "studiox.tw":
            entities = [simple("news", "文章"), simple("inquiry", "專案詢問"), simple("automation", "自動化流程")]
        default:
            entities = [simple("news", "最新消息"), simple("page_seo", "頁面 SEO")]
        }
        return #"{"site":{"name":"\#(site)","host":"\#(site)"},"level":"owner","tools":[],"entities":[\#(entities.joined(separator: ","))]}"#
    }

    // MARK: 行銷、通知、整合

    private static var campaigns: String { """
    {"campaigns":[
     {"id":"sc1","name":"中秋禮盒預購","body":"【晨麥手作】中秋禮盒開放預購，3 盒以上 9 折，9/30 前下單免運。","status":"draft","createdAt":"\(ago(hours: 5))","totalRecipients":0,"successCount":0,"failedCount":0},
     {"id":"sc2","name":"週年感謝","body":"【晨麥手作】謝謝你陪我們一年！本週全館蛋捲買二送一。","status":"sent","createdAt":"\(ago(hours: 400))","sentAt":"\(ago(hours: 398))","totalRecipients":172,"successCount":169,"failedCount":3}
    ]}
    """ }

    private static func campaign(id: String) -> String {
        let sent = id == "sc2"
        return """
    {"campaign":{"id":"\(id)","name":"\(sent ? "週年感謝" : "中秋禮盒預購")","body":"\(sent ? "【晨麥手作】謝謝你陪我們一年！本週全館蛋捲買二送一。" : "【晨麥手作】中秋禮盒開放預購，3 盒以上 9 折，9/30 前下單免運。")",
      "status":"\(sent ? "sent" : "draft")","createdAt":"\(ago(hours: sent ? 400 : 5))",\(sent ? #""sentAt":"\#(ago(hours: 398))","totalRecipients":172,"successCount":169,"failedCount":3"# : #""totalRecipients":0,"successCount":0,"failedCount":0"#)},
     "sends":\(sent ? #"[{"status":"failed","error":"空號"},{"status":"failed","error":"空號"},{"status":"failed","error":"拒收廣告簡訊"}]"# : "[]")}
    """ }

    private static var lineCampaigns: String { """
    {"campaigns":[
     {"id":"lc1","title":"中秋禮盒 3 盒 9 折","body":"中秋前下單，3 盒以上結帳輸入優惠碼就打 9 折，寄台北隔天到。","couponCode":"MOON10","buttonLabel":"去訂購","buttonUrl":"/zh/shop","audience":{"kind":"members"},"status":"sent","recipients":214,"sent":214,"createdAt":"\(ago(hours: 30))","sentAt":"\(ago(hours: 30))"},
     {"id":"lc2","title":"好久不見，送你免運","body":"想念蛋捲的味道嗎？這週下單免運費。","couponCode":"SHIPFREE","audience":{"kind":"inactive","days":90},"status":"sent","recipients":57,"sent":57,"createdAt":"\(ago(hours: 220))","sentAt":"\(ago(hours: 220))"}
    ]}
    """ }

    private static var pendingNotifications: String { """
    {"pending":[
     {"id":"pn1","kind":"order.status_changed","kindLabel":"訂單狀態更新","userName":"林小涵","scheduledAt":"\(ago(hours: -0.12))","status":"pending","description":"CM-24100612：已付款 → 已出貨"},
     {"id":"pn2","kind":"coupon.issued","kindLabel":"折價券已發放","userName":"陳柏宇","scheduledAt":"\(ago(hours: -0.2))","status":"pending","description":"WELCOME100（折 NT$100）"}
    ],
     "recent":[
     {"id":"pn3","kind":"user.tier_changed","kindLabel":"會員等級變動","userName":"王怡君","scheduledAt":"\(ago(hours: 6))","status":"sent","sentAt":"\(ago(hours: 6))"},
     {"id":"pn4","kind":"order.status_changed","kindLabel":"訂單狀態更新","userName":"張家豪","scheduledAt":"\(ago(hours: 26))","status":"cancelled","cancelledAt":"\(ago(hours: 26.1))"}
    ]}
    """ }

    private static var integrations: String { """
    {"integrations":[
     {"provider":"resend","enabled":true,"config":{},"updatedAt":"\(ago(hours: 900))"},
     {"provider":"mitake","enabled":true,"config":{},"updatedAt":"\(ago(hours: 1400))"},
     {"provider":"notifications","enabled":true,"config":{},"updatedAt":"\(ago(hours: 300))"},
     {"provider":"personalized_coupons","enabled":false,"config":{},"updatedAt":null}
    ]}
    """ }

    private static var coupons: String { """
    {"items":[
     {"id":"cp1","code":"MOON10","name":"中秋禮盒 9 折","discountLabel":"9 折","type":"percentage","value":10,"isActive":true,"usageCount":42,"usageLimit":500,"expiresAt":"\(ago(hours: -240))"},
     {"id":"cp3","code":"SHIPFREE","name":"滿千免運","discountLabel":"免運","type":"free_shipping","value":0,"isActive":true,"usageCount":118,"usageLimit":1000},
     {"id":"cp4","code":"WELCOME100","name":"新朋友折 100","discountLabel":"NT$100","type":"fixed","value":100,"isActive":true,"usageCount":63,"usageLimit":1000}
    ]}
    """ }

    /// 示範的「Xena 擬回覆／潤飾」
    private static func replyDraft(_ body: Data?) -> String {
        let json = body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        let text = json["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if json["mode"]?.string == "polish" {
            return "不好意思讓你久等了！" + text + "\n有任何問題都可以直接在這裡跟我說 🙏"
        }
        return "真的很抱歉讓你收到壓扁的禮盒 😣 我們馬上補寄一盒新的給你，今天下午寄出、明天就會到。碎掉的那盒不用寄回，可以直接留著吃沒關係！之後如果還有任何問題，直接在這裡跟我說就好。"
    }

    private static func record(entity: String, id: String?) -> String {
        if entity == "coupon" { return coupon(id: id) }
        return """
    {"entity":"\(entity)","id":"\(id ?? "p1")","title":"手工蛋捲禮盒",
     "values":{"title":"手工蛋捲禮盒","price":45000,"stock":38,"isPublished":true,"category":"禮盒","description":"每天早上現烤，奶油香、不甜膩。一盒 12 入，附提袋。"},
     "images":[]}
    """ }

    /// 訂單上用的兩張券：中秋 9 折（通用碼）、網站 AI 給這位會員的 85 折專屬券
    private static func coupon(id: String?) -> String {
        let personal = id == "cp2"
        return """
    {"entity":"coupon","id":"\(id ?? "cp1")","title":"\(personal ? "YG-K7Q2M9" : "MOON10")",
     "values":{"code":"\(personal ? "YG-K7Q2M9" : "MOON10")","name":"\(personal ? "林小涵 專屬折價" : "中秋禮盒 9 折")","type":"percentage","value":\(personal ? 15 : 10),
               "description":"\(personal ? "芝麻薄餅搭配蛋捲禮盒一起買打 85 折" : "中秋前下單，3 盒以上打 9 折")","usageLimit":\(personal ? 1 : 500),"perUserLimit":1,"isActive":true,"channel":"online"},
     "images":null}
    """ }
}
