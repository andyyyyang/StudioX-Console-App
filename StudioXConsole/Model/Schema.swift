import Foundation

// 網站的資料與欄位定義（GET /api/app/schema → 網站的 lib/mcp-schema.ts）。
// 和網站的 list / get / create / update / delete / set_images 查的是同一張實體登錄表：
// 欄位型別、必填、選項、上限、這個人現在能做什麼。App 的清單與編輯畫面照這份畫。

struct SiteSchema {
    var level: String
    var tools: Set<String>
    var entities: [EntitySchema]

    init(_ json: JSONValue) {
        level = json["level"]?.string ?? ""
        tools = Set((json["tools"]?.array ?? []).compactMap(\.string))
        entities = (json["entities"]?.array ?? []).map(EntitySchema.init)
    }

    func entity(_ key: String) -> EntitySchema? {
        entities.first { $0.key == key }
    }
}

struct EntitySchema: Identifiable, Hashable {
    enum ImageMode: String { case single, multiple }

    var key: String
    var label: String
    var singleton: Bool
    var canList: Bool
    var canGet: Bool
    var canUpdate: Bool
    var canCreate: Bool
    var canDelete: Bool
    var images: ImageMode?
    var deleteConfirm: String?
    var fields: [FieldSpec]
    var createFields: [FieldSpec]
    /// 內容集合（atelier-cms 的 collections）：欄位樹、翻譯
    var collection: CollectionSchema?

    var id: String { key }

    init(_ json: JSONValue) {
        key = json["key"]?.string ?? ""
        label = json["label"]?.string ?? key
        singleton = json["singleton"]?.bool ?? false
        let ops = json["ops"] ?? .null
        canList = ops["list"]?.bool ?? false
        canGet = ops["get"]?.bool ?? false
        canUpdate = ops["update"]?.bool ?? false
        canCreate = ops["create"]?.bool ?? false
        canDelete = ops["delete"]?.bool ?? false
        images = ops["images"]?.string.flatMap(ImageMode.init(rawValue:))
        deleteConfirm = json["deleteConfirm"]?.string
        fields = (json["fields"]?.array ?? []).map(FieldSpec.init)
        createFields = (json["createFields"]?.array ?? []).map(FieldSpec.init)
        collection = json["collection"].flatMap { $0.isNull ? nil : CollectionSchema($0) }
    }

    /// 編輯畫面能改什麼
    var editable: Bool { canUpdate || canCreate || canDelete || images != nil }

    static func == (a: EntitySchema, b: EntitySchema) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }
}

/// 一個欄位（網站的 FieldSpec：型別、能不能空、上下限、選項）
struct FieldSpec: Identifiable, Hashable {
    enum Kind: String {
        case string, text, slug, url, int, float, ntd, bool, date, json
        case `enum`
        case stringArray
    }

    var key: String
    /// 網站給的說明（可能帶「（說明）」與「［型別提示］」，畫面上拆開顯示）
    var rawLabel: String
    var kind: Kind
    var nullable: Bool
    var min: Double?
    var max: Double?
    var maxLen: Int?
    var values: [String]
    var hint: String?
    /// 新增時必填
    var required: Bool
    var defaultValue: JSONValue?

    var id: String { key }

    init(_ json: JSONValue) {
        key = json["key"]?.string ?? ""
        rawLabel = json["label"]?.string ?? key
        kind = json["type"]?.string.flatMap(Kind.init(rawValue:)) ?? .string
        nullable = json["nullable"]?.bool ?? false
        min = json["min"]?.double
        max = json["max"]?.double
        maxLen = json["maxLen"]?.int
        values = (json["values"]?.array ?? []).compactMap(\.string)
        hint = json["hint"]?.string
        required = json["required"]?.bool ?? false
        defaultValue = json["default"].flatMap { $0.isNull ? nil : $0 }
    }

    /// 標籤：「名稱（中）」→ 名稱（中）；「封面圖（建議 1600×840）［字串陣列］」→ 封面圖
    var label: String {
        var s = rawLabel
        if let i = s.firstIndex(of: "［") { s = String(s[..<i]) }
        // 內容集合的 label 是「標籤（說明）」：說明放 help
        if key != "status", let i = s.firstIndex(of: "（"), s.hasSuffix("）"), s.distance(from: s.startIndex, to: i) > 0 {
            let inner = s[s.index(after: i)..<s.index(before: s.endIndex)]
            // 「名稱（中）」「名稱（英）」這種短的留著
            if inner.count > 2 { s = String(s[..<i]) }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 說明（標籤後面括號裡的那段）
    var help: String? {
        var s = rawLabel
        if let i = s.firstIndex(of: "［") { s = String(s[..<i]) }
        guard let i = s.firstIndex(of: "（"), s.hasSuffix("）") else { return hint }
        let inner = String(s[s.index(after: i)..<s.index(before: s.endIndex)])
        return inner.count > 2 ? inner : hint
    }

    /// 英文版的欄位（*En、titleEn…），編輯畫面放在「English」那一組
    var isEnglish: Bool { key.hasSuffix("En") || key.hasSuffix("_en") }
}

// MARK: - 內容集合（atelier-cms 的 collections/types.ts 的 FieldDef）

struct CollectionSchema: Hashable {
    var key: String
    var label: String
    var singular: String?
    var description: String?
    var singleton: Bool
    var slugs: Bool
    var urlPattern: String?
    var seo: Bool
    var titleField: String
    var imageField: String?
    var translations: [String]
    var fields: [FieldDef]

    init(_ json: JSONValue) {
        key = json["key"]?.string ?? ""
        label = json["label"]?.string ?? key
        singular = json["singular"]?.string
        description = json["description"]?.string
        singleton = json["singleton"]?.bool ?? false
        slugs = json["slugs"]?.bool ?? true
        urlPattern = json["urlPattern"]?.string
        seo = json["seo"]?.bool ?? false
        titleField = json["titleField"]?.string ?? "title"
        imageField = json["imageField"]?.string
        translations = (json["translations"]?.array ?? []).compactMap(\.string)
        fields = (json["fields"]?.array ?? []).map(FieldDef.init)
    }

    func field(_ key: String) -> FieldDef? { fields.first { $0.key == key } }

    /// 有沒有要翻譯的欄位
    var hasTranslations: Bool { !translations.isEmpty && fields.contains(where: \.isLocalizedDeep) }
}

struct FieldDef: Identifiable, Hashable {
    enum Kind: String {
        case text, textarea, markdown, html, number, boolean, date, url, color, select, multiselect, tags, lines, image, images, refs, object, list
    }

    struct Option: Hashable {
        var value: String
        var label: String
    }

    var key: String
    var label: String
    var kind: Kind
    var required: Bool
    var help: String?
    var placeholder: String?
    var options: [Option]
    var fields: [FieldDef]
    var collection: String?
    var maxLength: Int?
    var localized: Bool

    var id: String { key }

    init(_ json: JSONValue) {
        key = json["key"]?.string ?? ""
        label = json["label"]?.string ?? key
        kind = json["type"]?.string.flatMap(Kind.init(rawValue:)) ?? .text
        required = json["required"]?.bool ?? false
        help = json["help"]?.string
        placeholder = json["placeholder"]?.string
        options = (json["options"]?.array ?? []).map { Option(value: $0["value"]?.string ?? "", label: $0["label"]?.string ?? $0["value"]?.string ?? "") }
        fields = (json["fields"]?.array ?? []).map(FieldDef.init)
        collection = json["collection"]?.string
        maxLength = json["maxLength"]?.int
        localized = json["localized"]?.bool ?? false
    }

    /// 自己或底下有要翻譯的欄位
    var isLocalizedDeep: Bool { localized || fields.contains(where: \.isLocalizedDeep) }

    /// 只留要翻譯的子欄位（翻譯分頁用）
    var localizedOnly: FieldDef? {
        if kind == .object || kind == .list {
            let kids = fields.compactMap(\.localizedOnly)
            guard !kids.isEmpty else { return nil }
            var copy = self
            copy.fields = kids
            return copy
        }
        return localized ? self : nil
    }
}

// MARK: - 一筆資料現在的值（GET /api/app/record）

struct RecordValues {
    var id: String
    var title: String?
    /// 欄位 key → 現在的值（和 update 比對的那一份；金額 ntd 是「分」）
    var values: [String: JSONValue]
    var images: [String]?

    init(_ json: JSONValue) {
        id = json["id"]?.string ?? ""
        title = json["title"]?.string
        if case .object(let o) = json["values"] ?? .null { values = o } else { values = [:] }
        images = json["images"].map { $0.array.compactMap(\.string) }
    }
}

// MARK: - 清單的一列（list 的回傳每種資料不一樣：照常見欄位挑標題、說明、圖、狀態）

struct RecordSummary: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var detail: String?
    var image: URL?
    var badge: String?
    var tone: Tone
    var date: Date?
    /// 原始資料（打開詳細頁時先顯示這份）
    var raw: JSONValue

    static func == (a: RecordSummary, b: RecordSummary) -> Bool { a.id == b.id && a.raw == b.raw }
    func hash(into h: inout Hasher) { h.combine(id) }

    init(_ json: JSONValue, entity: String) {
        let s = { (k: String) in json[k]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        id = s("id") ?? s("pageKey") ?? s("slug") ?? s("code") ?? UUID().uuidString
        let heading = s("title") ?? s("titleZh") ?? s("nameZh") ?? s("name") ?? s("subject") ?? s("page") ?? s("q_zh") ?? s("code")
            ?? s("orderNumber") ?? s("label") ?? s("email") ?? s("pageKey") ?? s("slug") ?? "（沒有標題）"
        title = heading
        // 第二行：價格、折扣、網址、寄件人
        let money = s("priceLabel") ?? s("discountLabel") ?? s("totalLabel") ?? s("lifetimeSpendLabel") ?? s("requiredSpendLabel")
        let where_ = s("path") ?? json["url"]?.string.flatMap { $0.hasPrefix("http") ? URL(string: $0)?.path() : $0 } ?? s("slug").map { "/" + $0 }
        subtitle = [money, s("category"), s("tagZh"), s("from"), s("email").flatMap { heading == $0 ? nil : $0 }, entity == "page_seo" ? where_ : nil]
            .compactMap { $0 }.prefix(2).joined(separator: "・").nilIfEmpty
        detail = s("description") ?? s("preview") ?? s("excerpt") ?? s("subtitleZh") ?? s("a_zh")
        image = (json["images"]?.array.first?.string ?? s("imageUrl") ?? s("coverImageUrl") ?? s("cover")).flatMap(URL.init(string:))
        date = json["updatedAt"]?.date ?? json["publishedAt"]?.date ?? json["receivedAt"]?.date ?? json["createdAt"]?.date

        // 狀態：上架／啟用／發布／未讀
        if let published = json["isPublished"]?.bool {
            badge = published ? "已上架" : "未上架"
            tone = published ? .active : .neutral
            if entity == "news" || entity == "post" { badge = published ? "已發布" : "草稿" }
        } else if let active = json["isActive"]?.bool {
            badge = active ? "啟用" : "停用"
            tone = active ? .active : .neutral
        } else if let status = s("status") {
            let shown = RecordSummary.status(status)
            badge = shown.0
            tone = shown.1
        } else if json["unread"]?.bool == true {
            badge = "未讀"
            tone = .gold
        } else if json["noIndex"]?.bool == true {
            badge = "不讓搜尋引擎收錄"
            tone = .warning
        } else {
            badge = nil
            tone = .neutral
        }
        if let stock = json["stock"]?.int, stock <= 5 {
            detail = stock == 0 ? "沒有庫存" : "庫存剩 \(stock)"
        }
        raw = json
    }

    static func status(_ s: String) -> (String, Tone) {
        switch s {
        case "published": ("已發布", .active)
        case "scheduled": ("排程中", .info)
        case "draft": ("草稿", .neutral)
        case "active": ("執行中", .active)
        case "paused": ("暫停", .warning)
        case "sent": ("已發送", .active)
        case "sending": ("發送中", .info)
        case "failed": ("失敗", .danger)
        case "waiting": ("等你決定", .gold)
        case "done": ("完成", .active)
        case "rejected": ("已拒絕", .neutral)
        case "running": ("執行中", .info)
        case "new": ("新的", .gold)
        case "replied": ("已回覆", .active)
        case "archived": ("已封存", .neutral)
        case "open": ("待回覆", .warning)
        case "answered": ("已回覆", .active)
        case "closed": ("已結案", .neutral)
        default: (s, .neutral)
        }
    }

    /// 從 list 的回傳裡找出清單（每種資料的 key 不一樣：products、coupons、items、posts…）
    static func rows(in json: JSONValue, entity: String) -> [RecordSummary] {
        guard case .object(let o) = json else { return [] }
        let preferred = ["items", "\(entity)s", entity.hasSuffix("y") ? "\(entity.dropLast())ies" : "", "posts", "pages", "tiers", "pending"]
        let isObjectList = { (k: String) -> Bool in
            guard let first = o[k]?.array.first, case .object = first else { return false }
            return true
        }
        let key = preferred.first { !$0.isEmpty && isObjectList($0) } ?? o.keys.sorted().first(where: isObjectList)
        return (key.flatMap { o[$0] }?.array ?? []).map { RecordSummary($0, entity: entity) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
