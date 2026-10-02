import SwiftUI

/// 打開一筆資料：特別的幾種有自己的畫面（會員、攤位菜單、黃毛丫頭的 FAQ 頁、信箱），其他用通用的編輯畫面
struct RecordView: View {
    let site: String
    let entity: String
    let id: String?
    @Environment(AppModel.self) private var model
    @State private var schema: EntitySchema?
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                SkeletonRows(rows: 5).pageWidth().padding(.top, 24).frame(maxHeight: .infinity, alignment: .top).brandPage()
            } else if entity == "user", let id {
                MemberView(site: site, memberID: id)
            } else if entity == "stall_menu" {
                StallMenuView(site: site)
            } else if entity == "mailbox", let id {
                MailboxItemView(site: site, itemID: id)
            } else if entity == "faq", schema?.collection == nil, let id, !id.contains("/") {
                FaqPageView(site: site, pageKey: id)
            } else {
                RecordEditor(site: site, entity: entity, mode: id.map { RecordEditor.Mode.edit($0) } ?? .singleton)
            }
        }
        .task {
            schema = await model.schema(for: site)?.entity(entity)
            loaded = true
        }
    }
}

/// 通用的編輯畫面：上面是預覽（照網站上的樣子），下面是欄位（照網站的欄位定義），改了才出現「儲存」。
/// 送出只帶改過的欄位，網站列出「舊 → 新」讓你確認後才真的改（和後台、AI 連接器同一套）。
struct RecordEditor: View {
    enum Mode: Hashable {
        case edit(String)
        case singleton
        case create

        var id: String? { if case .edit(let id) = self { id } else { nil } }
    }

    let site: String
    let entity: String
    let mode: Mode

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var schema: EntitySchema?
    @State private var original: [String: JSONValue] = [:]
    @State private var draft: [String: JSONValue] = [:]
    /// get 的完整內容（網址、變體、使用紀錄…）
    @State private var detail: JSONValue = .null
    @State private var images: [String] = []
    @State private var recordTitle: String?
    @State private var loading = true
    @State private var error: String?
    @State private var proposal: Proposal?
    @State private var pending: Pending?
    @State private var busy = false
    @State private var showAdvanced = false
    @State private var translationLocale: String?

    /// 等確認的是哪一種動作（確認成功之後要做的事不一樣）
    enum Pending { case save, create, delete, images }

    /// 只能寫、不能讀的欄位（一次性的操作），通用畫面不顯示
    private static let operationKeys: Set<String> = ["addItems", "removeProductIds", "updateItems", "removeItemIds", "sections"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                if loading {
                    SkeletonRows(rows: 6)
                } else if let schema {
                    header(schema)
                    preview(schema)
                    form(schema)
                    extras
                    if mode != .create {
                        footerActions(schema)
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                }
            }
            .frame(maxWidth: Metric.readable + 120, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .brandPage()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            Task { await finished(result) }
        }
        .task { await load() }
    }

    private var navigationTitle: String {
        if mode == .create { return "新增\(schema?.label ?? "")" }
        return recordTitle ?? schema?.label ?? ""
    }

    // MARK: 讀

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        guard let s = await model.schema(for: site)?.entity(entity) else {
            error = model.schemaErrors[site] ?? "這個網站沒有「\(entity)」，或你沒有權限。"
            return
        }
        schema = s
        if mode == .create {
            var start: [String: JSONValue] = [:]
            for f in s.createFields {
                if let d = f.defaultValue { start[f.key] = d }
            }
            original = [:]
            draft = start
            return
        }
        let id = mode.id
        let api = model.api
        let site = site, entity = entity
        // 兩個請求同時送（現在的值、完整內容）
        let recordTask = Task<RecordValues?, Never> {
            guard s.canUpdate || s.images != nil else { return nil }
            return try? await api.record(site: site, entity: entity, id: id)
        }
        let getTask = Task<JSONValue?, Never> {
            guard s.canGet else { return nil }
            return try? await api.get(site: site, entity: entity, id: id)
        }
        let record = await recordTask.value
        let got = await getTask.value
        if record == nil && got == nil {
            error = "拿不到這筆資料（可能已經被刪除，或網站還沒更新到支援 App 編輯的版本）。"
            return
        }
        detail = got ?? .null
        var values: [String: JSONValue] = [:]
        if let record {
            values = record.values
            recordTitle = record.title
            images = record.images ?? []
        } else if let got {
            values = Self.valuesFromGet(got, fields: s.fields)
        }
        if images.isEmpty { images = Self.imagesFromGet(detail) }
        if recordTitle == nil { recordTitle = Self.titleFromGet(detail) }
        // 金額：網站給「分」，畫面上用「元」
        for f in s.fields where f.kind == .ntd {
            if let cents = values[f.key]?.double { values[f.key] = .number(cents / 100) }
        }
        original = values
        draft = values
    }

    /// 網站還沒有 /api/app/record 時：從 get 的內容找同名的欄位（盡量）
    private static func valuesFromGet(_ got: JSONValue, fields: [FieldSpec]) -> [String: JSONValue] {
        guard case .object(let top) = got else { return [:] }
        var pool: [String: JSONValue] = top
        for (_, v) in top {
            if case .object(let inner) = v, inner["id"] != nil { pool.merge(inner) { a, _ in a } }
        }
        if case .object(let data) = top["data"] ?? .null { pool.merge(data) { _, b in b } }
        var out: [String: JSONValue] = [:]
        for f in fields {
            if let v = pool[f.key] { out[f.key] = v }
        }
        return out
    }

    private static func imagesFromGet(_ got: JSONValue) -> [String] {
        if let list = got["images"]?.array, !list.isEmpty {
            return list.compactMap { $0["url"]?.string ?? $0.string }
        }
        return []
    }

    private static func titleFromGet(_ got: JSONValue) -> String? {
        if let t = got["title"]?.string { return t }
        if case .object(let top) = got {
            for (_, v) in top {
                if let name = v["nameZh"]?.string ?? v["titleZh"]?.string ?? v["code"]?.string ?? v["name"]?.string { return name }
            }
        }
        return nil
    }

    // MARK: 頁首

    private func header(_ s: EntitySchema) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow([model.site(site)?.name, s.label].compactMap { $0 }.joined(separator: " · "))
            Headline(mode == .create ? "New *\(s.label)*" : (displayTitle ?? s.label), role: .h1)
            HStack(spacing: 8) {
                if let badge = statusBadge { StatusBadge(badge.0, tone: badge.1) }
                if !s.canUpdate && mode != .create {
                    StatusBadge("只能查看", tone: .neutral)
                }
            }
        }
        .reveal()
    }

    private var displayTitle: String? {
        for key in ["title", "titleZh", "nameZh", "name", "code", "q_zh"] {
            if let t = draft[key]?.string, !t.isEmpty { return t }
        }
        return recordTitle
    }

    private var statusBadge: (String, Tone)? {
        if let p = draft["isPublished"]?.bool { return p ? ("已上架", .active) : ("未上架", .neutral) }
        if let a = draft["isActive"]?.bool { return a ? ("啟用", .active) : ("停用", .neutral) }
        if let st = draft["status"]?.string { return RecordSummary.status(st) }
        return nil
    }

    // MARK: 預覽（照網站上的樣子，跟著欄位即時變）

    @ViewBuilder
    private func preview(_ s: EntitySchema) -> some View {
        switch entity {
        case "banner":
            BannerPreview(values: draft)
        case "coupon":
            CouponTicket(values: draft)
        case "page_seo":
            SerpPreview(title: draft["titleZh"]?.string ?? "", description: draft["descriptionZh"]?.string ?? "", url: detail["url"]?.string ?? model.site(site)?.url?.absoluteString ?? "")
        default:
            if s.images != nil, mode != .create {
                ImageGallery(site: site, entity: entity, id: mode.id ?? "", single: s.images == .single, images: $images)
            }
            if let c = s.collection, c.seo, mode != .create {
                let seo = draft["seo"] ?? .null
                SerpPreview(
                    title: seo["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? draft[c.titleField]?.string ?? "",
                    description: seo["description"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? draft["excerpt"]?.string ?? draft["summary"]?.string ?? draft["tagline"]?.string ?? "",
                    url: detail["publicUrl"]?.string ?? detail["url"]?.string ?? ""
                )
            }
        }
    }

    // MARK: 欄位

    private var fields: [FieldSpec] {
        guard let schema else { return [] }
        let list = mode == .create ? schema.createFields : schema.fields
        return list.filter { !Self.operationKeys.contains($0.key) }
    }

    private var editable: Bool { mode == .create || (schema?.canUpdate ?? false) }

    @ViewBuilder
    private func form(_ s: EntitySchema) -> some View {
        if let c = s.collection {
            collectionForm(c)
        } else {
            let main = fields.filter { !$0.isEnglish && $0.kind != .json }
            let english = fields.filter { $0.isEnglish && $0.kind != .json }
            let advanced = fields.filter { $0.kind == .json }
            fieldGroup(nil, main)
            if !english.isEmpty { fieldGroup("English", english) }
            if !advanced.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        withAnimation(Motion.ease) { showAdvanced.toggle() }
                    } label: {
                        HStack {
                            Eyebrow("進階", dot: nil)
                            Spacer()
                            Text(showAdvanced ? "−" : "+").font(.brand(18, .medium)).foregroundStyle(Theme.ink)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.row)
                    if showAdvanced { fieldGroup(nil, advanced) }
                }
            }
        }
    }

    private func fieldGroup(_ title: String?, _ list: [FieldSpec]) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            if let title { Eyebrow(title) }
            ForEach(list) { f in
                SpecField(spec: f, value: binding(f.key), required: mode == .create && f.required)
                    .disabled(!editable)
                    .overlay(alignment: .leading) { changedMark(f.key) }
            }
        }
    }

    /// 內容集合：內容（照集合的欄位順序）、發布、SEO、翻譯
    @ViewBuilder
    private func collectionForm(_ c: CollectionSchema) -> some View {
        let keys = Set(fields.map(\.key))
        VStack(alignment: .leading, spacing: 30) {
            Eyebrow("內容")
            ForEach(c.fields.filter { keys.contains($0.key) }) { def in
                DefField(def: def, value: binding(def.key))
                    .disabled(!editable)
                    .overlay(alignment: .leading) { changedMark(def.key) }
            }
        }
        let meta = fields.filter { ["slug", "status", "publishAt"].contains($0.key) }
        if !meta.isEmpty {
            VStack(alignment: .leading, spacing: 26) {
                Eyebrow(c.urlPattern.map { "發布・網址 \($0)" } ?? "發布")
                ForEach(meta) { f in
                    if f.key != "publishAt" || draft["status"]?.string == "scheduled" {
                        SpecField(spec: f, value: binding(f.key), required: mode == .create && f.required)
                            .disabled(!editable)
                            .overlay(alignment: .leading) { changedMark(f.key) }
                    }
                }
            }
        }
        if keys.contains("seo") {
            SeoFields(value: binding("seo"))
                .disabled(!editable)
        }
        if keys.contains("i18n"), c.hasTranslations {
            TranslationFields(collection: c, value: binding("i18n"), source: draft, locale: $translationLocale)
                .disabled(!editable)
        }
    }

    private func binding(_ key: String) -> Binding<JSONValue> {
        Binding(get: { draft[key] ?? .null }, set: { draft[key] = $0 })
    }

    /// 改過的欄位左邊一條橘線
    @ViewBuilder
    private func changedMark(_ key: String) -> some View {
        if mode != .create, changes[key] != nil {
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 2)
                .padding(.leading, -12)
                .transition(.opacity)
        }
    }

    // MARK: 變更

    /// 和原本不一樣的欄位（送出的格式：字串去掉前後空白、可以空的空字串變成 null）
    private var changes: [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for f in fields {
            let now = Self.normalize(draft[f.key] ?? .null, f)
            let before = Self.normalize(original[f.key] ?? .null, f)
            if mode == .create {
                if !now.isNull, now != .string(""), now != .array([]) { out[f.key] = now }
            } else if now != before {
                out[f.key] = now
            }
        }
        return out
    }

    private static func normalize(_ v: JSONValue, _ f: FieldSpec) -> JSONValue {
        switch v {
        case .string(let s):
            let t = f.kind == .text ? s.trimmingCharacters(in: .whitespacesAndNewlines) : s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty, f.nullable { return .null }
            return .string(t)
        case .array(let items):
            if f.kind == .stringArray {
                return .array(items.filter { !($0.string ?? "").trimmingCharacters(in: .whitespaces).isEmpty })
            }
            return v
        default:
            return v
        }
    }

    // MARK: 儲存列

    @ViewBuilder
    private var saveBar: some View {
        let count = changes.count
        if editable, mode == .create || count > 0 {
            HStack(spacing: 10) {
                if mode != .create {
                    Button("復原") {
                        withAnimation(Motion.ease) { draft = original }
                    }
                    .buttonStyle(.brand(.ghost, size: .lg))
                }
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                        Text(mode == .create ? "新增" : "儲存 \(count) 項變更")
                    }
                }
                .buttonStyle(.brand(.accent, size: .lg, fullWidth: true))
                .disabled(busy || (mode == .create && count == 0))
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, sizeClass == .regular ? Metric.gutterWide : Metric.gutter)
            .padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Rule() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            let outcome: ConsoleAPI.WriteOutcome
            if mode == .create {
                pending = .create
                outcome = try await model.api.proposeCreate(site: site, entity: entity, fields: changes)
            } else {
                pending = .save
                outcome = try await model.api.proposeUpdate(site: site, entity: entity, id: mode.id, fields: changes)
            }
            switch outcome {
            case .needsConfirmation(let p): proposal = p
            case .done(let r): await finished(r)
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    private func finished(_ result: JSONValue) async {
        switch pending {
        case .create:
            model.show("已新增\(schema?.label ?? "")")
            dismiss()
        case .delete:
            model.show("已刪除")
            dismiss()
        case .save:
            model.show("已更新「\(displayTitle ?? schema?.label ?? "")」")
            await load()
        case .images, nil:
            await load()
        }
        pending = nil
    }

    // MARK: 其他資訊（get 裡多的東西：變體、使用紀錄、組合的品項）

    @ViewBuilder
    private var extras: some View {
        if let variants = detail["variants"]?.array, !variants.isEmpty {
            InfoList(title: "規格（在後台修改）", rows: variants.map { v in
                (v["name"]?.string ?? "規格", [v["sku"]?.string, v["price"]?.int.map { ntd(cents: $0) }, v["stock"]?.int.map { "庫存 \($0)" }].compactMap { $0 }.joined(separator: "・"))
            })
        }
        if let usages = detail["usages"]?.array, !usages.isEmpty {
            InfoList(title: "使用紀錄", rows: usages.map { u in
                (u["orderNumber"]?.string ?? "—", [u["userEmail"]?.string, u["usedAt"]?.date?.shortText].compactMap { $0 }.joined(separator: "・"))
            })
        }
        if entity == "bundle", let items = detail["items"]?.array, !items.isEmpty {
            InfoList(title: "組合內容", rows: items.map { i in
                (i["productNameZh"]?.string ?? "商品", "× \(i["quantity"]?.int ?? 1)" + (i["productPrice"]?.int.map { "・單買 \(ntd(cents: $0))" } ?? ""))
            })
        }
        if let restricted = detail["products"]?.array, entity == "coupon", !restricted.isEmpty {
            InfoList(title: "只能用在這些商品", rows: restricted.map { ($0["nameZh"]?.string ?? "商品", "") })
        }
    }

    // MARK: 頁尾：打開網站、後台、刪除

    private func footerActions(_ s: EntitySchema) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Rule()
            HStack(spacing: 10) {
                if let url = (detail["publicUrl"]?.string).flatMap(URL.init(string:)) {
                    Button("在網站上看 ↗") { openURL(url) }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
                if let url = (detail["adminUrl"]?.string).flatMap(URL.init(string:)) {
                    Button("在後台打開 ↗") { openURL(url) }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
                Spacer()
                if s.canDelete, let id = mode.id {
                    Button("刪除") {
                        Task {
                            pending = .delete
                            do {
                                let outcome = try await model.api.proposeDelete(site: site, entity: entity, id: id)
                                switch outcome {
                                case .needsConfirmation(let p): proposal = p
                                case .done(let r): await finished(r)
                                }
                            } catch {
                                model.show(error.localizedDescription, tone: .danger)
                            }
                        }
                    }
                    .buttonStyle(.brand(.danger, size: .sm))
                }
            }
        }
    }
}

/// 唯讀的一串資訊（標題＋細線隔開的列）
struct InfoList: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title)
            RuledList(color: Theme.hair) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .textRole(.small)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 12)
                        Text(row.1)
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }
}

// MARK: - SEO（內容集合的 seo 欄位：標題、描述、分享圖、不讓搜尋引擎收錄）

struct SeoFields: View {
    @Binding var value: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Eyebrow("SEO（沒填就用標題與摘要）")
            TextBlock(label: "搜尋結果的標題", help: "30 字內最好；讀者會搜尋的關鍵字放前面", limit: 120, multiline: false, value: $value.member("title"))
            TextBlock(label: "搜尋結果的描述", help: "80–120 字", limit: 320, multiline: true, value: $value.member("description"))
            ImageURLField(label: "分享圖", help: "1200×630 最好", value: $value.member("ogImage").text)
            ToggleRow(label: "不讓搜尋引擎收錄", help: "勾了之後 Google 不會顯示這一頁", isOn: $value.member("noIndex").flag)
        }
    }
}

// MARK: - 翻譯（data.i18n.<語系>：結構跟原本一樣、只放要翻譯的欄位；旁邊附原文）

struct TranslationFields: View {
    let collection: CollectionSchema
    @Binding var value: JSONValue
    let source: [String: JSONValue]
    @Binding var locale: String?

    var body: some View {
        let current = locale ?? collection.translations.first ?? "en"
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Eyebrow("翻譯")
                Spacer()
                if collection.translations.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(collection.translations, id: \.self) { l in
                            FilterChip(title: Self.name(l), selected: l == current) { locale = l }
                        }
                    }
                }
            }
            Text("\(Self.name(current))：沒翻的欄位網站顯示原文；清單（例如 FAQ）要和原文同樣的順序與筆數。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
            ForEach(collection.fields.compactMap(\.localizedOnly)) { def in
                VStack(alignment: .leading, spacing: 8) {
                    DefField(def: def, value: $value.member(current).member(def.key))
                    if let original = source[def.key]?.string, !original.isEmpty, def.kind != .object, def.kind != .list {
                        Text("原文：\(original)")
                            .textRole(.xs)
                            .foregroundStyle(Theme.faint)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    static func name(_ locale: String) -> String {
        switch locale {
        case "en": "English"
        case "ja": "日本語"
        case "ko": "한국어"
        case "zh-CN": "简体中文"
        default: locale
        }
    }
}
