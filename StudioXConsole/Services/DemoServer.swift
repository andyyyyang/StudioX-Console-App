import Foundation

/// 示範模式：歡迎頁按「先看看示範」（或啟動參數 `-demo`）時不連 console，所有請求在這裡用假資料回答，
/// 走的是 App 原本的程式（ConsoleAPI.send 這一個入口），所以每個畫面都會照真的樣子畫出來。
/// 給還沒有帳號的人、App Store 的審核看（不會碰到任何真的網站和客人），也用在 UI 截圖（.github/workflows/ui-screenshots.yml）；
/// 網站（晨麥手作、木白設計）、客人的名字、訂單都是編的。寫入（回覆、改狀態…）照樣跳確認、回「已完成」，但什麼都不會真的發生。
///
/// 其他啟動參數：
///   -demoTab sites|orders|inbox|account|search   打開哪個分頁
///   -demoRoute site|traffic|order|thread|line|products|product|xena   打開哪一頁（line：LINE 來的 Xena 對話）
///   -demoSheet today|chenmai.studiox.tw   首頁卡片打開的 sheet
///   -demoLock YES   顯示 Face ID 的鎖定畫面
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
        case "/api/app/devices": body = ["configured": false, "device": .null]
        case "/api/app/notifications": body = ["supported": false]
        case "/api/app/account": body = ["ok": true, "demo": true]
        default:
            status = 404
            body = ["error": "not_found", "message": "示範模式沒有這個資料"]
        }
        let data = (try? JSONEncoder().encode(body)) ?? Data()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["content-type": "application/json"])!
        return (data, response)
    }

    // MARK: 和 Xena 的對話（UI 截圖：交代她做事、等你確認）

    private static let copilotThread = #"""
    {"thread":{"id":"demo-thread","title":"標出貨","view":[
     {"kind":"user","text":"已付款的訂單幫我全部標成已出貨"},
     {"kind":"tool","id":"demo-tool","name":"list","label":"查詢晨麥手作的訂單","args":"{}","status":"ok","ms":420},
     {"kind":"assistant","text":"晨麥手作有 **6 筆已付款**、還沒出貨的訂單，最早一筆是昨天下午的 CM-24100612（林小涵，NT$1,280）。\n\n我會把這 6 筆一起標成「已出貨」，客人會收到出貨通知。確認一下："},
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
    private static let readTools: Set<String> = ["list", "get", "search", "ops_report", "traffic_report", "search_report", "site_guide", "list_sites"]

    private static func tool(_ name: String, site: String, entity: String, args: JSONValue) -> String? {
        if !readTools.contains(name) {
            if args["confirmToken"]?.string != nil { return #"{"ok":true,"demo":true}"# }
            return #"{"needsConfirmation":true,"title":"確認（示範模式）","detail":"這是示範模式：按確認會顯示完成，但不會真的送出或修改任何資料。","confirmToken":"demo"}"#
        }
        switch (name, entity) {
        case ("ops_report", _): return site == "chenmai.studiox.tw" ? ops : nil
        case ("traffic_report", _): return traffic(site: site, days: args["days"]?.int ?? 7)
        case ("search_report", _): return search
        case ("list", "order"): return orders(status: args["status"]?.string)
        case ("get", "order"): return order(id: args["id"]?.string ?? "o1")
        case ("list", "support_thread"): return site == "chenmai.studiox.tw" ? threads : #"{"threads":[]}"#
        case ("get", "support_thread"): return thread
        case ("list", "assistant_conversation"):
            // 和網站一樣照 status 篩：open＝等專人＋專人接手、ai＝Xena 回答中
            let all = site == "studiox.tw" ? conversations : site == "chenmai.studiox.tw" ? shopConversations : nil
            return all.map { filtered($0, status: args["status"]?.string) }
        case ("get", "assistant_conversation"): return args["id"]?.string == "yc1" ? lineConversation : conversation
        case ("list", "inquiry"): return site == "studiox.tw" ? inquiries : nil
        case ("get", "inquiry"): return inquiryDetail
        case ("list", "mailbox"): return site == "chenmai.studiox.tw" ? mailbox : #"{"items":[]}"#
        case ("list", "product"): return products
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

    private static let shopTools = #"["list","get","search","update","create","delete","set_images","update_order","bulk_update_orders","refund_order","confirm_bank_transfer","ops_report","reply_support","reply_xena","traffic_report","search_report","issue_coupons"]"#
    private static let studioTools = #"["list","get","search","update","create","delete","set_images","traffic_report","search_report","reply_support","reply_xena"]"#
    private static let basicTools = #"["list","get","search","update","traffic_report"]"#

    private static var me: String { """
    {"user":{"id":"demo","name":"Andy","email":"demo@studiox.tw","staff":true},
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

    private static var ops: String { """
    {"summary":"昨天 14 筆訂單、收款 NT$12,860","range":{"label":"昨天"},"created":{"total":14},"paid":{"count":12,"revenueCents":1286000},
     "awaitingPayment":2,"paidButUnfulfilled":5,"notificationsOverdue":0,
     "support":{"awaitingReply":2,"oldestWaitHours":5,"unmatchedInbound":1},
     "alerts":["1 筆物流異常：包裹退回（CM-24100612）"]}
    """ }

    private static let customers = ["林小涵", "陳柏宇", "王怡君", "張家豪", "李思妤", "黃冠廷", "吳佩珊"]

    private static func orders(status: String?) -> String {
        let s = status ?? "paid"
        let rows = (0..<6).map { i -> String in
            let total = [1280, 860, 2140, 640, 1590, 990][i]
            return #"{"id":"o\#(i + 1)","orderNumber":"CM-2410\#(String(format: "%04d", 612 - i))","status":"\#(s)","total":\#(total * 100),"totalLabel":"NT$\#(total.formatted())","shippingName":"\#(customers[i])","createdAt":"\#(ago(hours: Double(3 + i * 5)))","paidAt":"\#(ago(hours: Double(2 + i * 5)))","paymentProvider":"\#(i == 2 ? "bank_transfer" : "payuni")"}"#
        }
        return #"{"orders":[\#(rows.joined(separator: ","))]}"#
    }

    private static func order(id: String) -> String { """
    {"order":{"id":"\(id)","orderNumber":"CM-24100612","status":"paid","total":128000,"totalLabel":"NT$1,280","subtotal":118000,"shippingFee":10000,"discountAmount":0,
      "shippingName":"林小涵","shippingPhone":"0912-000-000","email":"demo-customer@example.com","shippingMethod":"home","shippingAddress":"台南市中西區民族路二段 1 號",
      "paymentProvider":"payuni","createdAt":"\(ago(hours: 3))","paidAt":"\(ago(hours: 2))","note":"請下午送達，謝謝"},
     "items":[{"id":"i1","productName":"手工蛋捲禮盒","variantName":"原味・12 入","quantity":2,"unitPrice":45000},
              {"id":"i2","productName":"芝麻薄餅","variantName":"罐裝","quantity":1,"unitPrice":28000}],
     "trackUrl":null}
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

    private static var lineConversation: String { """
    {"id":"yc1","status":"waiting","channel":"line","line":{"name":"小雯","following":true},"member":{"name":"小雯"},
     "handoff":{"reason":"客人說收到時包裝破損"},"replyGoesTo":"回覆會從官方帳號傳到客人的 LINE（署名「真人客服」）",
     "messages":[
      {"role":"user","content":"請問蛋捲禮盒可以放多久？想寄給台北的朋友","at":"\(ago(hours: 50))","tag":"商品詢問","jev":{"human":false,"confidence":0.02}},
      {"role":"assistant","content":"原味蛋捲禮盒常溫可以放 **30 天**，開封後建議一週內吃完。寄台北隔天就到，盒子附提袋，送禮很方便。","at":"\(ago(hours: 50))"},
      {"role":"user","content":"我的訂單到哪了？","at":"\(ago(hours: 26))","tag":"訂單查詢","jev":{"human":false,"confidence":0.04}},
      {"role":"assistant","content":"你的訂單 **CM-24100607** 昨天已經出貨，黑貓單號 9012-3456-7890，預計今天送達。","at":"\(ago(hours: 26))"},
      {"role":"user","content":"蛋捲禮盒收到的時候盒子壓扁了","at":"\(ago(hours: 0.25))","tag":"收貨問題","jev":{"human":true,"confidence":0.93}},
      {"role":"assistant","content":"真的很抱歉！我已經請專人來處理，方便的話可以先拍一張照片傳給我們。","at":"\(ago(hours: 0.24))"},
      {"role":"event","content":"已經通知專人，專人會在這裡回覆你。","at":"\(ago(hours: 0.24))","event":"handoff"}
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
         "pages":[{"key":"/","visitors":\(base * 3),"pageviews":\(base * 5)},{"key":"/shop","visitors":\(base * 2),"pageviews":\(base * 4)},{"key":"/shop/egg-rolls","visitors":\(base),"pageviews":\(base * 2)}],
         "entries":[{"key":"/","visitors":\(base * 2),"pageviews":\(base * 2)}],
         "referrers":[{"key":"instagram.com","visitors":\(base),"pageviews":\(base * 2)},{"key":"google.com","visitors":\(base / 2),"pageviews":\(base)}],
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
     "pages":[{"key":"https://chenmai.studiox.tw/","clicks":210,"impressions":4100,"ctr":0.051,"position":5.2}],"countries":[{"key":"twn","clicks":460,"impressions":12100,"ctr":0.038,"position":8.1}]}
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
            entities = [product, simple("coupon", "折價券"), simple("banner", "商店橫幅"), simple("news", "公告"), simple("faq", "常見問題"), simple("user", "會員")]
        case "studiox.tw":
            entities = [simple("news", "文章"), simple("inquiry", "專案詢問"), simple("automation", "自動化流程")]
        default:
            entities = [simple("news", "最新消息"), simple("page_seo", "頁面 SEO")]
        }
        return #"{"site":{"name":"\#(site)","host":"\#(site)"},"level":"owner","tools":[],"entities":[\#(entities.joined(separator: ","))]}"#
    }

    private static func record(entity: String, id: String?) -> String { """
    {"entity":"\(entity)","id":"\(id ?? "p1")","title":"手工蛋捲禮盒",
     "values":{"title":"手工蛋捲禮盒","price":45000,"stock":38,"isPublished":true,"category":"禮盒","description":"每天早上現烤，奶油香、不甜膩。一盒 12 入，附提袋。"},
     "images":[]}
    """ }
}
