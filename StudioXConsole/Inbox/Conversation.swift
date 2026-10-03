import AVKit
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Xena 的客服對話

/// 網站上 Xena 的客服對話：官網右下角的 Xena，或網站的 LINE 官方帳號。
/// 版面照聊天 App：客人在左（頭像、白泡泡），我們在右（Xena 是彩虹細框、專人是品牌色）；
/// 同一個人連著說的合成一組、跨天放日期；上方是客人與狀態（右邊一顆主要動作），下方回覆。
/// 照片點開全螢幕（可以放大、分享），語音、影片直接播；專人附的卡片、Xena 帶客人去的頁面照客人看到的畫。
/// 網站有 reply_xena 就能在這裡回覆、接手、交給 Xena 繼續回答、結案；沒有的網站（還沒更新的）照舊到後台處理。
struct XenaConversationView: View {
    let site: String
    let conversationID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var detail: XenaConversationDetail?
    @State private var error: String?
    @State private var draft = ""
    /// 送出中的回覆：先畫出來，網站回來再換成真的
    @State private var pending: String?
    @State private var proposal: Proposal?
    @State private var replying = false
    @State private var working = false
    @State private var viewing: ViewedMedia?
    /// 照片從縮圖放大成全螢幕（iOS 的 zoom 轉場）
    @Namespace private var mediaSpace
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true
    /// 捲在上面時進來的新訊息
    @State private var unseen = 0
    /// 回覆裡附的照片、檔案、卡片、商品（輸入框上面一排）
    @State private var extras = ReplyExtras()
    /// Xena 正在擬回覆／潤飾
    @State private var drafting = false
    /// 「＋」選單，和它打開的東西
    @State private var showTools = false
    @State private var pendingTool: ReplyTool?
    @State private var replySheet: ReplySheet?
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var pickingOrder = false
    @State private var showMember = false
    /// 這個網站有哪些資料（有折價券、商品、會員才放那幾格）
    @State private var entities: Set<String> = []

    /// 這個網站能在 App 裡回覆、接手
    private var desk: Bool { model.site(site)?.hasXenaDesk ?? false }
    private var status: String? { detail?.status }
    private var siteName: String { model.site(site)?.name ?? site }
    private var who: String { detail?.who ?? (detail?.channel == .line ? "LINE 好友" : "網站訪客") }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let d = detail {
                    ConversationIntro(detail: d, siteName: siteName, site: site)
                        .padding(.bottom, 8)
                    timeline(d)
                    if let pending {
                        PendingReply(text: pending)
                            .padding(.top, 14)
                    }
                    if !desk, let admin = d.adminURL ?? model.site(site)?.adminURL {
                        Button { openURL(admin) } label: { Text("這個網站要到後台回覆 ↗") }
                            .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
                            .padding(.top, 24)
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    SkeletonRows(rows: 5)
                }
            }
            .frame(maxWidth: Metric.readable)
            .pageWidth()
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .scrollPosition($position)
        // 打開時在最新的一句；在最下面時內容變多（載入、照片撐開、新訊息）也貼著底部，捲上去看舊的就不動
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(atBottom ? .bottom : nil, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { g in
            // 看得到的範圍（內容的座標）碰到最後 100 點就算在最下面
            g.visibleRect.maxY >= g.contentSize.height - 100
        } action: { _, bottom in
            atBottom = bottom
            if bottom { unseen = 0 }
        }
        .refreshable { await load() }
        .brandPage()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if desk, detail != nil { composer }
        }
        // 聊天畫面：手機上收起底部的分頁列，留給回覆
        .toolbar(sizeClass == .regular ? .automatic : .hidden, for: .tabBar)
        .navigationTitle(who)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task { await load() }
        // 開著的時候每 15 秒看一次有沒有新訊息（客人在 LINE 或網站上又說話了）
        .task(id: conversationID) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                await load(quiet: true)
            }
        }
        .onChange(of: detail?.messages.count ?? 0) { old, new in
            guard new > old else { return }
            if old == 0 {
                // 剛載入：等這一輪排版好再到最底（不要動畫）
                Task {
                    await Task.yield()
                    position.scrollTo(edge: .bottom)
                }
            } else if atBottom || detail?.messages.last?.role == "staff" {
                // 在最下面、或是自己剛送出的：跟著捲到最新
                withAnimation(Motion.ease) { position.scrollTo(edge: .bottom) }
            } else {
                // 捲在上面看舊的就不打斷，右下角提示
                unseen += new - old
            }
        }
        .onAppear { model.openChats += 1 }
        .onDisappear { model.openChats = max(0, model.openChats - 1) }
        .fullScreenCover(item: $viewing) { media in
            MediaViewer(media: media)
                .navigationTransition(.zoom(sourceID: media.url, in: mediaSpace))
        }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            if replying { announceReply(result) } else { model.show("已更新") }
            replying = false
            Task {
                await load()
                await model.refreshAll()
            }
        }
        // 「＋」選單：選了之後選單先收起來，再打開要用的東西（相簿、相機、檔案、折價券…）
        .sheet(isPresented: $showTools, onDismiss: runTool) {
            ReplyMenuSheet(options: toolOptions) { tool in
                pendingTool = tool
                showTools = false
            }
        }
        .sheet(item: $replySheet) { sheet in replySheetView(sheet) }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: max(1, room), matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await stagePhotos(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: ReplyMedia.fileTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { stageFiles(urls) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { Task { await stageCamera(image) } }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("附上哪一筆訂單的進度？", isPresented: $pickingOrder, titleVisibility: .visible) {
            ForEach(detail?.orders ?? []) { order in
                Button("#\(order.number)・\(order.statusLabel)") { Task { await insertTrack(order) } }
            }
        }
        .navigationDestination(isPresented: $showMember) {
            if let id = detail?.memberID { MemberView(site: site, memberID: id) }
        }
        .task {
            if let schema = await model.schema(for: site) {
                entities = Set(schema.entities.filter(\.canList).map(\.key))
            }
            // UI 截圖（-demoTools YES）：打開「＋」選單
            if DemoServer.screenshots, UserDefaults.standard.bool(forKey: "demoTools") {
                try? await Task.sleep(for: .seconds(1.5))
                showTools = true
            }
        }
    }

    // MARK: 對話

    @ViewBuilder
    private func timeline(_ d: XenaConversationDetail) -> some View {
        // 轉真人的原因放在最後一次「通知專人」的事件下面
        let lastHandoff = d.messages.last { $0.role == "event" && ChatEventRow.kind(of: $0) == "handoff" }?.id
        let flagged = Self.jevFlags(d.messages)
        ForEach(ChatEntry.build(d.messages)) { entry in
            switch entry {
            case .time(_, let date):
                ChatTimeHeader(date: date)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
            case .event(let m):
                ChatEventRow(message: m, reason: m.id == lastHandoff ? d.handoffReason : nil)
                    .padding(.vertical, 8)
            case .message(let m, let first, let last):
                XenaChatRow(
                    message: m, first: first, last: last, jevFlag: flagged[m.id],
                    site: site, siteURL: model.site(site)?.url, space: mediaSpace
                ) { viewing = $0 }
                .padding(.top, first ? 10 : 2)
            }
        }
    }

    /// 「Jev 判斷要找人」標在客人連續幾句的最後一句下面（一組只標一次，機率取最高的），不把一組泡泡切開
    private static func jevFlags(_ messages: [XenaConversationMessage]) -> [Int: Double] {
        var out: [Int: Double] = [:]
        var run: [XenaConversationMessage] = []
        func close() {
            let flagged = run.compactMap { $0.jevHuman }.filter { $0.yes }
            if let last = run.last, let top = flagged.map { $0.confidence }.max() { out[last.id] = top }
            run = []
        }
        for m in messages {
            if m.role == "user" { run.append(m) } else { close() }
        }
        close()
        return out
    }

    // MARK: 上方：客人、狀態、主要動作

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) { title }
        if desk, let action = primaryAction {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action.label) { act(action.id) }
                    .font(.brand(14, .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .disabled(working || detail == nil)
            }
        }
        ToolbarItem(placement: .topBarTrailing) { menu }
    }

    private var title: some View {
        HStack(spacing: 9) {
            Avatar(name: who, imageURL: detail?.picture, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(who)
                    .font(.brand(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let detail {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        HStack(spacing: 5) {
                            Circle().fill(statusTone.dot).frame(width: 6, height: 6)
                            Text("\(detail.channel.label)・\(statusText)")
                                .lineLimit(1)
                        }
                        .font(.brand(11.5, .medium, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch status {
        case "waiting":
            if let at = detail?.handoffAt { return "等專人 \(waited(since: at))" }
            return "等專人"
        case "human": return "\(assigneeLabel)接手中"
        case "closed": return "已結案"
        case "ai": return "Xena 回答中"
        default: return status.map(XenaConversationSummary.label) ?? "Xena 客服"
        }
    }

    private var statusTone: Tone { status.map(XenaConversationSummary.tone) ?? .neutral }

    /// 誰接手：自己就說「你」；網站給的是 Email（atelier-cms）就不顯示地址
    private var assigneeLabel: String {
        guard let a = detail?.assignee, !a.isEmpty else { return "專人" }
        if let me = model.me, a.caseInsensitiveCompare(me.email) == .orderedSame || a == me.name { return "你" }
        return a.contains("@") ? "專人" : a
    }

    private func waited(since date: Date) -> String {
        let s = max(0, Date.now.timeIntervalSince(date))
        if s < 60 { return "剛剛" }
        if s < 3600 { return "\(Int(s / 60)) 分鐘" }
        if s < 86400 { return "\(Int(s / 3600)) 小時" }
        return "\(Int(s / 86400)) 天"
    }

    private var primaryAction: (id: String, label: String)? {
        switch status {
        case "ai", "waiting": (id: "takeover", label: "接手")
        case "human": (id: "release", label: "交給 Xena")
        case "closed": (id: "reopen", label: "重新開啟")
        default: nil
        }
    }

    @ViewBuilder
    private var menu: some View {
        Menu {
            if desk, let status {
                if status == "ai" || status == "waiting" {
                    Button("接手（Xena 先停止回答）", systemImage: "hand.raised") { act("takeover") }
                }
                if status == "human" || status == "waiting" {
                    Button("交給 Xena 繼續回答", systemImage: "sparkles") { act("release") }
                }
                if status != "closed" {
                    Button("結案", systemImage: "checkmark.circle") { act("close") }
                } else {
                    Button("重新開啟", systemImage: "arrow.uturn.backward.circle") { act("reopen") }
                }
            }
            if desk, status != "closed" {
                Button("請 Xena 擬回覆", systemImage: "sparkles") { xenaWrite(polish: false) }
            }
            Button("跟 Xena 討論這段對話", systemImage: "bubble.left.and.text.bubble.right") { askXenaForDraft() }
            if let url = detail?.adminURL ?? model.site(site)?.adminURL {
                Button("在後台打開", systemImage: "arrow.up.right.square") { openURL(url) }
            }
        } label: { HeroIcon("ellipsis-horizontal") }
    }

    private func act(_ action: String) {
        Task { await propose { try await model.api.proposeXena(site: site, id: conversationID, action: action) } }
    }

    private func askXenaForDraft() {
        let from = detail?.channel == .line ? "LINE 上" : "官網上"
        model.askXena("幫我看\(siteName)\(from)這段 Xena 客服對話（\(conversationID)），我想跟你討論怎麼回覆")
    }

    // MARK: 下方：回覆

    @ViewBuilder
    private var composer: some View {
        if status == "closed" {
            HStack(spacing: 12) {
                Text("已結案。客人再開口會回到 Xena。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                Button("重新開啟") { act("reopen") }
                    .buttonStyle(.brand(.ghost, size: .sm))
                    .disabled(working)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.sheet)
            .overlay(alignment: .top) { Rule() }
        } else {
            ChatComposer(
                text: $draft,
                placeholder: drafting ? "Xena 正在寫…" : status == "human" ? "回覆客人…" : "回覆客人（送出就由你接手）",
                hint: detail?.replyGoesTo ?? detail?.channel.replyHint,
                hintWarning: detail?.lineBlocked == true,
                sending: pending != nil,
                plus: { showTools = true },
                canSendEmpty: !extras.isEmpty,
                sendBlocked: extras.uploading || drafting,
                send: send
            ) {
                ReplyAccessory(
                    extras: $extras,
                    drafting: drafting,
                    retry: upload,
                    editCard: { replySheet = .card },
                    editProducts: { replySheet = .products }
                )
            }
            .overlay(alignment: .topTrailing) {
                if !atBottom {
                    JumpToLatest(count: unseen) {
                        withAnimation(Motion.ease) { position.scrollTo(edge: .bottom) }
                    }
                    .padding(.trailing, 16)
                    .offset(y: -54)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(Motion.fast, value: atBottom)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pending == nil, !text.isEmpty || !extras.isEmpty else { return }
        if extras.uploading {
            model.show("照片、檔案還在上傳，等一下下", tone: .warning)
            return
        }
        if extras.failed {
            model.show("有附件沒傳上去：點一下重試，或拿掉再送", tone: .warning)
            return
        }
        let staged = extras
        pending = text.isEmpty ? "📎 \(staged.summary)" : text
        draft = ""
        extras = ReplyExtras()
        withAnimation(Motion.ease) { position.scrollTo(edge: .bottom) }
        Task {
            let sent = await propose(reply: true) {
                try await model.api.proposeXenaReply(
                    site: site, id: conversationID, text: text,
                    attachments: staged.uploaded, card: staged.card, products: staged.products.map(\.id)
                )
            }
            // 沒送出（出錯、要另外確認）：字和附的東西放回去，不會不見
            if !sent {
                if draft.isEmpty { draft = text }
                if extras.isEmpty { extras = staged }
            }
            pending = nil
        }
    }

    // MARK: 「＋」選單

    /// 還能附幾個照片、檔案
    private var room: Int { (detail?.attach?.max ?? 4) - extras.files.count }

    private var toolOptions: ReplyMenuOptions {
        let replyWith = detail?.replyWith ?? ["card"]
        return ReplyMenuOptions(
            hasDraft: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            canRelease: status == "human" || status == "waiting",
            attach: replyWith.contains("attachments") ? detail?.attach : nil,
            room: room,
            coupons: entities.contains("coupon") && replyWith.contains("card"),
            issueCoupon: detail?.memberID != nil && model.site(site)?.tools.contains("issue_coupons") == true,
            products: replyWith.contains("products") && entities.contains("product"),
            card: replyWith.contains("card"),
            orders: !(detail?.orders.isEmpty ?? true),
            member: detail?.memberID != nil && entities.contains("user")
        )
    }

    /// 選單收起來之後才打開選的那一個（同一時間只能有一個畫面蓋上來）
    private func runTool() {
        guard let tool = pendingTool else { return }
        pendingTool = nil
        switch tool {
        case .xenaDraft: xenaWrite(polish: false)
        case .xenaPolish: xenaWrite(polish: true)
        case .release: act("release")
        case .photos: showPhotos = true
        case .camera: showCamera = true
        case .files: showFiles = true
        case .coupon: replySheet = .coupons
        case .issueCoupon: replySheet = .issue
        case .products: replySheet = .products
        case .card: replySheet = .card
        case .saved: replySheet = .saved
        case .track:
            let orders = detail?.orders ?? []
            if orders.count == 1, let order = orders.first {
                Task { await insertTrack(order) }
            } else {
                pickingOrder = true
            }
        case .member: showMember = true
        }
    }

    @ViewBuilder
    private func replySheetView(_ sheet: ReplySheet) -> some View {
        switch sheet {
        case .coupons:
            CouponPickerSheet(site: site) { extras.card = $0 }
        case .issue:
            IssueCouponSheet(site: site, userIDs: [detail?.memberID].compactMap { $0 }, to: who) { codes in
                guard let code = codes.first else { return }
                extras.card = StaffCard(title: "給你的專屬優惠", body: "結帳時輸入優惠碼就能使用。", couponCode: code, buttonLabel: "去逛逛", url: model.site(site)?.url)
                model.show("折價券發好了，已經附在回覆裡（點卡片可以改）")
            }
        case .products:
            ProductPickerSheet(site: site, initial: extras.products) { extras.products = $0 }
        case .card:
            CardEditorSheet(initial: extras.card, siteURL: model.site(site)?.url) { extras.card = $0 }
        case .saved:
            SavedRepliesSheet(current: draft) { insertText($0) }
        }
    }

    /// 放進輸入框：原本有字就接在後面
    private func insertText(_ text: String) {
        let current = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = current.isEmpty ? text : current + "\n" + text
    }

    /// Xena 讀整段對話擬一段回覆（輸入框有字就當重點），或潤飾輸入框裡的那段；放進輸入框，不會自己送出
    private func xenaWrite(polish: Bool) {
        guard !drafting else { return }
        let input = draft
        drafting = true
        Task {
            defer { drafting = false }
            do {
                let text = try await model.api.replyDraft(site: site, id: conversationID, polish: polish, text: input)
                withAnimation(Motion.ease) {
                    // 寫的時候又打了字：接在後面，不蓋掉
                    draft = draft == input ? text : draft + "\n\n" + text
                }
            } catch {
                model.show(error.localizedDescription, tone: .danger)
            }
        }
    }

    /// 訂單的進度和追蹤頁（客人不用登入就看得到）放進輸入框
    private func insertTrack(_ order: CustomerOrder) async {
        do {
            let o = try await model.api.order(site: site, id: order.id)
            let state = o.summary.status.label
            if let url = o.trackURL {
                insertText("你的訂單 #\(order.number) 目前是「\(state)」，最新進度可以在這裡看：\(url.absoluteString)")
            } else {
                insertText("你的訂單 #\(order.number) 目前是「\(state)」。")
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    // MARK: 照片、檔案（一選就開始傳到網站）

    private func stagePhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self) else {
                model.show("有一張照片讀不到", tone: .warning)
                continue
            }
            await stageImage(raw, name: "photo.jpg")
        }
    }

    private func stageCamera(_ image: UIImage) async {
        guard let raw = image.jpegData(compressionQuality: 0.95) else { return }
        await stageImage(raw, name: "photo.jpg")
    }

    /// 照片轉成 JPEG、壓到網站的上限以內（LINE 的預覽圖最多 1MB），再開始傳
    private func stageImage(_ raw: Data, name: String) async {
        guard room > 0 else {
            model.show("一次最多附 \(detail?.attach?.max ?? 4) 個", tone: .warning)
            return
        }
        let limit = detail?.attach?.imageBytes ?? 1_048_576
        let jpeg = await Task.detached(priority: .userInitiated) { ReplyMedia.jpeg(from: raw, limit: limit) }.value
        guard let jpeg else {
            model.show("這張照片轉不過來，換一張試試", tone: .warning)
            return
        }
        let base = (name as NSString).deletingPathExtension
        let file = StagedFile(
            name: "\(base.isEmpty ? "photo" : base).jpg",
            mime: "image/jpeg",
            data: jpeg,
            thumbnail: UIImage(data: jpeg)?.preparingThumbnail(of: CGSize(width: 160, height: 160))
        )
        withAnimation(Motion.fast) { extras.files.append(file) }
        upload(file.id)
    }

    private func stageFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                model.show("讀不到「\(url.lastPathComponent)」", tone: .warning)
                continue
            }
            let mime = ReplyMedia.mime(for: url)
            // 從檔案選的照片（HEIC、PNG…）也轉成 JPEG，LINE 上才是一張照片
            if mime.hasPrefix("image/") {
                let name = url.lastPathComponent
                Task { await stageImage(data, name: name) }
                continue
            }
            guard room > 0 else {
                model.show("一次最多附 \(detail?.attach?.max ?? 4) 個", tone: .warning)
                break
            }
            let limit = detail?.attach?.fileBytes ?? 20_971_520
            guard data.count <= limit else {
                model.show("「\(url.lastPathComponent)」太大了（最多 \(ReplyMedia.size(limit))）", tone: .warning)
                continue
            }
            let file = StagedFile(name: url.lastPathComponent, mime: mime, data: data)
            withAnimation(Motion.fast) { extras.files.append(file) }
            upload(file.id)
        }
    }

    /// 傳到網站：先拿一次性上傳連結（reply_xena 的 attach），再把檔案送過去；失敗的點一下重試
    private func upload(_ id: StagedFile.ID) {
        guard let i = extras.files.firstIndex(where: { $0.id == id }) else { return }
        extras.files[i].state = .uploading
        let file = extras.files[i]
        Task {
            do {
                let link = try await model.api.xenaAttachLink(site: site, id: conversationID, name: file.name, mime: file.mime, size: file.data.count)
                let uploaded = try await model.api.uploadAttachment(to: link, data: file.data, mime: file.mime, filename: file.name)
                setState(id, .ready(uploaded))
            } catch {
                setState(id, .failed(error.localizedDescription))
            }
        }
    }

    private func setState(_ id: StagedFile.ID, _ state: StagedFile.State) {
        // 傳的時候拿掉了就不管它
        guard let i = extras.files.firstIndex(where: { $0.id == id }) else { return }
        extras.files[i].state = state
    }

    private func load(quiet: Bool = false) async {
        do {
            detail = try await model.api.xenaConversation(site: site, id: conversationID)
            error = nil
        } catch {
            if !quiet { self.error = error.localizedDescription }
        }
    }

    /// 回覆送出了：照網站回報的說有沒有真的傳到客人的 LINE、有沒有寄信（沒傳到要讓專人知道）
    private func announceReply(_ result: JSONValue) {
        draft = ""
        extras = ReplyExtras()
        if result["lineSent"]?.bool == false {
            model.show("回覆存下來了，但沒有傳到客人的 LINE（可能封鎖了官方帳號，或本月訊息量用完）", tone: .warning)
        } else if let error = result["emailError"]?.string, !error.isEmpty {
            model.show("回覆已送出，但通知信沒寄出：\(error)", tone: .warning)
        } else if result["lineSent"]?.bool == true {
            model.show("已傳到客人的 LINE")
        } else {
            model.show(result["emailed"]?.bool == true ? "已送出回覆，也寄信通知客人" : "已送出回覆")
        }
    }

    /// 回傳 true：回覆已經送出（不用再確認）
    @discardableResult
    private func propose(reply: Bool = false, _ make: () async throws -> ConsoleAPI.WriteOutcome) async -> Bool {
        working = true
        defer { working = false }
        do {
            switch try await make() {
            case .needsConfirmation(let p):
                // 送出回覆：按「送出」就是確認了，不再跳一次確認（接手、結案這些動作照樣確認）
                if reply, p.typed == nil, !p.danger {
                    switch try await model.api.confirm(p, typed: nil) {
                    case .done(let result):
                        announceReply(result)
                        await load()
                        Task { await model.refreshAll() }
                        return true
                    case .needsOwner(let next):
                        replying = true
                        proposal = next
                        return false
                    }
                }
                replying = reply
                proposal = p
                return false
            case .done:
                if reply { draft = "" }
                model.show("已更新")
                await load()
                return true
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
            return false
        }
    }
}

// MARK: - 對話的一列一列

/// 對話排成一列一列（照 iMessage）：隔了 15 分鐘以上或跨天放一行時間；同一個人連著說的合成一組，
/// 組的最後一個泡泡有小尾巴；我們這邊換人說話時（Xena ↔ 專人）在第一個泡泡上面寫是誰
enum ChatEntry: Identifiable {
    case time(id: Int, Date)
    case event(XenaConversationMessage)
    case message(XenaConversationMessage, first: Bool, last: Bool)

    var id: String {
        switch self {
        case .time(let id, _): "t-\(id)"
        case .event(let m), .message(let m, _, _): "m-\(m.id)"
        }
    }

    /// 隔多久要再放一行時間
    static let gap: TimeInterval = 15 * 60

    /// 這一則前面要不要放時間（第一則、跨天、隔了 15 分鐘以上）
    static func needsTime(_ at: Date?, after previous: Date?) -> Bool {
        guard let at else { return false }
        guard let previous else { return true }
        return !Calendar.taipei.isDate(previous, inSameDayAs: at) || at.timeIntervalSince(previous) >= gap
    }

    static func build(_ messages: [XenaConversationMessage]) -> [ChatEntry] {
        var headers: [Bool] = []
        var lastAt: Date?
        for m in messages {
            headers.append(needsTime(m.at, after: lastAt))
            if let at = m.at { lastAt = at }
        }
        var out: [ChatEntry] = []
        for (i, m) in messages.enumerated() {
            if headers[i], let at = m.at { out.append(.time(id: m.id, at)) }
            if m.role == "event" {
                out.append(.event(m))
                continue
            }
            let previous = i > 0 ? messages[i - 1] : nil
            let next = i + 1 < messages.count ? messages[i + 1] : nil
            let first = headers[i] || !sameSender(previous, m)
            let last = next == nil || headers[i + 1] || !sameSender(m, next)
            out.append(.message(m, first: first, last: last))
        }
        return out
    }

    private static func sameSender(_ a: XenaConversationMessage?, _ b: XenaConversationMessage?) -> Bool {
        guard let a, let b, a.role == b.role, a.role != "event" else { return false }
        return a.role == "user" || a.author == b.author
    }
}

/// 泡泡的形狀（iMessage）：圓角 18；組的最後一個在說話的人那一側下角有小尾巴（尾巴佔 4 點寬，沒有尾巴的也留著，泡泡才對齊）
struct ChatBubbleShape: Shape {
    var mine: Bool
    var tail: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        if tail {
            // 先畫我們這邊（尾巴在右下），客人的再左右翻過來
            p.move(to: CGPoint(x: 20, y: h))
            p.addCurve(to: CGPoint(x: 0, y: h - 20), control1: CGPoint(x: 8, y: h), control2: CGPoint(x: 0, y: h - 8))
            p.addLine(to: CGPoint(x: 0, y: 20))
            p.addCurve(to: CGPoint(x: 20, y: 0), control1: CGPoint(x: 0, y: 8), control2: CGPoint(x: 8, y: 0))
            p.addLine(to: CGPoint(x: w - 21, y: 0))
            p.addCurve(to: CGPoint(x: w - 4, y: 20), control1: CGPoint(x: w - 12, y: 0), control2: CGPoint(x: w - 4, y: 8))
            p.addLine(to: CGPoint(x: w - 4, y: h - 11))
            p.addCurve(to: CGPoint(x: w, y: h), control1: CGPoint(x: w - 4, y: h - 1), control2: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: w + 0.05, y: h - 0.01))
            p.addCurve(to: CGPoint(x: w - 11, y: h - 4), control1: CGPoint(x: w - 4, y: h + 0.5), control2: CGPoint(x: w - 8, y: h - 1))
            p.addCurve(to: CGPoint(x: w - 25, y: h), control1: CGPoint(x: w - 16, y: h), control2: CGPoint(x: w - 20, y: h))
            p.closeSubpath()
        } else {
            p.addRoundedRect(in: CGRect(x: 0, y: 0, width: max(w - 4, 0), height: h), cornerSize: CGSize(width: 18, height: 18), style: .continuous)
        }
        if !mine {
            p = p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
        }
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// 泡泡是誰的：客人的灰底黑字；Xena 紫底白字、專人品牌橘白字（連結也是白的、加底線）
enum ChatBubbleKind {
    case customer, xena, staff

    var mine: Bool { self != .customer }

    var fill: Color {
        switch self {
        case .customer: Theme.bubbleIn
        case .xena: Theme.bubbleXena
        case .staff: Theme.bubbleStaff
        }
    }

    var text: Color { mine ? .white : Theme.ink }
    var link: Color { mine ? .white : Theme.accentText }
}

/// 一個泡泡（iMessage）
struct ChatBubble<Content: View>: View {
    let kind: ChatBubbleKind
    let tail: Bool
    let content: Content

    init(_ kind: ChatBubbleKind, tail: Bool = true, @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.tail = tail
        self.content = content()
    }

    var body: some View {
        content
            .font(.body)
            .foregroundStyle(kind.text)
            .tint(kind.link)
            .padding(.vertical, 9)
            .padding(.leading, kind.mine ? 13 : 17)
            .padding(.trailing, kind.mine ? 17 : 13)
            .frame(minHeight: 38)
            .background(kind.fill, in: ChatBubbleShape(mine: kind.mine, tail: tail))
            // 長按時浮起來的是泡泡本身（不是一塊方的）
            .contentShape(.contextMenuPreview, ChatBubbleShape(mine: kind.mine, tail: tail))
    }
}

/// 泡泡裡的字：網址可以點；我們這邊的照 Markdown（粗體、連結）；連結加底線（白字的泡泡上才看得出來）
func bubbleText(_ s: String, markdown parse: Bool) -> AttributedString {
    var out = parse ? markdown(s) : VisitorContent.linked(s)
    if parse {
        // Markdown 沒標成連結的網址也要能點
        let plain = String(out.characters)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                guard let url = match.url, let r = Range(match.range, in: plain), let ar = Range(r, in: out) else { continue }
                if out[ar].link == nil { out[ar].link = url }
            }
        }
    }
    let links = out.runs.filter { $0.link != nil }.map(\.range)
    for range in links {
        out[range][AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
    }
    return out
}

/// 一則訊息：客人在左（灰）、Xena 與專人在右（紫、橘）
private struct XenaChatRow: View {
    let message: XenaConversationMessage
    let first: Bool
    let last: Bool
    /// 這一組客人說的話 Jev 判斷要找人（機率）：標在組的最後一句下面
    let jevFlag: Double?
    let site: String
    let siteURL: URL?
    let space: Namespace.ID
    let open: (ViewedMedia) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        if message.role == "user" { customer } else { ours }
    }

    // MARK: 客人

    private var customer: some View {
        VStack(alignment: .leading, spacing: 4) {
            VisitorContent(text: message.content, tail: last, space: space, open: open)
                .contextMenu { menu }
            if let jevFlag {
                Label("Jev 判斷要找人（\(Int((jevFlag * 100).rounded()))%）", systemImage: "exclamationmark.bubble.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.warningFG)
                    .padding(.leading, 8)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.trailing, 56)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Xena、專人

    private var xena: Bool { message.role == "assistant" }

    /// 專人附的照片、檔案（一行「[圖片] 網址」「[檔案] 檔名 網址」）拆出來另外畫；剩下的字放在泡泡裡
    private var staffParts: (text: String, media: [VisitorContent.Part]) {
        guard message.role == "staff", message.content.contains("https://") else { return (message.content, []) }
        let parts = VisitorContent.parse(message.content)
        let media = parts.filter { part in
            if case .text = part.kind { return false }
            return true
        }
        guard !media.isEmpty else { return (message.content, []) }
        let text = parts.compactMap { part -> String? in
            if case .text(let s) = part.kind { return s }
            return nil
        }
        return (text.joined(separator: "\n\n"), media)
    }

    private var ours: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if first { sender }
            let split = staffParts
            // 只附卡片沒打字的（內容是「［卡片］標題」）：只畫卡片
            if !split.text.isEmpty, !message.isOnlyCardLabel, !(message.card != nil && split.text.hasPrefix("［卡片］")) {
                ChatBubble(xena ? .xena : .staff, tail: last && split.media.isEmpty) {
                    Text(bubbleText(split.text, markdown: true))
                }
                .contextMenu { menu }
            }
            ForEach(split.media) { part in
                staffMedia(part)
            }
            if let nav = message.navigate {
                NavigateChip(title: nav.title, url: URL(string: nav.path, relativeTo: siteURL)?.absoluteURL)
            }
            if let card = message.card {
                StaffCardView(card: card)
                    .contextMenu { menu }
            }
            if !message.products.isEmpty {
                ProductPicks(site: site, products: message.products)
            }
            if message.emailed, last {
                Text("也寄了 Email 給客人")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: 520, alignment: .trailing)
        .padding(.leading, 56)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 專人附的照片（點了放大）、檔案（點了打開）
    @ViewBuilder
    private func staffMedia(_ part: VisitorContent.Part) -> some View {
        switch part.kind {
        case .photo(let url):
            PhotoThumb(url: url, space: space) { open(ViewedMedia(url: url, kind: .photo)) }
                .contextMenu { menu }
        case .media(let kind, let title, let url, let location):
            MediaRow(kind: kind, title: title, location: location) {
                if let kind { open(ViewedMedia(url: url, kind: kind)) } else { openURL(url) }
            }
        case .missing(let text):
            MissingMedia(text: text)
        default:
            EmptyView()
        }
    }

    /// 誰說的（我們這邊換人時寫在第一個泡泡上面）
    private var sender: some View {
        HStack(spacing: 4) {
            if xena {
                Circle()
                    .fill(AngularGradient(colors: [Theme.xenaPink, Theme.xenaViolet, Theme.xenaCyan, Theme.xenaPink], center: .center))
                    .frame(width: 8, height: 8)
            }
            Text(xena ? "Xena" : (message.author ?? "專人"))
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Theme.muted)
        .padding(.trailing, 8)
    }

    @ViewBuilder
    private var menu: some View {
        Button("複製", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = message.role == "user" ? VisitorContent.plain(message.content) : message.content
        }
        if let at = message.at {
            Text("\(at.dayTitle) \(at.clockText)")
        }
        if message.role == "user", message.tag != nil || message.jevHuman != nil {
            let parts = [message.tag, message.jevHuman.map { "找人 \(Int(($0.confidence * 100).rounded()))%" }].compactMap { $0 }
            Text("Jev：\(parts.joined(separator: "・"))")
        }
    }
}

/// 送出中的回覆（淡一點，下面一行「傳送中…」，像 iMessage 的「傳送中」）
private struct PendingReply: View {
    let text: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ChatBubble(.staff) { Text(text) }
                .opacity(0.6)
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("傳送中…")
            }
            .font(.caption2)
            .foregroundStyle(Theme.muted)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: 520, alignment: .trailing)
        .padding(.leading, 56)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - 客人傳來的內容

/// 客人說的話，一行一行看：LINE 傳來的照片、貼圖顯示圖（點開全螢幕），影片、語音可以播，檔案、位置可以打開，
/// 語音轉成的文字跟在下面，其他照原樣（網址可以點）。
/// 「[圖片] 網址」「[貼圖：開心] 網址」「[影片 12 秒] 網址」「[語音 8 秒] 網址」「[檔案] 名稱 網址」「[位置] 地址 網址」
struct VisitorContent: View {
    let text: String
    /// 一組的最後一則：泡泡有小尾巴
    var tail = true
    /// 照片放大的轉場（沒有就是一般的全螢幕）
    var space: Namespace.ID?
    let open: (ViewedMedia) -> Void

    @Environment(\.openURL) private var openURL

    /// 一則裡的一段
    struct Part: Identifiable {
        enum Kind {
            case photo(URL)
            case sticker(URL)
            /// 影片、語音（App 裡播）；檔案、位置（kind 是 nil：交給系統打開）
            case media(ViewedMedia.Kind?, title: String, url: URL, location: Bool)
            /// 客人傳了東西，但原檔沒有存下來（舊的訊息、網站當時沒開圖片儲存）
            case missing(String)
            /// 語音轉成的文字
            case transcript(String)
            case text(String)
        }

        let id: Int
        let kind: Kind

        /// 照片、貼圖：不用包泡泡
        var isPicture: Bool {
            switch kind {
            case .photo, .sticker: true
            default: false
            }
        }
    }

    static func parse(_ text: String) -> [Part] {
        var parts: [Part] = []
        var paragraph: [String] = []
        func add(_ kind: Part.Kind) { parts.append(Part(id: parts.count, kind: kind)) }
        func flush() {
            let s = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { add(.text(s)) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "［", with: "[")
                .replacingOccurrences(of: "］", with: "]")
            if line.hasPrefix("["), let close = line.firstIndex(of: "]"), let kind = attachment(label: String(line[line.index(after: line.startIndex)..<close]), rest: String(line[line.index(after: close)...])) {
                flush()
                add(kind)
                continue
            }
            if let said = line.wholeMatch(of: /（語音內容：(.+)）/) {
                flush()
                add(.transcript(String(said.1)))
                continue
            }
            paragraph.append(raw)
        }
        flush()
        return parts
    }

    /// 「[標籤] … https://…」：標籤後面可能有檔名、地址，最後是網址；沒有網址的是原檔沒存下來（舊的訊息有「（沒有存下來：…）」）
    private static func attachment(label: String, rest raw: String) -> Part.Kind? {
        var rest = raw.trimmingCharacters(in: .whitespaces)
        var url: URL?
        let start = rest.lastIndex(of: " ").map { rest.index(after: $0) } ?? (rest.hasPrefix("https://") ? rest.startIndex : nil)
        if let start, let u = URL(string: String(rest[start...])), u.scheme == "https" {
            url = u
            rest = String(rest[..<start]).trimmingCharacters(in: .whitespaces)
        }
        let lost = url == nil && (rest.isEmpty || rest.hasPrefix("（沒有存下來"))
        if label == "圖片" {
            if let url { return .photo(url) }
            return lost ? .missing("照片沒有存下來") : nil
        }
        if label.hasPrefix("貼圖") {
            if let url { return .sticker(url) }
            return .text("［\(label)］")
        }
        if label.hasPrefix("影片") || label.hasPrefix("語音") {
            let video = label.hasPrefix("影片")
            if let url { return .media(video ? ViewedMedia.Kind.video : ViewedMedia.Kind.audio, title: label, url: url, location: false) }
            return lost ? .missing(video ? "影片沒有存下來" : "語音沒有存下來") : nil
        }
        if label.hasPrefix("檔案") {
            if let url { return .media(nil, title: rest.isEmpty ? "檔案" : rest, url: url, location: false) }
            return lost ? .missing("檔案沒有存下來") : nil
        }
        if label.hasPrefix("位置"), let url {
            return .media(nil, title: rest.isEmpty ? "位置" : rest, url: url, location: true)
        }
        return nil
    }

    /// 複製用：網址、系統附註拿掉
    static func plain(_ text: String) -> String {
        parse(text).map { part in
            switch part.kind {
            case .photo: "［照片］"
            case .sticker: "［貼圖］"
            case .media(_, let title, _, _): "［\(title)］"
            case .missing(let s): "［\(s)］"
            case .transcript(let s): "（語音內容：\(s)）"
            case .text(let s): s
            }
        }.joined(separator: "\n")
    }

    var body: some View {
        let parts = Self.parse(text)
        if !parts.isEmpty, parts.allSatisfy(\.isPicture) {
            // 只有照片、貼圖：不包泡泡（iMessage）
            VStack(alignment: .leading, spacing: 2) {
                ForEach(parts) { part($0) }
            }
        } else {
            ChatBubble(.customer, tail: tail) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(parts) { part($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func part(_ part: Part) -> some View {
        switch part.kind {
        case .photo(let url):
            PhotoThumb(url: url, space: space) { open(ViewedMedia(url: url, kind: .photo)) }
        case .sticker(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: 110, height: 110, alignment: .leading)
            .accessibilityLabel("客人傳的貼圖")
        case .media(let kind, let title, let url, let location):
            MediaRow(kind: kind, title: title, location: location) {
                if let kind { open(ViewedMedia(url: url, kind: kind)) } else { openURL(url) }
            }
        case .missing(let text):
            MissingMedia(text: text)
        case .transcript(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
            }
            .accessibilityLabel("語音內容：\(text)")
        case .text(let s):
            Text(bubbleText(s, markdown: false))
        }
    }

    /// 網址可以點
    static func linked(_ s: String) -> AttributedString {
        var out = AttributedString(s)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return out }
        for match in detector.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let url = match.url, let r = Range(match.range, in: s), let ar = Range(r, in: out) else { continue }
            out[ar].link = url
        }
        return out
    }
}

/// 客人傳的照片：照比例的縮圖（長邊最多 240、高最多 300），點了全螢幕
private struct PhotoThumb: View {
    let url: URL
    let space: Namespace.ID?
    let action: () -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                let size = Self.fit(image.size)
                Button(action: action) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipShape(.rect(cornerRadius: 18, style: .continuous))
                        .modifier(ZoomSource(id: url, space: space))
                }
                .buttonStyle(.press)
                .accessibilityLabel("客人傳的照片，點一下放大")
                .transition(.opacity)
            } else if failed {
                // 網站沒開圖片儲存時是向 LINE 拿的：LINE 刪掉之後就拿不到了
                MissingMedia(text: "照片載入不了（LINE 只保留一段時間）")
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.bubbleIn)
                    .frame(width: 220, height: 165)
                    .shimmer()
            }
        }
        .task(id: url) {
            let loaded = await ChatImages.thumbnail(url)
            withAnimation(Motion.fast) {
                image = loaded
                failed = loaded == nil
            }
        }
    }

    static func fit(_ s: CGSize) -> CGSize {
        guard s.width > 0, s.height > 0 else { return CGSize(width: 220, height: 165) }
        let scale = min(240 / s.width, 300 / s.height, 1)
        return CGSize(width: max((s.width * scale).rounded(), 72), height: max((s.height * scale).rounded(), 72))
    }
}

/// 對話裡的照片：下載一次、縮成畫面用得到的大小（原圖可能是 1200 萬畫素），捲來捲去不會重抓
enum ChatImages {
    private static let cache = NSCache<NSURL, UIImage>()

    /// 已經下載過的縮圖（全螢幕先放這張，原圖下載好再換）
    static func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    static func thumbnail(_ url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let result = try? await URLSession.shared.data(from: url) else { return nil }
        let (data, response) = result
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let full = UIImage(data: data) else { return nil }
        let longest = max(full.size.width, full.size.height, 1)
        let scale = min(1, 900 / longest)
        let target = CGSize(width: (full.size.width * scale).rounded(), height: (full.size.height * scale).rounded())
        let thumb = await full.byPreparingThumbnail(ofSize: target) ?? full
        cache.setObject(thumb, forKey: url as NSURL)
        return thumb
    }
}

/// 影片、語音、檔案、位置：一列（圖示、名稱、要做什麼）
private struct MediaRow: View {
    let kind: ViewedMedia.Kind?
    let title: String
    var location = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSoft, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.brand(14.5, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text(hint)
                        .font(.brand(11.5, .regular, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
    }

    private var icon: String {
        switch kind {
        case .video: "play.fill"
        case .audio: "waveform"
        case .photo: "photo"
        case nil: location ? "mappin.and.ellipse" : "doc.fill"
        }
    }

    private var hint: String {
        switch kind {
        case .video, .audio: "點一下播放"
        case .photo: "點一下放大"
        case nil: location ? "在地圖打開" : "點一下打開"
        }
    }
}

/// 看不到的照片、影片：一塊淡底、一個圖示、一句說明
struct MissingMedia: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "photo")
            .textRole(.small)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.soft, in: .rect(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 我們這邊附的東西

/// Xena 帶客人去的頁面（客人在 LINE 上看到的是一顆按鈕；網站上是直接帶過去）
private struct NavigateChip: View {
    let title: String
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { if let url { openURL(url) } } label: {
            HStack(spacing: 6) {
                HeroIcon("arrow-top-right-on-square", size: 13)
                Text("帶客人看：\(title)")
                    .lineLimit(1)
            }
            .font(.brand(12.5, .medium, relativeTo: .caption))
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.press)
        .disabled(url == nil)
    }
}

/// 專人附的行銷卡片：照客人在 LINE 上看到的畫（大圖、標題、說明、優惠碼、按鈕）
struct StaffCardView: View {
    let card: StaffCard
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = card.imageURL {
                AsyncImage(url: image) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Theme.soft
                    }
                }
                .frame(height: 136)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.brand(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                if let text = card.body {
                    Text(text)
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(6)
                }
                if let code = card.couponCode { coupon(code) }
                Button { if let url = card.url { openURL(url) } } label: {
                    Text(card.buttonLabel ?? "看看")
                        .font(.brand(14, .semibold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Theme.primary, in: .rect(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.press)
                .disabled(card.url == nil)
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: 264)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("附上的卡片：\(card.title)")
    }

    private func coupon(_ code: String) -> some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            HStack(spacing: 8) {
                HeroIcon("ticket", size: 15)
                    .foregroundStyle(Theme.accentText)
                Text(code)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                Text(copied ? "已複製" : "複製")
                    .font(.brand(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accentText.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .haptic(.success, trigger: copied) { _, new in new }
        .accessibilityLabel("優惠碼 \(code)，點一下複製")
    }
}

/// 專人推薦的商品（LINE 上是左右滑的商品卡片）：點了打開那個商品
private struct ProductPicks: View {
    let site: String
    let products: [(name: String, slug: String)]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("推薦的商品")
                .font(.brand(11, .medium, relativeTo: .caption2))
                .foregroundStyle(Theme.muted)
            FlowLayout(spacing: 6) {
                ForEach(Array(products.enumerated()), id: \.offset) { _, p in
                    NavigationLink(value: Route.record(site: site, entity: "product", id: p.slug)) {
                        HStack(spacing: 5) {
                            HeroIcon("shopping-bag", size: 13)
                            Text(p.name).lineLimit(1)
                        }
                        .font(.brand(12.5, .medium, relativeTo: .caption))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface, in: .capsule)
                        .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
                    }
                    .buttonStyle(.press)
                    .disabled(p.slug.isEmpty)
                }
            }
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }
}

// MARK: - 事件、日期

/// 對話裡發生的事（通知專人、接手、交還、結案）：置中的一顆小膠囊，用專人看得懂的話說；
/// 通知專人的那一則下面放轉真人的原因
struct ChatEventRow: View {
    let message: XenaConversationMessage
    var reason: String?
    @State private var expanded = false

    /// 舊的網站沒給種類：從客人看到的那句話猜
    static func kind(of m: XenaConversationMessage) -> String {
        if let e = m.event, !e.isEmpty { return e }
        let c = m.content
        if c.contains("通知專人") || c.contains("通知真人") || c.contains("找專人") { return "handoff" }
        if c.contains("接手") { return "takeover" }
        if c.contains("Xena 繼續") || c.contains("交還") { return "release" }
        if c.contains("重新開啟") { return "reopened" }
        if c.contains("結束") || c.contains("結案") { return "closed" }
        return "other"
    }

    private var described: (icon: String, text: String) {
        switch Self.kind(of: message) {
        case "handoff": (icon: "bell.fill", text: "Xena 通知了專人")
        case "takeover": (icon: "person.fill.checkmark", text: "\(message.author ?? "專人")接手了")
        case "release": (icon: "sparkles", text: "交給 Xena 繼續回答")
        case "closed": (icon: "checkmark.circle.fill", text: "結案")
        case "reopened": (icon: "arrow.uturn.backward.circle", text: "重新開啟")
        case "contact": (icon: "envelope.fill", text: "客人留了聯絡資料")
        case "login": (icon: "person.crop.circle.badge.checkmark", text: "客人登入了")
        case "logout": (icon: "rectangle.portrait.and.arrow.right", text: "客人登出了")
        default: (icon: "info.circle", text: message.content)
        }
    }

    var body: some View {
        let d = described
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: d.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(message.at.map { "\(d.text)・\($0.clockText)" } ?? d.text)
                    .lineLimit(2)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.muted)
            if let reason, !reason.isEmpty {
                Button { withAnimation(Motion.fast) { expanded.toggle() } } label: {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(expanded ? nil : 2)
                        .padding(.horizontal, 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("原因：\(reason)")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityHint(message.content)
    }
}

/// 兩則之間隔了一段時間（或跨天）的那一行時間（iMessage：「**今天** 21:20」）
struct ChatTimeHeader: View {
    let date: Date

    var body: some View {
        Text("\(Text(day).fontWeight(.semibold)) \(date.clockText)")
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    private var day: String {
        let cal = Calendar.taipei
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: .now)).day ?? 99
        if days < 7 { return date.weekdayText }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) { return date.dayTitle }
        return date.dayText
    }
}

// MARK: - 最上面：這是誰

/// 對話最上面：頭像、名字、從哪裡來、聊了哪些類別；同一位 LINE 好友之前的對話
private struct ConversationIntro: View {
    let detail: XenaConversationDetail
    let siteName: String
    let site: String

    private var name: String { detail.who ?? (detail.channel == .line ? "LINE 好友" : "網站訪客") }

    var body: some View {
        VStack(spacing: 6) {
            Avatar(name: name, imageURL: detail.picture, size: 58)
                .padding(.bottom, 4)
            Text(name)
                .font(.brand(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 6) {
                if detail.visitorOnline {
                    LiveDot()
                    Text("正在網站上・")
                }
                Text(origin)
            }
            .font(.brand(12.5, .regular, relativeTo: .caption))
            .foregroundStyle(Theme.muted)
            if !detail.topics.isEmpty {
                Text(detail.topics.prefix(6).joined(separator: "・"))
                    .font(.brand(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Theme.faint)
            }
            if detail.lineBlocked {
                StatusBadge("封鎖了官方帳號，回覆傳不到他的 LINE", tone: .danger)
                    .padding(.top, 4)
            }
            if !detail.orders.isEmpty {
                orders.padding(.top, 14)
            }
            if !detail.earlier.isEmpty {
                earlier.padding(.top, detail.orders.isEmpty ? 14 : 10)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// 會員最近的訂單（客人問到貨、退換貨時不用離開對話）
    private var orders: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近的訂單")
                .font(.brand(11.5, .medium, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 4)
            ForEach(detail.orders.prefix(3)) { o in
                NavigationLink(value: Route.order(site: site, id: o.id)) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(o.number)")
                                .font(.brand(14, .medium).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                            Text(o.items)
                                .font(.brand(11.5, .regular, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(o.totalLabel)
                                .font(.brand(14, .medium).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                            Text(o.statusLabel)
                                .font(.brand(11.5, .regular, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 9)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.row)
            }
        }
        .panel(padding: 14, radius: 14)
    }

    private var origin: String {
        var parts = [detail.channel == .line ? "LINE" : "官網", siteName]
        if let at = detail.startedAt { parts.append("\(at.shortText) 開始") }
        return parts.joined(separator: "・")
    }

    private var earlier: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("之前的對話")
                .font(.brand(11.5, .medium, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 4)
            ForEach(detail.earlier) { e in
                NavigationLink(value: Route.xenaConversation(site: site, id: e.id)) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.firstQuestion.map(VisitorPreview.text) ?? "一段對話")
                                .font(.brand(14, .medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text([e.startedAt?.shortText, e.statusLabel].compactMap { $0 }.joined(separator: "・"))
                                .font(.brand(11.5, .regular, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        HeroIcon("chevron-right", size: 14)
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(.vertical, 9)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.row)
            }
        }
        .panel(padding: 14, radius: 14)
    }
}

// MARK: - 回覆框

/// 聊天的回覆框：左邊請 Xena 幫忙擬、中間打字（會長高）、右邊送出；打字時上面一行說回覆會送到哪裡
struct ChatComposer<Accessory: View>: View {
    @Binding var text: String
    let placeholder: String
    var hint: String?
    var hintWarning: Bool
    var sending: Bool
    var draftWithXena: (() -> Void)?
    /// 左邊的「＋」：打開附件、Xena、折價券…的選單（Xena 對話）
    var plus: (() -> Void)?
    /// 沒打字也送得出去（附了照片、卡片）
    var canSendEmpty: Bool
    /// 先不能送（照片還在上傳、Xena 還在寫）
    var sendBlocked: Bool
    let send: () -> Void
    let accessory: Accessory

    @FocusState private var focused: Bool

    init(
        text: Binding<String>, placeholder: String, hint: String? = nil, hintWarning: Bool = false, sending: Bool = false,
        draftWithXena: (() -> Void)? = nil, plus: (() -> Void)? = nil, canSendEmpty: Bool = false, sendBlocked: Bool = false,
        send: @escaping () -> Void, @ViewBuilder accessory: () -> Accessory
    ) {
        _text = text
        self.placeholder = placeholder
        self.hint = hint
        self.hintWarning = hintWarning
        self.sending = sending
        self.draftWithXena = draftWithXena
        self.plus = plus
        self.canSendEmpty = canSendEmpty
        self.sendBlocked = sendBlocked
        self.send = send
        self.accessory = accessory()
    }

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var showSend: Bool { !empty || canSendEmpty || sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if focused || !text.isEmpty || hintWarning, let hint, !hint.isEmpty {
                Label(hint, systemImage: hintWarning ? "exclamationmark.triangle.fill" : "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(hintWarning ? Theme.dangerFG : Theme.muted)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
            accessory
            HStack(alignment: .bottom, spacing: 8) {
                if let plus {
                    Button(action: plus) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink2)
                            .frame(width: 36, height: 36)
                            .background(Theme.bubbleIn, in: .circle)
                    }
                    .buttonStyle(PressScale(scale: 0.9))
                    .accessibilityLabel("加照片、檔案、折價券，或請 Xena 幫忙")
                } else if let draftWithXena {
                    Button(action: draftWithXena) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.bubbleXena)
                            .frame(width: 36, height: 36)
                            .background(Theme.bubbleIn, in: .circle)
                    }
                    .buttonStyle(PressScale(scale: 0.9))
                    .accessibilityLabel("請 Xena 擬回覆")
                }
                // 輸入框裡右下角是送出（有字才出現；iMessage）
                HStack(alignment: .bottom, spacing: 4) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...8)
                        .focused($focused)
                        .padding(.leading, 14)
                        .padding(.vertical, 8)
                    if showSend {
                        Button(action: send) {
                            Group {
                                if sending {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else {
                                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.bubbleStaff, in: .circle)
                        }
                        .buttonStyle(PressScale(scale: 0.9))
                        .disabled(sending || sendBlocked)
                        .opacity(sendBlocked && !sending ? 0.45 : 1)
                        .keyboardShortcut(.return, modifiers: .command)
                        .padding(.trailing, 4)
                        .padding(.bottom, 4)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .accessibilityLabel("送出")
                    }
                }
                .frame(minHeight: 38)
                .background(Theme.page.opacity(0.6), in: .rect(cornerRadius: 19, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .strokeBorder(focused ? Theme.ink.opacity(0.28) : Theme.line, lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .top) { Rule() }
        .animation(Motion.fast, value: focused)
        .animation(Motion.fast, value: showSend)
    }
}

extension ChatComposer where Accessory == EmptyView {
    init(
        text: Binding<String>, placeholder: String, hint: String? = nil, hintWarning: Bool = false, sending: Bool = false,
        draftWithXena: (() -> Void)? = nil, plus: (() -> Void)? = nil, canSendEmpty: Bool = false, sendBlocked: Bool = false, send: @escaping () -> Void
    ) {
        self.init(
            text: text, placeholder: placeholder, hint: hint, hintWarning: hintWarning, sending: sending,
            draftWithXena: draftWithXena, plus: plus, canSendEmpty: canSendEmpty, sendBlocked: sendBlocked, send: send
        ) { EmptyView() }
    }
}

/// 捲在上面時：右下角回到最新（有新訊息時標數字）
private struct JumpToLatest: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                HeroIcon("chevron-down", size: 15)
                if count > 0 {
                    Text("\(count)").font(.brand(13, .semibold)).monospacedDigit()
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, count > 0 ? 12 : 0)
            .frame(minWidth: 38, minHeight: 38)
            .background(Theme.surface, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(PressScale(scale: 0.92))
        .accessibilityLabel(count > 0 ? "\(count) 則新訊息，捲到最新" : "捲到最新")
    }
}

// MARK: - 全螢幕看照片、播影片與語音

struct ViewedMedia: Identifiable {
    enum Kind { case photo, video, audio }
    let id = UUID()
    let url: URL
    let kind: Kind
}

/// 照片從縮圖放大的轉場來源（有 namespace 才加）
private struct ZoomSource: ViewModifier {
    let id: URL
    let space: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let space {
            content.matchedTransitionSource(id: id, in: space)
        } else {
            content
        }
    }
}

/// 客人傳的照片：從縮圖放大成全螢幕（像 iMessage、照片），兩指放大、點兩下放大縮小、點一下收起上面的按鈕、
/// 沒放大時往下拉就回去，可以分享或存到照片；影片與語音直接播
struct MediaViewer: View {
    let media: ViewedMedia

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    @State private var player: AVPlayer?
    /// 上面的關閉、分享（點一下照片收起來）
    @State private var chrome = true
    @State private var zoomed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch media.kind {
            case .photo:
                if let image {
                    ZoomableImage(image: image, zoomed: $zoomed) {
                        withAnimation(Motion.fast) { chrome.toggle() }
                    }
                    .ignoresSafeArea()
                } else if failed {
                    unavailable("照片載入不了（LINE 只保留一段時間）")
                } else {
                    ProgressView().tint(.white)
                }
            case .video, .audio:
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay {
                            if media.kind == .audio {
                                Image(systemName: "waveform")
                                    .font(.system(size: 64, weight: .light))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
        .overlay(alignment: .top) {
            if chrome { bar.transition(.opacity) }
        }
        .statusBarHidden(!chrome)
        // 放大看細節時拖曳是移動照片，不是關掉
        .interactiveDismissDisabled(zoomed)
        .task { await prepare() }
        .onDisappear { player?.pause() }
    }

    private var bar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("關閉")
            Spacer()
            if media.kind == .photo, let image {
                let picture = Image(uiImage: image)
                ShareLink(item: picture, preview: SharePreview("客人傳的照片", image: picture)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("分享或儲存照片")
            } else if media.kind != .photo {
                ShareLink(item: media.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("分享")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func unavailable(_ text: String) -> some View {
        Label(text, systemImage: "photo")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .padding(24)
    }

    private func prepare() async {
        switch media.kind {
        case .photo:
            // 先放對話裡的縮圖（轉場馬上有畫面），原圖下載好再換成清楚的
            image = ChatImages.cached(media.url)
            do {
                let (data, response) = try await URLSession.shared.data(from: media.url)
                let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
                if ok, let full = UIImage(data: data) {
                    image = full
                } else if image == nil {
                    failed = true
                }
            } catch {
                if image == nil { failed = true }
            }
        case .video, .audio:
            let p = AVPlayer(url: media.url)
            player = p
            p.play()
        }
    }
}

/// 兩指放大、放大後拖曳移動、點兩下放大縮小、點一下收起按鈕
private struct ZoomableImage: View {
    let image: UIImage
    @Binding var zoomed: Bool
    let tap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(max(lastScale * v.magnification, 1), 5) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1.01 { withAnimation(Motion.fast) { reset() } }
                        zoomed = scale > 1.01
                    }
            )
            // 沒放大時不接拖曳：往下拉交給系統的關閉手勢
            .simultaneousGesture(
                DragGesture()
                    .onChanged { v in
                        offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset },
                including: zoomed ? .all : .none
            )
            .onTapGesture(count: 2) {
                withAnimation(Motion.spring) {
                    if scale > 1.01 {
                        reset()
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                        zoomed = true
                    }
                }
            }
            .onTapGesture { tap() }
            .accessibilityLabel("客人傳的照片")
            .accessibilityAddTraits(.isImage)
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        zoomed = false
    }
}
