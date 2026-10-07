import SwiftUI

/// 客戶與網站（console 的 /admin/console）：每個客戶底下的網站、成員數、7 天訪客、同步狀態。
/// 管理者以上可以新增客戶、新增網站（建立後給一次網站的登入設定）。
struct CustomersView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<[ConsoleOrg]>()
    @State private var stats: [String: ConsoleSiteStats] = [:]
    @State private var addingOrg = false
    @State private var addingSite = false
    @State private var secret: SiteSecret?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                PageHeader("客戶與網站", eyebrow: "平台管理", subtitle: summary) {
                    if model.can("console.manage") { addMenu }
                }
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if let orgs = load.value {
                    if orgs.isEmpty {
                        EmptyState(title: "還沒有客戶", message: "先新增一個客戶，再替他新增網站。")
                    }
                    ForEach(orgs) { org in
                        orgSection(org)
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
        .pageTitle("客戶與網站")
        .task { if load.value == nil { await refresh() } }
        .sheet(isPresented: $addingOrg) {
            NewOrgSheet { await refresh() }
        }
        .sheet(isPresented: $addingSite) {
            NewSiteSheet(orgs: load.value ?? []) { created in
                secret = created
                Task { await refresh() }
            }
        }
        .sheet(item: $secret) { SiteSecretSheet(secret: $0) }
    }

    private var addMenu: some View {
        Menu {
            Button("新增客戶", systemImage: "person.crop.rectangle.badge.plus") { addingOrg = true }
            Button("新增網站", systemImage: "globe") { addingSite = true }
                .disabled((load.value ?? []).isEmpty)
        } label: {
            AddIconLabel()
        }
        .accessibilityLabel("新增")
    }

    private var summary: String? {
        guard let orgs = load.value else { return nil }
        let sites = orgs.reduce(0) { $0 + $1.sites.count }
        return "\(orgs.count) 個客戶・\(sites) 個網站"
    }

    private func refresh() async {
        await load.run {
            try await model.api.admin("console")["orgs"]?.array.map(ConsoleOrg.init) ?? []
        }
        // 7 天的訪客：網站連不上就沒有，不影響清單
        if let s = try? await model.api.admin("console/stats")["sites"] {
            stats = s.fields.compactMapValues { v in
                guard !v.isNull else { return nil }
                return ConsoleSiteStats(visitors: v["visitors"]?.int ?? 0, change: v["change"]?.double, live: v["live"]?.int ?? 0)
            }
        }
    }

    @ViewBuilder
    private func orgSection(_ org: ConsoleOrg) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(org.name)
                    .textRole(.h3)
                    .foregroundStyle(Theme.ink)
                if let note = org.note, !note.isEmpty {
                    Text(note)
                        .textRole(.small)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
            if org.sites.isEmpty {
                Text("還沒有網站")
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 8)
            } else {
                RuledList {
                    ForEach(org.sites) { site in
                        NavigationLink(value: Route.console(.site(site.id))) {
                            ConsoleSiteRow(site: site, stats: stats[site.id])
                        }
                        .buttonStyle(.row)
                    }
                }
            }
        }
    }
}

struct ConsoleSiteRow: View {
    let site: ConsoleSite
    var stats: ConsoleSiteStats?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(site.name)
                        .textRole(.body)
                        .foregroundStyle(Theme.ink)
                    if !site.active { StatusBadge("停用中", tone: .neutral) }
                    if site.lastSyncError != nil { StatusBadge("同步失敗", tone: .danger) }
                }
                Text("\(site.host)・\(site.members) 位成員")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let stats {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stats.visitors.formatted())
                        .font(.brand(15, .medium).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    Text("7 天訪客")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, 13)
        .contentShape(.rect)
    }
}

// MARK: - 新增客戶、網站

private struct NewOrgSheet: View {
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var note = ""

    var body: some View {
        AdminSheet(title: "新增客戶", subtitle: "客戶是一個公司或品牌，底下可以有好幾個網站。", action: "新增", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
            await model.adminRun("新增了「\(name)」") {
                _ = try await model.api.admin("console", method: "POST", body: ["name": .string(name.trimmingCharacters(in: .whitespaces)), "note": .string(note)])
                await onDone()
            }
        } content: {
            AdminTextField(label: "客戶名稱", text: $name, placeholder: "例如：黃毛丫頭", required: true)
            AdminTextField(label: "備註（選填）", text: $note, placeholder: "聯絡人、合約…只有 StudioX 看得到", multiline: true)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct NewSiteSheet: View {
    let orgs: [ConsoleOrg]
    var onCreated: (SiteSecret) -> Void
    @Environment(AppModel.self) private var model
    @State private var orgID = ""
    @State private var name = ""
    @State private var cmsURL = "https://"
    @State private var siteURL = "https://"

    var body: some View {
        AdminSheet(title: "新增網站", subtitle: "建立後會給一次網站的登入設定（三行環境變數），放進網站後台就能用 StudioX 登入。", action: "建立網站", disabled: !valid) {
            var created: SiteSecret?
            let ok = await model.adminRun("建立了「\(name)」") {
                var body: [String: JSONValue] = ["orgId": .string(orgID), "name": .string(name.trimmingCharacters(in: .whitespaces)), "cmsUrl": .string(cmsURL.trimmingCharacters(in: .whitespaces))]
                let site = siteURL.trimmingCharacters(in: .whitespaces)
                if site.count > "https://".count { body["siteUrl"] = .string(site) }
                let r = try await model.api.admin("console/sites", method: "POST", body: .object(body))
                created = SiteSecret(siteName: r["site"]?["name"]?.string ?? name, env: r["env"]?.string ?? "")
            }
            if ok, let created { onCreated(created) }
            return ok
        } content: {
            AdminPicker(label: "客戶", selection: $orgID, options: orgs.map { ($0.id, $0.name) })
            AdminTextField(label: "網站名稱", text: $name, placeholder: "例如：黃毛丫頭官網", required: true)
            AdminTextField(label: "後台網址", text: $cmsURL, placeholder: "https://admin.example.com", hint: "網站後台（studiox-cms）的網址，要 https", required: true, keyboard: .URL)
            AdminTextField(label: "前台網址（選填）", text: $siteURL, placeholder: "https://example.com", hint: "客人看到的網站；和後台同一個就不用填", keyboard: .URL)
        }
        .presentationDetents([.large])
        .onAppear { if orgID.isEmpty { orgID = orgs.first?.id ?? "" } }
    }

    private var valid: Bool {
        !orgID.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: cmsURL)?.host() != nil
    }
}

// MARK: - 一個網站

/// 一個網站：狀態、成員、邀請、設定、登入設定（console 的 /admin/console/sites/[id]）
struct ConsoleSiteView: View {
    let siteID: String
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var load = AdminLoad<ConsoleSiteDetail>()
    @State private var addingMember = false
    @State private var inviting = false
    @State private var editing = false
    @State private var secret: SiteSecret?
    @State private var invite: InviteResult?
    @State private var confirmRotate = false
    @State private var removing: ConsoleSiteDetail.Member?
    @State private var syncing = false

    private var canManage: Bool { model.can("console.manage") }
    private var isOwner: Bool { model.me?.consoleLevel == "owner" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                if let d = load.value {
                    content(d)
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
        .pageTitle(load.value?.name ?? "網站")
        .task { if load.value == nil { await refresh() } }
        .sheet(isPresented: $addingMember) {
            AddMemberSheet(siteID: siteID, isOwner: isOwner) { await refresh() }
        }
        .sheet(isPresented: $inviting) {
            InviteSheet(siteID: siteID, isOwner: isOwner) { result in
                invite = result
                Task { await refresh() }
            }
        }
        .sheet(item: $invite) { InviteResultSheet(result: $0) }
        .sheet(isPresented: $editing) {
            if let d = load.value {
                EditSiteSheet(detail: d, isOwner: isOwner) { await refresh() }
            }
        }
        .sheet(item: $secret) { SiteSecretSheet(secret: $0) }
        .confirmationDialog("重新產生登入密鑰？", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("重新產生", role: .destructive) { Task { await rotate() } }
        } message: {
            Text("舊的密鑰會立刻失效：網站要換上新的環境變數之前，大家都沒辦法用 StudioX 登入那個網站。")
        }
        .confirmationDialog("把這個人移出網站？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { m in
            Button("移出 \(m.name ?? m.email)", role: .destructive) { Task { await remove(m) } }
        } message: { _ in
            Text("他就不能再管理這個網站（他的 StudioX 帳號還在）。")
        }
    }

    @ViewBuilder
    private func content(_ d: ConsoleSiteDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(d.name, eyebrow: d.orgName ?? "網站", subtitle: d.siteURL ?? d.cmsURL) {
                if canManage {
                    Button("編輯") { editing = true }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
            }
            HStack(spacing: 8) {
                StatusBadge(d.active ? "使用中" : "停用中", tone: d.active ? .active : .neutral)
                if d.supportDesk { StatusBadge("StudioX 代管客服", tone: .info) }
            }
            HStack(spacing: 10) {
                if let url = URL(string: d.siteURL ?? d.cmsURL) {
                    Button("打開網站 ↗") { openURL(url) }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
                if let url = URL(string: "\(d.cmsURL)/login?sso=studiox") {
                    Button("網站後台 ↗") { openURL(url) }
                        .buttonStyle(.brand(.ghost, size: .sm))
                }
            }
        }

        // 成員
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("成員・\(d.members.count)", role: .h3) {
                if canManage {
                    Menu {
                        Button("加已有帳號的人", systemImage: "person.badge.plus") { addingMember = true }
                        Button("產生邀請連結", systemImage: "link") { inviting = true }
                    } label: {
                        MoreLinkLabel(title: "加人")
                    }
                }
            }
            if d.members.isEmpty {
                Text("還沒有成員。產生邀請連結傳給對方，用 Apple 登入就加入了。")
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
            } else {
                RuledList {
                    ForEach(d.members) { m in
                        memberRow(m)
                    }
                }
            }
        }

        // 還沒用的邀請
        if !d.invites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHead("還沒接受的邀請", role: .h3)
                RuledList {
                    ForEach(d.invites) { inv in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(inv.email ?? "沒有指定 Email")
                                    .textRole(.body)
                                    .foregroundStyle(Theme.ink)
                                Text("\(ConsoleLevel.label(inv.level))・\(inv.expiresAt.map { "\($0.shortText) 到期" } ?? "")")
                                    .textRole(.xs)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if canManage {
                                Button("撤銷") { Task { await revoke(inv) } }
                                    .buttonStyle(.brand(.quiet, size: .sm))
                            }
                        }
                        .padding(.vertical, 11)
                    }
                }
            }
        }

        // 同步
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("成員同步", role: .h3) {
                if canManage {
                    Button(syncing ? "同步中…" : "立即同步") { Task { await sync() } }
                        .buttonStyle(.brand(.ghost, size: .sm))
                        .disabled(syncing)
                }
            }
            Text("成員、職能、簽名改了都會推到網站；網站連不上時這裡會寫原因。")
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            if let error = d.lastSyncError {
                ErrorNote(message: "上次同步失敗：\(error)")
            } else if let at = d.lastSyncAt {
                Text("上次同步：\(at.relativeText)")
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
            }
        }

        // 登入設定
        VStack(alignment: .leading, spacing: 8) {
            SectionHead("用 StudioX 登入的設定", role: .h3) {
                if isOwner {
                    Button("重新產生密鑰") { confirmRotate = true }
                        .buttonStyle(.brand(.quiet, size: .sm))
                }
            }
            RuledList {
                InfoRow(label: "Client ID", value: d.clientID, mono: true, copy: true)
                InfoRow(label: "Issuer", value: d.issuer, mono: true, copy: true)
                InfoRow(label: "Callback", value: d.redirectURI, mono: true, copy: true)
            }
            Text("密鑰只在建立網站、重新產生時看得到一次。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private func memberRow(_ m: ConsoleSiteDetail.Member) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(m.name ?? m.email)
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                Text([m.name == nil ? nil : m.email, m.title, m.appleLinked ? "Apple 登入" : nil].compactMap { $0 }.joined(separator: "・"))
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if canManage {
                Menu {
                    Picker("職能", selection: Binding(get: { m.level }, set: { level in Task { await setLevel(m, level) } })) {
                        ForEach(ConsoleLevel.all, id: \.self) { l in
                            Text(ConsoleLevel.label(l)).tag(l)
                                .disabled(l == "owner" && !isOwner)
                        }
                    }
                    Divider()
                    Button("移出網站", systemImage: "person.badge.minus", role: .destructive) { removing = m }
                        .disabled(m.level == "owner" && !isOwner)
                } label: {
                    HStack(spacing: 4) {
                        Text(ConsoleLevel.label(m.level))
                        HeroIcon("chevron-down", size: 11)
                    }
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                }
            } else {
                Text(ConsoleLevel.label(m.level))
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.vertical, 12)
    }

    private func refresh() async {
        await load.run { ConsoleSiteDetail(try await model.api.admin("console/sites/\(siteID)")) }
    }

    private func setLevel(_ m: ConsoleSiteDetail.Member, _ level: String) async {
        guard level != m.level else { return }
        await model.adminRun("\(m.name ?? m.email) 改成\(ConsoleLevel.label(level))") {
            let r = try await model.api.admin("console/sites/\(siteID)/members", method: "PATCH", body: ["userId": .string(m.userID), "level": .string(level)])
            if r["sync"]?["ok"]?.bool == false { model.show("已經改了，但推到網站失敗：\(r["sync"]?["error"]?.string ?? "")", tone: .warning) }
        }
        await refresh()
    }

    private func remove(_ m: ConsoleSiteDetail.Member) async {
        guard await model.lock.verify("把 \(m.name ?? m.email) 移出網站") else { return }
        await model.adminRun("已經把 \(m.name ?? m.email) 移出") {
            _ = try await model.api.admin("console/sites/\(siteID)/members", method: "DELETE", body: ["userId": .string(m.userID)])
        }
        await refresh()
    }

    private func revoke(_ inv: ConsoleSiteDetail.Invite) async {
        await model.adminRun("邀請已撤銷") {
            _ = try await model.api.admin("console/sites/\(siteID)/invites", method: "DELETE", body: ["inviteId": .string(inv.id)])
        }
        await refresh()
    }

    private func sync() async {
        syncing = true
        defer { syncing = false }
        await model.adminRun("同步好了") {
            _ = try await model.api.admin("console/sites/\(siteID)", method: "POST", body: ["action": "sync"])
        }
        await refresh()
    }

    private func rotate() async {
        guard await model.lock.verify("重新產生網站的登入密鑰") else { return }
        var created: SiteSecret?
        await model.adminRun(nil) {
            let r = try await model.api.admin("console/sites/\(siteID)", method: "POST", body: ["action": "rotate"])
            created = SiteSecret(siteName: load.value?.name ?? "網站", env: r["env"]?.string ?? "")
        }
        if let created { secret = created }
    }
}

// MARK: - 成員、邀請

private struct AddMemberSheet: View {
    let siteID: String
    let isOwner: Bool
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var level = "manager"

    var body: some View {
        AdminSheet(title: "加已有帳號的人", subtitle: "對方要已經用這個 Email 登入過 StudioX；還沒有帳號的人請改用邀請連結。", action: "加進網站", disabled: !email.contains("@")) {
            await model.adminRun("加進來了") {
                let r = try await model.api.admin("console/sites/\(siteID)/members", method: "POST", body: ["email": .string(email.trimmingCharacters(in: .whitespaces)), "level": .string(level)])
                if r["sync"]?["ok"]?.bool == false { model.show("加好了，但推到網站失敗：\(r["sync"]?["error"]?.string ?? "")", tone: .warning) }
                await onDone()
            }
        } content: {
            AdminTextField(label: "Email", text: $email, placeholder: "name@example.com", required: true, keyboard: .emailAddress)
            LevelPicker(level: $level, isOwner: isOwner)
        }
        .presentationDetents([.medium, .large])
    }
}

/// 職能：負責人只有 StudioX 的負責人能指派
private struct LevelPicker: View {
    @Binding var level: String
    let isOwner: Bool

    var body: some View {
        AdminPicker(label: "職能", selection: $level,
                    options: ConsoleLevel.all.filter { $0 != "owner" || isOwner }.map { ($0, ConsoleLevel.label($0)) },
                    hint: ConsoleLevel.hint(level))
    }
}

struct InviteResult: Identifiable, Hashable {
    var id: String { url }
    let url: String
    let email: String?
    let sent: Bool
    let sendError: String?
    let expiresAt: Date?
}

private struct InviteSheet: View {
    let siteID: String
    let isOwner: Bool
    var onCreated: (InviteResult) -> Void
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var level = "manager"
    @State private var send = true

    var body: some View {
        AdminSheet(title: "產生邀請連結", subtitle: "連結 7 天內有效、只能用一次；對方打開用 Apple 登入就加入網站。", action: "產生") {
            var result: InviteResult?
            let to = email.trimmingCharacters(in: .whitespaces)
            let ok = await model.adminRun(nil) {
                var body: [String: JSONValue] = ["level": .string(level)]
                if !to.isEmpty {
                    body["email"] = .string(to)
                    body["send"] = .bool(send)
                }
                let r = try await model.api.admin("console/sites/\(siteID)/invites", method: "POST", body: .object(body))
                result = InviteResult(url: r["url"]?.string ?? "", email: to.isEmpty ? nil : to, sent: r["sent"]?.bool ?? false,
                                      sendError: r["sendError"]?.string, expiresAt: r["expiresAt"]?.date)
            }
            if ok, let result { onCreated(result) }
            return ok
        } content: {
            LevelPicker(level: $level, isOwner: isOwner)
            AdminTextField(label: "對方的 Email（選填）", text: $email, placeholder: "填了只有這個人能用", keyboard: .emailAddress)
            if !email.trimmingCharacters(in: .whitespaces).isEmpty {
                AdminToggle(label: "直接寄邀請信給他", isOn: $send, hint: "不寄的話，產生後自己把連結傳給他")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct InviteResultSheet: View {
    let result: InviteResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Headline(result.sent ? "邀請信寄出了" : "邀請連結", role: .h2)
                if let error = result.sendError {
                    ErrorNote(message: "信沒有寄出：\(error)。請把連結傳給對方。")
                } else if result.sent, let email = result.email {
                    Text("已經寄到 \(email)；也可以把連結直接傳給他。")
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                }
                Text(result.url)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.ink.opacity(0.05), in: .rect(cornerRadius: Metric.radius))
                if let at = result.expiresAt {
                    Text("\(at.dayText) 前有效、只能用一次")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
                HStack(spacing: 10) {
                    CopyButton(text: result.url, title: "複製連結")
                    ShareLink(item: result.url) { Text("傳給他") }
                        .buttonStyle(.brand(.accent, size: .sm))
                }
                Spacer()
            }
            .padding(24)
            .background { Theme.sheet.ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 編輯網站

private struct EditSiteSheet: View {
    let detail: ConsoleSiteDetail
    let isOwner: Bool
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var siteURL = ""
    @State private var cmsURL = ""
    @State private var active = true
    @State private var supportDesk = false

    var body: some View {
        AdminSheet(title: "編輯網站", action: "儲存", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
            if !active && detail.active {
                guard await model.lock.verify("停用「\(detail.name)」") else { return false }
            }
            return await model.adminRun("存好了") {
                var body: [String: JSONValue] = [:]
                if name != detail.name { body["name"] = .string(name.trimmingCharacters(in: .whitespaces)) }
                let site = siteURL.trimmingCharacters(in: .whitespaces)
                if site != (detail.siteURL ?? "") { body["siteUrl"] = site.isEmpty ? .null : .string(site) }
                if isOwner {
                    if cmsURL != detail.cmsURL { body["cmsUrl"] = .string(cmsURL.trimmingCharacters(in: .whitespaces)) }
                    if active != detail.active { body["status"] = .string(active ? "active" : "suspended") }
                    if supportDesk != detail.supportDesk { body["supportDesk"] = .bool(supportDesk) }
                }
                guard !body.isEmpty else { return }
                let r = try await model.api.admin("console/sites/\(detail.id)", method: "PATCH", body: .object(body))
                if r["sync"]?["ok"]?.bool == false { model.show("存好了，但推到網站失敗：\(r["sync"]?["error"]?.string ?? "")", tone: .warning) }
                await onDone()
            }
        } content: {
            AdminTextField(label: "網站名稱", text: $name, required: true)
            AdminTextField(label: "前台網址", text: $siteURL, placeholder: "https://example.com", keyboard: .URL)
            if isOwner {
                AdminTextField(label: "後台網址", text: $cmsURL, hint: "改了之後網站的登入 Callback 也會跟著變", required: true, keyboard: .URL)
                AdminToggle(label: "使用中", isOn: $active, hint: "停用後成員都不能從 StudioX 登入、AI 連不到這個網站")
                AdminToggle(label: "StudioX 代管客服", isOn: $supportDesk, hint: "這個網站的客服對話也進 StudioX 的收件匣")
            } else {
                Text("後台網址、停用、代管客服只有 StudioX 的負責人能改。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            name = detail.name
            siteURL = detail.siteURL ?? ""
            cmsURL = detail.cmsURL
            active = detail.active
            supportDesk = detail.supportDesk
        }
    }
}
