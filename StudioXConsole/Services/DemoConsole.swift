import SwiftUI

/// 示範資料：StudioX 的三個網站（studiox.tw、黃毛丫頭、博信國際），時間都是相對現在，打開永遠是「昨晚到現在」。
/// Xena 的回答是照關鍵字寫好的劇本，但走的是正式的事件格式（工具呼叫、確認卡片、提問、卡片），
/// 按下確認後真的會改這裡的資料（訂單狀態、客服對話、草稿、值班紀錄）。
final class DemoConsole: ConsoleBackend {
    private let now = Date()
    private var siteData: [Site] = []
    private var orderData: [Order] = []
    private var conversationData: [Conversation] = []
    private var noteData: [XenaNote] = []
    private var logData: [ShiftEntry] = []
    /// 登入的人（客服回覆署名用）
    private var staffName = "Andy"

    /// 等確認的動作（確認碼只在「伺服器」這邊）
    private struct Proposal {
        var typed: String?
        var apply: () -> String
        var followUp: String?
    }
    private var proposals: [String: Proposal] = [:]

    /// Xena 問了你什麼（ask_user），回答時接著做
    private enum AskKind {
        case lateOrder
        case draftSite
    }
    private var asks: [String: AskKind] = [:]

    private enum Step {
        case pause(Double)
        case event(CopilotEvent)
        case say(String)
    }

    private static let studiox = "studiox.tw"
    private static let yellowgirl = "yellowgirl.tw"
    private static let bsi = "www.bsi-med.com"

    init() {
        siteData = makeSites()
        orderData = makeOrders()
        conversationData = makeConversations()
        noteData = makeNotes()
        logData = makeLog()
        proposals["note-prep"] = Proposal(
            typed: nil,
            apply: { [weak self] in self?.preparePaidOrders() ?? "" },
            followUp: "好了 ✓ 客人 10 分鐘後會收到備貨通知。出貨單要我幫你整理嗎？"
        )
    }

    private func ago(_ minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60)
    }

    // MARK: - ConsoleBackend

    func signIn(_ method: SignInMethod) async throws -> StaffUser {
        try? await Task.sleep(for: .milliseconds(900))
        let user: StaffUser
        switch method {
        case .apple:
            user = StaffUser(name: "Andy", email: "andy@studiox.tw")
        case .email(let email, let password):
            let trimmed = email.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("@"), !password.isEmpty else { throw ConsoleError.badCredentials }
            let name = trimmed.split(separator: "@").first.map(String.init) ?? "你"
            user = StaffUser(name: name.prefix(1).uppercased() + name.dropFirst(), email: trimmed)
        }
        staffName = user.name
        return user
    }

    func sites() async throws -> [Site] { siteData }
    func orders() async throws -> [Order] { orderData.sorted { $0.placedAt > $1.placedAt } }
    func conversations() async throws -> [Conversation] { conversationData.sorted { $0.updatedAt > $1.updatedAt } }
    func notes() async throws -> [XenaNote] { noteData }
    func shiftLog() async throws -> [ShiftEntry] { logData.sorted { $0.at < $1.at } }

    func chat(_ request: XenaRequest) -> AsyncThrowingStream<CopilotEvent, any Error> {
        var built: [Step] = []
        if request.threadID == nil {
            built.append(.event(.thread(id: newID("thread"), title: String(request.message.prefix(24)))))
        }
        built.append(.pause(0.45))
        built += script(for: request)
        let steps = built
        return AsyncThrowingStream { continuation in
            let task = Task {
                for step in steps {
                    if Task.isCancelled { break }
                    switch step {
                    case .pause(let seconds):
                        try? await Task.sleep(for: .seconds(seconds))
                    case .event(let event):
                        continuation.yield(event)
                    case .say(let text):
                        for chunk in text.chunked(3) {
                            if Task.isCancelled { break }
                            continuation.yield(.text(chunk))
                            try? await Task.sleep(for: .milliseconds(22))
                        }
                    }
                }
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func decide(_ cardID: String, approve: Bool, typed: String?) async throws -> DecideResult {
        guard let proposal = proposals[cardID] else {
            return DecideResult(status: .expired, result: "這張確認卡已經失效了", followUp: nil)
        }
        guard approve else {
            proposals[cardID] = nil
            return DecideResult(status: .cancelled, result: "已取消，什麼都沒改", followUp: "好，先不動。需要的時候再叫我。")
        }
        if let word = proposal.typed, typed?.trimmingCharacters(in: .whitespaces) != word {
            throw ConsoleError.typedMismatch(word)
        }
        try? await Task.sleep(for: .milliseconds(700))
        proposals[cardID] = nil
        let result = proposal.apply()
        return DecideResult(status: .done, result: result, followUp: proposal.followUp)
    }

    func setStatus(_ status: ConversationStatus, conversation id: String) async throws {
        guard let i = conversationData.firstIndex(where: { $0.id == id }) else { return }
        conversationData[i].status = status
        conversationData[i].updatedAt = .now
        let who = conversationData[i].visitor
        switch status {
        case .human: record("你接手了\(who)的對話", symbol: "person.fill.checkmark", site: conversationData[i].siteID, tone: .ok)
        case .ai: record("你把\(who)的對話交還給我", symbol: "arrow.uturn.backward", site: conversationData[i].siteID, tone: .info)
        case .closed: record("\(who)的對話結案了", symbol: "checkmark.seal.fill", site: conversationData[i].siteID, tone: .muted)
        case .waiting: break
        }
    }

    func reply(_ text: String, conversation id: String, as staff: String) async throws {
        guard let i = conversationData.firstIndex(where: { $0.id == id }) else { return }
        try? await Task.sleep(for: .milliseconds(300))
        conversationData[i].lines.append(ChatLine(id: newID("line"), author: .staff(staff), text: text, at: .now))
        conversationData[i].status = .human
        conversationData[i].updatedAt = .now
    }

    // MARK: - 寫入（確認之後才會跑）

    private func record(_ text: String, symbol: String, site: String? = nil, tone: Tone = .ok) {
        logData.append(ShiftEntry(id: newID("log"), at: .now, symbol: symbol, text: text, siteID: site, tone: tone))
    }

    private func resolveNote(_ id: String, _ result: String) {
        guard let i = noteData.firstIndex(where: { $0.id == id }) else { return }
        noteData[i].resolution = result
        noteData[i].proposal?.status = .done
    }

    @discardableResult
    private func preparePaidOrders() -> String {
        var moved: [String] = []
        for i in orderData.indices where orderData[i].status == .paid {
            orderData[i].status = .preparing
            moved.append(orderData[i].number)
        }
        proposals["note-prep"] = nil
        guard !moved.isEmpty else {
            resolveNote("note-prep", "已經都在備貨了")
            return "沒有需要改的訂單了"
        }
        let result = "\(moved.count) 筆改成備貨中"
        resolveNote("note-prep", "依你的確認，\(result)")
        record("依你的確認，把 \(moved.count) 筆訂單改成備貨中", symbol: "shippingbox.fill", site: Self.yellowgirl)
        return result
    }

    // MARK: - Xena 的劇本

    private func has(_ text: String, _ words: String...) -> Bool {
        words.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func site(in text: String) -> String? {
        if has(text, "studiox") { return Self.studiox }
        if has(text, "黃毛丫頭", "yellowgirl", "鴨頭") { return Self.yellowgirl }
        if has(text, "博信", "bsi") { return Self.bsi }
        return nil
    }

    private func name(of siteID: String) -> String {
        siteData.first { $0.id == siteID }?.name ?? siteID
    }

    private func script(for r: XenaRequest) -> [Step] {
        let m = r.message
        if let answering = r.answering, let kind = asks.removeValue(forKey: answering) {
            switch kind {
            case .lateOrder: return lateOrderChoice(m)
            case .draftSite: return draft(siteID: site(in: m) ?? Self.studiox)
            }
        }
        if let order = orderData.first(where: { m.contains($0.number) }) {
            if has(m, "退款") { return refund(order) }
            if let target = OrderStatus.allCases.first(where: { m.contains("改成\($0.rawValue)") || m.contains("改成「\($0.rawValue)」") }) {
                return move(order, to: target)
            }
            return describe(order)
        }
        if has(m, "擬一段回覆給"), let c = conversationData.first(where: { m.contains($0.visitor) }),
           !c.visitor.hasPrefix("張經理"), c.visitor != "林先生" {
            return replyDraft(c)
        }
        if has(m, "林先生", "晚到", "延誤", "加急", "物流") { return lateOrder() }
        if has(m, "備貨", "已付款的") { return preparePaid() }
        if has(m, "報價", "澄光", "張經理") { return quote() }
        if has(m, "等我", "回覆", "客服", "收件匣") { return waiting() }
        if has(m, "起草", "新消息", "文章", "公告") { return draft(siteID: site(in: m) ?? r.siteID) }
        if has(m, "營收", "業績", "訂單", "賣了", "生意") { return revenue() }
        if has(m, "流量", "訪客", "數據", "怎麼樣") { return traffic(siteID: site(in: m) ?? r.siteID) }
        if has(m, "你是誰", "xena", "嗨", "哈囉", "你好", "hello") { return intro() }
        return fallback(m)
    }

    private func tool(_ name: String, _ label: String, args: String = "{}", result: String) -> [Step] {
        let id = newID("tool")
        let ms = Int.random(in: 260...820)
        return [
            .event(.tool(ToolRecord(id: id, name: name, label: label, args: args, status: .running))),
            .pause(Double(ms) / 1000),
            .event(.toolDone(id: id, status: .ok, result: result, ms: ms)),
            .pause(0.2),
        ]
    }

    private func proposed(_ label: String) -> Step {
        .event(.tool(ToolRecord(id: newID("tool"), name: "update", label: label, args: "{}", status: .proposed)))
    }

    private func propose(_ card: ConfirmCard, followUp: String?, apply: @escaping () -> String) -> Step {
        proposals[card.id] = Proposal(typed: card.typed, apply: apply, followUp: followUp)
        return .event(.confirm(card))
    }

    private func suggest(_ items: String...) -> Step {
        .event(.suggestions(items))
    }

    private func orderCard(_ o: Order) -> EntityCard {
        EntityCard(
            entity: "order", id: o.id, kind: "訂單", title: o.number,
            subtitle: "\(o.customer)・\(o.total.ntd)",
            badge: CardBadge(label: o.status.rawValue, tone: o.status.tone.rawValue),
            fields: [CardField(label: "品項", value: o.summary), CardField(label: "付款", value: o.payment)],
            href: nil, image: nil, site: o.siteID
        )
    }

    private func threadCard(_ c: Conversation) -> EntityCard {
        EntityCard(
            entity: "support_thread", id: c.id, kind: "客服對話", title: c.visitor,
            subtitle: "\(name(of: c.siteID))・\(c.category)",
            badge: CardBadge(label: c.status.label, tone: c.status.tone.rawValue),
            fields: [CardField(label: "最後一句", value: c.preview)],
            href: nil, image: nil, site: c.siteID
        )
    }

    private func intro() -> [Step] {
        [
            .say("我是 **Xena**，StudioX 幫你配的店長 👋\n\n我 24 小時看著你的網站：訂單、客服、流量、內容。半夜有客人問運費，我回；有人要找真人，我叫你；每天早上把昨晚的事整理給你。\n\n要我動手改東西（改訂單、寄信、發文章）時，**一定先跳確認卡片問你**，你按了我才做。"),
            suggest("今天營收多少？", "有誰在等我回覆？", "這週流量怎麼樣？"),
        ]
    }

    private func fallback(_ m: String) -> [Step] {
        [
            .say("收到：「\(m)」\n\n這個雛形還沒接上正式的 console，我現在用的是示範資料，懂的事情有限 🙂 先試試這些？"),
            suggest("今天營收多少？", "有誰在等我回覆？", "把已付款的訂單改成備貨中", "幫博信國際起草一篇新消息"),
        ]
    }

    private func revenue() -> [Step] {
        let day = orderData.filter { $0.siteID == Self.yellowgirl && $0.placedAt > ago(24 * 60) }
        let paid = day.filter { $0.status != .pending && $0.status != .cancelled && $0.status != .refunded }
        let waitingPrep = orderData.filter { $0.status == .paid }
        let pending = day.filter { $0.status == .pending }
        let sum = paid.reduce(0) { $0 + $1.total }
        var text = "過去 24 小時，黃毛丫頭有 **\(day.count) 筆訂單**，已付款的合計 **\(sum.ntd)**。\n\n"
        text += "• 已付款、等你備貨：\(waitingPrep.count) 筆\n"
        text += "• 待付款（ATM 還沒入帳）：\(pending.count) 筆\n"
        text += "• 林先生那筆已出貨的還在轉運，比預計晚一天\n\n"
        text += "中秋禮盒開始有人買了 🥮 比上週同一天多 2 筆。"
        return tool("list", "查詢黃毛丫頭過去 24 小時的訂單", args: #"{"entity":"order","since":"24h"}"#, result: "\(day.count) 筆")
            + [
                .say(text),
                .event(.cards(CardsItem(id: newID("cards"), title: "最新的訂單", cards: day.prefix(4).map(orderCard)))),
                suggest("把已付款的訂單改成備貨中", "林先生的訂單晚到了，怎麼處理？", "這週流量怎麼樣？"),
            ]
    }

    private func preparePaid() -> [Step] {
        let paid = orderData.filter { $0.status == .paid }
        let steps = tool("list", "找出已付款、還沒備貨的訂單", args: #"{"entity":"order","status":"paid"}"#, result: "\(paid.count) 筆")
        guard !paid.isEmpty else {
            return steps + [.say("目前沒有已付款、還沒備貨的訂單 👍"), suggest("今天營收多少？")]
        }
        let list = paid.map { "\($0.number) \($0.customer)" }.joined(separator: "\n")
        let card = ConfirmCard(
            id: newID("confirm"),
            title: "把 \(paid.count) 筆訂單改成「備貨中」",
            detail: "黃毛丫頭\n\(list)\n改完 10 分鐘後寄備貨通知給客人",
            danger: false, typed: nil, status: .pending
        )
        return steps + [
            .say("找到 \(paid.count) 筆已付款的訂單。改之前跟你確認一下："),
            proposed("修改 \(paid.count) 筆訂單的狀態"),
            propose(card, followUp: "好了 ✓ 客人 10 分鐘後會收到備貨通知。出貨單要我幫你整理嗎？") { [weak self] in
                self?.preparePaidOrders() ?? ""
            },
        ]
    }

    private func describe(_ o: Order) -> [Step] {
        var text = "**\(o.number)**・\(o.customer)\n• \(o.summary)\n• 合計 \(o.total.ntd)（\(o.payment)）\n• 狀態：\(o.status.rawValue)"
        if let l = o.logistics { text += "\n• 物流：\(l)" }
        if let n = o.note { text += "\n• 備註：\(n)" }
        var next: [String] = []
        if let s = o.status.next { next.append("把 \(o.number) 改成\(s.rawValue)") }
        if o.status != .refunded && o.status != .pending { next.append("幫 \(o.number) 退款") }
        return tool("get", "查詢訂單 \(o.number)", args: #"{"entity":"order"}"#, result: o.status.rawValue)
            + [.say(text), .event(.suggestions(next))]
    }

    private func move(_ o: Order, to target: OrderStatus) -> [Step] {
        guard o.status != target else { return [.say("\(o.number) 已經是「\(target.rawValue)」了。")] }
        let card = ConfirmCard(
            id: newID("confirm"),
            title: "把 \(o.number) 改成「\(target.rawValue)」",
            detail: "\(o.customer)・\(o.summary)\n目前：\(o.status.rawValue)" + (target == .shipped ? "\n改成已出貨會建立黑貓託運單並通知客人" : ""),
            danger: false, typed: nil, status: .pending
        )
        let id = o.id
        return tool("get", "查詢訂單 \(o.number)", result: o.status.rawValue) + [
            proposed("修改訂單狀態"),
            propose(card, followUp: "改好了 ✓") { [weak self] in
                guard let self, let i = self.orderData.firstIndex(where: { $0.id == id }) else { return "" }
                self.orderData[i].status = target
                self.record("依你的確認，把 \(o.number) 改成\(target.rawValue)", symbol: "shippingbox.fill", site: o.siteID)
                return "\(o.number) 已改成\(target.rawValue)"
            },
        ]
    }

    private func refund(_ o: Order) -> [Step] {
        let card = ConfirmCard(
            id: newID("confirm"),
            title: "退款 \(o.total.ntd) 給\(o.customer)",
            detail: "\(o.number)・\(o.payment)\n退款後訂單改成「已退款」，並寄通知信給客人。退了就不能復原。",
            danger: true, typed: "退款", status: .pending
        )
        let id = o.id
        return tool("get", "查詢訂單 \(o.number)", result: o.status.rawValue) + [
            .say("\(o.customer)的訂單合計 \(o.total.ntd)，用\(o.payment)付款，會原路退回。這個動作不能復原，要你打字確認："),
            proposed("退款"),
            propose(card, followUp: "已經退款 ✓ PAYUNi 處理約 3～7 個工作天，客人會收到通知信。") { [weak self] in
                guard let self, let i = self.orderData.firstIndex(where: { $0.id == id }) else { return "" }
                self.orderData[i].status = .refunded
                self.record("依你的確認，退款 \(o.total.ntd) 給\(o.customer)", symbol: "arrow.uturn.left.circle.fill", site: o.siteID, tone: .warn)
                return "已退款 \(o.total.ntd)"
            },
        ]
    }

    private func lateOrder() -> [Step] {
        let askID = newID("ask")
        asks[askID] = .lateOrder
        return tool("get", "查詢訂單 YG2610010098", result: "已出貨・黑貓")
            + tool("logistics_status", "查黑貓貨態", result: "轉運中，晚一天")
            + [
                .say("林先生的訂單 **YG2610010098**（家庭分享組合 ×2）黑貓 10/1 收件，現在還在轉運中心，預計明天下午才到。他說 **明天中午** 要送人，會趕不上。\n\n冷藏宅配沒辦法加急，我想到三個做法："),
                .event(.ask(AskItem(
                    id: askID,
                    question: "要怎麼處理？",
                    options: ["傳簡訊跟他說明，附上門市自取的折價券", "幫他補寄一份到門市，明早自取", "我自己打電話給他"],
                    multiple: false, allowText: true
                ))),
            ]
    }

    private func lateOrderChoice(_ choice: String) -> [Step] {
        guard let i = conversationData.firstIndex(where: { $0.visitor == "林先生" }) else { return fallback(choice) }
        let convID = conversationData[i].id
        if has(choice, "簡訊") {
            let sms = "林先生您好，您的鴨頭因黑貓轉運延誤，預計明天下午送達。明早可到嘉義文化路門市自取一份，憑此簡訊折 100 元。黃毛丫頭"
            let card = ConfirmCard(
                id: newID("confirm"),
                title: "傳簡訊給林先生（0928-***-114）",
                detail: "「\(sms)」\n經三竹簡訊寄出（2 則），並發一張 NT$100 門市折價券",
                danger: false, typed: nil, status: .pending
            )
            return [
                .say("好，簡訊我先擬好了，你看一下："),
                proposed("傳簡訊、發折價券"),
                propose(card, followUp: "寄出了 ✓ 我也在客服對話裡留了紀錄，他回覆的話會通知你。") { [weak self] in
                    guard let self, let j = self.conversationData.firstIndex(where: { $0.id == convID }) else { return "" }
                    self.conversationData[j].lines.append(ChatLine(id: newID("line"), author: .xena, text: "（已傳簡訊）\(sms)", at: .now))
                    self.conversationData[j].status = .human
                    self.conversationData[j].updatedAt = .now
                    self.resolveNote("note-late", "傳了簡訊、發了門市折價券")
                    self.record("依你的確認，傳簡訊給林先生並發折價券", symbol: "message.fill", site: Self.yellowgirl)
                    return "簡訊已送出、折價券已發"
                },
            ]
        }
        if has(choice, "補寄", "門市") {
            let card = ConfirmCard(
                id: newID("confirm"),
                title: "建立補寄單（NT$0）",
                detail: "林先生・家庭分享組合 ×2\n明早 10:00 前備好，嘉義文化路門市自取",
                danger: false, typed: nil, status: .pending
            )
            return [
                .say("可以，我開一張 NT$0 的補寄單，讓門市明早備好。原本那箱到了請他自己留著，不用退回："),
                proposed("建立補寄訂單"),
                propose(card, followUp: "建好了 ✓ 門市明早會收到備貨通知。要不要我也傳簡訊告訴林先生？") { [weak self] in
                    guard let self else { return "" }
                    self.orderData.append(Order(
                        id: newID("order"), number: "YG2610020040", siteID: Self.yellowgirl, customer: "林先生", phone: "0928-***-114",
                        lines: [OrderLine(name: "家庭分享組合", qty: 2, price: 0)], shippingFee: 0, status: .preparing,
                        payment: "補寄（不收費）", shipping: "門市自取・嘉義文化路", placedAt: .now, note: "補 YG2610010098 的延誤", logistics: nil
                    ))
                    self.resolveNote("note-late", "建了補寄單，明早門市自取")
                    self.record("依你的確認，幫林先生建了補寄單", symbol: "shippingbox.fill", site: Self.yellowgirl)
                    return "補寄單 YG2610020040 已建立"
                },
            ]
        }
        return [
            .say("好，電話是 **0928-***-114**。打完跟我說結果，我幫你在對話裡記一筆。這段對話我先不動，等你處理。"),
            suggest("有誰在等我回覆？"),
        ]
    }

    private func quote() -> [Step] {
        guard let i = conversationData.firstIndex(where: { $0.visitor.hasPrefix("張經理") }) else { return fallback("報價") }
        let convID = conversationData[i].id
        let draft = """
        張經理您好，
        謝謝您對 StudioX 的興趣！依您描述的需求（品牌網站＋會員＋線上金流），初步規劃如下：
        • 時程：8～12 週（設計 3 週、開發 5～7 週、測試上線 2 週）
        • 費用：NT$18～35 萬，依會員功能與金流串接方式而定
        • 包含：後台（內容、訂單、會員）、Xena AI 客服、SEO 與流量儀表板
        方便的話，這週約 30 分鐘線上會議，把需求對清楚後一週內給正式報價。
        —— StudioX
        """
        let card = ConfirmCard(
            id: newID("confirm"),
            title: "寄給張經理（chang@example.com）",
            detail: "從 StudioX 客服信箱寄出；這段對話會標成「你接手中」",
            danger: false, typed: nil, status: .pending
        )
        return tool("get", "讀取澄光設計的客服對話", result: "4 則訊息")
            + tool("search_site", "查 StudioX 的服務與報價區間", result: "網站建置、系統開發")
            + [
                .say("我擬了一份回覆，你看看：\n\n\(draft)"),
                proposed("寄出客服回覆"),
                propose(card, followUp: "寄出了 ✓ 這段對話我標成你接手中，張經理回信會直接進收件匣。") { [weak self] in
                    guard let self, let j = self.conversationData.firstIndex(where: { $0.id == convID }) else { return "" }
                    self.conversationData[j].lines.append(ChatLine(id: newID("line"), author: .staff(self.staffName), text: draft, at: .now))
                    self.conversationData[j].status = .human
                    self.conversationData[j].updatedAt = .now
                    self.resolveNote("note-quote", "回覆寄出了，等張經理回信")
                    self.record("依你的確認，把報價回覆寄給澄光設計", symbol: "paperplane.fill", site: Self.studiox)
                    return "已寄出"
                },
            ]
    }

    /// 幫你擬一段客服回覆（確認後寄出，對話標成你接手中）
    private func replyDraft(_ c: Conversation) -> [Step] {
        let text = switch c.category {
        case "產品詢問": "您好，血氧機目前有現貨，今天下午三點前確認訂單，最快明天出貨。需要的話我把報價單和出貨時程一起寄給您。"
        case "運費": "您好，冷藏宅配一箱 NT$180，滿 NT$1,500 免運；離島與部分偏遠地區另計。有其他問題隨時找我們！"
        default: "您好，謝謝您的留言！我們看到了，會盡快幫您處理，有任何問題都可以直接回覆這裡。"
        }
        let convID = c.id
        let card = ConfirmCard(
            id: newID("confirm"),
            title: "回覆\(c.visitor)",
            detail: "「\(text)」\n從\(name(of: c.siteID))的客服寄出；這段對話會標成「你接手中」",
            danger: false, typed: nil, status: .pending
        )
        return tool("get", "讀取\(c.visitor)的客服對話", result: "\(c.lines.count) 則訊息") + [
            .say("我照對話內容擬了一段，你看看："),
            proposed("寄出客服回覆"),
            propose(card, followUp: "寄出了 ✓ 對方回覆的話會出現在收件匣。") { [weak self] in
                guard let self, let i = self.conversationData.firstIndex(where: { $0.id == convID }) else { return "" }
                self.conversationData[i].lines.append(ChatLine(id: newID("line"), author: .staff(self.staffName), text: text, at: .now))
                self.conversationData[i].status = .human
                self.conversationData[i].updatedAt = .now
                self.record("依你的確認，回覆了\(self.conversationData[i].visitor)", symbol: "paperplane.fill", site: self.conversationData[i].siteID)
                return "已寄出"
            },
        ]
    }

    private func waiting() -> [Step] {
        let list = conversationData
            .filter { $0.status == .waiting || ($0.status == .human && $0.lastFromVisitor) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let steps = tool("list", "查詢三個網站等你回覆的對話", args: #"{"entity":"support_thread","status":"waiting"}"#, result: "\(list.count) 段")
        guard !list.isEmpty else {
            return steps + [.say("現在沒有人在等你 🙌 其他的我都回好了。"), suggest("今天營收多少？")]
        }
        var text = "有 **\(list.count) 段**在等你：\n\n"
        for c in list {
            text += "• **\(c.visitor)**（\(name(of: c.siteID))・\(c.category)）：\(c.preview.prefix(28))…\n"
        }
        text += "\n其他的我都回好了，今天一共回了 9 位訪客。"
        return steps + [
            .say(text),
            .event(.cards(CardsItem(id: newID("cards"), title: nil, cards: list.map(threadCard)))),
            suggest("幫我擬一份給澄光設計張經理的報價回覆", "林先生的訂單晚到了，怎麼處理？"),
        ]
    }

    private func traffic(siteID: String?) -> [Step] {
        let list = siteID.map { id in siteData.filter { $0.id == id } } ?? siteData
        var text = "最近 7 天：\n\n"
        for s in list {
            let change = s.stats.change.map(percentChange) ?? "—"
            let top = s.stats.pages.first.map { "，最多人看〈\($0.title)〉" } ?? ""
            text += "• **\(s.name)**：\(s.stats.visitors.formatted()) 位訪客（\(change)）\(top)\n"
        }
        let live = list.reduce(0) { $0 + $1.stats.live }
        text += "\n現在一共 \(live) 人在線上。"
        if siteID == nil || siteID == Self.studiox { text += "StudioX 的成長主要來自 Google 搜尋「AI 客服」。" }
        return tool("traffic_report", "讀取流量報表（7 天）", args: #"{"days":7}"#, result: "\(list.count) 個網站")
            + [.say(text), suggest("幫博信國際起草一篇新消息", "今天營收多少？")]
    }

    private func draft(siteID: String?) -> [Step] {
        guard let siteID else {
            let askID = newID("ask")
            asks[askID] = .draftSite
            return [.event(.ask(AskItem(id: askID, question: "要發在哪個網站？", options: siteData.map(\.name), multiple: false, allowText: false)))]
        }
        let title: String
        let summary: String
        let outline: [String]
        switch siteID {
        case Self.bsi:
            title = "血氧機選購指南：診所該注意的 5 個規格"
            summary = "從量測準確度、耐用度到保固，整理診所採購血氧機時最常問的問題。"
            outline = ["為什麼準確度要看 ±2%", "成人與兒童探頭", "電池與清潔", "保固與校正", "博信的產品怎麼選"]
        case Self.yellowgirl:
            title = "中秋前最後出貨日公告"
            summary = "中秋節前最後一天冷藏出貨是 10/3，想在節前收到的朋友請把握時間！"
            outline = ["最後出貨日與到貨時間", "門市自取的時段", "禮盒還剩多少"]
        default:
            title = "小店的 AI 店長：Xena 一天都在做什麼"
            summary = "從回答運費、轉真人到每日摘要，看一位 AI 店長怎麼陪小店值班 24 小時。"
            outline = ["半夜的客服", "什麼時候叫真人", "每天早上的摘要", "為什麼動手前一定先問"]
        }
        let siteName = name(of: siteID)
        let card = ConfirmCard(
            id: newID("confirm"),
            title: "在\(siteName)建立草稿「\(title)」",
            detail: "存成草稿，不會發布；之後可以在後台或這裡改",
            danger: false, typed: nil, status: .pending
        )
        return tool("list", "讀取\(siteName)的內容與最近的搜尋關鍵字", result: "OK")
            + [
                .say("我起草了一篇，先存成草稿給你看：\n\n**\(title)**\n\(summary)\n\n大綱：\n" + outline.map { "• \($0)" }.joined(separator: "\n")),
                proposed("建立草稿"),
                propose(card, followUp: "存好了 ✓ 草稿在\(siteName)後台的「最新消息」。要我排程在週五早上發布嗎？") { [weak self] in
                    guard let self, let i = self.siteData.firstIndex(where: { $0.id == siteID }) else { return "" }
                    self.siteData[i].content.insert(ContentEntry(id: newID("entry"), collection: "最新消息", title: title, state: .draft, updatedAt: .now), at: 0)
                    if siteID == Self.bsi { self.resolveNote("note-bsi", "起草了「\(title)」") }
                    self.record("依你的確認，在\(siteName)建立草稿「\(title)」", symbol: "doc.badge.plus", site: siteID)
                    return "草稿已建立"
                },
            ]
    }
}

// MARK: - 示範資料

private extension DemoConsole {
    func trend(_ visitors: [Int], ratio: Double) -> [TrafficPoint] {
        let cal = Calendar.current
        return visitors.enumerated().map { i, v in
            let day = cal.date(byAdding: .day, value: i - visitors.count + 1, to: now) ?? now
            let label = "\(cal.component(.month, from: day))/\(cal.component(.day, from: day))"
            return TrafficPoint(label: label, visitors: v, pageviews: Int(Double(v) * ratio))
        }
    }

    func makeSites() -> [Site] {
        [
            Site(
                id: Self.studiox, name: "StudioX.tw", org: "StudioX", domain: "studiox.tw",
                adminURL: URL(string: "https://cms.studiox.tw/admin")!, role: .owner,
                modules: [.content, .assistant, .support], icon: .mark, tint: Brand.accent,
                stats: SiteStats(
                    live: 7, visitors: 1204, pageviews: 3870, bounceRate: 0.41, avgDuration: 94, change: 0.18,
                    trend: trend([142, 168, 155, 190, 176, 201, 172], ratio: 3.2),
                    pages: [
                        PageStat(path: "/news/typesafe-jev-decision-model", title: "TypeSafe Jev：先分類，再回答", visitors: 188),
                        PageStat(path: "/", title: "首頁", visitors: 520),
                        PageStat(path: "/services/ai", title: "AI 導入", visitors: 214),
                        PageStat(path: "/projects", title: "作品", visitors: 160),
                    ]
                ),
                content: [
                    ContentEntry(id: "s-1", collection: "最新消息", title: "AI 客服導入前要準備的事", state: .scheduled, updatedAt: ago(60 * 5)),
                    ContentEntry(id: "s-2", collection: "最新消息", title: "小店電商自動化的五個起點", state: .draft, updatedAt: ago(60 * 26)),
                    ContentEntry(id: "s-3", collection: "最新消息", title: "TypeSafe Jev：先分類，再回答", state: .published, updatedAt: ago(60 * 72)),
                ]
            ),
            Site(
                id: Self.yellowgirl, name: "黃毛丫頭", org: "黃毛丫頭", domain: "yellowgirl.tw",
                adminURL: URL(string: "https://cms.yellowgirl.tw/admin")!, role: .owner,
                modules: [.content, .assistant, .support, .commerce], icon: .letter("黃"), tint: Color(hex: 0xF2B705),
                stats: SiteStats(
                    live: 21, visitors: 3212, pageviews: 11480, bounceRate: 0.33, avgDuration: 151, change: 0.07,
                    trend: trend([402, 455, 438, 471, 520, 498, 428], ratio: 3.6),
                    pages: [
                        PageStat(path: "/", title: "首頁地圖", visitors: 1380),
                        PageStat(path: "/shop", title: "商店", visitors: 940),
                        PageStat(path: "/shop/bundles/family", title: "家庭分享組合", visitors: 402),
                        PageStat(path: "/news/mid-autumn", title: "中秋禮盒預購開跑", visitors: 310),
                    ]
                ),
                content: [
                    ContentEntry(id: "y-1", collection: "最新消息", title: "冷藏宅配運費調整公告", state: .draft, updatedAt: ago(130)),
                    ContentEntry(id: "y-2", collection: "最新消息", title: "中秋禮盒預購開跑", state: .published, updatedAt: ago(60 * 24 * 5)),
                ]
            ),
            Site(
                id: Self.bsi, name: "博信國際", org: "BSI", domain: "www.bsi-med.com",
                adminURL: URL(string: "https://console.studiox.tw/sites")!, role: .owner,
                modules: [.content, .assistant], icon: .letter("博"), tint: Color(hex: 0x2F6FDB),
                stats: SiteStats(
                    live: 3, visitors: 363, pageviews: 902, bounceRate: 0.52, avgDuration: 71, change: -0.04,
                    trend: trend([41, 52, 47, 58, 61, 49, 55], ratio: 2.5),
                    pages: [
                        PageStat(path: "/products", title: "產品型錄", visitors: 96),
                        PageStat(path: "/", title: "首頁", visitors: 120),
                        PageStat(path: "/about", title: "關於博信", visitors: 55),
                    ]
                ),
                content: [
                    ContentEntry(id: "b-1", collection: "最新消息", title: "2026 醫療器材展參展紀錄", state: .published, updatedAt: ago(60 * 24 * 34)),
                ]
            ),
        ]
    }

    func makeOrders() -> [Order] {
        let ship = "黑貓宅配・冷藏"
        return [
            Order(id: "o-31", number: "YG2610020031", siteID: Self.yellowgirl, customer: "王小姐", phone: "0912-***-318",
                  lines: [OrderLine(name: "招牌鴨頭", qty: 2, price: 90), OrderLine(name: "鴨翅", qty: 4, price: 35), OrderLine(name: "米血糕", qty: 2, price: 25)],
                  shippingFee: 180, status: .paid, payment: "ATM 轉帳（已入帳）", shipping: ship, placedAt: ago(95), note: nil, logistics: nil),
            Order(id: "o-27", number: "YG2610020027", siteID: Self.yellowgirl, customer: "陳先生", phone: "0935-***-207",
                  lines: [OrderLine(name: "家庭分享組合", qty: 1, price: 680), OrderLine(name: "豆干", qty: 2, price: 20)],
                  shippingFee: 180, status: .paid, payment: "信用卡", shipping: ship, placedAt: ago(160), note: nil, logistics: nil),
            Order(id: "o-19", number: "YG2610020019", siteID: Self.yellowgirl, customer: "林媽媽", phone: "0921-***-552",
                  lines: [OrderLine(name: "招牌鴨頭", qty: 3, price: 90), OrderLine(name: "鴨脖子", qty: 2, price: 40), OrderLine(name: "甜不辣", qty: 2, price: 30)],
                  shippingFee: 180, status: .paid, payment: "ATM 轉帳（已入帳）", shipping: ship, placedAt: ago(290), note: "下午收件", logistics: nil),
            Order(id: "o-12", number: "YG2610020012", siteID: Self.yellowgirl, customer: "黃先生", phone: "0987-***-031",
                  lines: [OrderLine(name: "中秋禮盒", qty: 2, price: 880)],
                  shippingFee: 0, status: .pending, payment: "ATM 轉帳（等待入帳）", shipping: ship, placedAt: ago(330), note: nil, logistics: nil),
            Order(id: "o-98", number: "YG2610010098", siteID: Self.yellowgirl, customer: "林先生", phone: "0928-***-114",
                  lines: [OrderLine(name: "家庭分享組合", qty: 2, price: 680)],
                  shippingFee: 0, status: .shipped, payment: "信用卡", shipping: ship, placedAt: ago(60 * 40), note: "10/3 中午要送人",
                  logistics: "黑貓 10/1 收件，轉運中（比預計晚一天）"),
            Order(id: "o-85", number: "YG2610010085", siteID: Self.yellowgirl, customer: "張先生", phone: "0910-***-776",
                  lines: [OrderLine(name: "中秋禮盒", qty: 1, price: 880), OrderLine(name: "米血糕", qty: 4, price: 25)],
                  shippingFee: 0, status: .preparing, payment: "信用卡", shipping: ship, placedAt: ago(60 * 26), note: nil, logistics: nil),
            Order(id: "o-90", number: "YG2610010090", siteID: Self.yellowgirl, customer: "吳小姐", phone: "0958-***-640",
                  lines: [OrderLine(name: "招牌鴨頭", qty: 2, price: 90), OrderLine(name: "鴨翅", qty: 2, price: 35)],
                  shippingFee: 180, status: .completed, payment: "LINE Pay", shipping: ship, placedAt: ago(60 * 50), note: nil, logistics: "已送達"),
        ]
    }

    func makeConversations() -> [Conversation] {
        [
            Conversation(
                id: "c-lin", siteID: Self.yellowgirl, visitor: "林先生", contact: "0928-***-114", category: "訂單問題", humanScore: 0.86, status: .waiting,
                lines: [
                    ChatLine(id: "l1", author: .visitor, text: "我前天訂的鴨頭還沒到，明天中午要送人，可以加急嗎？", at: ago(500)),
                    ChatLine(id: "l2", author: .xena, text: "我查了你的訂單 YG2610010098：黑貓 10/1 收件，目前在轉運，比預計晚一天。冷藏宅配沒辦法加急，我請店裡的人幫你想辦法。", at: ago(499)),
                    ChatLine(id: "l3", author: .visitor, text: "可以找真人嗎？我很急", at: ago(497)),
                    ChatLine(id: "l4", author: .xena, text: "好，我已經通知店裡，他們看到會馬上回你。也可以先留電話，我們直接打給你。", at: ago(496)),
                    ChatLine(id: "l5", author: .visitor, text: "0928-***-114，麻煩了", at: ago(495)),
                ],
                updatedAt: ago(495)
            ),
            Conversation(
                id: "c-chang", siteID: Self.studiox, visitor: "張經理（澄光設計）", contact: "chang@example.com", category: "費用報價", humanScore: 0.91, status: .waiting,
                lines: [
                    ChatLine(id: "l1", author: .visitor, text: "你好，我們想做一個有會員和金流的品牌網站，大概需要多少預算跟時間？", at: ago(130)),
                    ChatLine(id: "l2", author: .xena, text: "可以的！有會員和金流的網站通常 8～12 週，費用依功能大約 NT$18～35 萬。想要精準報價的話，我請專人跟你聯絡？", at: ago(129)),
                    ChatLine(id: "l3", author: .visitor, text: "好，麻煩了，我的 Email 是 chang@example.com", at: ago(127)),
                    ChatLine(id: "l4", author: .xena, text: "記下了，已經轉給專人，上班時間一天內會回覆你 🙌", at: ago(126)),
                ],
                updatedAt: ago(126)
            ),
            Conversation(
                id: "c-2377", siteID: Self.yellowgirl, visitor: "訪客 #2377", contact: nil, category: "運費", humanScore: 0.12, status: .ai,
                lines: [
                    ChatLine(id: "l1", author: .visitor, text: "冷藏宅配運費多少？滿多少免運？", at: ago(40)),
                    ChatLine(id: "l2", author: .xena, text: "冷藏宅配一箱 NT$180，滿 NT$1,500 免運。離島與部分偏遠地區另計喔！", at: ago(40)),
                ],
                updatedAt: ago(40)
            ),
            Conversation(
                id: "c-li", siteID: Self.bsi, visitor: "李小姐（安康診所）", contact: "li@example.com", category: "產品詢問", humanScore: 0.82, status: .human,
                lines: [
                    ChatLine(id: "l1", author: .visitor, text: "想詢問血氧機的經銷價格", at: ago(60 * 20)),
                    ChatLine(id: "l2", author: .xena, text: "經銷價格要由業務提供，我幫你轉給專人，請留一下 Email？", at: ago(60 * 20)),
                    ChatLine(id: "l3", author: .staff("Andy"), text: "李小姐您好，經銷價格表已寄到您的信箱，有問題隨時找我。", at: ago(60 * 19)),
                    ChatLine(id: "l4", author: .visitor, text: "收到了，請問最快什麼時候可以出貨？", at: ago(60 * 3)),
                ],
                updatedAt: ago(60 * 3)
            ),
            Conversation(
                id: "c-2369", siteID: Self.yellowgirl, visitor: "訪客 #2369", contact: nil, category: "商品詢問", humanScore: 0.08, status: .closed,
                lines: [
                    ChatLine(id: "l1", author: .visitor, text: "鴨頭會辣嗎？小朋友可以吃嗎", at: ago(60 * 9)),
                    ChatLine(id: "l2", author: .xena, text: "招牌鴨頭是醬香微甜、不辣，小朋友也可以吃！想吃辣的話可以加購辣椒醬包 🌶️", at: ago(60 * 9)),
                ],
                updatedAt: ago(60 * 9)
            ),
        ]
    }

    func makeNotes() -> [XenaNote] {
        [
            XenaNote(
                id: "note-late", kind: .attention, siteID: Self.yellowgirl,
                title: "林先生的訂單會晚到",
                body: "YG2610010098 黑貓 10/1 收件，現在還在轉運。他明天中午要送人，在客服問能不能加急——Jev 判斷要找人（86%），我已經推播給你。",
                at: ago(495), prompt: "林先生的訂單晚到了，怎麼處理比較好？", promptLabel: "一起想辦法"
            ),
            XenaNote(
                id: "note-prep", kind: .suggestion, siteID: Self.yellowgirl,
                title: "3 筆訂單可以備貨了",
                body: "王小姐、陳先生、林媽媽的訂單都付款了。要我改成「備貨中」嗎？改完照「給客人的通知」，10 分鐘後通知客人。",
                at: ago(60),
                proposal: ConfirmCard(
                    id: "note-prep", title: "把 3 筆訂單改成「備貨中」",
                    detail: "黃毛丫頭\nYG2610020031 王小姐\nYG2610020027 陳先生\nYG2610020019 林媽媽\n改完 10 分鐘後寄備貨通知給客人",
                    danger: false, typed: nil, status: .pending
                )
            ),
            XenaNote(
                id: "note-quote", kind: .attention, siteID: Self.studiox,
                title: "澄光設計在等報價",
                body: "張經理想做有會員和金流的品牌網站，留了 Email。Jev 分類：費用報價（91%）。我先給了 18～35 萬的區間。",
                at: ago(126), prompt: "幫我擬一份給澄光設計張經理的報價回覆", promptLabel: "幫我擬回覆"
            ),
            XenaNote(
                id: "note-bsi", kind: .insight, siteID: Self.bsi,
                title: "博信國際 34 天沒有新內容",
                body: "上一篇是參展紀錄。這週「血氧機」在 Google 的曝光多了 12%，要不要我依產品型錄起草一篇新消息？",
                at: ago(60 * 6), prompt: "幫博信國際起草一篇新消息", promptLabel: "起草一篇"
            ),
        ]
    }

    func makeLog() -> [ShiftEntry] {
        [
            ShiftEntry(id: "g1", at: ago(840), symbol: "moon.stars.fill", text: "新的一輪值班開始。三個網站都正常，網域與憑證都還有效", siteID: nil, tone: .info),
            ShiftEntry(id: "g2", at: ago(790), symbol: "bubble.left.and.bubble.right.fill", text: "回覆 4 位訪客的冷藏運費問題", siteID: Self.yellowgirl, tone: .ok),
            ShiftEntry(id: "g3", at: ago(620), symbol: "waveform.path.ecg", text: "studiox.tw 回應變慢 2 分鐘（重新部署），已經恢復", siteID: Self.studiox, tone: .warn),
            ShiftEntry(id: "g4", at: ago(495), symbol: "bell.badge.fill", text: "林先生問能不能加急，判斷要找人，已經推播給你", siteID: Self.yellowgirl, tone: .warn),
            ShiftEntry(id: "g5", at: ago(330), symbol: "cart.fill", text: "黃先生訂了中秋禮盒 ×2，等 ATM 入帳", siteID: Self.yellowgirl, tone: .muted),
            ShiftEntry(id: "g6", at: ago(240), symbol: "externaldrive.fill.badge.checkmark", text: "清掉 400 天前的流量資料，備份完成", siteID: nil, tone: .muted),
            ShiftEntry(id: "g7", at: ago(126), symbol: "envelope.badge.fill", text: "澄光設計的張經理留了 Email，等你報價", siteID: Self.studiox, tone: .warn),
            ShiftEntry(id: "g8", at: ago(60), symbol: "sun.max.fill", text: "寄出每日摘要給你", siteID: nil, tone: .ok),
            ShiftEntry(id: "g9", at: ago(40), symbol: "checkmark.bubble.fill", text: "回答了「滿多少免運」", siteID: Self.yellowgirl, tone: .ok),
        ]
    }
}
