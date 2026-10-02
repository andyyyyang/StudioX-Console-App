import SwiftUI

// 有自己樣子的幾種資料：會員、攤位菜單、FAQ 頁（黃毛丫頭）、信箱。
// 寫入一樣走網站的兩步驟確認。

// MARK: - 會員（user：消費、等級、RFM、最近的訂單、折價券；可以發折價券）

struct MemberView: View {
    let site: String
    let memberID: String
    @Environment(AppModel.self) private var model
    @State private var data: JSONValue?
    @State private var error: String?
    @State private var issuing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                if let data {
                    content(data)
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 5)
                }
            }
            .frame(maxWidth: Metric.readable + 120, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await load() }
        .brandPage()
        .navigationTitle("會員")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.site(site)?.tools.contains("issue_coupons") == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("發折價券") { issuing = true }
                }
            }
        }
        .sheet(isPresented: $issuing) {
            IssueCouponSheet(site: site, userIDs: [memberID], to: data?["user"]?["name"]?.string ?? data?["user"]?["email"]?.string ?? "這位會員")
        }
        .task { await load() }
    }

    private func load() async {
        do {
            data = try await model.api.get(site: site, entity: "user", id: memberID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func content(_ d: JSONValue) -> some View {
        let u = d["user"] ?? .null
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Avatar(name: u["name"]?.string ?? u["email"]?.string ?? "?", size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(u["adminLevelLabel"]?.string ?? (u["tier"]?["name"]?.string ?? u["tier"]?.string ?? "會員"))
                    if let at = u["createdAt"]?.date {
                        Text("\(at.dayText) 加入")
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            Headline(u["name"]?.string ?? "（沒有名字）", role: .h1)
            VStack(alignment: .leading, spacing: 6) {
                if let email = u["email"]?.string, let url = URL(string: "mailto:\(email)") {
                    Link(email, destination: url)
                }
                if let phone = u["phone"]?.string, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(phone + ((u["phoneVerified"]?.bool ?? false) ? " ✓" : ""), destination: url)
                }
            }
            .textRole(.body)
            .tint(Theme.ink)
        }
        .reveal()

        StatGrid {
            Stat(value: Double(u["lifetimeSpendCents"]?.int ?? 0) / 100, label: "累積消費", format: { "NT$" + Int($0.rounded()).formatted() })
            Stat(value: Double(d["rfm"]?["orderCount"]?.int ?? d["recentOrders"]?.array.count ?? 0), label: "訂單")
            Stat(value: Double(u["invitedCount"]?.int ?? 0), label: "邀請的朋友")
            Stat(value: Double(d["rfm"]?["recencyDays"]?.int ?? 0), label: "距離上次購買（天）")
        }

        if let rfm = d["rfm"], !rfm.isNull, let segment = rfm["segment"]?.string {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("顧客分群（RFM）")
                HStack(spacing: 10) {
                    StatusBadge(Self.segment(segment).0, tone: Self.segment(segment).1)
                    Text(Self.segment(segment).2)
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                }
                Text("最近 90 天 \(rfm["frequency90d"]?.int ?? 0) 筆、\(ntd(cents: rfm["monetaryCents"]?.int ?? 0))")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }

        if let orders = d["recentOrders"]?.array, !orders.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("最近的訂單")
                RuledList {
                    ForEach(Array(orders.enumerated()), id: \.offset) { _, o in
                        Button {
                            if let id = o["id"]?.string { model.open(.order(site: site, id: id)) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(o["orderNumber"]?.string ?? "")
                                        .font(.brand(15, .medium).monospacedDigit())
                                        .foregroundStyle(Theme.ink)
                                    Text(o["createdAt"]?.date?.shortText ?? "")
                                        .textRole(.xs)
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                let status = OrderStatus(raw: o["status"]?.string ?? "")
                                StatusBadge(status.label, tone: status.tone)
                                Text(o["totalLabel"]?.string ?? "")
                                    .font(.brand(15, .medium).monospacedDigit())
                                    .foregroundStyle(Theme.ink)
                                    .frame(minWidth: 70, alignment: .trailing)
                            }
                            .padding(.vertical, 14)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.row)
                    }
                }
            }
        }

        if let coupons = d["coupons"]?.array, !coupons.isEmpty {
            InfoList(title: "折價券", rows: coupons.map { c in
                (c["code"]?.string ?? "", [(c["isActive"]?.bool ?? false) ? "可以用" : "停用", c["expiresAt"]?.date.map { "\($0.dayText) 到期" }].compactMap { $0 }.joined(separator: "・"))
            })
        }
    }

    /// RFM 分群（lib/personalized/rfm.ts）
    static func segment(_ s: String) -> (String, Tone, String) {
        switch s {
        case "champion": ("冠軍", .gold, "常買、買得多、最近才買")
        case "loyal": ("忠誠", .active, "固定回來買")
        case "promising": ("有潛力", .info, "最近買過，還不常買")
        case "new": ("新客", .info, "剛第一次購買")
        case "at_risk": ("快流失", .warning, "以前常買，最近沒來")
        case "sleep": ("沉睡", .neutral, "很久沒有購買")
        default: (s, .neutral, "")
        }
    }
}

/// 發折價券給會員（每人一張一次性的券，排入「折價券已發放」通知）
struct IssueCouponSheet: View {
    let site: String
    let userIDs: [String]
    let to: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: JSONValue] = ["type": "fixed", "channel": "both"]
    @State private var proposal: Proposal?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Headline("Send a *coupon*", role: .h2)
                    Text("給 \(to)：一張一次性的券，網站會通知他。")
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                    CouponTicket(values: values)
                    ChoiceField(label: "類型", field: "type", options: [("fixed", "折抵金額"), ("percentage", "打折（%）"), ("free_shipping", "免運")], value: bind("type"))
                    if values["type"]?.string != "free_shipping" {
                        FieldBlock(label: values["type"]?.string == "percentage" ? "折扣（%）" : "折抵（元）", required: true) {
                            NumberInput(value: bind("value"), prefix: values["type"]?.string == "percentage" ? nil : "NT$")
                        }
                    }
                    TextBlock(label: "名稱", help: "客人在券上看到的字", limit: 120, value: bind("name"))
                    FieldBlock(label: "最低消費（元）") {
                        NumberInput(value: bind("minimumOrder"), prefix: "NT$", nullable: true)
                    }
                    ChoiceField(label: "通路", field: "channel", options: [("both", "線上和門市都能用"), ("online", "只限線上"), ("in_store", "只限門市")], value: bind("channel"))
                    DateField(label: "到期", value: bind("expiresAt"), nullable: true)
                }
                .padding(24)
            }
            .background(Theme.sheet.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                        Text("發送")
                    }
                }
                .buttonStyle(.brand(.accent, size: .lg, fullWidth: true))
                .disabled(busy || (values["type"]?.string != "free_shipping" && (values["value"]?.double ?? 0) <= 0))
                .padding(20)
                .background(Theme.sheet)
            }
            .navigationTitle("發折價券")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
                let issued = result["issued"]?.array.count ?? 0
                model.show(issued > 0 ? "已發出 \(issued) 張折價券" : "已送出")
                dismiss()
            }
        }
    }

    private func bind(_ key: String) -> Binding<JSONValue> {
        Binding(get: { values[key] ?? .null }, set: { values[key] = $0 })
    }

    private func send() async {
        busy = true
        defer { busy = false }
        var fields = values.filter { !$0.value.isNull && $0.value != .string("") }
        if fields["type"]?.string == "free_shipping" { fields["value"] = 0 }
        do {
            let outcome = try await model.api.proposeIssueCoupons(site: site, userIDs: userIDs, fields: fields)
            if case .needsConfirmation(let p) = outcome { proposal = p }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }
}

// MARK: - 攤位菜單（stall_menu：現場的價目表，一個分類一段）

struct StallMenuView: View {
    let site: String
    @Environment(AppModel.self) private var model
    @State private var data: JSONValue?
    @State private var error: String?
    @State private var editing: StallItem?
    @State private var proposal: Proposal?

    struct StallItem: Identifiable {
        var id: String
        var section: String
        var values: [String: JSONValue]
        var isNew: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(model.site(site)?.name ?? site)
                    Headline("The *menu*", role: .h1)
                    Text("攤位現場的價目表：菜單頁與 Xena 回答「現場多少錢」都用這份。價格是元。")
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                }
                .reveal()
                if let data {
                    ForEach(Array((data["sections"]?.array ?? []).enumerated()), id: \.offset) { _, section in
                        sectionView(section)
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 6)
                }
            }
            .frame(maxWidth: Metric.readable + 120, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await load() }
        .brandPage()
        .navigationTitle("攤位菜單")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { item in
            StallItemSheet(item: item) { fields in
                Task { await propose(item: item, fields: fields) }
            } onRemove: {
                Task { await propose(remove: item.id) }
            }
        }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { _ in
            model.show("菜單已更新")
            Task { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            data = try await model.api.get(site: site, entity: "stall_menu", id: nil)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sectionView(_ section: JSONValue) -> some View {
        let name = section["section"]?.string ?? ""
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Headline(name, role: .h3)
                if let en = section["sectionEn"]?.string {
                    Text(en)
                        .font(.serif(18, italic: true))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("＋ 品項") {
                    editing = StallItem(id: UUID().uuidString, section: name, values: ["isAvailable": true], isNew: true)
                }
                .buttonStyle(.brand(.ghost, size: .sm))
            }
            RuledList {
                ForEach(Array((section["items"]?.array ?? []).enumerated()), id: \.offset) { _, item in
                    Button {
                        if case .object(let o) = item {
                            editing = StallItem(id: item["id"]?.string ?? "", section: name, values: o, isNew: false)
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item["nameZh"]?.string ?? "")
                                    .textRole(.h4)
                                    .foregroundStyle(Theme.ink)
                                    .strikethrough(item["isAvailable"]?.bool == false, color: Theme.muted)
                                let sub = [item["nameEn"]?.string, item["note"]?.string, item["productName"]?.string.map { "線上：\($0)" }].compactMap { $0 }.joined(separator: "・")
                                if !sub.isEmpty {
                                    Text(sub)
                                        .textRole(.xs)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer()
                            if item["isAvailable"]?.bool == false {
                                StatusBadge("暫停供應", tone: .neutral)
                            }
                            Text(Self.price(item))
                                .font(.brand(16, .medium).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.row)
                }
            }
        }
    }

    static func price(_ item: JSONValue) -> String {
        guard let p = item["priceNtd"]?.int else { return "現場" }
        if let max = item["priceMaxNtd"]?.int { return "NT$\(p)/\(max)" }
        return "NT$\(p)"
    }

    private func propose(item: StallItem, fields: [String: JSONValue]) async {
        do {
            let args: [String: JSONValue]
            if item.isNew {
                var add = fields
                add["section"] = .string(item.section)
                args = ["addItems": [.object(add)]]
            } else {
                var upd = fields
                upd["id"] = .string(item.id)
                args = ["updateItems": [.object(upd)]]
            }
            let outcome = try await model.api.proposeUpdate(site: site, entity: "stall_menu", id: nil, fields: args)
            if case .needsConfirmation(let p) = outcome { proposal = p }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    private func propose(remove id: String) async {
        do {
            let outcome = try await model.api.proposeUpdate(site: site, entity: "stall_menu", id: nil, fields: ["removeItemIds": [.string(id)]])
            if case .needsConfirmation(let p) = outcome { proposal = p }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }
}

/// 改一個菜單品項（只送改過的欄位）
private struct StallItemSheet: View {
    let item: StallMenuView.StallItem
    let onSave: ([String: JSONValue]) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: JSONValue] = [:]

    private let keys = ["nameZh", "nameEn", "priceNtd", "priceMaxNtd", "note", "isAvailable"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Headline(item.isNew ? "New *item*" : (item.values["nameZh"]?.string ?? "品項"), role: .h2)
                    Eyebrow(item.section)
                    TextBlock(label: "名稱", limit: 60, required: true, value: bind("nameZh"))
                    TextBlock(label: "英文名稱", limit: 80, value: bind("nameEn"))
                    FieldBlock(label: "價格（元）", hint: "空白＝不標價，菜單寫「現場」") {
                        NumberInput(value: bind("priceNtd"), integer: true, prefix: "NT$", nullable: true)
                    }
                    FieldBlock(label: "第二個價格（元）", hint: "價目表寫兩個價格時（例如 140/150）填 150") {
                        NumberInput(value: bind("priceMaxNtd"), integer: true, prefix: "NT$", nullable: true)
                    }
                    TextBlock(label: "備註", help: "一份、3 支、時價…", limit: 40, value: bind("note"))
                    ToggleRow(label: "供應中", help: "關掉＝暫停供應、菜單上不顯示", isOn: bind("isAvailable").flag)
                    if !item.isNew {
                        Button("刪除這個品項") {
                            dismiss()
                            onRemove()
                        }
                        .buttonStyle(.brand(.danger, size: .sm))
                    }
                }
                .padding(24)
            }
            .background(Theme.sheet.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item.isNew ? "新增" : "儲存") {
                        dismiss()
                        onSave(changes)
                    }
                    .disabled(changes.isEmpty || (values["nameZh"]?.string ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { values = item.values }
    }

    private var changes: [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for k in keys {
            var now = values[k] ?? .null
            if case .string(let s) = now, s.trimmingCharacters(in: .whitespaces).isEmpty { now = .null }
            let before = item.isNew ? JSONValue.null : (item.values[k] ?? .null)
            if now != before { out[k] = now }
        }
        return out
    }

    private func bind(_ key: String) -> Binding<JSONValue> {
        Binding(get: { values[key] ?? .null }, set: { values[key] = $0 })
    }
}

// MARK: - FAQ 頁（黃毛丫頭：一個頁面一組問答，題目的 id 是 <pageKey>/<index>）

struct FaqPageView: View {
    let site: String
    let pageKey: String
    @Environment(AppModel.self) private var model
    @State private var data: JSONValue?
    @State private var error: String?
    @State private var open: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(model.site(site)?.name ?? site)
                    Headline("*FAQ*・\(pageKey)", role: .h1)
                    if let url = data?["publicUrl"]?.string {
                        Text(url).textRole(.xs).foregroundStyle(Theme.muted)
                    }
                }
                .reveal()
                if let data {
                    let groups = Self.groups(data)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 12) {
                            if let title = group.0 { Eyebrow(title) }
                            RuledList {
                                ForEach(Array(group.1.enumerated()), id: \.offset) { _, item in
                                    faqRow(item)
                                }
                            }
                        }
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 5)
                }
            }
            .frame(maxWidth: Metric.readable + 120, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await load() }
        .brandPage()
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            data = try await model.api.get(site: site, entity: "faq", id: pageKey)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func groups(_ d: JSONValue) -> [(String?, [JSONValue])] {
        var out: [(String?, [JSONValue])] = []
        let top = d["faq"]?.array ?? []
        if !top.isEmpty { out.append((nil, top)) }
        for s in d["sections"]?.array ?? [] {
            out.append((s["category_zh"]?.string, s["items"]?.array ?? []))
        }
        return out
    }

    /// FAQ 的一題（Faq.astro：「＋」打開時轉 45° 變橘）
    private func faqRow(_ item: JSONValue) -> some View {
        let id = item["id"]?.string ?? ""
        let isOpen = open == id
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(Motion.ease) { open = isOpen ? nil : id }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Text(item["q_zh"]?.string ?? "")
                        .textRole(.h4)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text("+")
                        .font(.brand(20, .medium))
                        .foregroundStyle(isOpen ? Theme.onAccent : Theme.ink)
                        .rotationEffect(.degrees(isOpen ? 45 : 0))
                        .frame(width: 32, height: 32)
                        .background(isOpen ? Theme.accent : .clear, in: .rect(cornerRadius: Metric.radiusSm))
                        .overlay(RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(isOpen ? .clear : Theme.line, lineWidth: 1))
                }
                .padding(.vertical, 18)
                .contentShape(.rect)
            }
            .buttonStyle(.row)
            if isOpen {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item["a_zh"]?.string ?? "")
                        .textRole(.body)
                        .foregroundStyle(Theme.ink2)
                    if let en = item["q_en"]?.string, !en.isEmpty {
                        Text(en)
                            .font(.serif(16, italic: true))
                            .foregroundStyle(Theme.muted)
                    }
                    NavigationLink(value: Route.record(site: site, entity: "faq", id: id)) {
                        Text("編輯這一題")
                    }
                    .buttonStyle(.brand(.ghost, size: .sm, arrow: true))
                }
                .padding(.bottom, 18)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - 信箱（不是客服對話的信：第一次寫信來的人、廠商、金流商…）

struct MailboxItemView: View {
    let site: String
    let itemID: String
    @Environment(AppModel.self) private var model
    @State private var data: JSONValue?
    @State private var error: String?
    @State private var category = "other"
    @State private var proposal: Proposal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let data {
                    let e = data["email"] ?? .null
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(e["from"]?.string ?? "")
                        Headline(e["subject"]?.string ?? "（沒有主旨）", role: .h2)
                        Text(e["receivedAt"]?.date?.shortText ?? "")
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                    }
                    if let warning = data["warning"]?.string {
                        Text(warning)
                            .textRole(.xs)
                            .foregroundStyle(Theme.warningFG)
                    }
                    Text(e["text"]?.string ?? "")
                        .textRole(.body)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .panel()
                    if let files = e["attachments"]?.array, !files.isEmpty {
                        InfoList(title: "附件（檔案在 Resend 收件匣，保留 30 天）", rows: files.map { ($0["filename"]?.string ?? $0["name"]?.string ?? $0.string ?? "檔案", $0["size"]?.int.map { "\($0 / 1024) KB" } ?? "") })
                    }
                    if let hints = data["memberHint"]?.array, !hints.isEmpty {
                        InfoList(title: "可能是這位會員（不會自動綁定）", rows: hints.map { ($0["name"]?.string ?? "", $0["email"]?.string ?? "") })
                    }
                    actions(e)
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 5)
                }
            }
            .frame(maxWidth: Metric.readable, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .brandPage()
        .navigationTitle("信箱")
        .navigationBarTitleDisplayMode(.inline)
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { _ in
            model.show("已處理")
            Task { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            data = try await model.api.get(site: site, entity: "mailbox", id: itemID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func actions(_ e: JSONValue) -> some View {
        if let thread = e["threadId"]?.string {
            Button("打開客服對話") { model.open(.thread(site: site, id: thread)) }
                .buttonStyle(.brand(.primary, arrow: true))
        } else if e["handled"]?.string != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(e["handled"]?.string ?? "")
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
                Button("放回收件匣") { Task { await act(["action": "restore"]) } }
                    .buttonStyle(.brand(.ghost))
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow("這封是客人寫來的？")
                ChoiceField(label: "分類", field: "category", options: ["order", "shipping", "refund", "product", "coupon", "account", "wholesale", "other"].map { ($0, OptionLabels.label(field: "category", value: $0)) }, value: Binding(get: { .string(category) }, set: { category = $0.string ?? "other" }))
                HStack(spacing: 10) {
                    Button("轉成客服對話") { Task { await act(["action": "adopt", "category": .string(category)]) } }
                        .buttonStyle(.brand(.primary, arrow: true))
                    Button("不是客人，收起來") { Task { await act(["action": "ignore", "note": "App：不是客人"]) } }
                        .buttonStyle(.brand(.ghost))
                }
                Text("信裡的內容是寄件人寫的；要求付款、改匯款帳號、點連結的，一律先查證。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func act(_ fields: [String: JSONValue]) async {
        do {
            let outcome = try await model.api.proposeUpdate(site: site, entity: "mailbox", id: itemID, fields: fields)
            switch outcome {
            case .needsConfirmation(let p): proposal = p
            case .done:
                model.show("已處理")
                await load()
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }
}
