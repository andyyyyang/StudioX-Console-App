import SwiftUI

// MARK: - 後台人員

/// console 自己的後台人員（/admin/team，只有負責人）：誰能進 console、是什麼職能。
/// 新的人用邀請連結加入（綁定 Email、7 天內有效、只能用一次），不用再交接密碼
struct TeamView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<(managedBy: String?, members: [TeamMember], invites: [StaffInvite])>()
    @State private var adding = false
    @State private var editing: TeamMember?
    @State private var invite: InviteResult?
    @State private var working: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageHeader("後台人員", eyebrow: "平台管理", subtitle: "能進 StudioX Console 的人。客戶網站的成員在「客戶與網站」裡管。") {
                    if load.value?.managedBy == nil && load.value != nil {
                        Button { adding = true } label: { AddIconLabel() }
                            .buttonStyle(.plain)
                            .accessibilityLabel("邀請後台人員")
                    }
                }
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if let v = load.value {
                    if let managed = v.managedBy {
                        Text("人員由 \(managed) 統一管理，這裡只能看。")
                            .textRole(.small)
                            .foregroundStyle(Theme.muted)
                    }
                    RuledList {
                        ForEach(v.members) { m in
                            Button { if v.managedBy == nil { editing = m } } label: { row(m) }
                                .buttonStyle(.row)
                        }
                    }
                    if !v.invites.isEmpty {
                        invitesSection(v.invites, canManage: v.managedBy == nil)
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
        .pageTitle("後台人員")
        .task { if load.value == nil { await refresh() } }
        .sheet(isPresented: $adding) {
            InviteStaffSheet(onInvited: { result in
                invite = result
                Task { await refresh() }
            })
        }
        .sheet(item: $invite) { InviteResultSheet(result: $0) }
        .sheet(item: $editing) { m in
            TeamMemberSheet(member: m, isSelf: m.id == model.me?.id) { await refresh() }
        }
    }

    private func row(_ m: TeamMember) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(m.name ?? m.email).textRole(.body).foregroundStyle(Theme.ink)
                    if m.id == model.me?.id { StatusBadge("你", tone: .info) }
                }
                Text([m.name == nil ? nil : m.email, m.hasPassword ? "有密碼" : "Apple 登入"].compactMap { $0 }.joined(separator: "・"))
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text(ConsoleLevel.label(m.level))
                .textRole(.small)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    /// 還沒接受的邀請：重寄、撤銷（撤銷了可以再邀請，不用驗證）
    private func invitesSection(_ invites: [StaffInvite], canManage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("還沒接受的邀請", role: .h3)
            RuledList {
                ForEach(invites) { inv in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(inv.email).textRole(.body).foregroundStyle(Theme.ink)
                            Text([ConsoleLevel.label(inv.level), inv.expiresAt.map { "\($0.shortText) 到期" }].compactMap { $0 }.joined(separator: "・"))
                                .textRole(.xs)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        if canManage {
                            Button("重寄") { Task { await resend(inv) } }
                                .buttonStyle(.brand(.ghost, size: .sm))
                            Button("撤銷") { Task { await revoke(inv) } }
                                .buttonStyle(.brand(.quiet, size: .sm))
                        }
                    }
                    .padding(.vertical, 11)
                    .disabled(working == inv.id)
                }
            }
        }
    }

    private func resend(_ inv: StaffInvite) async {
        working = inv.id
        defer { working = nil }
        var result: InviteResult?
        await model.adminRun(nil) {
            let r = try await model.api.admin("team/invites/resend", method: "POST", body: ["inviteId": .string(inv.id)])
            result = InviteResult(url: r["url"]?.string ?? "", email: inv.email, sent: r["sent"]?.bool ?? false,
                                  sendError: r["sendError"]?.string, expiresAt: r["expiresAt"]?.date)
        }
        if let result { invite = result }
        await refresh()
    }

    private func revoke(_ inv: StaffInvite) async {
        working = inv.id
        defer { working = nil }
        await model.adminRun("撤銷了給 \(inv.email) 的邀請") {
            _ = try await model.api.admin("team/invites", method: "DELETE", body: ["inviteId": .string(inv.id)])
        }
        await refresh()
    }

    private func refresh() async {
        await load.run {
            let r = try await model.api.admin("team")
            return (r["managedBy"]?.string, (r["members"]?.array ?? []).map(TeamMember.init), (r["invites"]?.array ?? []).map(StaffInvite.init))
        }
    }
}

/// 隨機密碼（大小寫、數字，避開容易看錯的字）
nonisolated private func randomPassword(_ n: Int = 16) -> String {
    let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789")
    var rng = SystemRandomNumberGenerator()
    return String((0..<n).map { _ in chars[Int(rng.next(upperBound: UInt32(chars.count)))] })
}

/// 邀請後台人員：Email＋職能，寄邀請信（也可以自己把連結傳給他）。
/// 對方打開連結、用這個 Email 的帳號（Apple 或 Email）登入就加入，不用交接密碼
private struct InviteStaffSheet: View {
    var onInvited: (InviteResult) -> Void
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var level = "manager"
    @State private var send = true

    var body: some View {
        AdminSheet(title: "邀請後台人員", subtitle: "對方打開邀請連結、用這個 Email 的帳號登入就加入 console。連結 7 天內有效、只能用一次。", action: send ? "寄出邀請" : "產生連結", disabled: !email.contains("@")) {
            let to = email.trimmingCharacters(in: .whitespaces)
            var result: InviteResult?
            let ok = await model.adminRun(nil) {
                let r = try await model.api.admin("team/invites", method: "POST", body: ["email": .string(to), "level": .string(level), "send": .bool(send)])
                result = InviteResult(url: r["url"]?.string ?? "", email: to, sent: r["sent"]?.bool ?? false,
                                      sendError: r["sendError"]?.string, expiresAt: r["expiresAt"]?.date)
            }
            if ok, let result { onInvited(result) }
            return ok
        } content: {
            AdminTextField(label: "Email", text: $email, placeholder: "name@studiox.tw", required: true, keyboard: .emailAddress)
            AdminPicker(label: "職能", selection: $level, options: ConsoleLevel.all.map { ($0, ConsoleLevel.label($0)) }, hint: ConsoleLevel.hint(level))
            AdminToggle(label: "直接寄邀請信給他", isOn: $send, hint: "不寄的話，產生後自己把連結傳給他")
        }
        .presentationDetents([.medium, .large])
    }
}

private struct TeamMemberSheet: View {
    let member: TeamMember
    let isSelf: Bool
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var level = ""
    @State private var name = ""
    @State private var newPassword: String?
    /// 移除收不回來：確認選單＋Face ID（2 分鐘內驗證過就不再跳）
    @State private var confirmRemove = false

    var body: some View {
        // 改職能、名字、密碼都改得回來：按「儲存」就是確認
        AdminSheet(title: member.name ?? member.email, subtitle: member.email, action: "儲存") {
            await model.adminRun("存好了") {
                var body: [String: JSONValue] = [:]
                if level != member.level { body["level"] = .string(level) }
                if name != (member.name ?? "") { body["name"] = .string(name) }
                if let newPassword { body["password"] = .string(newPassword) }
                guard !body.isEmpty else { return }
                _ = try await model.api.admin("team/\(member.id)", method: "PATCH", body: .object(body))
                await onDone()
            }
        } content: {
            AdminTextField(label: "名字", text: $name)
            AdminPicker(label: "職能", selection: $level, options: ConsoleLevel.all.map { ($0, ConsoleLevel.label($0)) }, hint: isSelf ? "改自己的職能要小心：至少要留一位負責人" : ConsoleLevel.hint(level))
            VStack(alignment: .leading, spacing: 10) {
                if let newPassword {
                    InfoRow(label: "新密碼", value: newPassword, mono: true, copy: true)
                    Text("按「儲存」才會換；請用安全的方式交給他。")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                } else {
                    Button("重設密碼") { newPassword = randomPassword() }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
            }
            if !isSelf {
                Button("移除這位後台人員", role: .destructive) { confirmRemove = true }
                    .buttonStyle(.brand(.quiet, size: .sm))
                    .confirmationDialog("移除 \(member.email)？", isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("移除", role: .destructive) {
                            Task { await model.verified("移除後台人員 \(member.email)") { await remove() } }
                        }
                    } message: {
                    Text("他就不能再進 console（他管理的客戶網站另外在「客戶與網站」移出）。")
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            level = member.level
            name = member.name ?? ""
        }
    }

    /// 移除（確認過了：確認選單＋Face ID）
    private func remove() async {
        let ok = await model.adminRun("移除了 \(member.email)") {
            _ = try await model.api.admin("team/\(member.id)", method: "DELETE")
        }
        if ok {
            await onDone()
            dismiss()
        }
    }
}

// MARK: - 操作紀錄

/// 操作紀錄（/admin/audit）：誰在什麼時候改了什麼。最近 200 筆，可以照類別篩
struct AuditView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<[AuditEntry]>()
    @State private var category = "all"

    private static let categories: [(id: String, label: String, prefixes: [String])] = [
        ("all", "全部", []),
        ("console", "客戶與網站", ["console."]),
        ("platform", "平台", ["platform."]),
        ("team", "人員", ["team."]),
        ("ai", "AI", ["mcp.", "copilot.", "assistant.", "inbox.xena"]),
        ("app", "從 App", []),
    ]

    private var shown: [AuditEntry] {
        let all = load.value ?? []
        guard let c = Self.categories.first(where: { $0.id == category }), category != "all" else { return all }
        if category == "app" { return all.filter { $0.source == "app" } }
        return all.filter { e in c.prefixes.contains { e.action.hasPrefix($0) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader("操作紀錄", eyebrow: "平台管理", subtitle: "console 上每一次的修改：誰、什麼時候、改了什麼。最近 200 筆。")
                    ScrollView(.horizontal, showsIndicators: false) {
                        FilterBar(items: Self.categories.map(\.id), selection: $category, title: { id in Self.categories.first { $0.id == id }?.label ?? id })
                    }
                }
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if load.value != nil {
                    if shown.isEmpty {
                        EmptyState(title: "沒有紀錄")
                    } else {
                        RuledList {
                            ForEach(shown) { e in row(e) }
                        }
                    }
                } else if load.loading {
                    SkeletonRows(rows: 6)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await refresh() }.value }
        .brandPage()
        .pageTitle("操作紀錄")
        .task { if load.value == nil { await refresh() } }
    }

    private func row(_ e: AuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(e.ok ? Theme.successFG : Theme.dangerFG)
                    .frame(width: 6, height: 6)
                Text(e.summary)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Text([e.actionLabel, e.actor, e.createdAt?.relativeText].compactMap { $0 }.joined(separator: "・"))
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let s = e.sourceLabel {
                    StatusBadge(s, tone: s == "StudioX App" ? .info : .gold)
                }
            }
            .padding(.leading, 14)
        }
        .padding(.vertical, 11)
    }

    private func refresh() async {
        await load.run {
            (try await model.api.admin("audit", query: [URLQueryItem(name: "limit", value: "200")])["entries"]?.array ?? []).map(AuditEntry.init)
        }
    }
}

// MARK: - Xena AI

/// Xena AI（/admin/ai/settings、connect、records）：開關與現況、外部 AI 連接器、每一次 AI 呼叫工具的紀錄
struct XenaAdminView: View {
    @Environment(AppModel.self) private var model
    @State private var settings: XenaSettings?
    @State private var connectors: [AiConnector]?
    @State private var records: [AiRecord] = []
    @State private var stats: JSONValue?
    @State private var recordsAll = false
    @State private var more = false
    @State private var page = 1
    @State private var status = ""
    @State private var source = ""
    @State private var error: String?
    @State private var loadingMore = false
    /// 撤銷收不回來：確認選單＋Face ID（2 分鐘內驗證過就不再跳）
    @State private var revoking: AiConnector?
    @State private var opened: AiRecord?

    private var owner: Bool { model.can("mcp.manage") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                PageHeader("Xena AI", eyebrow: "平台管理", subtitle: "console 的 Xena（App、網頁上的對話）與從 Claude、ChatGPT 連進來的 AI。")
                if let error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if owner, let s = settings { settingsSection(s) }
                if owner, let connectors { connectorsSection(connectors) }
                recordsSection
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await refresh() }.value }
        .brandPage()
        .pageTitle("Xena AI")
        .task { await refresh() }
        .onChange(of: status) { Task { await loadRecords(reset: true) } }
        .onChange(of: source) { Task { await loadRecords(reset: true) } }
        .confirmationDialog("撤銷「\(revoking?.name ?? "")」？", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible, presenting: revoking) { c in
            Button("撤銷", role: .destructive) {
                Task { await model.verified("撤銷「\(c.name)」") { await revoke(c) } }
            }
        } message: { _ in
            Text("它所有的登入立刻失效；要再用得重新連接、重新登入。")
        }
        .sheet(item: $opened) { RecordSheet(record: $0) }
    }

    @ViewBuilder
    private func settingsSection(_ s: XenaSettings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHead("開關", role: .h3)
            AdminToggle(label: "Xena AI", isOn: Binding(get: { s.enabled }, set: { v in Task { await setEnabled(v) } }),
                        hint: "關掉之後 App 和網頁上的 Xena 對話都不能用（各網站右下角的 AI 客服不受影響）")
            if let problem = s.problem {
                ErrorNote(message: problem)
            }
            RuledList {
                InfoRow(label: "模型", value: s.auto ? "Auto（Jev 判斷每個問題用哪一級，最高到\(s.ceiling)）" : s.ceiling)
                if let f = s.fallback { InfoRow(label: "備援", value: f) }
                InfoRow(label: "Jev", value: s.jevReady ? "可以用" : "沒有金鑰（只用一般模型）")
                ForEach(s.providers) { p in
                    InfoRow(label: p.name, value: p.hasKey ? "有金鑰" : "沒有金鑰")
                }
            }
            Text("模型與金鑰在「金鑰庫」「網站服務」設定。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private func connectorsSection(_ list: [AiConnector]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("外部 AI 連接器", role: .h3)
            Text("從 Claude、ChatGPT 連進來的。撤銷之後它的登入全部失效。")
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            if list.isEmpty {
                Text("還沒有外部 AI 連進來。")
                    .textRole(.small)
                    .foregroundStyle(Theme.faint)
            } else {
                RuledList {
                    ForEach(list) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(c.name).textRole(.body).foregroundStyle(Theme.ink)
                                    if !c.enabled { StatusBadge("已撤銷", tone: .neutral) }
                                }
                                Text([c.activeTokens > 0 ? "\(c.activeTokens) 個登入" : "沒有登入", c.lastUsedAt.map { "\($0.relativeText)用過" }].compactMap { $0 }.joined(separator: "・"))
                                    .textRole(.xs)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            if c.enabled {
                                Button("撤銷") { revoking = c }
                                    .buttonStyle(.brand(.quiet, size: .sm))
                            }
                        }
                        .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHead("呼叫紀錄", role: .h3)
            Text(recordsAll ? "每一次 AI 呼叫工具都記在這裡（所有人的）。修改會先記一筆「提案」，按了確認才有執行的那一筆。" : "你自己的 AI 呼叫紀錄。")
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            if let s = stats {
                StatGrid(columns: 3) {
                    Stat(value: Double(s["calls"]?.int ?? 0), label: "近 30 天")
                    Stat(value: Double(s["writes"]?.int ?? 0), label: "確認後的修改")
                    Stat(value: Double(s["failed"]?.int ?? 0), label: "失敗")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(title: "全部", selected: status == "" && source == "") { status = ""; source = "" }
                    FilterChip(title: "Xena", selected: source == "copilot") { source = source == "copilot" ? "" : "copilot" }
                    FilterChip(title: "外部 AI", selected: source == "external") { source = source == "external" ? "" : "external" }
                    FilterChip(title: "提案", selected: status == "proposal") { status = status == "proposal" ? "" : "proposal" }
                    FilterChip(title: "失敗", selected: status == "error") { status = status == "error" ? "" : "error" }
                }
            }
            if records.isEmpty {
                Text("沒有紀錄。")
                    .textRole(.small)
                    .foregroundStyle(Theme.faint)
            } else {
                RuledList {
                    ForEach(records) { r in
                        Button { opened = r } label: { recordRow(r) }
                            .buttonStyle(.row)
                    }
                }
                if more {
                    Button(loadingMore ? "載入中…" : "更早的紀錄") { Task { await loadRecords(reset: false) } }
                        .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
                        .disabled(loadingMore)
                }
            }
        }
    }

    private func recordRow(_ r: AiRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(!r.ok ? Theme.dangerFG : r.proposal ? Theme.warningFG : Theme.successFG)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.label).textRole(.small).foregroundStyle(Theme.ink).lineLimit(1)
                    if r.proposal { StatusBadge("提案", tone: .warning) }
                }
                Text([r.site, r.source, r.actor].compactMap { $0 }.joined(separator: "・"))
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(r.createdAt?.relativeText ?? "")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func refresh() async {
        error = nil
        if owner {
            settings = (try? await model.api.admin("api/copilot/settings")).map(XenaSettings.init)
            connectors = (try? await model.api.admin("mcp-connectors"))?["clients"]?.array.map(AiConnector.init)
        }
        await loadRecords(reset: true)
    }

    private func loadRecords(reset: Bool) async {
        let next = reset ? 1 : page + 1
        loadingMore = !reset
        defer { loadingMore = false }
        var q = [URLQueryItem(name: "page", value: String(next))]
        if !status.isEmpty { q.append(URLQueryItem(name: "status", value: status)) }
        if !source.isEmpty { q.append(URLQueryItem(name: "source", value: source)) }
        do {
            let r = try await model.api.admin("ai-records", query: q)
            let list = (r["records"]?.array ?? []).map(AiRecord.init)
            records = reset ? list : records + list
            page = next
            more = r["more"]?.bool ?? false
            recordsAll = r["all"]?.bool ?? false
            if reset { stats = r["stats"] }
        } catch {
            if records.isEmpty { self.error = error.localizedDescription }
        }
    }

    /// 開、關 Xena AI（改得回來：再打開就好，不用驗證）
    private func setEnabled(_ on: Bool) async {
        await model.adminRun(on ? "Xena AI 開了" : "Xena AI 關了") {
            settings = XenaSettings(try await model.api.admin("api/copilot/settings", method: "PATCH", body: ["enabled": .bool(on)]))
        }
    }

    /// 撤銷（確認過了：確認選單＋Face ID）
    private func revoke(_ c: AiConnector) async {
        await model.adminRun("撤銷了「\(c.name)」") {
            _ = try await model.api.admin("mcp-connectors", method: "POST", body: ["action": "revoke", "clientId": .string(c.clientID)])
        }
        connectors = (try? await model.api.admin("mcp-connectors"))?["clients"]?.array.map(AiConnector.init)
    }
}

private struct RecordSheet: View {
    let record: AiRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Headline(record.label, role: .h2)
                    RuledList {
                        InfoRow(label: "工具", value: record.tool, mono: true)
                        if let at = record.createdAt { InfoRow(label: "時間", value: "\(at.dayText) \(at.clockText)") }
                        InfoRow(label: "來源", value: record.source)
                        if let a = record.actor { InfoRow(label: "操作者", value: a) }
                        if let v = record.approvedVia { InfoRow(label: "批准方式", value: v) }
                        if let ms = record.durationMs { InfoRow(label: "花了", value: ms < 1000 ? "\(ms) ms" : String(format: "%.1f 秒", Double(ms) / 1000)) }
                        InfoRow(label: "結果", value: record.ok ? (record.proposal ? "提案（還沒執行）" : "成功") : "失敗")
                    }
                    if let e = record.error {
                        ErrorNote(message: e)
                    }
                    if let args = record.args {
                        Text(args)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.ink.opacity(0.05), in: .rect(cornerRadius: Metric.radius))
                    }
                }
                .padding(24)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
