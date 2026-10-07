import SwiftUI

// 發送優惠：同一則優惠用 LINE、簡訊，或兩個一起發（網站的 send_promotion，和網站後台的「發送優惠」同一套規則），
// 發送紀錄是簡訊活動（campaign）和 LINE 推播（line_campaign）合在一起。還沒有 send_promotion 的網站用 LINE 推播的寫法
// （LineCampaignComposer）。寫入一律走網站的兩步驟確認，要打「發送」才會發。

// MARK: - 發送優惠（簡訊和 LINE 一起：send_promotion；發送紀錄是 campaign＋line_campaign 合在一起）

/// 怎麼發（和網站後台的「發送優惠」一樣）
enum PromotionChannel: String, CaseIterable, Hashable {
    case lineFirst = "line_first", line, sms, both

    var title: String {
        switch self {
        case .lineFirst: "LINE 優先"
        case .line: "只發 LINE"
        case .sms: "只發簡訊"
        case .both: "兩個都發"
        }
    }

    var hint: String {
        switch self {
        case .lineFirst: "有綁 LINE 的傳 LINE，沒有的發簡訊：每人只收一則、省簡訊費"
        case .line: "不花簡訊費；沒綁 LINE 的會員收不到"
        case .sms: "同意接收行銷簡訊、手機驗證過的會員"
        case .both: "有綁 LINE 又同意收簡訊的人會收到兩則"
        }
    }

    var usesLine: Bool { self != .sms }
    var usesSMS: Bool { self != .line }
}

/// 發送優惠：寫一則（LINE、簡訊，或兩個一起），下面是發過的（同一次發的 LINE 和簡訊合成一列）
struct PromotionsView: View {
    let site: String

    @Environment(AppModel.self) private var model
    @State private var items: [PromotionItem] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var composing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader("發送優惠", eyebrow: model.site(site)?.name ?? site, subtitle: "同一則優惠用 LINE、簡訊，或兩個一起發。LINE 優先：有綁 LINE 的傳 LINE、其他人發簡訊，每人只收一則。")
                    Button("寫一則優惠") { composing = true }
                        .buttonStyle(.brand(.accent, size: .md, arrow: true))
                }
                if let error {
                    ErrorNote(message: error) { Task { await load() } }
                }
                if !loaded {
                    SkeletonRows(rows: 4)
                } else if items.isEmpty {
                    EmptyState(title: "還沒發過優惠", message: "發過的會留在這裡：發給誰、LINE 和簡訊各幾位、發完了沒有。")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("發送紀錄")
                        RuledList {
                            ForEach(items) { item in row(item) }
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
        .pageTitle("發送優惠")
        .sheet(isPresented: $composing) {
            PromotionComposer(site: site) { Task { await load() } }
        }
        .task {
            await load()
            // UI 截圖（-demoScroll compose）：直接打開「寫一則優惠」
            if DemoServer.screenshots, UserDefaults.standard.string(forKey: "demoScroll") == "compose" { composing = true }
        }
        // 發送中的：每 5 秒更新一次進度
        .task(id: sending) {
            guard sending else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await load()
            }
        }
    }

    private var sending: Bool { items.contains { $0.status == "sending" } }

    /// 有簡訊的點進去看結果（成功、失敗的原因）；簡訊草稿也是在那裡發或刪
    @ViewBuilder
    private func row(_ item: PromotionItem) -> some View {
        if let id = item.sms?["id"]?.string {
            NavigationLink(value: Route.record(site: site, entity: "campaign", id: id)) {
                PromotionRow(item: item)
            }
            .buttonStyle(.row)
        } else {
            PromotionRow(item: item)
        }
    }

    /// LINE 和簡訊一起讀；一邊讀不到（例如沒有那個權限）另一邊照樣列
    private func load() async {
        async let lineList = Self.campaigns(model, site: site, entity: "line_campaign")
        async let smsList = Self.campaigns(model, site: site, entity: "campaign")
        var failure: String?
        var line: [JSONValue] = []
        var sms: [JSONValue] = []
        do {
            line = try await lineList
        } catch {
            failure = error.localizedDescription
        }
        do {
            sms = try await smsList
        } catch {
            failure = failure ?? error.localizedDescription
        }
        withAnimation(Motion.ease) {
            items = PromotionItem.merge(line: line, sms: sms)
            loaded = true
        }
        error = line.isEmpty && sms.isEmpty ? failure : nil
    }

    private static func campaigns(_ model: AppModel, site: String, entity: String) async throws -> [JSONValue] {
        let r = try await model.api.list(site: site, entity: entity)
        return r.raw["campaigns"]?.array ?? r.raw["items"]?.array ?? []
    }
}

/// 發過的一則優惠：同一次發的 LINE 和簡訊（標題一樣、一分鐘內建立的）合成一筆
struct PromotionItem: Identifiable {
    var line: JSONValue?
    var sms: JSONValue?

    var id: String {
        [line?["id"]?.string.map { "line:\($0)" }, sms?["id"]?.string.map { "sms:\($0)" }].compactMap { $0 }.joined(separator: "+")
    }

    var title: String { line?["title"]?.string ?? sms?["name"]?.string ?? "優惠" }
    var text: String? { line?["body"]?.string ?? sms?["body"]?.string }
    var created: Date { [line?["createdAt"]?.date, sms?["createdAt"]?.date].compactMap { $0 }.min() ?? .distantPast }
    var sentAt: Date? { [line?["sentAt"]?.date, sms?["sentAt"]?.date].compactMap { $0 }.max() }
    var couponCode: String? { [line?["couponCode"]?.string, sms?["couponCode"]?.string].compactMap { $0 }.first { !$0.isEmpty } }

    /// 整則的狀態：有一邊還在傳就是傳送中（LINE 的 draft 是「準備開始傳」）、有一邊沒完成就是沒有完成
    var status: String {
        let lineStatus = line?["status"]?.string
        let smsStatus = sms?["status"]?.string
        let all = [lineStatus, smsStatus].compactMap { $0 }
        if all.contains("sending") || lineStatus == "draft" { return "sending" }
        if all.contains("failed") { return "failed" }
        if !all.isEmpty, all.allSatisfy({ $0 == "sent" }) { return "sent" }
        return "draft"
    }

    /// 「LINE 214 位收到・簡訊 66 位收到」
    var channels: String {
        var parts: [String] = []
        if let l = line {
            let recipients = l["recipients"]?.int ?? 0
            let sent = l["sent"]?.int ?? 0
            switch l["status"]?.string {
            case "sent": parts.append("LINE \(sent) 位收到")
            case "failed": parts.append("LINE 沒有傳完（\(sent)／\(recipients) 位）")
            default: parts.append(recipients > 0 ? "LINE 傳送中（\(recipients) 位）" : "LINE 準備開始傳")
            }
        }
        if let s = sms {
            let total = s["totalRecipients"]?.int ?? 0
            let ok = s["successCount"]?.int ?? 0
            let failed = s["failedCount"]?.int ?? 0
            switch s["status"]?.string {
            case "draft": parts.append("簡訊草稿（還沒發）")
            case "sending": parts.append("簡訊已發 \(ok + failed)／\(total) 位")
            default: parts.append(failed > 0 ? "簡訊 \(ok) 位收到、\(failed) 位沒收到" : "簡訊 \(ok) 位收到")
            }
        }
        return parts.joined(separator: "・")
    }

    /// 對象（LINE 優先的簡訊只發給沒綁 LINE 的，對象寫 LINE 那一邊的就好）
    var audience: String {
        let a = line?["audience"] ?? sms?["audience"]
        switch a?["kind"]?.string {
        case "all": return "所有 LINE 好友"
        case "inactive": return "\(a?["days"]?.int ?? 90) 天沒買的會員"
        case "bought": return "買過指定商品的會員"
        default: return "所有會員"
        }
    }

    static func merge(line: [JSONValue], sms: [JSONValue]) -> [PromotionItem] {
        var smsLeft = sms
        var items: [PromotionItem] = line.map { l in
            guard let title = l["title"]?.string, let at = l["createdAt"]?.date,
                  let i = smsLeft.firstIndex(where: { s in
                      s["name"]?.string == title && s["createdAt"]?.date.map { abs($0.timeIntervalSince(at)) < 60 } == true
                  })
            else { return PromotionItem(line: l, sms: nil) }
            return PromotionItem(line: l, sms: smsLeft.remove(at: i))
        }
        items += smsLeft.map { PromotionItem(line: nil, sms: $0) }
        return items.sorted { $0.created > $1.created }
    }
}

private struct PromotionRow: View {
    let item: PromotionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                let s = campaignStatus(item.status)
                StatusBadge(s.0, tone: s.1)
            }
            if let text = item.text, !text.isEmpty {
                Text(text)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
            Text(item.channels)
                .textRole(.small)
                .foregroundStyle(Theme.ink)
            Text(meta)
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var meta: String {
        var parts = [item.audience]
        if let code = item.couponCode { parts.append("優惠碼 \(code)") }
        parts.append((item.sentAt ?? item.created).shortText)
        return parts.joined(separator: "・")
    }
}

/// 寫一則優惠：內容（LINE 卡片）、發給誰、怎麼發、簡訊內容。改了什麼就請網站重新試算（每個管道幾位、簡訊拆成幾則、
/// 今天的額度、不能發的原因 —— 和真的發是同一份計算），沒問題才能按下一步；下一步是網站的確認，要打「發送」才會發
struct PromotionComposer: View {
    let site: String
    var onSent: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: JSONValue] = ["buttonLabel": "去看看", "buttonUrl": "/zh/shop"]
    @State private var audience: LineAudience = .members
    @State private var days = 90
    @State private var productID: String?
    /// 自己選的管道；沒選就用網站的預設（有設定 LINE 是 LINE 優先，不然只發簡訊）
    @State private var picked: PromotionChannel?
    /// 簡訊內容自己改過了（沒改過就用網站從標題、說明、優惠碼組的那一則）
    @State private var smsEdited = false
    @State private var options = PromoOptions()
    /// 網站的試算，和它是照哪一份內容算的（內容又改了就要等新的試算）
    @State private var preview: JSONValue?
    @State private var previewedFor: [String: JSONValue]?
    @State private var previewError: String?
    @State private var previewing = false
    @State private var proposal: Proposal?
    @State private var busy = false

    private var channel: PromotionChannel? { picked ?? preview?["channel"]?.string.flatMap(PromotionChannel.init(rawValue:)) }
    private var usesLine: Bool { channel?.usesLine ?? true }
    private var usesSMS: Bool { channel?.usesSMS ?? true }
    private var lineConfigured: Bool { preview?["line"]?["configured"]?.bool ?? true }
    private var people: Int { preview?["people"]?.int ?? 0 }
    private var problems: [String] { (preview?["problems"]?.array ?? []).compactMap(\.string) }
    private var fresh: Bool { previewedFor == draft }
    private var canSend: Bool { fresh && preview?["canSend"]?.bool == true && people > 0 }
    private var hasContent: Bool {
        ["title", "body", "smsText"].contains { key in (values[key]?.string ?? "").contains { char in !char.isWhitespace } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if usesLine {
                        LineCardPreview(values: values, theme: options.theme)
                    }
                    TextBlock(label: "標題", limit: 80, required: true, value: bind("title"), placeholder: "例如：中秋禮盒 3 盒 9 折")
                    TextBlock(label: "說明", help: usesLine ? "LINE 卡片上的內容" : "只發簡訊時不會用到（簡訊內容在下面）", limit: 500, required: usesLine, multiline: true, value: bind("body"), placeholder: "優惠內容、期限、怎麼用")
                    PromoCouponPicker(coupons: options.coupons, selection: selection("couponCode"))
                    if usesLine {
                        PromoImagePicker(products: options.products, selection: selection("imageUrl"))
                        TextBlock(label: "按鈕文字", limit: 20, value: bind("buttonLabel"))
                        TextBlock(label: "按鈕連結", help: "站內路徑（/zh/shop）或 https:// 網址", value: bind("buttonUrl"), kind: .url)
                    }
                    audiencePicker
                    channelPicker
                    if usesSMS {
                        smsSection
                    }
                    summary
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { Theme.sheet.ignoresSafeArea() }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationTitle("發送優惠")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .interactiveDismissDisabled(hasContent)
            .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
                model.show("開始發了：\(result["people"]?.int ?? people) 人")
                onSent()
                dismiss()
            }
            .task { options = await PromoOptions.load(model, site: site) }
            // 改了什麼就重新試算：停手一下才算，又改了就作廢這一次
            .task(id: draft) {
                if preview != nil { try? await Task.sleep(for: .milliseconds(700)) }
                guard !Task.isCancelled else { return }
                await refreshPreview(draft)
            }
            .onChange(of: audience) { old, new in
                // 「所有 LINE 好友」只能用 LINE 發；換回會員就回到網站的預設
                if new == .all { picked = .line } else if old == .all { picked = nil }
                if new == .bought, productID == nil { productID = options.products.first?.id }
            }
        }
    }

    private func bind(_ key: String) -> Binding<JSONValue> {
        Binding(get: { values[key] ?? .null }, set: { values[key] = $0 })
    }

    private func selection(_ key: String) -> Binding<String?> {
        Binding(get: { values[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }, set: { values[key] = $0.map(JSONValue.string) })
    }

    /// 簡訊內容：沒改過顯示網站組的那一則，一改就變成自己的
    private var smsText: Binding<JSONValue> {
        Binding(
            get: { smsEdited ? (values["smsText"] ?? .null) : (preview?["sms"]?["text"] ?? .null) },
            set: {
                smsEdited = true
                values["smsText"] = $0
            }
        )
    }

    // MARK: 對象、管道、簡訊

    private var audiencePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("發給誰")
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            FilterBar(items: lineConfigured ? [LineAudience.members, .inactive, .bought, .all] : [.members, .inactive, .bought], selection: $audience, title: Self.audienceTitle)
            switch audience {
            case .inactive:
                InactiveDaysStepper(days: $days)
            case .bought:
                PromoProductMenu(products: options.products, selection: $productID)
            default:
                EmptyView()
            }
            Text("只會發給願意收的人：簡訊要同意接收行銷簡訊、手機驗證過；LINE 要還是好友、沒有取消訂閱。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
    }

    private static func audienceTitle(_ a: LineAudience) -> String {
        switch a {
        case .members: "所有會員"
        case .inactive: "很久沒買的"
        case .bought: "買過某個商品"
        case .all: "所有 LINE 好友"
        }
    }

    private var channelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("怎麼發")
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            ForEach(PromotionChannel.allCases, id: \.self) { c in
                channelChoice(c)
            }
            if !lineConfigured {
                Text("還沒有設定 LINE 官方帳號，現在只能發簡訊。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func channelChoice(_ c: PromotionChannel) -> some View {
        let off = (c.usesLine && !lineConfigured) || (audience == .all && c != .line)
        let on = channel == c
        return Button {
            withAnimation(Motion.ease) { picked = c }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .strokeBorder(on ? Theme.accent : Theme.line, lineWidth: on ? 6 : 1.5)
                    .frame(width: 20, height: 20)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(c.title)
                            .textRole(.h4)
                            .foregroundStyle(Theme.ink)
                        if c == .lineFirst, lineConfigured {
                            StatusBadge("建議", tone: .gold)
                        }
                    }
                    Text(c.hint)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(on ? Theme.accentSoft : Color.clear, in: .rect(cornerRadius: Metric.radiusSm))
            .overlay { RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(on ? Theme.accent : Theme.line, lineWidth: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .disabled(off)
        .opacity(off ? 0.45 : 1)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var smsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextBlock(
                label: "簡訊內容",
                help: smsEdited ? "自己改過了。" : "從標題、優惠碼自動帶入（說明放得進一則才放）。",
                limit: 500,
                multiline: true,
                value: smsText,
                placeholder: "先寫標題，這裡會自動帶入"
            )
            if smsEdited {
                Button("回到自動帶入") {
                    smsEdited = false
                    values["smsText"] = nil
                }
                .buttonStyle(.brand(.quiet, size: .sm))
            }
            if let sms = preview?["sms"], let full = sms["fullText"]?.string, !full.isEmpty {
                let segments = sms["segments"]?.int ?? 1
                VStack(alignment: .leading, spacing: 6) {
                    Text("客人收到的是")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                    Text(full)
                        .textRole(.small)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surface, in: .rect(cornerRadius: 14))
                    Text("\(sms["chars"]?.int ?? full.count) 字・每人 \(segments) 則\(segments > 1 ? "（改短一點可以省一半以上）" : "")")
                        .textRole(.xs)
                        .foregroundStyle(segments > 1 ? Theme.warningFG : Theme.muted)
                }
            }
            Text("簡訊照則數計費：70 字一則（含後面自動加的退訂說明），超過拆成每則 67 字。不能有網址、Email、電話（電信業者會擋）。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: 試算

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Eyebrow("發送前試算")
                if previewing { ProgressView().controlSize(.mini) }
            }
            if let p = preview {
                VStack(alignment: .leading, spacing: 2) {
                    Text([p["audienceLabel"]?.string, p["channelLabel"]?.string].compactMap { $0 }.joined(separator: "・"))
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                    Text("\(p["people"]?.int ?? 0) 人")
                        .textRole(.h3)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                }
                RuledList(color: Theme.hair) {
                    ForEach(summaryRows(p), id: \.label) { r in
                        HStack(alignment: .firstTextBaseline) {
                            Text(r.label)
                                .textRole(.small)
                                .foregroundStyle(Theme.ink2)
                            Spacer(minLength: 12)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(r.value)
                                    .textRole(.h4)
                                    .foregroundStyle(r.warn ? Theme.dangerFG : Theme.ink)
                                    .monospacedDigit()
                                if let sub = r.sub {
                                    Text(sub)
                                        .textRole(.xs)
                                        .foregroundStyle(r.warn ? Theme.dangerFG : Theme.muted)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
                if !problems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(problems, id: \.self) { problem in
                            HStack(alignment: .top, spacing: 8) {
                                HeroIcon("exclamation-triangle", size: 14)
                                    .padding(.top, 2)
                                Text(problem)
                                    .textRole(.small)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(Theme.dangerFG)
                        }
                    }
                }
            } else if previewError == nil {
                SkeletonRows(rows: 2)
            }
            // 試算沒成功（網路、網站）：按一下再算一次；舊的試算照樣留著看，但要算成功才能發
            if let previewError {
                ErrorNote(message: previewError) { Task { await refreshPreview(draft) } }
            }
        }
        .panel(padding: 16)
    }

    private struct SummaryRow {
        let label: String
        let value: String
        var sub: String?
        var warn = false
    }

    /// 每個管道幾位、簡訊計費則數與今天的額度、LINE 優先省下多少（和網站後台的試算一樣）
    private func summaryRows(_ p: JSONValue) -> [SummaryRow] {
        var rows: [SummaryRow] = []
        let line = p["line"] ?? .null
        let sms = p["sms"] ?? .null
        let smsRecipients = sms["recipients"]?.int ?? 0
        let segments = sms["segments"]?.int ?? 0
        if line["on"]?.bool == true {
            let configured = line["configured"]?.bool ?? false
            rows.append(SummaryRow(label: "LINE", value: "\(line["recipients"]?.int ?? 0) 人", sub: configured ? "每一則都算進官方帳號的每月訊息量" : "還沒有設定 LINE", warn: !configured))
        }
        if sms["on"]?.bool == true {
            rows.append(SummaryRow(label: "簡訊", value: "\(smsRecipients) 人", sub: smsRecipients > 0 ? "\(segments) 則 × \(smsRecipients) 人＝\(sms["billed"]?.int ?? 0) 則計費" : nil))
            if smsRecipients > 0 {
                let used = sms["usedToday"]?.int ?? 0
                let cap = sms["cap"]?.int ?? 0
                let after = sms["remainingToday"]?.int.map { $0 - smsRecipients }
                rows.append(SummaryRow(
                    label: "今天的簡訊額度",
                    value: cap > 0 ? "\(used) / \(cap)" : "已發 \(used)",
                    sub: after.map { $0 >= 0 ? "發完還剩 \($0) 則" : "不夠：還差 \(-$0) 則" } ?? "不限",
                    warn: (after ?? 0) < 0
                ))
            }
        }
        if let moved = p["movedToLine"]?.int, moved > 0 {
            rows.append(SummaryRow(label: "LINE 優先省下", value: "\(moved * max(1, segments)) 則簡訊", sub: "\(moved) 位會員改收 LINE"))
        }
        return rows
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 8) {
                    if busy || (previewing && !fresh) { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                    Text(canSend ? "發送給 \(people) 人" : "下一步")
                }
            }
            .buttonStyle(.brand(.accent, size: .md, fullWidth: true, arrow: true))
            .disabled(busy || !canSend)
            Text(footnote)
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(Theme.sheet)
    }

    private var footnote: String {
        if !fresh, !previewing, previewError != nil { return "試算沒有成功，算成功才能發（上面可以再算一次）。" }
        if fresh, let first = problems.first { return first }
        return "下一步會出網站的確認，要打「發送」才會發；發出去就收不回來。"
    }

    // MARK: 讀、送

    /// 給網站的內容（試算和發送同一份；簡訊沒改過就不帶，網站自己組）
    private var draft: [String: JSONValue] {
        var a: [String: JSONValue] = ["audience": audience.args(days: days, productID: productID)]
        if let picked { a["channel"] = .string(picked.rawValue) }
        for key in ["title", "body", "imageUrl", "couponCode", "buttonLabel", "buttonUrl"] {
            if let v = values[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { a[key] = .string(v) }
        }
        if smsEdited, let v = values["smsText"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            a["smsText"] = .string(v)
        }
        return a
    }

    private func refreshPreview(_ args: [String: JSONValue]) async {
        previewing = true
        defer { previewing = false }
        var a = args
        a["dryRun"] = true
        do {
            let r = try await model.api.tool("send_promotion", site: site, a)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.ease) {
                preview = r
                previewedFor = args
            }
            previewError = nil
        } catch {
            guard !Task.isCancelled else { return }
            previewError = error.localizedDescription
        }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        await proposeWrite(model, "send_promotion", site: site, draft, into: $proposal) {
            onSent()
            dismiss()
        }
    }
}

// MARK: - LINE 優惠推播（還沒有「發送優惠」的網站）

/// 寫一則 LINE 優惠推播：卡片的樣子（照網站的 LINE 卡片樣式）、對象、先看人數，下一步網站確認（要打「發送」）。
/// 網站有「發送優惠」（send_promotion）的話用 PromotionComposer（簡訊和 LINE 一起），這個是還沒有的網站用的
struct LineCampaignComposer: View {
    let site: String
    var onSent: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: JSONValue] = ["buttonLabel": "去看看", "buttonUrl": "/zh/shop"]
    @State private var audience: LineAudience = .all
    @State private var days = 90
    @State private var productID: String?
    @State private var options = PromoOptions()
    @State private var recipients: Int?
    @State private var counting = false
    @State private var proposal: Proposal?
    @State private var busy = false

    private var title: String { values["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var text: String { values["body"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var ready: Bool { !title.isEmpty && !text.isEmpty && (audience != .bought || productID != nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    LineCardPreview(values: values, theme: options.theme)
                    TextBlock(label: "標題", limit: 80, required: true, value: bind("title"), placeholder: "例如：中秋禮盒 3 盒 9 折")
                    TextBlock(label: "說明", limit: 500, required: true, multiline: true, value: bind("body"), placeholder: "優惠內容、期限、怎麼用")
                    PromoImagePicker(products: options.products, selection: selection("imageUrl"))
                    PromoCouponPicker(coupons: options.coupons, selection: selection("couponCode"))
                    TextBlock(label: "按鈕文字", limit: 20, value: bind("buttonLabel"))
                    TextBlock(label: "按鈕連結", help: "站內路徑（/zh/shop）或 https:// 網址", value: bind("buttonUrl"), kind: .url)
                    audiencePicker
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { Theme.sheet.ignoresSafeArea() }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationTitle("LINE 推播")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .interactiveDismissDisabled(!title.isEmpty || !text.isEmpty)
            .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
                model.show("開始傳了：\(result["recipients"]?.int ?? recipients ?? 0) 位")
                onSent()
                dismiss()
            }
            .task { options = await PromoOptions.load(model, site: site) }
            // 換了對象：人數重算
            .onChange(of: audienceArgs) { recipients = nil }
        }
    }

    private func bind(_ key: String) -> Binding<JSONValue> {
        Binding(get: { values[key] ?? .null }, set: { values[key] = $0 })
    }

    private func selection(_ key: String) -> Binding<String?> {
        Binding(get: { values[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }, set: { values[key] = $0.map(JSONValue.string) })
    }

    private var audiencePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("傳給誰")
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            FilterBar(items: [LineAudience.all, .members, .inactive, .bought], selection: $audience, title: \.title)
            switch audience {
            case .inactive:
                InactiveDaysStepper(days: $days)
            case .bought:
                PromoProductMenu(products: options.products, selection: $productID)
            default:
                EmptyView()
            }
            Text("還是好友、沒有取消訂閱的才收得到。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
    }

    private var audienceArgs: JSONValue { audience.args(days: days, productID: productID) }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { await count() }
                } label: {
                    HStack(spacing: 6) {
                        if counting { ProgressView().controlSize(.small) }
                        Text(recipients.map { "\($0) 位收得到" } ?? "看看幾位收得到")
                    }
                }
                .buttonStyle(.brand(.ghost, size: .md))
                .disabled(counting || (audience == .bought && productID == nil))
                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                        Text("下一步")
                    }
                }
                .buttonStyle(.brand(.accent, size: .md, fullWidth: true, arrow: true))
                .disabled(busy || !ready)
            }
            Text("下一步會出網站的確認，要打「發送」才會傳；傳出去就收不回來。")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
        .padding(20)
        .background(Theme.sheet)
    }

    // MARK: 送

    private func args(dryRun: Bool) -> [String: JSONValue] {
        var a: [String: JSONValue] = ["audience": audienceArgs]
        if dryRun {
            a["dryRun"] = true
            return a
        }
        for key in ["title", "body", "imageUrl", "couponCode", "buttonLabel", "buttonUrl"] {
            if let v = values[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { a[key] = .string(v) }
        }
        return a
    }

    private func count() async {
        counting = true
        defer { counting = false }
        do {
            let r = try await model.api.tool("send_line_campaign", site: site, args(dryRun: true))
            recipients = r["recipients"]?.int ?? 0
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        await proposeWrite(model, "send_line_campaign", site: site, args(dryRun: false), into: $proposal) {
            onSent()
            dismiss()
        }
    }
}

// MARK: - 寫優惠共用的欄位（發送優惠、LINE 推播）

/// 寫優惠要用到的：商品（大圖、「買過某個商品」）、啟用中的折價券、網站的 LINE 卡片樣式
private struct PromoOptions {
    var products: [RecordSummary] = []
    var coupons: [RecordSummary] = []
    var theme: JSONValue?

    static func load(_ model: AppModel, site: String) async -> PromoOptions {
        var o = PromoOptions()
        o.products = (try? await model.api.list(site: site, entity: "product", filters: ["publishedOnly": true, "limit": 100]))?.rows ?? []
        o.coupons = (try? await model.api.list(site: site, entity: "coupon", filters: ["activeOnly": true, "limit": 50]))?.rows ?? []
        o.theme = try? await model.api.get(site: site, entity: "line_theme", id: nil)
        return o
    }

    /// 能附在優惠上的券：通用（沒指定會員）、沒過期、還沒用完（網站只收這種，打別的會被擋）
    static func promoCodes(_ coupons: [RecordSummary]) -> [String] {
        coupons.compactMap { c -> String? in
            let r = c.raw
            guard let code = r["code"]?.string, !code.isEmpty else { return nil }
            if let email = r["assignedUserEmail"]?.string, !email.isEmpty { return nil }
            if let expires = r["expiresAt"]?.date, expires < .now { return nil }
            if let limit = r["usageLimit"]?.int, let used = r["usageCount"]?.int, used >= limit { return nil }
            return code
        }
    }
}

extension LineAudience {
    /// 網站的 audience 參數
    func args(days: Int, productID: String?) -> JSONValue {
        switch self {
        case .all: ["kind": "all"]
        case .members: ["kind": "members"]
        case .inactive: ["kind": "inactive", "days": .number(Double(days))]
        case .bought: ["kind": "bought", "productId": productID.map(JSONValue.string) ?? .null]
        }
    }
}

/// 大圖：從商品的照片選一張（或不放）
private struct PromoImagePicker: View {
    let products: [RecordSummary]
    @Binding var selection: String?

    var body: some View {
        let withImages = products.filter { $0.image != nil }
        if !withImages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("LINE 大圖（選填）")
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        choice(nil)
                        ForEach(withImages.prefix(24), id: \.id) { p in choice(p.image) }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    private func choice(_ url: URL?) -> some View {
        let on = selection == url?.absoluteString
        return Button {
            selection = url?.absoluteString
        } label: {
            Group {
                if let url {
                    RemoteImage(url: url, aspect: 1, radius: 0)
                } else {
                    Text("不放").textRole(.xs).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 72, height: 72)
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: Metric.radiusSm))
            .overlay { RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(on ? Theme.accent : Theme.line, lineWidth: on ? 2 : 1) }
        }
        .buttonStyle(.press)
        .accessibilityLabel(url == nil ? "不放大圖" : "用這張商品照片")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 優惠碼：從能附的折價券選（網站只收通用、啟用中、沒過期、還沒用完的券，打別的會被擋）
private struct PromoCouponPicker: View {
    let coupons: [RecordSummary]
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("優惠碼（選填）")
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            let codes = PromoOptions.promoCodes(coupons)
            if codes.isEmpty {
                Text("沒有可以附的通用折價券（要啟用中、沒過期、沒有指定會員）。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            } else {
                FlowLayout(spacing: 6) {
                    FilterChip(title: "不附", selected: selection == nil) { selection = nil }
                    ForEach(codes.prefix(12), id: \.self) { code in
                        FilterChip(title: code, selected: selection == code) { selection = code }
                    }
                }
            }
        }
    }
}

/// 「買過某個商品」：選商品
private struct PromoProductMenu: View {
    let products: [RecordSummary]
    @Binding var selection: String?

    var body: some View {
        Menu {
            ForEach(products.prefix(60), id: \.id) { p in
                Button(p.title) { selection = p.id }
            }
        } label: {
            HStack {
                Text(products.first { $0.id == selection }?.title ?? "選一個商品")
                    .textRole(.small)
                    .foregroundStyle(selection == nil ? Theme.muted : Theme.ink)
                Spacer()
                HeroIcon("chevron-down", size: 12).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rule() }
        }
    }
}

/// 「很久沒買的」：幾天沒買（7～730 天）
private struct InactiveDaysStepper: View {
    @Binding var days: Int

    var body: some View {
        Stepper(value: $days, in: 7...730, step: days < 60 ? 7 : 30) {
            Text("\(days) 天沒買的會員").textRole(.small).foregroundStyle(Theme.ink)
        }
    }
}

/// LINE 卡片的樣子（照網站的 LINE 卡片樣式：主色按鈕、強調色的優惠碼）
private struct LineCardPreview: View {
    let values: [String: JSONValue]
    let theme: JSONValue?

    var body: some View {
        let primary = theme?["primary"]?.string.flatMap(Color.init(hexString:)) ?? Theme.accent
        let accent = theme?["accent"]?.string.flatMap(Color.init(hexString:)) ?? Theme.accent
        let ink = theme?["text"]?.string.flatMap(Color.init(hexString:)) ?? Color(white: 0.1)
        VStack(alignment: .leading, spacing: 0) {
            if let url = values["imageUrl"]?.string.flatMap(URL.init(string:)) {
                // LINE 卡片的大圖是 20:13
                RemoteImage(url: url, aspect: 20 / 13, radius: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let name = theme?["name"]?.string, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.6))
                }
                Text(values["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "標題")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ink)
                Text(values["body"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "說明會出現在這裡")
                    .font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.8))
                    .lineLimit(5)
                if let code = values["couponCode"]?.string, !code.isEmpty {
                    Text("優惠碼 \(code)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                }
                if let label = values["buttonLabel"]?.string, !label.isEmpty, values["buttonUrl"]?.string?.isEmpty == false {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(primary, in: .rect(cornerRadius: 8))
                        .padding(.top, 6)
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.black.opacity(0.08)) }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(red: 0.55, green: 0.67, blue: 0.79).opacity(0.35), in: .rect(cornerRadius: Metric.radius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LINE 卡片預覽")
    }
}
