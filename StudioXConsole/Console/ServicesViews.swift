import SwiftUI

// MARK: - 申請

/// 客戶申請的方案、加購、服務（console 的 /admin/platform/requests）：負責人開通或說明為什麼不通過
struct RequestsView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<[PlatformRequest]>()
    @State private var filter = "pending"
    @State private var answering: (PlatformRequest, approve: Bool)?

    private var shown: [PlatformRequest] {
        let all = load.value ?? []
        return filter == "pending" ? all.filter(\.pending) : all
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader("申請", eyebrow: "平台管理", subtitle: "客戶在網站後台「方案」申請的方案、加購與服務。開通之後馬上生效。")
                    FilterBar(items: ["pending", "all"], selection: $filter, title: { $0 == "pending" ? "等你處理" : "全部" })
                }
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if load.value != nil {
                    if shown.isEmpty {
                        EmptyState(title: filter == "pending" ? "沒有等你處理的申請" : "還沒有申請")
                    } else {
                        RuledList {
                            ForEach(shown) { r in row(r) }
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
        .pageTitle("申請")
        .task { if load.value == nil { await refresh() } }
        .sheet(isPresented: Binding(get: { answering != nil }, set: { if !$0 { answering = nil } })) {
            if let a = answering {
                AnswerRequestSheet(request: a.0, approve: a.approve) { await refresh() }
            }
        }
    }

    @ViewBuilder
    private func row(_ r: PlatformRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.label)
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                StatusBadge(r.statusLabel, tone: r.tone)
            }
            Text([r.site, r.org, r.requestedBy, r.createdAt?.relativeText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "・"))
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
            if let note = r.note, !note.isEmpty {
                Text("「\(note)」")
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reply = r.reply, !reply.isEmpty {
                Text("回覆：\(reply)")
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if r.pending && model.can("platform.manage") {
                HStack(spacing: 10) {
                    Button("開通") { answering = (r, true) }
                        .buttonStyle(.brand(.accent, size: .sm))
                    Button("不通過") { answering = (r, false) }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 14)
    }

    private func refresh() async {
        await load.run { (try await model.api.admin("platform/requests")["requests"]?.array ?? []).map(PlatformRequest.init) }
    }
}

private struct AnswerRequestSheet: View {
    let request: PlatformRequest
    let approve: Bool
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var reply = ""

    var body: some View {
        AdminSheet(
            title: approve ? "開通「\(request.label)」" : "不通過「\(request.label)」",
            subtitle: approve ? "\(request.site)（\(request.org)）。方案、加購會馬上套用到客戶的訂閱。" : "說明原因，客戶在網站後台的「方案」看得到。",
            action: approve ? "開通" : "不通過",
            danger: !approve,
            disabled: !approve && reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ) {
            await model.adminRun(approve ? "開通了" : "已回覆客戶") {
                var body: [String: JSONValue] = ["id": .string(request.id), "action": .string(approve ? "approve" : "reject")]
                let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { body["reply"] = .string(text) }
                _ = try await model.api.admin("platform/requests", method: "PATCH", body: .object(body))
                await onDone()
            }
        } content: {
            AdminTextField(label: approve ? "給客戶的話（選填）" : "原因", text: $reply, placeholder: approve ? "例如：已經開通，有問題隨時找我們" : "例如：要先有 AI 客服才能開 LINE", required: !approve, multiline: true)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 網站服務

/// 每個網站開了哪些服務（console 的 /admin/platform/services）：點進去一個網站調整
struct ServicesMatrixView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<ServiceMatrix>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader("網站服務", eyebrow: "平台管理", subtitle: "每個網站用哪把金鑰、開了哪些服務、要不要計費。點一個網站調整。")
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if let m = load.value {
                    RuledList {
                        ForEach(m.sites) { site in
                            NavigationLink(value: Route.console(.siteServices(site.id))) {
                                row(site, labels: m.services)
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
        .pageTitle("網站服務")
        .task { if load.value == nil { await refresh() } }
    }

    @ViewBuilder
    private func row(_ site: ServiceMatrix.Row, labels: [(id: String, label: String)]) -> some View {
        let on = labels.filter { site.services[$0.id]?.enabled == true }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(site.name)
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                if !site.active { StatusBadge("停用中", tone: .neutral) }
                Spacer()
                HeroIcon("chevron-right", size: 13).foregroundStyle(Theme.faint)
            }
            Text(site.org)
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
            if on.isEmpty {
                Text("還沒開任何服務")
                    .textRole(.xs)
                    .foregroundStyle(Theme.faint)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(on, id: \.id) { s in
                        Chip(s.label)
                    }
                }
            }
        }
        .padding(.vertical, 13)
        .contentShape(.rect)
    }

    private func refresh() async {
        await load.run { ServiceMatrix(try await model.api.admin("platform/services")) }
    }
}

/// 一個網站的服務：開關、金鑰、計費、上限、設定；LINE 可以一鍵接上；AI 客服另外一張
struct SiteServicesView: View {
    let siteID: String
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var load = AdminLoad<(name: String, org: String, services: [SiteService])>()
    @State private var editing: SiteService?
    @State private var assistant: JSONValue?
    @State private var editingAssistant = false
    @State private var lineResult: LineConnectResult?
    @State private var connectingLine = false

    private var canManage: Bool { model.can("platform.manage") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let v = load.value {
                    PageHeader(v.name, eyebrow: v.org, subtitle: canManage ? "點一項服務調整。改了之後網站一分鐘內拿到新設定。" : "只有負責人能改服務。")
                    RuledList {
                        ForEach(v.services) { s in
                            Button { if canManage { editing = s } } label: { serviceRow(s) }
                                .buttonStyle(.row)
                                .disabled(!canManage)
                        }
                    }
                    assistantSection
                    if let line = v.services.first(where: { $0.id == "line" }), line.configured, canManage {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHead("LINE 官方帳號", role: .h3) {
                                Button(connectingLine ? "接上中…" : "自動接上 LINE") { Task { await connectLine() } }
                                    .buttonStyle(.brand(.ghost, size: .sm))
                                    .disabled(connectingLine)
                            }
                            Text("設好 Webhook、讓網站拿新設定、請 LINE 打一次測試、讀回官方帳號。按幾次都可以（檢查用）。")
                                .textRole(.small)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                } else if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                } else {
                    SkeletonRows(rows: 6)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await refresh() }.value }
        .brandPage()
        .pageTitle(load.value?.name ?? "網站服務")
        .task { if load.value == nil { await refresh() } }
        .sheet(item: $editing) { s in
            ServiceEditSheet(siteID: siteID, service: s) { await refresh() }
        }
        .sheet(isPresented: $editingAssistant) {
            if let assistant {
                AssistantSheet(siteID: siteID, data: assistant) { await refresh() }
            }
        }
        .sheet(item: Binding(get: { lineResult.map { LineResultBox(result: $0) } }, set: { lineResult = $0?.result })) { box in
            LineResultSheet(result: box.result)
        }
    }

    @ViewBuilder
    private func serviceRow(_ s: SiteService) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(s.label)
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                StatusBadge(!s.configured ? "沒有設定" : s.enabled ? "開著" : "關著", tone: !s.configured ? .neutral : s.enabled ? .active : .warning)
            }
            Text(detail(s))
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private func detail(_ s: SiteService) -> String {
        var parts = [s.providerLabel]
        if s.configured {
            parts.append(s.keyLabel.map { "金鑰：\($0)" } ?? "沒選金鑰")
            if s.metered {
                parts.append(s.billable ? "計費" : "不計費")
                if let cap = s.capNtd { parts.append("上限 NT$\(Int(cap).formatted())") }
                if let m = s.monthToDateNtd { parts.append("這個月 NT$\(Int(m.rounded()).formatted())") }
            }
        }
        return parts.joined(separator: "・")
    }

    @ViewBuilder
    private var assistantSection: some View {
        if let a = assistant {
            VStack(alignment: .leading, spacing: 10) {
                SectionHead("AI 客服（網站右下角的 Xena）", role: .h3) {
                    if canManage {
                        Button("設定") { editingAssistant = true }
                            .buttonStyle(.brand(.ghost, size: .sm))
                    }
                }
                let s = a["settings"] ?? .null
                HStack(spacing: 8) {
                    StatusBadge(a["configured"]?.bool == true ? (a["enabled"]?.bool == true ? "開著" : "關著") : "沒有設定",
                                tone: a["enabled"]?.bool == true ? .active : .neutral)
                    Text([s["provider"]?.string, s["family"]?.string ?? s["model"]?.string].compactMap { $0 }.joined(separator: " · "))
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func refresh() async {
        await load.run {
            let r = try await model.api.admin("platform/services/\(siteID)")
            return (r["site"]?["name"]?.string ?? "", r["site"]?["org"]?.string ?? "", (r["services"]?.array ?? []).map(SiteService.init))
        }
        assistant = try? await model.api.admin("platform/services/\(siteID)/assistant")
    }

    private func connectLine() async {
        connectingLine = true
        defer { connectingLine = false }
        await model.adminRun(nil) {
            lineResult = LineConnectResult(try await model.api.admin("platform/services/\(siteID)/line", method: "POST"))
        }
    }
}

private struct LineResultBox: Identifiable {
    var id: String { result.webhook + result.steps.map(\.key).joined() }
    let result: LineConnectResult
}

private struct LineResultSheet: View {
    let result: LineConnectResult
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Headline(result.ok ? "LINE 接好了" : "還有幾步要處理", role: .h2)
                    if let account = result.account {
                        Text(account).textRole(.small).foregroundStyle(Theme.ink2)
                    }
                    RuledList {
                        ForEach(result.steps) { step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                HeroIcon(step.ok == true ? "check-circle" : step.ok == false ? "x-circle" : "hand-raised", size: 16)
                                    .foregroundStyle(step.ok == true ? Theme.successFG : step.ok == false ? Theme.dangerFG : Theme.warningFG)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.label).textRole(.body).foregroundStyle(Theme.ink)
                                    if let d = step.detail {
                                        Text(d).textRole(.xs).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                    }
                                    if let url = step.linkURL {
                                        Button("\(step.linkLabel ?? "打開") ↗") { openURL(url) }
                                            .buttonStyle(.brand(.quiet, size: .sm))
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    InfoRow(label: "Webhook", value: result.webhook, mono: true, copy: true)
                }
                .padding(24)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 一項服務：開關、金鑰、計費、上限、設定欄位。密鑰欄位留空＝不變（不會把「已設定」寫回去）
private struct ServiceEditSheet: View {
    let siteID: String
    let service: SiteService
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var enabled = true
    @State private var keyID = ""
    @State private var billable = true
    @State private var cap = ""
    @State private var settings: [String: String] = [:]
    @State private var confirmRemove = false

    var body: some View {
        AdminSheet(title: service.label, subtitle: service.description.isEmpty ? service.providerLabel : service.description, action: "儲存", disabled: keyID.isEmpty && enabled) {
            await model.adminRun("\(service.label)存好了") {
                var body: [String: JSONValue] = ["service": .string(service.id), "enabled": .bool(enabled), "keyId": keyID.isEmpty ? .null : .string(keyID)]
                if service.metered {
                    body["billable"] = .bool(billable)
                    let c = Double(cap.trimmingCharacters(in: .whitespaces))
                    body["capNtd"] = c.map { JSONValue.number($0) } ?? .null
                }
                if !service.settingsFields.isEmpty {
                    var out: [String: JSONValue] = [:]
                    for f in service.settingsFields {
                        let v = (settings[f.key] ?? "").trimmingCharacters(in: .whitespaces)
                        // 密鑰：空白＝不變（伺服器的規則），不送遮起來的「已設定」
                        if f.secret && v.isEmpty { continue }
                        out[f.key] = .string(v)
                    }
                    body["settings"] = .object(out)
                }
                _ = try await model.api.admin("platform/services/\(siteID)", method: "PUT", body: .object(body))
                await onDone()
            }
        } content: {
            AdminToggle(label: "開著", isOn: $enabled, hint: "關掉之後網站就不能用這項服務（設定會留著）")
            AdminPicker(label: "金鑰（\(service.providerLabel)）", selection: $keyID,
                        options: [("", "不使用金鑰")] + service.keys.map { ($0.id, "\($0.label)\($0.own ? "（客戶自己的）" : "")\($0.disabled ? "・停用中" : "")\($0.hint.map { "・\($0)" } ?? "")") },
                        hint: service.keys.isEmpty ? "金鑰庫還沒有這種金鑰，先到「金鑰庫」新增" : nil)
            if service.metered {
                AdminToggle(label: "向客戶計費", isOn: $billable, hint: "關掉＝StudioX 吸收這項費用（客戶自己的金鑰不計費）")
                AdminTextField(label: "每月上限（元，選填）", text: $cap, placeholder: "不限", hint: "到上限就暫停這項服務，避免帳單爆掉", keyboard: .numberPad)
            }
            ForEach(service.settingsFields) { f in
                settingField(f)
            }
            if service.configured {
                Button("移除這項服務", role: .destructive) { confirmRemove = true }
                    .buttonStyle(.brand(.quiet, size: .sm))
                    .confirmationDialog("移除「\(service.label)」？", isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("移除", role: .destructive) {
                            Task {
                                await model.adminRun("移除了\(service.label)") {
                                    _ = try await model.api.admin("platform/services/\(siteID)", method: "DELETE", query: [URLQueryItem(name: "service", value: service.id)])
                                    await onDone()
                                }
                            }
                        }
                    } message: {
                        Text("網站就不能再用這項服務，設定也會清掉。")
                    }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            enabled = service.configured ? service.enabled : true
            keyID = service.keyID ?? (service.keys.first { !$0.disabled }?.id ?? "")
            billable = service.billable
            cap = service.capNtd.map { String(Int($0)) } ?? ""
            // 密鑰欄位一律從空白開始（伺服器給的是遮起來的「••••（已設定）」）
            var s: [String: String] = [:]
            for f in service.settingsFields { s[f.key] = f.secret ? "" : (service.settings[f.key] ?? "") }
            settings = s
        }
    }

    @ViewBuilder
    private func settingField(_ f: PlatformField) -> some View {
        let binding = Binding(get: { settings[f.key] ?? "" }, set: { settings[f.key] = $0 })
        if !f.options.isEmpty {
            AdminPicker(label: f.label, selection: binding, options: f.options.map { ($0.value, $0.label) }, hint: f.hint)
        } else {
            let isSet = f.secret && !(service.settings[f.key] ?? "").isEmpty
            AdminTextField(label: f.label + (f.optional ? "（選填）" : ""), text: binding,
                           placeholder: isSet ? "已設定（留空＝不變；填 - 清掉）" : (f.placeholder ?? ""),
                           hint: f.hint, secure: f.secret, keyboard: f.secret ? .asciiCapable : .default)
        }
    }
}

/// AI 客服：開關、用哪家的模型、給 Xena 的說明、紀錄保留
private struct AssistantSheet: View {
    let siteID: String
    let data: JSONValue
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var enabled = false
    @State private var provider = ""
    @State private var family = ""
    @State private var instructions = ""
    @State private var fastReplies = true
    @State private var followUps = true
    @State private var logConversations = true
    @State private var retentionDays = ""
    @State private var rateLimit = ""

    private var providers: [JSONValue] { data["providers"]?.array ?? [] }
    private var families: [(value: String, label: String)] {
        let p = providers.first { $0["id"]?.string == provider } ?? .null
        return (p["families"]?.array ?? []).map { ($0["family"]?.string ?? "", "\($0["family"]?.string ?? "")（\($0["latest"]?.string ?? "")）") }
    }

    var body: some View {
        AdminSheet(title: "AI 客服", subtitle: "網站右下角的 Xena。用 StudioX 的金鑰，用量照網站服務計費。", action: "儲存") {
            await model.adminRun("AI 客服存好了") {
                var settings: [String: JSONValue] = [
                    "instructions": .string(instructions),
                    "fastReplies": .bool(fastReplies), "followUps": .bool(followUps), "logConversations": .bool(logConversations),
                ]
                if !provider.isEmpty { settings["provider"] = .string(provider) }
                if !family.isEmpty { settings["family"] = .string(family) }
                if let d = Int(retentionDays) { settings["retentionDays"] = .number(Double(d)) }
                if let r = Int(rateLimit) { settings["rateLimit"] = .number(Double(r)) }
                _ = try await model.api.admin("platform/services/\(siteID)/assistant", method: "PUT", body: ["enabled": .bool(enabled), "settings": .object(settings)])
                await onDone()
            }
        } content: {
            AdminToggle(label: "開著", isOn: $enabled, hint: "關掉之後網站右下角不會出現 Xena")
            AdminPicker(label: "模型供應商", selection: $provider,
                        options: providers.map { ($0["id"]?.string ?? "", "\($0["name"]?.string ?? "")\($0["provisioned"]?.bool == false ? "（沒有金鑰）" : "")") })
            if !families.isEmpty {
                AdminPicker(label: "模型", selection: $family, options: families, hint: "永遠用這一系列最新的版本")
            }
            AdminTextField(label: "給 Xena 的說明", text: $instructions, placeholder: "語氣、要強調的事、不能說的事…", hint: "最多 4000 字", multiline: true)
            AdminToggle(label: "快速回答", isOn: $fastReplies, hint: "會思考的模型盡量少想一點：回答更快、更省")
            AdminToggle(label: "建議問題", isOn: $followUps, hint: "每次回答後附上 2–3 個建議問題，訪客點一下就能接著問")
            AdminToggle(label: "記錄對話", isOn: $logConversations, hint: "收件匣看得到；關掉就只有當下的對話")
            AdminTextField(label: "對話保留天數", text: $retentionDays, keyboard: .numberPad)
            AdminTextField(label: "每個 IP 每 10 分鐘最多幾則", text: $rateLimit, hint: "擋濫用；一般訪客不會碰到", keyboard: .numberPad)
        }
        .presentationDetents([.large])
        .onAppear {
            let s = data["settings"] ?? .null
            enabled = data["enabled"]?.bool ?? false
            provider = s["provider"]?.string ?? ""
            family = s["family"]?.string ?? ""
            instructions = s["instructions"]?.string ?? ""
            fastReplies = s["fastReplies"]?.bool ?? true
            followUps = s["followUps"]?.bool ?? true
            logConversations = s["logConversations"]?.bool ?? true
            retentionDays = s["retentionDays"]?.int.map(String.init) ?? ""
            rateLimit = s["rateLimit"]?.int.map(String.init) ?? ""
        }
    }
}
