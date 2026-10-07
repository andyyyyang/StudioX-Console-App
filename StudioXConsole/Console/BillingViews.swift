import Charts
import SwiftUI

// MARK: - 用量

/// 用量（console 的 /admin/platform 與 /admin/platform/ai）：這個月寄信、簡訊、AI 的成本與向客戶收的錢；AI 的 token 細項
struct UsageView: View {
    @Environment(AppModel.self) private var model
    @State private var period = PeriodPicker.current
    @State private var tab = "services"
    @State private var usage: UsageReport?
    @State private var ai: JSONValue?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader("用量", eyebrow: "平台管理", subtitle: "成本是 StudioX 付給供應商的，收費是照價目向客戶收的（含方案內含的額度）。")
                    HStack(spacing: 10) {
                        PeriodPicker(period: $period)
                        Spacer()
                    }
                    FilterBar(items: ["services", "ai"], selection: $tab, title: { $0 == "services" ? "所有服務" : "AI 細項" })
                }
                if let error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if tab == "services" {
                    if let u = usage { services(u) } else { SkeletonRows(rows: 5) }
                } else {
                    if let ai { aiSection(ai) } else { SkeletonRows(rows: 5) }
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await refresh() }.value }
        .brandPage()
        .pageTitle("用量")
        .task(id: period) { await refresh() }
    }

    @ViewBuilder
    private func services(_ u: UsageReport) -> some View {
        StatGrid(columns: 3) {
            Stat(value: Double(u.costMicros) / 1_000_000, label: "成本", format: { ntdMicros(Int($0 * 1_000_000)) })
            Stat(value: Double(u.priceMicros) / 1_000_000, label: "收費", format: { ntdMicros(Int($0 * 1_000_000)) })
            Stat(value: Double(u.calls), label: "次數")
        }
        if u.daily.contains(where: { $0.costMicros > 0 || $0.priceMicros > 0 }) {
            UsageChart(points: u.daily.map { UsageChart.Point(day: $0.day, cost: Double($0.costMicros) / 1_000_000, price: Double($0.priceMicros) / 1_000_000) })
                .frame(height: 180)
        }
        let byOrg = Dictionary(grouping: u.rows, by: \.org)
        ForEach(byOrg.keys.sorted(), id: \.self) { org in
            let rows = byOrg[org] ?? []
            VStack(alignment: .leading, spacing: 8) {
                SectionHead(org, aside: ntdMicros(rows.reduce(0) { $0 + $1.priceMicros }), role: .h4)
                RuledList {
                    ForEach(rows) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(serviceName(r.service, model: r.model))
                                    .textRole(.small)
                                    .foregroundStyle(Theme.ink)
                                Text("\(r.site)・\(r.calls.formatted()) 次\(r.billable ? "" : "・不計費")")
                                    .textRole(.xs)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(ntdMicros(r.priceMicros))
                                    .font(.brand(14, .medium).monospacedDigit())
                                    .foregroundStyle(Theme.ink)
                                Text("成本 \(ntdMicros(r.costMicros))")
                                    .textRole(.xs)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        if u.rows.isEmpty {
            EmptyState(title: "這個月還沒有用量")
        }
    }

    @ViewBuilder
    private func aiSection(_ j: JSONValue) -> some View {
        let rows = j["rows"]?.array ?? []
        let cost = rows.reduce(0) { $0 + ($1["costMicros"]?.int ?? 0) }
        let price = rows.reduce(0) { $0 + ($1["priceMicros"]?.int ?? 0) }
        let input = rows.reduce(0) { $0 + ($1["input"]?.int ?? 0) }
        let output = rows.reduce(0) { $0 + ($1["output"]?.int ?? 0) }
        StatGrid(columns: 2) {
            Stat(value: Double(cost) / 1_000_000, label: "成本", format: { ntdMicros(Int($0 * 1_000_000)) })
            Stat(value: Double(price) / 1_000_000, label: "收費", format: { ntdMicros(Int($0 * 1_000_000)) })
            Stat(value: Double(input), label: "輸入 token")
            Stat(value: Double(output), label: "輸出 token")
        }
        if rows.isEmpty {
            EmptyState(title: "這個月還沒有 AI 用量")
        } else {
            RuledList {
                ForEach(rows.indices, id: \.self) { i in
                    let r = rows[i]
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r["model"]?.string ?? r["service"]?.string ?? "")
                                .textRole(.small)
                                .foregroundStyle(Theme.ink)
                            Text([r["site"]?.string, featureName(r["feature"]?.string), "\(r["calls"]?.int ?? 0) 次"].compactMap { $0 }.joined(separator: "・"))
                                .textRole(.xs)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(ntdMicros(r["priceMicros"]?.int ?? 0))
                                .font(.brand(14, .medium).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                            Text("\(tokens(r["input"]?.int ?? 0)) → \(tokens(r["output"]?.int ?? 0))")
                                .textRole(.xs)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private func featureName(_ f: String?) -> String? {
        switch f {
        case nil, "": nil
        case "assistant": "AI 客服"
        case "copilot": "Xena AI"
        case "jev": "Jev"
        case "triage": "Jev 分類"
        case "reply-suggest": "回覆建議"
        case "reply-draft": "擬回覆"
        case "tts": "語音"
        case "stt": "語音轉文字"
        default: f
        }
    }

    private func serviceName(_ s: String, model: String?) -> String {
        if let model, s.hasPrefix("llm.") { return model }
        switch s {
        case "email": return "Email"
        case "sms": return "簡訊"
        case "jev": return "Jev"
        case "storage": return "檔案儲存"
        case "search": return "Google 搜尋成效"
        case "payment": return "金流"
        case "logistics": return "物流查詢"
        case "line": return "LINE"
        default: return s
        }
    }

    private func refresh() async {
        error = nil
        do {
            let q = [URLQueryItem(name: "period", value: period)]
            usage = UsageReport(try await model.api.admin("platform/usage", query: q))
            ai = try await model.api.admin("platform/ai-usage", query: q)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 每天的成本與收費（兩根並排的柱子）
private struct UsageChart: View {
    struct Point: Identifiable {
        var id: String { day }
        let day: String
        let cost: Double
        let price: Double
        /// 2026-10-07 → 7
        var label: String { String(Int(day.suffix(2)) ?? 0) }
    }

    let points: [Point]

    var body: some View {
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("日", p.label), y: .value("金額", p.cost))
                    .foregroundStyle(by: .value("種類", "成本"))
                    .position(by: .value("種類", "成本"))
                BarMark(x: .value("日", p.label), y: .value("金額", p.price))
                    .foregroundStyle(by: .value("種類", "收費"))
                    .position(by: .value("種類", "收費"))
            }
        }
        .chartForegroundStyleScale(["成本": Theme.ink.opacity(0.3), "收費": Theme.accent])
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks { value in
                if let s = value.as(String.self), let n = Int(s), n == 1 || n % 5 == 0 {
                    AxisValueLabel()
                }
            }
        }
    }
}

// MARK: - 帳單

/// 每個客戶這個月的帳單（console 的 /admin/platform/billing）：草稿每次打開重算；開立、標成已付款、作廢
struct BillingView: View {
    @Environment(AppModel.self) private var model
    @State private var period = PeriodPicker.current
    @State private var load = AdminLoad<[OrgStatement]>()
    @State private var opened: OrgStatement?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader("帳單", eyebrow: "平台管理", subtitle: "草稿每次打開都照最新的用量重算；開立之後就固定了。")
                    HStack {
                        PeriodPicker(period: $period)
                        Spacer()
                    }
                }
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if let list = load.value {
                    let total = list.reduce(0) { $0 + $1.totalMicros }
                    StatGrid(columns: 2) {
                        Stat(value: Double(total) / 1_000_000, label: "這個月合計", format: { ntdMicros(Int($0 * 1_000_000)) })
                        Stat(value: Double(list.filter { $0.status == "paid" }.count), label: "已付款", note: "共 \(list.count) 位客戶")
                    }
                    RuledList {
                        ForEach(list) { s in
                            Button { opened = s } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(s.org).textRole(.body).foregroundStyle(Theme.ink)
                                        Text("\(s.lines.count) 項").textRole(.xs).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(ntdMicros(s.totalMicros))
                                            .font(.brand(16, .medium).monospacedDigit())
                                            .foregroundStyle(Theme.ink)
                                        StatusBadge(s.statusLabel, tone: s.tone)
                                    }
                                }
                                .padding(.vertical, 12)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.row)
                        }
                    }
                } else if load.loading {
                    SkeletonRows(rows: 4)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await refresh() }.value }
        .brandPage()
        .pageTitle("帳單")
        .task(id: period) { await refresh() }
        .sheet(item: $opened) { s in
            StatementSheet(statement: s, period: period) { await refresh() }
        }
    }

    private func refresh() async {
        await load.run {
            (try await model.api.admin("platform/billing", query: [URLQueryItem(name: "period", value: period)])["statements"]?.array ?? []).map(OrgStatement.init)
        }
    }
}

private struct StatementSheet: View {
    let statement: OrgStatement
    let period: String
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adjustment = ""
    @State private var note = ""
    @State private var working = false

    private var canManage: Bool { model.can("platform.manage") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(PeriodPicker.label(period))
                        HStack(alignment: .firstTextBaseline) {
                            Headline(statement.org, role: .h2)
                            Spacer()
                            StatusBadge(statement.statusLabel, tone: statement.tone)
                        }
                    }
                    RuledList {
                        ForEach(statement.lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(line.label).textRole(.small).foregroundStyle(Theme.ink)
                                    Text([line.site == "—" ? nil : line.site, line.quantity != 0 ? "\(line.quantity.formatted()) \(line.unit)" : nil].compactMap { $0 }.joined(separator: "・"))
                                        .textRole(.xs).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 8)
                                Text(ntdMicros(line.amountMicros))
                                    .font(.brand(14, .medium).monospacedDigit())
                                    .foregroundStyle(line.amountMicros < 0 ? Theme.successFG : Theme.ink)
                            }
                            .padding(.vertical, 9)
                        }
                        totalRow("小計", statement.subtotalMicros)
                        if statement.adjustmentMicros != 0 { totalRow("調整", statement.adjustmentMicros) }
                        totalRow("合計", statement.totalMicros, strong: true)
                    }
                    if canManage && statement.status == "draft" {
                        AdminTextField(label: "調整（元，可以是負的）", text: $adjustment, placeholder: "0", hint: "折讓、補收", keyboard: .numbersAndPunctuation)
                        AdminTextField(label: "備註", text: $note, placeholder: "客戶看得到", multiline: true)
                    } else if let note = statement.note, !note.isEmpty {
                        Text("備註：\(note)").textRole(.small).foregroundStyle(Theme.ink2)
                    }
                    if canManage { actions }
                }
                .padding(24)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            adjustment = statement.adjustmentMicros == 0 ? "" : String(Int((Double(statement.adjustmentMicros) / 1_000_000).rounded()))
            note = statement.note ?? ""
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            switch statement.status {
            case "draft":
                Button("開立帳單") { Task { await act("issue", "開立了") } }
                    .buttonStyle(.brand(.accent, size: .lg, fullWidth: true))
                Button("存草稿") { Task { await act("save", "存好了") } }
                    .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
            case "issued":
                Button("標成已付款") { Task { await act("paid", "標成已付款") } }
                    .buttonStyle(.brand(.accent, size: .lg, fullWidth: true))
                HStack(spacing: 10) {
                    Button("改回草稿") { Task { await act("reopen", "改回草稿了") } }
                        .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
                    Button("作廢") { Task { await act("void", "作廢了") } }
                        .buttonStyle(.brand(.quiet, size: .md, fullWidth: true))
                }
            default:
                Button("改回草稿") { Task { await act("reopen", "改回草稿了") } }
                    .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
            }
        }
        .disabled(working)
    }

    private func totalRow(_ label: String, _ micros: Int, strong: Bool = false) -> some View {
        HStack {
            Text(label).textRole(strong ? .body : .small).foregroundStyle(strong ? Theme.ink : Theme.muted)
            Spacer()
            Text(ntdMicros(micros))
                .font(.brand(strong ? 18 : 14, strong ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 9)
    }

    private func act(_ action: String, _ done: String) async {
        if action == "void" || action == "paid" {
            guard await model.lock.verify(action == "void" ? "作廢帳單" : "標成已付款") else { return }
        }
        working = true
        defer { working = false }
        let ok = await model.adminRun(done) {
            var body: [String: JSONValue] = ["orgId": .string(statement.orgID), "period": .string(period), "action": .string(action)]
            if statement.status == "draft" {
                body["adjustmentNtd"] = .number(Double(adjustment.trimmingCharacters(in: .whitespaces)) ?? 0)
                body["note"] = .string(note)
            }
            _ = try await model.api.admin("platform/billing", method: "POST", body: .object(body))
        }
        if ok {
            await onDone()
            dismiss()
        }
    }
}

// MARK: - 方案

/// 客戶訂的方案與加購（console 的 /admin/platform/plans）。方案本身（價錢、內容）在網頁上編
struct PlansView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<PlanCatalog>()
    @State private var editing: PlanCatalog.Org?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                PageHeader("方案", eyebrow: "平台管理", subtitle: "每個客戶訂的方案與加購。方案的價錢與內容在網頁版的 console 編輯。")
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if let c = load.value {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHead("客戶", role: .h3)
                        RuledList {
                            ForEach(c.orgs) { org in
                                Button { if model.can("platform.manage") { editing = org } } label: { orgRow(org, c) }
                                    .buttonStyle(.row)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHead("方案", role: .h3)
                        ForEach(c.plans) { p in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(p.name).textRole(.h4).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text("NT$\(Int(p.price).formatted()) / 月")
                                        .font(.brand(14, .medium).monospacedDigit())
                                        .foregroundStyle(Theme.ink)
                                }
                                if !p.tagline.isEmpty {
                                    Text(p.tagline).textRole(.small).foregroundStyle(Theme.ink2)
                                }
                                ForEach(p.lines, id: \.self) { line in
                                    Text("・\(line)").textRole(.xs).foregroundStyle(Theme.muted)
                                }
                            }
                            .panel(padding: 16)
                        }
                    }
                    if !c.addons.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHead("加購", role: .h3)
                            RuledList {
                                ForEach(c.addons) { a in
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(a.name).textRole(.small).foregroundStyle(Theme.ink)
                                            Text(a.description).textRole(.xs).foregroundStyle(Theme.muted).lineLimit(2)
                                        }
                                        Spacer(minLength: 8)
                                        Text("NT$\(Int(a.price).formatted())")
                                            .font(.brand(14, .medium).monospacedDigit())
                                            .foregroundStyle(Theme.ink)
                                    }
                                    .padding(.vertical, 10)
                                }
                            }
                        }
                    }
                } else if load.loading {
                    SkeletonRows(rows: 5)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await refresh() }.value }
        .brandPage()
        .pageTitle("方案")
        .task { if load.value == nil { await refresh() } }
        .sheet(item: $editing) { org in
            if let c = load.value {
                SubscriptionSheet(catalog: c, org: org) { load.value = $0 }
            }
        }
    }

    @ViewBuilder
    private func orgRow(_ org: PlanCatalog.Org, _ c: PlanCatalog) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(org.name).textRole(.body).foregroundStyle(Theme.ink)
                Text(([c.plan(org.planID)?.name ?? "還沒有方案"] + addonNames(org, c)).joined(separator: "・"))
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let fee = org.monthlyFeeNtd {
                Text("NT$\(Int(fee).formatted())")
                    .font(.brand(14, .medium).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    /// 「多 3 個座位 ×2」
    private func addonNames(_ org: PlanCatalog.Org, _ c: PlanCatalog) -> [String] {
        var names: [String] = []
        for addon in c.addons {
            let qty = org.addons[addon.id] ?? 0
            if qty > 0 { names.append(qty > 1 ? "\(addon.name) ×\(qty)" : addon.name) }
        }
        return names
    }

    private func refresh() async {
        await load.run { PlanCatalog(try await model.api.admin("platform/plans")) }
    }
}

private struct SubscriptionSheet: View {
    let catalog: PlanCatalog
    let org: PlanCatalog.Org
    var onSaved: (PlanCatalog) -> Void
    @Environment(AppModel.self) private var model
    @State private var planID = ""
    @State private var addons: [String: Int] = [:]
    @State private var note = ""

    var body: some View {
        AdminSheet(title: org.name, subtitle: "改了馬上生效：網站的 Xena 額度、座位、內含的簡訊與 Email 都照新方案。", action: "儲存") {
            if planID.isEmpty && org.planID != nil {
                guard await model.lock.verify("拿掉「\(org.name)」的方案") else { return false }
            }
            return await model.adminRun("\(org.name)的方案存好了") {
                let list: [JSONValue] = addons.filter { $0.value > 0 }.map { ["id": .string($0.key), "qty": .number(Double($0.value))] }
                let r = try await model.api.admin("platform/plans", method: "PATCH", body: [
                    "orgId": .string(org.id), "planId": planID.isEmpty ? .null : .string(planID), "addons": .array(list), "note": .string(note),
                ])
                onSaved(PlanCatalog(r))
            }
        } content: {
            AdminPicker(label: "方案", selection: $planID, options: [("", "沒有方案")] + catalog.plans.map { ($0.id, "\($0.name)（NT$\(Int($0.price).formatted())）") })
            if !catalog.addons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("加購").textRole(.small).foregroundStyle(Theme.muted)
                    ForEach(catalog.addons) { a in
                        Stepper(value: Binding(get: { addons[a.id] ?? 0 }, set: { addons[a.id] = $0 }), in: 0...99) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.name)\((addons[a.id] ?? 0) > 0 ? " ×\(addons[a.id] ?? 0)" : "")").textRole(.body).foregroundStyle(Theme.ink)
                                Text("NT$\(Int(a.price).formatted())").textRole(.xs).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            AdminTextField(label: "備註", text: $note, placeholder: "只有 StudioX 看得到", multiline: true)
        }
        .presentationDetents([.large])
        .onAppear {
            planID = org.planID ?? ""
            addons = org.addons
            note = org.note ?? ""
        }
    }
}

// MARK: - 價目

/// 價目（console 的 /admin/platform/pricing）：匯率、AI 加成、Email 與簡訊的成本與售價、個別客戶的特價
struct PricingView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<Pricing>()
    @State private var editingGlobal = false
    @State private var editingOrg: (id: String, name: String)?

    private var canManage: Bool { model.can("platform.manage") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                PageHeader("價目", eyebrow: "平台管理", subtitle: "改了之後從現在起的用量照新價目算；已經開立的帳單不變。") {
                    if canManage && load.value != nil {
                        Button("編輯") { editingGlobal = true }
                            .buttonStyle(.brand(.ghost, size: .sm))
                    }
                }
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if let p = load.value {
                    RuledList {
                        InfoRow(label: "美元匯率", value: "1 USD = \(p.fxUsdTwd.formatted()) TWD")
                        InfoRow(label: "AI 加成", value: "成本 × \(p.llmMarkup.formatted())")
                        InfoRow(label: "Email", value: "成本 NT$\(p.emailCost.formatted())・收 NT$\(p.emailPrice.formatted()) / 封")
                        InfoRow(label: "簡訊", value: "成本 NT$\(p.smsCost.formatted())・收 NT$\(p.smsPrice.formatted()) / 則")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHead("個別客戶的價目", role: .h3)
                        Text("沒設定的照上面的價目。")
                            .textRole(.small)
                            .foregroundStyle(Theme.muted)
                        RuledList {
                            ForEach(p.orgs, id: \.id) { org in
                                Button { if canManage { editingOrg = org } } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(org.name).textRole(.body).foregroundStyle(Theme.ink)
                                        Spacer(minLength: 8)
                                        Text(overrideText(p.overrides[org.id]))
                                            .textRole(.xs)
                                            .foregroundStyle(p.overrides[org.id] == nil ? Theme.faint : Theme.ink2)
                                            .multilineTextAlignment(.trailing)
                                    }
                                    .padding(.vertical, 12)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.row)
                            }
                        }
                    }
                } else if load.loading {
                    SkeletonRows(rows: 4)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await refresh() }.value }
        .brandPage()
        .pageTitle("價目")
        .task { if load.value == nil { await refresh() } }
        .sheet(isPresented: $editingGlobal) {
            if let p = load.value {
                PricingSheet(pricing: p) { load.value = $0 }
            }
        }
        .sheet(isPresented: Binding(get: { editingOrg != nil }, set: { if !$0 { editingOrg = nil } })) {
            if let org = editingOrg, let p = load.value {
                OrgPricingSheet(orgID: org.id, name: org.name, current: p.overrides[org.id]) { load.value = $0 }
            }
        }
    }

    private func overrideText(_ o: Pricing.OrgOverride?) -> String {
        guard let o else { return "照一般價目" }
        return [
            o.monthlyFee.map { "月費 NT$\(Int($0).formatted())" },
            o.llmMarkup.map { "AI ×\($0.formatted())" },
            o.emailPrice.map { "Email NT$\($0.formatted())" },
            o.smsPrice.map { "簡訊 NT$\($0.formatted())" },
        ].compactMap { $0 }.joined(separator: "・")
    }

    private func refresh() async {
        await load.run { Pricing(try await model.api.admin("platform/pricing")) }
    }
}

private func numberText(_ v: Double?) -> String { v.map { $0.formatted(.number.grouping(.never)) } ?? "" }
private func number(_ s: String) -> JSONValue {
    guard let n = Double(s.trimmingCharacters(in: .whitespaces)) else { return .null }
    return .number(n)
}

private struct PricingSheet: View {
    let pricing: Pricing
    var onSaved: (Pricing) -> Void
    @Environment(AppModel.self) private var model
    @State private var fx = ""
    @State private var markup = ""
    @State private var emailCost = ""
    @State private var emailPrice = ""
    @State private var smsCost = ""
    @State private var smsPrice = ""

    var body: some View {
        AdminSheet(title: "價目", subtitle: "從現在起的用量照新價目算。", action: "儲存") {
            await model.adminRun("價目存好了") {
                let r = try await model.api.admin("platform/pricing", method: "PATCH", body: [
                    "fxUsdTwd": number(fx), "llmMarkup": number(markup),
                    "email": ["cost": number(emailCost), "price": number(emailPrice)],
                    "sms": ["cost": number(smsCost), "price": number(smsPrice)],
                ])
                onSaved(Pricing(r))
            }
        } content: {
            AdminTextField(label: "美元匯率（1 USD ＝ ? TWD）", text: $fx, keyboard: .decimalPad)
            AdminTextField(label: "AI 加成（成本的幾倍）", text: $markup, hint: "例如 1.3＝成本加三成", keyboard: .decimalPad)
            AdminTextField(label: "Email 成本（元／封）", text: $emailCost, keyboard: .decimalPad)
            AdminTextField(label: "Email 售價（元／封）", text: $emailPrice, keyboard: .decimalPad)
            AdminTextField(label: "簡訊成本（元／則）", text: $smsCost, keyboard: .decimalPad)
            AdminTextField(label: "簡訊售價（元／則）", text: $smsPrice, keyboard: .decimalPad)
        }
        .presentationDetents([.large])
        .onAppear {
            fx = numberText(pricing.fxUsdTwd)
            markup = numberText(pricing.llmMarkup)
            emailCost = numberText(pricing.emailCost)
            emailPrice = numberText(pricing.emailPrice)
            smsCost = numberText(pricing.smsCost)
            smsPrice = numberText(pricing.smsPrice)
        }
    }
}

private struct OrgPricingSheet: View {
    let orgID: String
    let name: String
    let current: Pricing.OrgOverride?
    var onSaved: (Pricing) -> Void
    @Environment(AppModel.self) private var model
    @State private var fee = ""
    @State private var markup = ""
    @State private var emailPrice = ""
    @State private var smsPrice = ""

    var body: some View {
        AdminSheet(title: name, subtitle: "這個客戶的特價；留空＝照一般價目。全部留空就是取消特價。", action: "儲存") {
            await model.adminRun("\(name)的價目存好了") {
                var org: [String: JSONValue] = ["id": .string(orgID)]
                for (k, v) in [("monthlyFee", fee), ("llmMarkup", markup), ("emailPrice", emailPrice), ("smsPrice", smsPrice)] {
                    let n = number(v)
                    if !n.isNull { org[k] = n }
                }
                let r = try await model.api.admin("platform/pricing", method: "PATCH", body: ["org": .object(org)])
                onSaved(Pricing(r))
            }
        } content: {
            AdminTextField(label: "月費（元）", text: $fee, placeholder: "照方案", keyboard: .decimalPad)
            AdminTextField(label: "AI 加成（倍）", text: $markup, placeholder: "照一般價目", keyboard: .decimalPad)
            AdminTextField(label: "Email 售價（元／封）", text: $emailPrice, placeholder: "照一般價目", keyboard: .decimalPad)
            AdminTextField(label: "簡訊售價（元／則）", text: $smsPrice, placeholder: "照一般價目", keyboard: .decimalPad)
        }
        .presentationDetents([.large])
        .onAppear {
            fee = numberText(current?.monthlyFee)
            markup = numberText(current?.llmMarkup)
            emailPrice = numberText(current?.emailPrice)
            smsPrice = numberText(current?.smsPrice)
        }
    }
}
