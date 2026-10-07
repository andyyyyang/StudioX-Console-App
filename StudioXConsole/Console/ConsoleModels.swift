import Foundation

// 平台管理：console 自己的管理後台（studiox-cms 的 /api/admin/*，和網頁後台同一支 API）回來的資料。
// 欄位照 lib/console/core.ts、lib/platform/*.ts。金額：*Micros 是 NT$ × 1,000,000，*Ntd 是元。

enum ConsoleLevel {
    static let all = ["owner", "manager", "fulfillment", "staff"]

    static func label(_ level: String) -> String {
        switch level {
        case "owner": "負責人"
        case "manager": "管理者"
        case "fulfillment": "訂單處理人員"
        case "staff": "員工"
        default: level
        }
    }

    static func hint(_ level: String) -> String {
        switch level {
        case "owner": "全部權限，包含網站設定、人員權限、AI 連接器"
        case "manager": "日常管理：內容、訂單、客服、行銷"
        case "fulfillment": "只處理訂單與出貨"
        case "staff": "看資料、回覆客服"
        default: ""
        }
    }
}

/// NT$ × 1,000,000 → NT$1,234（一元以下寫到小數兩位）
func ntdMicros(_ micros: Int) -> String {
    let amount = Double(micros) / 1_000_000
    if amount != 0, abs(amount) < 1 { return "NT$" + amount.formatted(.number.precision(.fractionLength(2))) }
    return "NT$" + Int(amount.rounded()).formatted(.number)
}

extension JSONValue {
    /// 物件的每一個 key（沒有就是空的）
    var fields: [String: JSONValue] {
        if case .object(let o) = self { return o }
        return [:]
    }
}

// MARK: - 客戶與網站

struct ConsoleOrg: Identifiable, Hashable {
    let id: String
    var name: String
    var note: String?
    var sites: [ConsoleSite]

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? ""
        name = j["name"]?.string ?? ""
        note = j["note"]?.string
        sites = (j["sites"]?.array ?? []).map(ConsoleSite.init)
    }
}

struct ConsoleSite: Identifiable, Hashable {
    let id: String
    var orgID: String
    var name: String
    var siteURL: String?
    var cmsURL: String
    var active: Bool
    var lastSyncAt: Date?
    var lastSyncError: String?
    var members: Int

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? ""
        orgID = j["orgId"]?.string ?? ""
        name = j["name"]?.string ?? ""
        siteURL = j["siteUrl"]?.string
        cmsURL = j["cmsUrl"]?.string ?? ""
        active = (j["status"]?.string ?? "active") == "active"
        lastSyncAt = j["lastSyncAt"]?.date
        lastSyncError = j["lastSyncError"]?.string
        members = j["members"]?.int ?? 0
    }

    /// 網址只留網域（顯示用）
    var host: String { URL(string: siteURL ?? cmsURL)?.host() ?? (siteURL ?? cmsURL) }
}

struct ConsoleSiteStats: Hashable {
    var visitors: Int
    var change: Double?
    var live: Int
}

/// 一個網站的詳細（GET /api/admin/console/sites/[id]）
struct ConsoleSiteDetail {
    struct Member: Identifiable, Hashable {
        var id: String { userID }
        let userID: String
        var email: String
        var name: String?
        var level: String
        var since: Date?
        var appleLinked: Bool
        var title: String?
    }

    struct Invite: Identifiable, Hashable {
        let id: String
        var email: String?
        var level: String
        var expiresAt: Date?
        var createdAt: Date?
    }

    var id: String
    var name: String
    var orgID: String
    var orgName: String?
    var siteURL: String?
    var cmsURL: String
    var clientID: String
    var active: Bool
    var supportDesk: Bool
    var lastSyncAt: Date?
    var lastSyncError: String?
    var createdAt: Date?
    var issuer: String
    var redirectURI: String
    var env: String
    var members: [Member]
    var invites: [Invite]
    /// 上線進度（建立網站 → 登入設定 → 負責人 → 方案 → 服務 → LINE）；console 舊版沒有就是空的
    var launch: [LaunchStep]

    /// 上線進度裡必要的步驟都完成了（LINE 這種選用的不算）
    var launched: Bool { launch.allSatisfy { $0.optional || $0.state == "done" } }

    init(_ j: JSONValue) {
        let s = j["site"] ?? .null
        id = s["id"]?.string ?? ""
        name = s["name"]?.string ?? ""
        orgID = s["orgId"]?.string ?? ""
        orgName = j["org"]?["name"]?.string
        siteURL = s["siteUrl"]?.string
        cmsURL = s["cmsUrl"]?.string ?? ""
        clientID = s["clientId"]?.string ?? ""
        active = (s["status"]?.string ?? "active") == "active"
        supportDesk = s["supportDesk"]?.bool ?? false
        lastSyncAt = s["lastSyncAt"]?.date
        lastSyncError = s["lastSyncError"]?.string
        createdAt = s["createdAt"]?.date
        let login = j["login"] ?? .null
        issuer = login["issuer"]?.string ?? ""
        redirectURI = login["redirectUri"]?.string ?? ""
        env = login["env"]?.string ?? ""
        members = (j["members"]?.array ?? []).map {
            Member(userID: $0["userId"]?.string ?? "", email: $0["email"]?.string ?? "", name: $0["name"]?.string,
                   level: $0["level"]?.string ?? "staff", since: $0["since"]?.date, appleLinked: $0["appleLinked"]?.bool ?? false,
                   title: $0["signature"]?["title"]?.string)
        }
        invites = (j["invites"]?.array ?? []).map {
            Invite(id: $0["id"]?.string ?? "", email: $0["email"]?.string, level: $0["level"]?.string ?? "staff",
                   expiresAt: $0["expiresAt"]?.date, createdAt: $0["createdAt"]?.date)
        }
        launch = (j["launch"]?.array ?? []).map(LaunchStep.init)
    }
}

/// 網站上線的一步（console 的 lib/console/launch.ts）
struct LaunchStep: Identifiable, Hashable {
    /// site、login、owner、plan、services、line
    let key: String
    var label: String
    /// done、waiting（等對方）、todo
    var state: String
    var detail: String
    /// 後台的網址（# 開頭是同一頁的區塊）
    var href: String?
    var optional: Bool
    var id: String { key }

    init(_ j: JSONValue) {
        key = j["key"]?.string ?? ""
        label = j["label"]?.string ?? ""
        state = j["state"]?.string ?? "todo"
        detail = j["detail"]?.string ?? ""
        href = j["href"]?.string
        optional = j["optional"]?.bool ?? false
    }

    var icon: String {
        switch state {
        case "done": "check-circle"
        case "waiting": "clock"
        default: optional ? "information-circle" : "exclamation-circle"
        }
    }

    var tone: Tone {
        switch state {
        case "done": .active
        case "waiting": .info
        default: optional ? .neutral : .warning
        }
    }
}

// MARK: - 待辦

/// console 的待辦（GET /api/admin/console/todos；後台首頁最上面那一塊）：首頁「要處理」也列出來
struct ConsoleTodo: Identifiable, Hashable {
    /// requests、drafts、unpaid、sync、unstaffed、nokey、cap、disabledKey
    let key: String
    var title: String
    var detail: String
    var count: Int
    /// 後台的網址；只有一筆時直接是那一筆
    var href: String
    var tone: Tone
    var id: String { key }

    init(_ j: JSONValue) {
        key = j["key"]?.string ?? ""
        title = j["title"]?.string ?? ""
        detail = j["detail"]?.string ?? ""
        count = j["count"]?.int ?? 0
        href = j["href"]?.string ?? ""
        switch j["tone"]?.string ?? "" {
        case "danger": tone = .danger
        case "warning": tone = .warning
        default: tone = .info
        }
    }

    var icon: String {
        switch key {
        case "requests": "inbox"
        case "drafts": "document-text"
        case "unpaid": "banknotes"
        case "sync": "exclamation-triangle"
        case "unstaffed": "users"
        case "cap": "chart-bar"
        default: "key"
        }
    }

    /// 點了去 App 的哪一頁
    var page: ConsolePage { ConsolePage(adminPath: href) ?? .home }
}

extension ConsolePage {
    /// 後台網址 → App 的平台管理頁（/admin/console/sites/<id>、/admin/platform/billing?…）；對不上回 nil
    init?(adminPath href: String) {
        let path = href.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
        let parts = path.split(separator: "/").map(String.init)
        guard parts.first == "admin" else { return nil }
        let rest = Array(parts.dropFirst())
        if rest == ["console"] {
            self = .customers
        } else if rest.count == 3, rest[0] == "console", rest[1] == "sites" {
            self = .site(rest[2])
        } else if rest == ["platform"] {
            self = .usage
        } else if rest.count >= 2, rest[0] == "platform" {
            switch rest[1] {
            case "requests": self = .requests
            case "billing": self = .billing
            case "keys": self = .keys
            case "plans": self = .plans
            case "services": self = rest.count >= 3 ? .siteServices(rest[2]) : .services
            default: return nil
            }
        } else {
            return nil
        }
    }
}

/// 建立網站、重新產生密鑰：只有這一次看得到的登入設定
struct SiteSecret: Identifiable, Hashable {
    var id: String { env }
    let siteName: String
    let env: String
}

// MARK: - 申請

struct PlatformRequest: Identifiable, Hashable {
    let id: String
    var site: String
    var org: String
    var label: String
    var note: String?
    var status: String
    var reply: String?
    var requestedBy: String?
    var handledBy: String?
    var handledAt: Date?
    var createdAt: Date?

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? ""
        site = j["site"]?.string ?? ""
        org = j["org"]?.string ?? ""
        label = j["label"]?.string ?? j["service"]?.string ?? ""
        note = j["note"]?.string
        status = j["status"]?.string ?? "pending"
        reply = j["reply"]?.string
        requestedBy = j["requestedByName"]?.string ?? j["requestedByEmail"]?.string
        handledBy = j["handledByEmail"]?.string
        handledAt = j["handledAt"]?.date
        createdAt = j["createdAt"]?.date
    }

    var pending: Bool { status == "pending" }
    var statusLabel: String {
        switch status {
        case "pending": "等你處理"
        case "approved": "已開通"
        case "rejected": "沒有通過"
        case "cancelled": "客戶取消"
        default: status
        }
    }
    var tone: Tone {
        switch status {
        case "pending": .gold
        case "approved": .active
        case "rejected": .danger
        default: .neutral
        }
    }
}

// MARK: - 網站服務

/// 表單欄位（lib/platform/registry.ts 的 Field）：金鑰與服務設定共用
struct PlatformField: Identifiable, Hashable {
    var id: String { key }
    let key: String
    var label: String
    var secret: Bool
    var placeholder: String?
    var hint: String?
    var options: [(value: String, label: String)]
    var optional: Bool

    init(_ j: JSONValue) {
        key = j["key"]?.string ?? ""
        label = j["label"]?.string ?? ""
        secret = j["secret"]?.bool ?? false
        placeholder = j["placeholder"]?.string
        hint = j["hint"]?.string
        options = (j["options"]?.array ?? []).map { ($0["value"]?.string ?? "", $0["label"]?.string ?? "") }
        optional = j["optional"]?.bool ?? false
    }

    static func == (a: Self, b: Self) -> Bool { a.key == b.key && a.label == b.label }
    func hash(into h: inout Hasher) { h.combine(key) }
}

struct ServiceMatrix {
    struct Cell: Hashable {
        var enabled: Bool
        var billable: Bool
        var keyLabel: String?
        var own: Bool
        var capNtd: Double?
    }

    struct Row: Identifiable, Hashable {
        let id: String
        var name: String
        var org: String
        var active: Bool
        var services: [String: Cell]
    }

    var services: [(id: String, label: String)]
    var sites: [Row]

    init(_ j: JSONValue) {
        services = (j["services"]?.array ?? []).map { ($0["id"]?.string ?? "", $0["label"]?.string ?? "") }
        sites = (j["sites"]?.array ?? []).map { s in
            Row(id: s["id"]?.string ?? "", name: s["name"]?.string ?? "", org: s["org"]?.string ?? "",
                active: (s["status"]?.string ?? "active") == "active",
                services: (s["services"] ?? .null).fields.mapValues { c in
                    Cell(enabled: c["enabled"]?.bool ?? false, billable: c["billable"]?.bool ?? true, keyLabel: c["keyLabel"]?.string,
                         own: c["own"]?.bool ?? false, capNtd: c["capNtd"]?.double)
                })
        }
    }
}

/// 一個網站的某一項服務（GET /api/admin/platform/services/[siteId]）
struct SiteService: Identifiable, Hashable {
    struct Key: Identifiable, Hashable {
        let id: String
        var label: String
        var hint: String?
        var disabled: Bool
        var own: Bool
    }

    let id: String
    var label: String
    var description: String
    var providerLabel: String
    var metered: Bool
    var settingsFields: [PlatformField]
    var configured: Bool
    var enabled: Bool
    var keyID: String?
    var billable: Bool
    var capNtd: Double?
    var settings: [String: String]
    var monthToDateNtd: Double?
    var keys: [Key]

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? ""
        label = j["label"]?.string ?? ""
        description = j["description"]?.string ?? ""
        providerLabel = j["providerLabel"]?.string ?? ""
        metered = (j["metering"]?.string ?? "none") != "none"
        settingsFields = (j["settingsFields"]?.array ?? []).map(PlatformField.init)
        configured = j["configured"]?.bool ?? false
        enabled = j["enabled"]?.bool ?? false
        keyID = j["keyId"]?.string
        billable = j["billable"]?.bool ?? true
        capNtd = j["capNtd"]?.double
        settings = (j["settings"] ?? .null).fields.compactMapValues(\.string)
        monthToDateNtd = j["monthToDateNtd"]?.double
        keys = (j["keys"]?.array ?? []).map {
            Key(id: $0["id"]?.string ?? "", label: $0["label"]?.string ?? "", hint: $0["hint"]?.string,
                disabled: $0["disabled"]?.bool ?? false, own: $0["own"]?.bool ?? false)
        }
    }

    var keyLabel: String? { keys.first { $0.id == keyID }?.label }
}

struct LineConnectResult: Hashable {
    struct Step: Identifiable, Hashable {
        var id: String { key }
        let key: String
        var label: String
        var ok: Bool?
        var detail: String?
        var linkLabel: String?
        var linkURL: URL?
    }

    var ok: Bool
    var webhook: String
    var account: String?
    var steps: [Step]

    init(_ j: JSONValue) {
        ok = j["ok"]?.bool ?? false
        webhook = j["webhook"]?.string ?? ""
        if let name = j["account"]?["name"]?.string {
            account = [name, j["account"]?["id"]?.string].compactMap { $0 }.joined(separator: " ")
        }
        steps = (j["steps"]?.array ?? []).map {
            Step(key: $0["key"]?.string ?? UUID().uuidString, label: $0["label"]?.string ?? "", ok: $0["ok"]?.bool,
                 detail: $0["detail"]?.string, linkLabel: $0["link"]?["label"]?.string, linkURL: $0["link"]?["url"]?.string.flatMap(URL.init(string:)))
        }
    }
}

// MARK: - 金鑰庫

struct PlatformKey: Identifiable, Hashable {
    let id: String
    var provider: String
    var label: String
    var hint: String?
    var orgID: String?
    var org: String?
    var disabled: Bool
    var lastUsedAt: Date?
    var createdAt: Date?
    var uses: Int

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? ""
        provider = j["provider"]?.string ?? ""
        label = j["label"]?.string ?? ""
        hint = j["hint"]?.string
        orgID = j["orgId"]?.string
        org = j["org"]?.string
        disabled = j["disabled"]?.bool ?? false
        lastUsedAt = j["lastUsedAt"]?.date
        createdAt = j["createdAt"]?.date
        uses = j["sites"]?.int ?? 0
    }
}

struct KeyProvider: Identifiable, Hashable {
    let id: String
    var label: String
    var fields: [PlatformField]
    var note: String?
    var doc: URL?
}

struct KeyVault {
    var keys: [PlatformKey]
    var providers: [KeyProvider]
    var orgs: [(id: String, name: String)]

    init(_ j: JSONValue) {
        keys = (j["keys"]?.array ?? []).map(PlatformKey.init)
        providers = (j["providers"] ?? .null).fields.map { id, p in
            KeyProvider(id: id, label: p["label"]?.string ?? id, fields: (p["fields"]?.array ?? []).map(PlatformField.init),
                        note: p["note"]?.string, doc: p["doc"]?.string.flatMap(URL.init(string:)))
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        orgs = (j["orgs"]?.array ?? []).map { ($0["id"]?.string ?? "", $0["name"]?.string ?? "") }
    }

    func provider(_ id: String) -> KeyProvider? { providers.first { $0.id == id } }
}

// MARK: - 用量、帳單

struct UsageReport {
    struct Row: Identifiable, Hashable {
        var id: String { "\(siteID)·\(service)·\(model ?? "")·\(billable)" }
        let siteID: String
        var org: String
        var site: String
        var service: String
        var model: String?
        var billable: Bool
        var calls: Int
        var quantity: Double
        var costMicros: Int
        var priceMicros: Int
    }

    var period: String
    var rows: [Row]
    var daily: [(day: String, costMicros: Int, priceMicros: Int)]
    var costMicros: Int
    var priceMicros: Int
    var calls: Int

    init(_ j: JSONValue) {
        period = j["period"]?.string ?? ""
        rows = (j["rows"]?.array ?? []).map {
            Row(siteID: $0["siteId"]?.string ?? "", org: $0["org"]?.string ?? "", site: $0["site"]?.string ?? "", service: $0["service"]?.string ?? "",
                model: $0["model"]?.string, billable: $0["billable"]?.bool ?? true, calls: $0["calls"]?.int ?? 0, quantity: $0["quantity"]?.double ?? 0,
                costMicros: $0["costMicros"]?.int ?? 0, priceMicros: $0["priceMicros"]?.int ?? 0)
        }
        daily = (j["daily"]?.array ?? []).map { ($0["day"]?.string ?? "", $0["costMicros"]?.int ?? 0, $0["priceMicros"]?.int ?? 0) }
        costMicros = j["totals"]?["costMicros"]?.int ?? 0
        priceMicros = j["totals"]?["priceMicros"]?.int ?? 0
        calls = j["totals"]?["calls"]?.int ?? 0
    }
}

/// 一個客戶這個月的帳單
struct OrgStatement: Identifiable, Hashable {
    struct Line: Identifiable, Hashable {
        let id = UUID()
        var site: String
        var label: String
        var quantity: Double
        var unit: String
        var amountMicros: Int
    }

    var id: String { orgID }
    let orgID: String
    var org: String
    /// draft／issued／paid／void（還沒存過也是 draft）
    var status: String
    var note: String?
    var issuedAt: Date?
    var paidAt: Date?
    var lines: [Line]
    var subtotalMicros: Int
    var adjustmentMicros: Int
    var totalMicros: Int

    init(_ j: JSONValue) {
        orgID = j["orgId"]?.string ?? ""
        org = j["org"]?.string ?? ""
        let s = j["statement"] ?? .null
        status = s["status"]?.string ?? "draft"
        note = s["note"]?.string
        issuedAt = s["issuedAt"]?.date
        paidAt = s["paidAt"]?.date
        lines = (j["lines"]?.array ?? []).map {
            Line(site: $0["site"]?.string ?? "", label: $0["label"]?.string ?? "", quantity: $0["quantity"]?.double ?? 0,
                 unit: $0["unit"]?.string ?? "", amountMicros: $0["amountMicros"]?.int ?? 0)
        }
        subtotalMicros = j["subtotalMicros"]?.int ?? 0
        adjustmentMicros = j["adjustmentMicros"]?.int ?? 0
        totalMicros = j["totalMicros"]?.int ?? 0
    }

    var statusLabel: String {
        switch status {
        case "draft": "草稿"
        case "issued": "已開立"
        case "paid": "已付款"
        case "void": "作廢"
        default: status
        }
    }
    var tone: Tone {
        switch status {
        case "issued": .gold
        case "paid": .active
        case "void": .neutral
        default: .info
        }
    }
}

// MARK: - 方案、價目

struct PlanCatalog {
    struct Plan: Identifiable, Hashable {
        let id: String
        var name: String
        var tagline: String
        var price: Double
        var lines: [String]
    }

    struct Addon: Identifiable, Hashable {
        let id: String
        var name: String
        var description: String
        var price: Double
    }

    struct Org: Identifiable, Hashable {
        let id: String
        var name: String
        var sites: Int
        var planID: String?
        var addons: [String: Int]
        var note: String?
        var monthlyFeeNtd: Double?
    }

    var plans: [Plan]
    var addons: [Addon]
    var orgs: [Org]

    init(_ j: JSONValue) {
        let c = j["catalog"] ?? .null
        plans = (c["plans"]?.array ?? []).map {
            Plan(id: $0["id"]?.string ?? "", name: $0["name"]?.string ?? "", tagline: $0["tagline"]?.string ?? "",
                 price: $0["price"]?.double ?? 0, lines: ($0["lines"]?.array ?? []).compactMap(\.string))
        }
        addons = (c["addons"]?.array ?? []).map {
            Addon(id: $0["id"]?.string ?? "", name: $0["name"]?.string ?? "", description: $0["description"]?.string ?? "", price: $0["price"]?.double ?? 0)
        }
        orgs = (j["orgs"]?.array ?? []).map { o in
            let sub = o["subscription"] ?? .null
            var addons: [String: Int] = [:]
            for a in sub["addons"]?.array ?? [] {
                if let id = a["id"]?.string { addons[id] = a["qty"]?.int ?? 1 }
            }
            return Org(id: o["id"]?.string ?? "", name: o["name"]?.string ?? "", sites: o["sites"]?.int ?? 0,
                       planID: sub["planId"]?.string, addons: addons, note: sub["note"]?.string, monthlyFeeNtd: o["monthlyFeeNtd"]?.double)
        }
    }

    func plan(_ id: String?) -> Plan? { plans.first { $0.id == id } }
}

struct Pricing {
    struct OrgOverride: Hashable {
        var llmMarkup: Double?
        var emailPrice: Double?
        var smsPrice: Double?
        var monthlyFee: Double?
    }

    var fxUsdTwd: Double
    var llmMarkup: Double
    var emailCost: Double
    var emailPrice: Double
    var smsCost: Double
    var smsPrice: Double
    var overrides: [String: OrgOverride]
    var orgs: [(id: String, name: String)]

    init(_ j: JSONValue) {
        let p = j["pricing"] ?? .null
        fxUsdTwd = p["fxUsdTwd"]?.double ?? 0
        llmMarkup = p["llmMarkup"]?.double ?? 0
        emailCost = p["email"]?["cost"]?.double ?? 0
        emailPrice = p["email"]?["price"]?.double ?? 0
        smsCost = p["sms"]?["cost"]?.double ?? 0
        smsPrice = p["sms"]?["price"]?.double ?? 0
        overrides = (p["orgs"] ?? .null).fields.mapValues {
            OrgOverride(llmMarkup: $0["llmMarkup"]?.double, emailPrice: $0["emailPrice"]?.double, smsPrice: $0["smsPrice"]?.double, monthlyFee: $0["monthlyFee"]?.double)
        }
        orgs = (j["orgs"]?.array ?? []).map { ($0["id"]?.string ?? "", $0["name"]?.string ?? "") }
    }
}

// MARK: - 後台人員、操作紀錄、Xena

struct TeamMember: Identifiable, Hashable {
    let id: String
    var email: String
    var name: String?
    var level: String
    var createdAt: Date?
    var hasPassword: Bool

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? ""
        email = j["email"]?.string ?? ""
        name = j["name"]?.string
        level = j["level"]?.string ?? "staff"
        createdAt = j["createdAt"]?.date
        hasPassword = j["hasPassword"]?.bool ?? false
    }
}

/// 還沒接受的後台人員邀請（綁定 Email、7 天內有效、只能用一次）
struct StaffInvite: Identifiable, Hashable {
    let id: String
    var email: String
    var level: String
    var expiresAt: Date?
    var createdAt: Date?
    var invitedBy: String?

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? ""
        email = j["email"]?.string ?? ""
        level = j["level"]?.string ?? "staff"
        expiresAt = j["expiresAt"]?.date
        createdAt = j["createdAt"]?.date
        invitedBy = j["invitedBy"]?.string
    }
}

struct AuditEntry: Identifiable, Hashable {
    let id: String
    var action: String
    var actionLabel: String
    var actor: String?
    var actorLevel: String?
    var entityLabel: String?
    var summary: String
    var source: String
    var ok: Bool
    var createdAt: Date?

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? UUID().uuidString
        action = j["action"]?.string ?? ""
        actionLabel = j["actionLabel"]?.string ?? action
        actor = j["actorName"]?.string ?? j["actorEmail"]?.string
        actorLevel = j["actorLevel"]?.string
        entityLabel = j["entityLabel"]?.string
        summary = j["summary"]?.string ?? ""
        source = j["source"]?.string ?? "admin"
        ok = j["ok"]?.bool ?? true
        createdAt = j["createdAt"]?.date
    }

    var sourceLabel: String? {
        switch source {
        case "app": "StudioX App"
        case "mcp": "AI 連接器"
        case "system": "系統"
        default: nil
        }
    }
}

struct AiRecord: Identifiable, Hashable {
    let id: String
    var tool: String
    var site: String?
    var label: String
    var args: String?
    var ok: Bool
    var proposal: Bool
    var approvedVia: String?
    var xena: Bool
    var source: String
    var actor: String?
    var error: String?
    var durationMs: Int?
    var createdAt: Date?

    init(_ j: JSONValue) {
        id = j["id"]?.string ?? UUID().uuidString
        tool = j["tool"]?.string ?? ""
        site = j["site"]?.string
        label = j["label"]?.string ?? tool
        args = j["args"]?.string
        ok = j["ok"]?.bool ?? true
        proposal = j["proposal"]?.bool ?? false
        approvedVia = j["approvedViaLabel"]?.string
        xena = j["xena"]?.bool ?? false
        source = j["source"]?.string ?? ""
        actor = j["actorEmail"]?.string
        error = j["error"]?.string
        durationMs = j["durationMs"]?.int
        createdAt = j["createdAt"]?.date
    }
}

struct AiConnector: Identifiable, Hashable {
    var id: String { clientID }
    let clientID: String
    var name: String
    var lastUsedAt: Date?
    var enabled: Bool
    var activeTokens: Int

    init(_ j: JSONValue) {
        clientID = j["clientId"]?.string ?? ""
        name = j["clientName"]?.string ?? "未命名的連接器"
        lastUsedAt = j["lastUsedAt"]?.date
        enabled = j["isEnabled"]?.bool ?? true
        activeTokens = j["activeTokens"]?.int ?? 0
    }
}

/// Xena AI 的開關與現況（GET /api/copilot/settings）
struct XenaSettings {
    struct Provider: Identifiable, Hashable {
        let id: String
        var name: String
        var hasKey: Bool
        var source: String?
    }

    var enabled: Bool
    var auto: Bool
    var ceiling: String
    var tiers: [(label: String, allowed: Bool, models: [String])]
    var fallback: String?
    var jevReady: Bool
    var problem: String?
    var providers: [Provider]

    init(_ j: JSONValue) {
        enabled = j["settings"]?["enabled"]?.bool ?? false
        auto = j["auto"]?.bool ?? false
        ceiling = j["ceiling"]?["label"]?.string ?? ""
        tiers = (j["tiers"]?.array ?? []).map { ($0["label"]?.string ?? "", $0["allowed"]?.bool ?? false, ($0["models"]?.array ?? []).compactMap(\.string)) }
        if let f = j["fallback"], !f.isNull {
            fallback = [f["provider"]?.string, f["model"]?.string].compactMap { $0 }.joined(separator: " · ")
        }
        jevReady = j["jev"]?["ready"]?.bool ?? false
        problem = j["problem"]?.string
        providers = (j["providers"]?.array ?? []).map {
            Provider(id: $0["id"]?.string ?? "", name: $0["name"]?.string ?? "", hasKey: $0["hasKey"]?.bool ?? false, source: $0["source"]?.string)
        }
    }
}
