import SwiftUI

// 行銷與通知：簡訊活動（看結果、發草稿）、LINE 優惠推播的紀錄（還沒有「發送優惠」的網站）、待發通知（取消、立即送出）、
// 整合（寄測試信、送測試簡訊）、重算會員等級。發送優惠（簡訊和 LINE 一起發）在 PromotionViews.swift。
// 和網站後台做得到的一樣；寫入一律走網站的兩步驟確認，要打「發送」的照樣要打。

/// 寫入的第一步：網站要確認就交給確認表單，不用確認的直接完成（行銷、發送優惠共用）
@MainActor
func proposeWrite(_ model: AppModel, _ tool: String, site: String, _ args: [String: JSONValue], into proposal: Binding<Proposal?>, done: () async -> Void) async {
    do {
        switch try await model.api.propose(tool, site: site, args) {
        case .needsConfirmation(let p): proposal.wrappedValue = p
        case .done:
            model.show("完成")
            await done()
        }
    } catch {
        model.show(error.localizedDescription, tone: .danger)
    }
}

func campaignStatus(_ status: String?) -> (String, Tone) {
    switch status {
    case "sending": ("傳送中", .info)
    case "sent": ("已發送", .active)
    case "failed": ("沒有完成", .danger)
    default: ("草稿", .neutral)
    }
}

// MARK: - 簡訊活動（campaign：草稿 → 看人數 → 發送）

struct CampaignView: View {
    let site: String
    let campaignID: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var data: JSONValue?
    @State private var error: String?
    /// 試算：收得到的人數、今天已用的額度、是不是靜音時段
    @State private var preview: JSONValue?
    @State private var proposal: Proposal?
    /// 確認的是哪一件事（刪除草稿完成要離開這頁）
    @State private var deleting = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let data {
                    content(data["campaign"] ?? data, sends: data["sends"]?.array ?? [])
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
        .refreshable { await Task { await load() }.value }
        .brandPage()
        .pageTitle(data?["campaign"]?["name"]?.string ?? "簡訊活動")
        .task { await load() }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            if deleting {
                model.show("已刪除")
                dismiss()
                return
            }
            let ok = result["successCount"]?.int ?? result["sent"]?.int
            model.show(ok.map { "已發送，\($0) 則成功" } ?? "已發送")
            Task { await load() }
        }
    }

    private func load() async {
        do {
            data = try await model.api.get(site: site, entity: "campaign", id: campaignID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder
    private func content(_ c: JSONValue, sends: [JSONValue]) -> some View {
        let status = c["status"]?.string ?? "draft"
        let text = c["body"]?.string ?? ""
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(c["name"]?.string ?? "簡訊活動", eyebrow: "簡訊活動・\(model.site(site)?.name ?? site)")
            HStack(spacing: 8) {
                let s = campaignStatus(status)
                StatusBadge(s.0, tone: s.1)
                if let at = (c["sentAt"]?.date ?? c["createdAt"]?.date) {
                    Text((c["sentAt"]?.date != nil ? "\(at.shortText) 發送" : "\(at.shortText) 建立"))
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .textRole(.body)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
            // 中文簡訊一則 70 字（含發送時自動加上的退訂說明，實際以網站計算為準）
            Text("\(text.count) 字・約 \(max(1, Int((Double(text.count) / 67).rounded(.up)))) 則簡訊的長度")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
        if status == "draft" {
            draftActions
        } else {
            results(c, sends: sends)
        }
    }

    private var draftActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("發送")
            if let p = preview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("收得到的會員 \(p["recipientCount"]?.int ?? 0) 位")
                        .textRole(.h4)
                        .foregroundStyle(Theme.ink)
                    if let used = p["usedToday"]?.int {
                        let cap = p["cap"]?.int ?? 0
                        Text(cap > 0 ? "今天已發 \(used) 則／上限 \(cap) 則" : "今天已發 \(used) 則")
                            .textRole(.small)
                            .foregroundStyle(Theme.ink2)
                    }
                    if p["isQuietHour"]?.bool == true {
                        Text("現在是靜音時段（晚上 9 點到早上 8 點），這段時間不能發送。")
                            .textRole(.small)
                            .foregroundStyle(Theme.warningFG)
                    }
                }
                .panel(padding: 16)
            }
            FlowLayout(spacing: 10) {
                Button(preview == nil ? "看看會寄給幾位" : "重新算一次") { Task { await dryRun() } }
                    .buttonStyle(.brand(.ghost, size: .md))
                Button("發送…") {
                    Task {
                        deleting = false
                        working = true
                        await proposeWrite(model, "send_campaign", site: site, ["id": .string(campaignID)], into: $proposal) { await load() }
                        working = false
                    }
                }
                .buttonStyle(.brand(.accent, size: .md, arrow: true))
                .disabled(preview?["isQuietHour"]?.bool == true)
                Button("刪除草稿") {
                    deleting = true
                    Task { await proposeWrite(model, "delete", site: site, ["entity": "campaign", "id": .string(campaignID)], into: $proposal) { dismiss() } }
                }
                .buttonStyle(.brand(.quiet, size: .md))
            }
            .disabled(working)
            Text("簡訊會產生費用、送出就收不回來；下一步會出網站的確認，要打「發送」才會寄。只寄給同意接收行銷簡訊的會員。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
    }

    private func dryRun() async {
        working = true
        defer { working = false }
        do {
            preview = try await model.api.tool("send_campaign", site: site, ["id": .string(campaignID), "dryRun": true])
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    @ViewBuilder
    private func results(_ c: JSONValue, sends: [JSONValue]) -> some View {
        let total = c["totalRecipients"]?.int ?? sends.count
        let ok = c["successCount"]?.int ?? sends.filter { $0["status"]?.string == "sent" }.count
        let failed = c["failedCount"]?.int ?? sends.filter { $0["status"]?.string == "failed" }.count
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("結果")
            StatGrid(columns: 3) {
                Stat(value: Double(total), label: "收件人")
                Stat(value: Double(ok), label: "成功")
                Stat(value: Double(failed), label: "失敗")
            }
            // 失敗的原因（不列電話）
            let reasons = Dictionary(grouping: sends.compactMap { $0["status"]?.string == "failed" ? ($0["error"]?.string ?? "原因不明") : nil }, by: { $0 })
            if !reasons.isEmpty {
                InfoList(title: "失敗的原因", rows: reasons.map { ($0.key, "\($0.value.count) 則") }.sorted { $0.0 < $1.0 })
            }
        }
    }
}

// MARK: - LINE 優惠推播（line_campaign 的紀錄＋寫一則新的）

struct LineCampaignsView: View {
    let site: String

    @Environment(AppModel.self) private var model
    @State private var rows: [JSONValue] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var composing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader("LINE 推播", eyebrow: model.site(site)?.name ?? site, subtitle: "傳一張品牌樣式的優惠卡片給 LINE 好友：可以選所有好友、綁定的會員、很久沒買的，或買過某個商品的。")
                    if model.site(site)?.tools.contains("send_line_campaign") == true {
                        Button("寫一則推播") { composing = true }
                            .buttonStyle(.brand(.accent, size: .md, arrow: true))
                    }
                }
                if let error {
                    ErrorNote(message: error) { Task { await load() } }
                }
                if !loaded {
                    SkeletonRows(rows: 4)
                } else if rows.isEmpty {
                    EmptyState(title: "還沒傳過推播", message: "傳過的會留在這裡，看得到傳給幾位、傳完了沒有。")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("傳過的")
                        RuledList {
                            ForEach(rows.indices, id: \.self) { i in LineCampaignRow(c: rows[i]) }
                        }
                    }
                }
            }
            .frame(maxWidth: Metric.readable + 80, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await load() }.value }
        .brandPage()
        .pageTitle("LINE 推播")
        .sheet(isPresented: $composing) {
            LineCampaignComposer(site: site) { Task { await load() } }
        }
        .task { await load() }
        // 傳送中的：每 5 秒更新一次進度
        .task(id: rows.contains { $0["status"]?.string == "sending" }) {
            guard rows.contains(where: { $0["status"]?.string == "sending" }) else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await load()
            }
        }
    }

    private func load() async {
        do {
            let r = try await model.api.list(site: site, entity: "line_campaign")
            withAnimation(Motion.ease) {
                rows = r.raw["campaigns"]?.array ?? r.raw["items"]?.array ?? []
                loaded = true
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
            loaded = true
        }
    }
}

private struct LineCampaignRow: View {
    let c: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(c["title"]?.string ?? "推播")
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                let s = campaignStatus(c["status"]?.string)
                StatusBadge(s.0, tone: s.1)
            }
            if let body = c["body"]?.string {
                Text(body)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
            Text(meta)
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 14)
    }

    private var meta: String {
        var parts = [LineAudience.label(c["audience"])]
        let recipients = c["recipients"]?.int ?? 0
        let sent = c["sent"]?.int ?? 0
        if recipients > 0 { parts.append(c["status"]?.string == "sending" ? "已傳 \(sent)／\(recipients) 位" : "\(sent) 位收到") }
        if let code = c["couponCode"]?.string, !code.isEmpty { parts.append("優惠碼 \(code)") }
        if let at = c["sentAt"]?.date ?? c["createdAt"]?.date { parts.append(at.shortText) }
        return parts.joined(separator: "・")
    }
}

/// 推播的對象
enum LineAudience: Hashable {
    case all, members, inactive, bought

    var title: String {
        switch self {
        case .all: "所有好友"
        case .members: "綁定的會員"
        case .inactive: "很久沒買的"
        case .bought: "買過某個商品"
        }
    }

    static func label(_ a: JSONValue?) -> String {
        switch a?["kind"]?.string {
        case "members": "綁定的會員"
        case "inactive": "\(a?["days"]?.int ?? 90) 天沒買的會員"
        case "bought": "買過指定商品的會員"
        default: "所有好友"
        }
    }
}

// MARK: - 待發通知（訂單狀態、等級變動、發券的通知會先倒數幾分鐘；可以取消並復原，或立即送出）

struct PendingNotificationsView: View {
    let site: String

    @Environment(AppModel.self) private var model
    @State private var data: JSONValue?
    @State private var error: String?
    @State private var proposal: Proposal?
    /// 確認的是取消還是立即送出
    @State private var action = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader("待發通知", eyebrow: model.site(site)?.name ?? site, subtitle: "改訂單狀態、會員等級、發折價券之後，通知會先等幾分鐘才寄給客人；改錯了可以在這裡取消，狀態會一起復原。")
                }
                if let error {
                    ErrorNote(message: error) { Task { await load() } }
                }
                if let data {
                    let pending = data["pending"]?.array ?? []
                    let recent = data["recent"]?.array ?? []
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("倒數中 \(pending.count)")
                        if pending.isEmpty {
                            Text("沒有等著寄的通知。")
                                .textRole(.small)
                                .foregroundStyle(Theme.muted)
                        } else {
                            RuledList {
                                ForEach(pending.indices, id: \.self) { i in pendingRow(pending[i]) }
                            }
                        }
                    }
                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow("最近的")
                            RuledList {
                                ForEach(recent.prefix(30).indices, id: \.self) { i in recentRow(recent[i]) }
                            }
                        }
                    }
                } else if error == nil {
                    SkeletonRows(rows: 4)
                }
            }
            .frame(maxWidth: Metric.readable + 80, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await load() }.value }
        .brandPage()
        .pageTitle("待發通知")
        .task {
            // 倒數會變：開著的時候每 30 秒更新
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { _ in
            model.show(action == "cancel" ? "已取消，狀態也復原了" : "已送出")
            Task { await load() }
        }
    }

    private func load() async {
        do {
            data = try await model.api.list(site: site, entity: "pending_notification").raw
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func who(_ n: JSONValue) -> String {
        n["userName"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? n["userEmail"]?.string ?? "客人"
    }

    private func pendingRow(_ n: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(n["kindLabel"]?.string ?? n["kind"]?.string ?? "通知")
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let at = n["scheduledAt"]?.date {
                    Text(at > .now ? "\(max(1, Int(at.timeIntervalSinceNow / 60))) 分鐘後寄出" : "馬上寄出")
                        .textRole(.xs)
                        .foregroundStyle(Theme.warningFG)
                }
            }
            Text([who(n), n["description"]?.string].compactMap { $0 }.joined(separator: "・"))
                .textRole(.small)
                .foregroundStyle(Theme.ink2)
            if model.site(site)?.tools.contains("manage_notification") == true, let id = n["id"]?.string {
                HStack(spacing: 10) {
                    Button("立即送出") { act(id, "send_now") }
                        .buttonStyle(.brand(.ghost, size: .sm))
                    Button("取消並復原") { act(id, "cancel") }
                        .buttonStyle(.brand(.quiet, size: .sm))
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 14)
    }

    private func recentRow(_ n: JSONValue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(n["kindLabel"]?.string ?? n["kind"]?.string ?? "通知")
                    .textRole(.small)
                    .foregroundStyle(Theme.ink)
                Text([who(n), n["failedReason"]?.string].compactMap { $0 }.joined(separator: "・"))
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            let status = Self.status(n["status"]?.string)
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status.0, tone: status.1)
                if let at = n["sentAt"]?.date ?? n["cancelledAt"]?.date ?? n["scheduledAt"]?.date {
                    Text(at.shortText).textRole(.xs).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func act(_ id: String, _ action: String) {
        self.action = action
        Task { await proposeWrite(model, "manage_notification", site: site, ["id": .string(id), "action": .string(action)], into: $proposal) { await load() } }
    }

    private static func status(_ s: String?) -> (String, Tone) {
        switch s {
        case "sent": ("已寄出", .active)
        case "cancelled": ("已取消", .neutral)
        case "failed": ("失敗", .danger)
        default: (s ?? "", .neutral)
        }
    }
}

// MARK: - 整合（Email、簡訊…：狀態、寄測試信、送測試簡訊；金鑰只在後台改）

struct IntegrationsView: View {
    let site: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var data: JSONValue?
    @State private var error: String?
    @State private var testing: String?
    @State private var sentKind = "email"
    @State private var proposal: Proposal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader("整合", eyebrow: model.site(site)?.name ?? site, subtitle: "網站寄信、發簡訊用的服務。金鑰只顯示片段，要改到後台；這裡可以寄一封測試信、送一則測試簡訊確認設定沒問題。")
                }
                if let error {
                    ErrorNote(message: error) { Task { await load() } }
                }
                if let data {
                    let rows = data["integrations"]?.array ?? data["items"]?.array ?? []
                    RuledList {
                        ForEach(rows.indices, id: \.self) { i in row(rows[i]) }
                    }
                    if let admin = data["adminUrl"]?.string.flatMap(URL.init(string:)) {
                        Button("到後台設定 ↗") { openURL(admin) }
                            .buttonStyle(.brand(.ghost, size: .md))
                    }
                } else if error == nil {
                    SkeletonRows(rows: 4)
                }
            }
            .frame(maxWidth: Metric.readable + 80, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await load() }.value }
        .brandPage()
        .pageTitle("整合")
        .task { await load() }
        .sheet(item: Binding(get: { testing.map(TestKind.init) }, set: { testing = $0?.id })) { kind in
            IntegrationTestSheet(kind: kind.id, defaultTo: kind.id == "email" ? (model.me?.email ?? "") : "") { to, message in
                sentKind = kind.id
                var args: [String: JSONValue] = ["kind": .string(kind.id), "to": .string(to)]
                if !message.isEmpty { args["message"] = .string(message) }
                Task { await proposeWrite(model, "test_integration", site: site, args, into: $proposal) {} }
            }
        }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { _ in
            model.show(sentKind == "sms" ? "測試簡訊送出了" : "測試信寄出了")
        }
    }

    private struct TestKind: Identifiable {
        let id: String
    }

    private func load() async {
        do {
            data = try await model.api.list(site: site, entity: "integration").raw
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func label(_ provider: String) -> String {
        switch provider {
        case "mitake": "簡訊（三竹）"
        case "resend": "Email（Resend）"
        case "notifications": "通知"
        case "personalized_coupons": "AI 個人化折扣"
        case "site_settings": "網站設定"
        case "ai_connector": "AI 連接器"
        case "line": "LINE 官方帳號"
        default: provider
        }
    }

    private func row(_ r: JSONValue) -> some View {
        let provider = r["provider"]?.string ?? r["service"]?.string ?? r["key"]?.string ?? ""
        let enabled = r["enabled"]?.bool ?? false
        let canTest = model.site(site)?.tools.contains("test_integration") == true
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(r["label"]?.string ?? Self.label(provider))
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                if let at = r["updatedAt"]?.date {
                    Text("\(at.shortText) 更新設定")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            if canTest && enabled && (provider == "resend" || provider == "mitake") {
                Button(provider == "resend" ? "寄測試信" : "送測試簡訊") { testing = provider == "resend" ? "email" : "sms" }
                    .buttonStyle(.brand(.ghost, size: .sm))
            }
            StatusBadge(enabled ? "啟用" : "關閉", tone: enabled ? .active : .neutral)
        }
        .padding(.vertical, 14)
    }
}

private struct IntegrationTestSheet: View {
    let kind: String
    let defaultTo: String
    var onSubmit: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var message = ""
    @FocusState private var focused: Int?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Headline(kind == "sms" ? "送測試簡訊" : "寄測試信", role: .h2)
                FieldBlock(label: kind == "sms" ? "手機號碼" : "收件 Email", required: true, focused: focused == 0) {
                    TextField(kind == "sms" ? "09xxxxxxxx" : "you@example.com", text: $to)
                        .keyboardType(kind == "sms" ? .phonePad : .emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: 0)
                        .fieldText()
                }
                FieldBlock(label: "內容（選填）", hint: "空白就用網站預設的測試內容", focused: focused == 1) {
                    TextField("", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focused, equals: 1)
                        .fieldText()
                }
                if kind == "sms" {
                    Text("測試簡訊會產生一則簡訊的費用。")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("下一步") {
                    dismiss()
                    onSubmit(to.trimmingCharacters(in: .whitespaces), message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.brand(.primary, size: .lg, fullWidth: true))
                .disabled(to.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(24)
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear { if to.isEmpty { to = defaultTo } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 重算會員等級（改了等級規則之後；一位或全部）

/// 會員等級清單上面的「重算全部」
struct RecomputeTiersButton: View {
    let site: String
    var userID: String?

    @Environment(AppModel.self) private var model
    @State private var proposal: Proposal?
    @State private var working = false

    var body: some View {
        if model.site(site)?.tools.contains("recompute_tiers") == true {
            VStack(alignment: .leading, spacing: 8) {
                Button(userID == nil ? "照現在的規則重算全部會員" : "重算這位的等級") {
                    Task {
                        working = true
                        var args: [String: JSONValue] = [:]
                        if let userID { args["userId"] = .string(userID) }
                        await proposeWrite(model, "recompute_tiers", site: site, args, into: $proposal) {}
                        working = false
                    }
                }
                .buttonStyle(.brand(.ghost, size: .sm))
                .disabled(working)
                if userID == nil {
                    Text("改了等級規則網站會自動重算；這裡是想馬上再算一次時用（不另外通知會員）。")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
            .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
                if let tier = result["tierName"]?.string {
                    model.show("重算好了：\(tier)")
                } else if let n = result["changed"]?.int {
                    model.show("重算好了，\(n) 位的等級有變")
                } else {
                    model.show("重算好了")
                }
                Task { await model.refreshAll() }
            }
        }
    }
}
