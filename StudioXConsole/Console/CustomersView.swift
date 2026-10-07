import SwiftUI

/// 客戶與網站（console 的 /admin/console）：每個客戶底下的網站、成員數、7 天訪客、同步狀態。
/// 管理者以上可以新增客戶、新增網站（建立後給一次網站的登入設定）。
struct CustomersView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<[ConsoleOrg]>()
    @State private var stats: [String: ConsoleSiteStats] = [:]
    @State private var addingOrg = false
    /// 新增網站：nil＝沒開；空字串＝自己選客戶；客戶 id＝那個客戶底下
    @State private var addingSiteFor: String?
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
                        if model.can("console.manage") {
                            EmptyState(title: "還沒有客戶", message: "新增客戶時可以順便建第一個網站。", actionTitle: "新增客戶", action: { addingOrg = true })
                        } else {
                            EmptyState(title: "還沒有客戶")
                        }
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
            NewOrgSheet(onDone: { await refresh() }, onSiteCreated: { secret = $0 })
        }
        .sheet(isPresented: Binding(get: { addingSiteFor != nil }, set: { if !$0 { addingSiteFor = nil } })) {
            NewSiteSheet(orgs: load.value ?? [], preselect: addingSiteFor ?? "") { created in
                secret = created
                Task { await refresh() }
            }
        }
        .sheet(item: $secret) { SiteSecretSheet(secret: $0) }
    }

    private var addMenu: some View {
        Menu {
            Button("新增客戶", systemImage: "person.crop.rectangle.badge.plus") { addingOrg = true }
            Button("新增網站", systemImage: "globe") { addingSiteFor = "" }
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
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
                Spacer(minLength: 8)
                // 這個客戶底下再加一個網站（不用再選客戶）
                if model.can("console.manage") {
                    Button("＋ 網站") { addingSiteFor = org.id }
                        .buttonStyle(.brand(.ghost, size: .sm))
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

/// 新增客戶；填了網站網址就順便建第一個網站（後台網址預填 https://cms.<網域>），建好給一次登入設定
private struct NewOrgSheet: View {
    var onDone: () async -> Void
    /// 順便建了第一個網站：只出現這一次的登入設定
    var onSiteCreated: (SiteSecret) -> Void
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var note = ""
    @State private var siteURL = "https://"
    @State private var cmsURL = "https://"
    /// 後台網址自己改過就不再跟著網站網址預填
    @State private var cmsEdited = false

    var body: some View {
        AdminSheet(title: "新增客戶", subtitle: "客戶是一個公司或品牌，底下可以有好幾個網站；填了網站網址就順便建第一個網站。", action: wantsSite ? "新增客戶與網站" : "新增", disabled: !valid) {
            let clean = name.trimmingCharacters(in: .whitespaces)
            var created: SiteSecret?
            let ok = await model.adminRun("新增了「\(clean)」") {
                var body: [String: JSONValue] = ["name": .string(clean), "note": .string(note)]
                if wantsSite {
                    var site: [String: JSONValue] = ["name": .string(clean), "siteUrl": .string(front), "cmsUrl": .string(cms)]
                    if front == cms { site["siteUrl"] = nil }
                    body["site"] = .object(site)
                }
                let r = try await model.api.admin("console", method: "POST", body: .object(body))
                if let env = r["env"]?.string {
                    created = SiteSecret(siteName: r["site"]?["name"]?.string ?? clean, env: env)
                }
                await onDone()
            }
            if ok, let created { onSiteCreated(created) }
            return ok
        } content: {
            AdminTextField(label: "客戶名稱", text: $name, placeholder: "例如：黃毛丫頭", required: true)
            AdminTextField(label: "網站網址（選填）", text: $siteURL, placeholder: "https://example.com", hint: "填了就順便建第一個網站（名稱先用客戶名稱，之後可以改）", keyboard: .URL)
            if wantsSite {
                AdminTextField(label: "網站後台網址", text: cmsBinding, placeholder: "https://cms.example.com", hint: "網站後台（studiox-cms）的網址，要 https", required: true, keyboard: .URL)
            }
            AdminTextField(label: "備註（選填）", text: $note, placeholder: "聯絡人、合約…只有 StudioX 看得到", multiline: true)
        }
        .presentationDetents([.large])
        .onChange(of: siteURL) { _, url in
            guard !cmsEdited, let host = URL(string: url.trimmingCharacters(in: .whitespaces))?.host(), host.contains(".") else { return }
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            cmsURL = "https://cms.\(bare)"
        }
    }

    private var front: String { siteURL.trimmingCharacters(in: .whitespaces) }
    private var cms: String { cmsURL.trimmingCharacters(in: .whitespaces) }
    private var wantsSite: Bool { front.count > "https://".count }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (!wantsSite || URL(string: cms)?.host() != nil)
    }
    private var cmsBinding: Binding<String> {
        Binding(get: { cmsURL }, set: { cmsURL = $0; cmsEdited = true })
    }
}

private struct NewSiteSheet: View {
    let orgs: [ConsoleOrg]
    /// 從客戶卡片的「＋ 網站」來的：先選好那個客戶
    var preselect = ""
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
        .onAppear {
            if orgID.isEmpty { orgID = orgs.contains(where: { $0.id == preselect }) ? preselect : orgs.first?.id ?? "" }
        }
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
    /// 重新產生密鑰、移出成員都收不回來：確認選單＋Face ID（2 分鐘內驗證過就不再跳）
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
            AddMemberSheet(siteID: siteID, isOwner: isOwner, firstMember: load.value?.members.isEmpty == true,
                           onDone: { await refresh() }, onInvited: { invite = $0 })
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
            Button("重新產生", role: .destructive) {
                Task { await model.verified("重新產生網站的登入密鑰") { await rotate() } }
            }
        } message: {
            Text("舊的密鑰會立刻失效：網站要換上新的環境變數之前，大家都沒辦法用 StudioX 登入那個網站。")
        }
        .confirmationDialog("把這個人移出網站？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { m in
            Button("移出 \(m.name ?? m.email)", role: .destructive) {
                Task { await model.verified("把 \(m.name ?? m.email) 移出網站") { await remove(m) } }
            }
        } message: { _ in
            Text("他就不能再管理這個網站（他的 StudioX 帳號還在）。")
        }
    }

    /// 上線進度：每一步做完了沒，沒做的點了去那裡（登入設定、成員就在這一頁下面）
    private func launchCard(_ d: ConsoleSiteDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("上線進度", aside: "\(d.launch.filter { $0.state == "done" }.count)／\(d.launch.count) 完成", role: .h3)
            RuledList {
                ForEach(d.launch) { step in
                    launchRow(step)
                }
            }
        }
    }

    @ViewBuilder
    private func launchRow(_ step: LaunchStep) -> some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: 12) {
            HeroIcon(step.icon, size: 16)
                .foregroundStyle(step.tone.foreground)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 3) {
                Text(step.label + (step.optional ? "（選用）" : ""))
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                Text(step.detail)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        // 還沒做、有地方可以去（另一頁）的才能點；同一頁的（# 開頭）往下捲就看得到
        if step.state != "done", let href = step.href, !href.hasPrefix("#"), let page = ConsolePage(adminPath: href) {
            NavigationLink(value: Route.console(page)) { row.contentShape(.rect) }
                .buttonStyle(.row)
        } else {
            row
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

        // 上線進度：還有必要的步驟沒做完才出現
        if !d.launch.isEmpty, !d.launched {
            launchCard(d)
        }

        // 成員
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("成員・\(d.members.count)", role: .h3) {
                if canManage {
                    Menu {
                        Button("用 Email 加人", systemImage: "person.badge.plus") { addingMember = true }
                        Button("產生邀請連結", systemImage: "link") { inviting = true }
                    } label: {
                        MoreLinkLabel(title: "加人")
                    }
                }
            }
            if d.members.isEmpty {
                Text("還沒有成員。填對方的 Email：有 StudioX 帳號的直接加進來，還沒有的會收到邀請信。")
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

    /// 移出（確認過了：確認選單＋Face ID）
    private func remove(_ m: ConsoleSiteDetail.Member) async {
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

    /// 重新產生（確認過了：確認選單＋Face ID）
    private func rotate() async {
        var created: SiteSecret?
        await model.adminRun(nil) {
            let r = try await model.api.admin("console/sites/\(siteID)", method: "POST", body: ["action": "rotate"])
            created = SiteSecret(siteName: load.value?.name ?? "網站", env: r["env"]?.string ?? "")
        }
        if let created { secret = created }
    }
}

// MARK: - 成員、邀請

/// 用 Email 加人：有 StudioX 帳號的直接加進網站；還沒有的（console 回 no_account）改寄邀請信——
/// 同一個欄位，不用先知道對方有沒有帳號
private struct AddMemberSheet: View {
    let siteID: String
    let isOwner: Bool
    /// 網站還沒有任何成員：第一位預設負責人（只有 StudioX 的負責人能指派）
    var firstMember = false
    var onDone: () async -> Void
    /// 對方還沒有帳號、寄了邀請：給上一頁顯示邀請連結
    var onInvited: (InviteResult) -> Void
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var level = "manager"

    var body: some View {
        AdminSheet(title: "加人", subtitle: "有 StudioX 帳號的直接加進網站；還沒有的會收到邀請信（7 天內有效），用 Apple 登入就加入。", action: "加進網站", disabled: !email.contains("@")) {
            let to = email.trimmingCharacters(in: .whitespaces)
            var invited: InviteResult?
            let ok = await model.adminRun(nil) {
                do {
                    let r = try await model.api.admin("console/sites/\(siteID)/members", method: "POST", body: ["email": .string(to), "level": .string(level)])
                    if r["sync"]?["ok"]?.bool == false {
                        model.show("加好了，但推到網站失敗：\(r["sync"]?["error"]?.string ?? "")", tone: .warning)
                    } else {
                        model.show("把 \(to) 加進來了")
                    }
                } catch let e as AdminCodeError where e.code == "no_account" {
                    // 還沒有帳號：寄邀請信
                    let r = try await model.api.admin("console/sites/\(siteID)/invites", method: "POST",
                                                      body: ["level": .string(level), "email": .string(to), "send": .bool(true)])
                    invited = InviteResult(url: r["url"]?.string ?? "", email: to, sent: r["sent"]?.bool ?? false,
                                           sendError: r["sendError"]?.string, expiresAt: r["expiresAt"]?.date)
                }
                await onDone()
            }
            if ok, let invited { onInvited(invited) }
            return ok
        } content: {
            AdminTextField(label: "Email", text: $email, placeholder: "name@example.com", required: true, keyboard: .emailAddress)
            LevelPicker(level: $level, isOwner: isOwner)
        }
        .presentationDetents([.medium, .large])
        .onAppear { if firstMember && isOwner { level = "owner" } }
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
        // 停用改得回來（再打開「使用中」）：按「儲存」就是確認，不用再驗證
        AdminSheet(title: "編輯網站", action: "儲存", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
            await model.adminRun("存好了") {
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
