import AVFoundation
import SwiftUI

/// 跟 Xena 用說的，一來一往（手機上的 Apple Intelligence 先處理，再跟雲端的 Xena 配合）：
///   你說（水珠跟著你的音量起伏、字幕邊說邊出字）→ 停一下就當作說完 →
///   Apple Intelligence 先聽懂：切頁、念卡片、再說一次、確認／取消、選選項、閒聊、結束，手機上馬上處理；
///   其他的整理好交給雲端的 Xena（和打字同一個 Xena、同一份對話紀錄），她先回一句「好，我看一下…」→
///   回答的第一句馬上說；短的就說完，太長的由 Apple Intelligence 濃縮成兩三句重點，整段放卡片（標題＋重點）→
///   水珠跟著她說的每個字 → 說完換你說。沒有 Apple Intelligence：看關鍵字、照順序念到上限。
/// 點一下水珠：她在說就停下來換你說；你在說就當作說完了。
/// 她丟出來的東西（問你的問題＋選項、資料卡片、要你確認的事）照樣出現在畫面上：可以按，也可以用說的回答
/// （一般的確認說「確認／取消」就好；退款、刪除這類危險的一定要在畫面上按，會再驗證 Face ID）。
@Observable
final class XenaConversation {
    enum State: Equatable {
        case off
        case preparing
        case listening
        case thinking
        case speaking
        /// 停著等你點（沒聽到聲音、有事要你確認）
        case paused
        case failed(String)
    }

    private(set) var state: State = .off
    /// 你正在說的話（字幕；說完就變成這一輪的「你說的」）
    private(set) var heard = ""
    /// 這一輪你說的（說完的那一句，或在畫面上按的選項）
    private(set) var said = ""
    /// Xena 這一輪的回答（字幕）
    private(set) var reply = ""
    /// 之前的每一輪（往上滑可以找回來）
    private(set) var history: [VoiceTurn] = []
    /// 這一輪、下一輪（你正在說的那一塊）的 id：說完時那一塊直接接成這一輪，畫面上不會跳
    private(set) var liveID = UUID().uuidString
    private(set) var nextID = UUID().uuidString
    /// 這一輪她丟出來、要放在畫面上的東西（問題＋選項、資料卡片、確認卡片）
    private(set) var turnItems: [ChatItem] = []
    /// 還沒回答的問題
    private(set) var pendingAsk: AskItem?
    /// 還沒決定的確認卡片
    private(set) var pendingCard: ConfirmCard?
    /// 回答太長：整段放在卡片上給你看（她只說開頭和重點；說「念給我聽」才全部念）
    private(set) var readingCard: ReadingCard?
    /// 最近一張長回答卡片（移到上面去了也一樣，說「念給我聽」念這張）
    @ObservationIgnored private var lastCard: ReadingCard?
    /// 已經移到上面（之前的輪）的東西：這一輪不再重複顯示
    @ObservationIgnored private var archivedIDs: Set<String> = []
    @ObservationIgnored private var liveItemIDs: [String] = []
    /// 這次聽你說話用的是 iOS 26 的 SpeechAnalyzer（不然是舊的語音辨識）
    private(set) var usesAnalyzer = false
    /// 麥克風被拒絕：畫面上給「打開設定」
    private(set) var needsSettings = false

    /// 你說話時水珠跟著你的音量（能量低一點，只是起伏）
    let micVoice = XenaVoice(intensity: 0.4)
    let mouth = XenaMouth()

    @ObservationIgnored private let ear = XenaEar()
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var meter: Task<Void, Never>?
    @ObservationIgnored private var micTurn: Int?
    /// 這一次的回答念到第幾個字（Xena 回一句念一句）
    @ObservationIgnored private var spokenUpTo = 0
    @ObservationIgnored private var awaitingReply = false
    /// 最後一則「你說的」（按了選項也算）：變了就是新的一輪
    @ObservationIgnored private var lastUserID: String?
    /// 已經念過的問題、確認卡片（不重念）
    @ObservationIgnored private var announced: Set<String> = []
    /// 念過、等你決定的那張確認卡片：決定了要說結果
    @ObservationIgnored private var watchedCard: String?
    /// 用說的確認、正在送出的那張（沒送成功要說一聲，不要卡在「想一下」）
    @ObservationIgnored private var votedCard: String?
    /// 這一輪馬上說出口的第一句（通常就是答案）；後面的先留著，等整段回來看長短再決定
    @ObservationIgnored private var firstSaid = ""
    @ObservationIgnored private var held: [String] = []
    /// 這一輪已經先回過「好，我看一下…」（她自己的「我查一下」就不再說）
    @ObservationIgnored private var ackSaid = false
    /// 她上一次說出口的每一句（「再說一次」）
    @ObservationIgnored private var spokenLines: [String] = []
    /// Apple Intelligence 正在聽懂你說的話（她可能已經先回了一句）
    @ObservationIgnored private var routing = false
    /// 這一輪已經說過「我在查…」的工具
    @ObservationIgnored private var toldTools: Set<String> = []
    /// 等太久就說一聲「還在查」
    @ObservationIgnored private var waitTalk: Task<Void, Never>?
    /// 長的回答收尾中（請 Apple Intelligence 濃縮重點）
    @ObservationIgnored private var wrappingUp = false
    /// 一次最多念多少字（大約 15 秒），再長就放卡片
    static let speechBudget = 90
    /// 指令：說完「好，打開訂單」就關掉語音、切過去
    @ObservationIgnored private var afterSpeaking: (() -> Void)?

    init() {
        mouth.onIdle = { [weak self] in self?.mouthIdle() }
    }

    func attach(_ model: AppModel) {
        self.model = model
    }

    var mood: XenaMood {
        switch state {
        case .listening: .listening
        case .thinking, .preparing: .thinking
        case .speaking: .speaking
        default: .idle
        }
    }

    /// 水珠現在跟著誰的聲音
    var activeVoice: XenaVoice {
        state == .listening ? micVoice : mouth.voice
    }

    // MARK: 開始、結束

    func start() async {
        switch state {
        case .off, .paused, .failed: break
        default: return
        }
        // UI 截圖：放一段示範的對話（示範模式本身照樣可以用說的，Xena 用示範的回答）
        if DemoServer.screenshots {
            showDemo()
            return
        }
        state = .preparing
        needsSettings = false
        // 之前的對話不算這一輪
        lastUserID = model?.xena.items.last(where: { if case .user = $0 { true } else { false } })?.id
        XenaLocal.shared.prewarm()
        guard await XenaEar.requestMicrophone() else {
            needsSettings = true
            state = .failed(XenaEar.Failure.microphoneDenied.localizedDescription)
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
        } catch {
            state = .failed("聲音打不開：\(error.localizedDescription)")
            return
        }
        await listen()
    }

    /// 關掉語音（離開畫面、App 進背景）
    func end() {
        state = .off
        silence?.cancel()
        meter?.cancel()
        awaitingReply = false
        afterSpeaking = nil
        mouth.stop()
        if let micTurn { micVoice.end(micTurn) }
        micTurn = nil
        heard = ""
        said = ""
        reply = ""
        turnItems = []
        history = []
        archivedIDs = []
        liveItemIDs = []
        pendingAsk = nil
        pendingCard = nil
        watchedCard = nil
        readingCard = nil
        lastCard = nil
        wrappingUp = false
        firstSaid = ""
        held = []
        spokenLines = []
        routing = false
        waitTalk?.cancel()
        let ear = ear
        Task {
            await ear.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// 點一下水珠
    func tap() async {
        switch state {
        case .listening:
            await doneTalking()
        case .speaking, .thinking:
            // 打斷：她不說了，換你說（Xena 的回答照樣存在對話紀錄裡）
            state = .preparing
            awaitingReply = false
            wrappingUp = false
            held = []
            routing = false
            waitTalk?.cancel()
            afterSpeaking = nil
            mouth.stop()
            await listen()
        case .paused, .failed:
            if case .failed = state { await restart() } else { await listen() }
        case .off:
            await start()
        case .preparing:
            break
        }
    }

    private func restart() async {
        state = .off
        await start()
    }

    // MARK: 聽

    private func listen() async {
        state = .preparing
        mouth.stop()
        heard = ""
        do {
            try await ear.start(locale: Locale(identifier: "zh-TW")) { [weak self] text, _ in
                Task { @MainActor in self?.hear(text) }
            }
        } catch {
            needsSettings = (error as? XenaEar.Failure) == .speechDenied
            state = .failed(error.localizedDescription)
            return
        }
        usesAnalyzer = ear.usesAnalyzer
        state = .listening
        micTurn = micVoice.begin()
        meter?.cancel()
        meter = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .listening else { return }
                self.micVoice.hear(Double(self.ear.level))
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        armSilence(waitingForFirstWord: true)
    }

    private func hear(_ text: String) {
        guard state == .listening else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != heard else { return }
        heard = trimmed
        armSilence(waitingForFirstWord: trimmed.isEmpty)
    }

    /// 停一下就當作說完了（還沒開口：等久一點，太久就先停下來，不要一直開著麥克風）
    private func armSilence(waitingForFirstWord: Bool) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: waitingForFirstWord ? .seconds(8) : .milliseconds(1100))
            guard !Task.isCancelled, let self, self.state == .listening else { return }
            if self.heard.isEmpty {
                await self.stopListening()
                self.state = .paused
            } else {
                await self.doneTalking()
            }
        }
    }

    private func stopListening() async {
        silence?.cancel()
        meter?.cancel()
        if let micTurn { micVoice.end(micTurn) }
        micTurn = nil
        await ear.stop()
    }

    /// 你說完了：先讓手機上的 Apple Intelligence 聽懂這一句；它能處理的馬上做，其他的整理好交給雲端的 Xena
    private func doneTalking() async {
        guard state == .listening else { return }
        state = .thinking
        let text = heard
        await stopListening()
        guard !text.isEmpty else {
            state = .paused
            return
        }
        let previous = spokenLines
        spokenLines = []
        let known = context(previous: previous)
        // 你說的那一塊接成新的一輪，上一輪往上移
        startTurn(said: text)
        // 要交給 Xena 的：她針對內容先回的那一句一好就說（「好，我查一下昨天的訂單。」），不等後面
        var reacted = false
        routing = true
        let intent = await XenaLocal.shared.understand(text, context: known) { [weak self] line in
            guard let self, self.state == .thinking, Self.isAck(line, for: text) else { return }
            reacted = true
            self.say(line)
        }
        routing = false
        // 等它的時候被打斷、關掉了
        guard state == .thinking || (reacted && state == .speaking) else { return }
        if let intent {
            handle(intent, text: text, previous: previous, reacted: reacted)
        } else {
            fallback(text)
        }
    }

    /// 聽懂一句話時要一起看的：網站、畫面上等你確認的事、她問你的問題、有沒有長回答的卡片、她剛剛說的
    private func context(previous: [String]) -> VoiceContext {
        var c = VoiceContext()
        c.sites = model?.sites.map(\.name) ?? []
        if let card = pendingCard { c.card = card.title }
        if let ask = pendingAsk {
            c.question = ask.question
            c.options = ask.options
        }
        c.hasReadingCard = lastCard != nil
        c.lastReply = previous.isEmpty ? (reply.isEmpty ? history.last?.reply ?? "" : reply) : previous.joined()
        return c
    }

    /// 這一輪的樣子（畫面用）
    private var liveTurn: VoiceTurn {
        VoiceTurn(id: liveID, said: said, reply: reply, card: readingCard, items: turnItems)
    }

    /// 畫面上的每一輪：之前的、這一輪、你正在說的
    var turns: [VoiceTurn] {
        var all = history
        let live = liveTurn
        if !live.isEmpty { all.append(live) }
        if !heard.isEmpty { all.append(VoiceTurn(id: nextID, said: heard)) }
        return all
    }

    /// 新的一輪：這一輪移到上面，你正在說的那一塊（同一個 id）接成這一輪
    private func startTurn(said text: String) {
        let live = liveTurn
        if !live.isEmpty {
            history.append(live)
            if history.count > 40 { history.removeFirst(history.count - 40) }
        }
        archivedIDs.formUnion(liveItemIDs)
        liveItemIDs = []
        liveID = nextID
        nextID = UUID().uuidString
        said = text
        heard = ""
        reply = ""
        readingCard = nil
        turnItems = []
    }

    /// Apple Intelligence 聽懂了：手機上能做的馬上做，其他的交給 Xena
    private func handle(_ intent: VoiceIntent, text: String, previous: [String], reacted: Bool) {
        switch intent.action {
        case .open:
            go(Command(place: intent.place, site: intent.site))
        case .read where lastCard != nil:
            readAloud()
        case .again where !previous.isEmpty:
            for line in previous { say(line) }
            if !mouth.speaking { replyDone() }
        case .approve where pendingCard != nil, .reject where pendingCard != nil:
            let card = pendingCard!
            if card.danger || card.typed != nil {
                speakLocally("「\(card.title)」比較重要，請在畫面上按確認。")
                return
            }
            // 同意一定要很明確（「好」「確認」「做吧」這類短短一句）；取消要短；不明確就當成一般的話交給 Xena
            let approve = intent.action == .approve
            if approve ? Self.decision(in: text) == true : (Self.decision(in: text) == false || text.count <= 10) {
                decide(card, approve: approve)
            } else {
                forward(intent, text: text, reacted: reacted)
            }
        case .answer where pendingAsk != nil:
            let ask = pendingAsk!
            send(Self.pick(intent.answer, from: ask, original: text), answering: ask.id)
        case .chat where Self.casual(intent.say):
            speakLocally(intent.say)
        case .done:
            close(after: "好，有需要再叫我。")
        default:
            forward(intent, text: text, reacted: reacted)
        }
    }

    /// 沒有 Apple Intelligence：看關鍵字
    private func fallback(_ text: String) {
        if lastCard != nil, Self.wantsReading(text) {
            readAloud()
            return
        }
        // 等你決定的確認卡片：「確認」「取消」（危險的不行，要在畫面上按）
        if let card = pendingCard, !card.danger, card.typed == nil, let approve = Self.decision(in: text) {
            decide(card, approve: approve)
            return
        }
        // 她問你的問題：這句就是答案
        if let ask = pendingAsk {
            send(text, answering: ask.id)
            return
        }
        if let command = Self.keyword(text) {
            go(command)
            return
        }
        send(text, answering: nil)
        ackSaid = true
        say("好，我看一下。")
    }

    /// 交給雲端的 Xena：Apple Intelligence 整理過的話（只修正聽錯的字，數字對得上才用）。
    /// 她針對內容先回的一句（已經說了就不再說；沒有就說「好，我看一下。」），雲端的回答接在後面
    private func forward(_ intent: VoiceIntent?, text: String, reacted: Bool) {
        var message = text
        if let intent, intent.action == .ask, Self.faithful(intent.message, to: text) {
            message = intent.message
        }
        // 她問了問題還沒回答：這句就當作回答
        send(message, answering: pendingAsk?.id)
        ackSaid = true
        if reacted {
            // 先回的那一句還在說（送出時被設成「想一下」）
            if mouth.speaking { state = .speaking }
            return
        }
        if let line = intent?.say, intent?.action == .ask, Self.isAck(line, for: text) {
            say(line)
        } else {
            say("好，我看一下。")
        }
    }

    /// 用說的決定確認卡片（結果出來會再說一聲）
    private func decide(_ card: ConfirmCard, approve: Bool) {
        watchedCard = card.id
        votedCard = card.id
        model?.xena.decide(card.id, approve: approve)
    }

    /// 手機上直接回一句（閒聊、提醒），說完換你說
    private func speakLocally(_ line: String) {
        reply = line
        if AppSettings.shared.speakReplies {
            say(line)
        } else {
            replyDone()
        }
    }

    /// 說一句就關掉語音的畫面
    private func close(after line: String) {
        guard let model else { return }
        reply = line
        let leave = { [weak self] in
            self?.end()
            model.showVoice = false
        }
        if AppSettings.shared.speakReplies {
            afterSpeaking = leave
            say(line)
        } else {
            leave()
        }
    }

    /// 她問的問題：Apple Intelligence 聽出來選的是哪一個（「第二個」也算）；對不上選項就用你說的原話
    static func pick(_ said: String, from ask: AskItem, original: String) -> String {
        let a = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return original }
        if let exact = ask.options.first(where: { $0 == a }) { return exact }
        if let near = ask.options.first(where: { $0.contains(a) || a.contains($0) }) { return near }
        return original
    }

    /// 整理過的話還是原本的意思：不是空的、數字都是你說過的、沒有多出一大段
    static func faithful(_ message: String, to text: String) -> Bool {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.count >= 2 && m.count <= text.count * 2 + 12
            && XenaLocal.numbers(in: m).isSubset(of: XenaLocal.numbers(in: text))
    }

    /// 「好，我查一下昨天的訂單。」：短、數字只能是你說過的（還沒查，不能先講答案）
    static func isAck(_ line: String, for text: String) -> Bool {
        (2...24).contains(line.count) && XenaLocal.numbers(in: line).isSubset(of: XenaLocal.numbers(in: text))
    }

    /// 閒聊的一句：短、沒有數字（不能講到店裡的資料）
    static func casual(_ line: String) -> Bool {
        (1...30).contains(line.count) && XenaLocal.numbers(in: line).isEmpty
    }

    private func send(_ text: String, answering: String?) {
        guard let model else { return }
        if model.xena.isBusy { model.xena.stop() }
        model.xena.send(text, answering: answering)
        beginTurn()
    }

    /// 新的一輪（你說的、或你在畫面上按了選項）
    private func beginTurn() {
        guard let session = model?.xena else { return }
        lastUserID = session.items.last(where: { if case .user = $0 { true } else { false } })?.id
        reply = ""
        spokenUpTo = 0
        firstSaid = ""
        held = []
        ackSaid = false
        toldTools = []
        wrappingUp = false
        readingCard = nil
        lastCard = nil
        // 等太久（雲端在查比較多的資料）：像真人一樣說一聲，不要一直沒聲音
        waitTalk?.cancel()
        waitTalk = Task { [weak self] in
            for line in ["還在查，再等我一下。", "資料比較多，快好了。"] {
                try? await Task.sleep(for: .seconds(line.hasPrefix("還在") ? 7 : 9))
                guard !Task.isCancelled, let self, self.awaitingReply, self.firstSaid.isEmpty,
                      self.state == .thinking, !self.mouth.speaking else { return }
                self.say(line)
            }
        }
        awaitingReply = true
        turnItems = []
        pendingAsk = nil
        state = .thinking
    }

    /// 「確認」「好」→ true；「取消」「不要」→ false；聽不出來 nil（當成一般的話）
    static func decision(in text: String) -> Bool? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard t.count <= 8 else { return nil }
        let no = ["取消", "不要", "先不要", "不用", "算了", "不行", "等一下"]
        if no.contains(where: t.contains) { return false }
        let yes = ["確認", "確定", "好", "可以", "執行", "對", "沒問題", "同意", "OK", "ok", "要", "做吧", "照做", "送出", "沒錯", "就這樣"]
        if yes.contains(where: t.contains) { return true }
        return nil
    }

    // MARK: Xena 的回答

    /// 對話有變（AppModel.xena.revision）：念新的句子、把她丟出來的東西放到畫面上、確認卡片決定了說結果
    func sessionChanged() {
        guard state != .off, let session = model?.xena else { return }
        let items = session.items
        let userIndex = items.lastIndex(where: { if case .user = $0 { true } else { false } })
        // 你在畫面上按了選項（不是用說的）：也是新的一輪
        if let userIndex, items[userIndex].id != lastUserID {
            if state == .listening { Task { await stopListening() } }
            mouth.stop()
            if case .user(_, let t) = items[userIndex] { startTurn(said: t) }
            beginTurn()
        }
        let start = userIndex.map { items.index(after: $0) } ?? items.startIndex
        // text：這一輪她說的整段（念的時候用）；shownText、shown：還沒移到上面去的（這一輪顯示的）
        var text = ""
        var shownText = ""
        var shown: [ChatItem] = []
        var ids: [String] = []
        var ask: AskItem?
        var card: ConfirmCard?
        var running: [ToolRecord] = []
        for item in items[start...] {
            let fresh = !archivedIDs.contains(item.id)
            switch item {
            case .tool(let t):
                if t.status == .running { running.append(t) }
            case .assistant(_, let t), .notice(_, let t):
                text += text.isEmpty ? t : "\n" + t
                if fresh {
                    shownText += shownText.isEmpty ? t : "\n" + t
                    ids.append(item.id)
                }
            case .ask(let a):
                if fresh { shown.append(item); ids.append(item.id) }
                if a.answer == nil { ask = a }
            case .confirm(let c):
                if fresh { shown.append(item); ids.append(item.id) }
                if c.status == .pending, card == nil { card = c }
            case .cards:
                if fresh { shown.append(item); ids.append(item.id) }
            default:
                break
            }
        }
        // 手機上自己回的那一句（閒聊、切頁）不要被蓋掉
        if !shownText.isEmpty || awaitingReply { reply = shownText }
        turnItems = shown
        liveItemIDs = ids
        pendingAsk = ask
        pendingCard = card

        // 用說的確認送出去了、卡片還是沒決定（網路、伺服器的問題）：說一聲，換你再說一次
        if let id = votedCard, !session.deciding.contains(id), card?.id == id {
            votedCard = nil
            reply = "沒有完成，再說一次確認，或按畫面上的按鈕。"
            say(reply)
            if !mouth.speaking { replyDone() }
            return
        }
        if let id = votedCard, card?.id != id { votedCard = nil }

        // 等你決定的那張卡片有結果了：說一聲
        if let id = watchedCard, let decided = shown.compactMap({ item -> ConfirmCard? in
            if case .confirm(let c) = item, c.id == id { return c }
            return nil
        }).first, decided.status != .pending {
            watchedCard = nil
            if state == .listening { Task { await stopListening() } }
            let line: String? = switch decided.status {
            case .done: decided.result.map { "好了。\($0)" } ?? "好了，處理完了。"
            case .cancelled: "好，先不做。"
            case .failed: "沒有成功。\(decided.result ?? "")"
            case .expired: "這個確認已經過期了，要的話再跟我說一次。"
            case .pending: nil
            }
            if let line {
                if reply.isEmpty { reply = line }
                say(line)
            }
            if !mouth.speaking { replyDone() }
            return
        }

        guard awaitingReply else { return }
        tellTools(running)
        let finished = !session.isBusy
        if text.count > spokenUpTo {
            let (sentences, used) = Self.sentences(in: String(text.dropFirst(spokenUpTo)), final: finished)
            spokenUpTo += used
            for sentence in sentences { speakOrHold(sentence) }
        }
        guard finished else { return }
        // 短的：剩下的說完
        if firstSaid.count + held.reduce(0, { $0 + $1.count }) <= Self.speechBudget && !Self.needsCard(text) {
            let rest = held
            held = []
            awaitingReply = false
            for sentence in rest { say(sentence) }
            announce(ask: ask, card: card, text: text)
            if !mouth.speaking { replyDone() }
            return
        }
        // 太長（或是表格、一長串清單）：整段放卡片，Apple Intelligence 濃縮成用說的重點，再說「可以看卡片、要念就跟我說」
        guard !wrappingUp, lastCard == nil else { return }
        wrappingUp = true
        readingCard = ReadingCard(text: text)
        lastCard = readingCard
        let rest = held
        held = []
        let opening = firstSaid
        Task { [weak self] in
            let digest = await XenaLocal.shared.digest(of: text, alreadySaid: opening)
            guard let self, self.wrappingUp else { return }
            self.wrappingUp = false
            self.awaitingReply = false
            if let digest {
                self.readingCard?.title = digest.title
                self.readingCard?.points = digest.points
                self.lastCard?.title = digest.title
                self.lastCard?.points = digest.points
                if !digest.spoken.isEmpty { self.say(digest.spoken) }
            } else {
                // 沒有 Apple Intelligence：照順序念到上限
                var budget = Self.speechBudget - opening.count
                for sentence in rest {
                    budget -= sentence.count
                    guard budget >= 0 || opening.isEmpty && sentence == rest.first else { break }
                    self.say(sentence)
                }
            }
            self.say("詳細的我放在卡片上了，你可以看一下；要我念給你聽也可以跟我說。")
            self.announce(ask: ask, card: card, text: text)
            if !self.mouth.speaking { self.replyDone() }
        }
    }

    /// 這一輪她問你的問題、要你確認的事：念出來（畫面上也有）
    private func announce(ask: AskItem?, card: ConfirmCard?, text: String) {
        if let ask, !announced.contains(ask.id) {
            announced.insert(ask.id)
            if !text.contains(ask.question) { say(ask.question) }
        }
        if let card, !announced.contains(card.id) {
            announced.insert(card.id)
            watchedCard = card.id
            if card.danger || card.typed != nil {
                say("「\(card.title)」這件事比較重要，請在畫面上確認。")
            } else {
                say("要我「\(card.title)」嗎？說確認或取消，也可以按畫面上的按鈕。")
            }
        }
    }

    /// 她在查東西就說在查什麼（「我來查詢黃毛丫頭的訂單。」）：還沒開始回答、嘴巴空著的時候才說；
    /// 第一個工具已經被「好，我查一下…」說過了就不重複
    private func tellTools(_ running: [ToolRecord]) {
        for tool in running where !toldTools.contains(tool.id) {
            let first = toldTools.isEmpty
            toldTools.insert(tool.id)
            let label = tool.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, firstSaid.isEmpty, !mouth.speaking, !(first && ackSaid) else { continue }
            say(first ? "我來\(label)。" : "接著\(label)。")
        }
    }

    /// 第一句馬上說（通常就是答案）；後面的先留著，等整段回來看長短：短的說完，長的濃縮成重點
    private func speakOrHold(_ sentence: String) {
        if firstSaid.isEmpty && held.isEmpty && Self.isFiller(sentence) {
            // 「我查一下。」：已經先回過「好，我看一下」就不再說；沒回過就說，但不算第一句
            if !ackSaid { say(sentence) }
            return
        }
        if firstSaid.isEmpty && held.isEmpty {
            firstSaid = sentence
            say(sentence)
        } else {
            held.append(sentence)
        }
    }

    /// 「我查一下」「稍等」這類沒有內容的開頭
    static func isFiller(_ sentence: String) -> Bool {
        let words = ["查一下", "看一下", "查查", "稍等", "等我", "我來", "馬上"]
        return sentence.count <= 16 && XenaLocal.numbers(in: sentence).isEmpty && words.contains(where: sentence.contains)
    }

    /// 用聽的不好懂：表格、一長串清單
    static func needsCard(_ text: String) -> Bool {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.contains(where: { $0.hasPrefix("|") }) { return true }
        let items = lines.filter { $0.hasPrefix("- ") || $0.hasPrefix("• ") || $0.hasPrefix("* ") || $0.prefixMatch(of: /\d+[.、)]/) != nil }
        return items.count >= 4
    }

    /// 把卡片上的整段念出來（說「念給我聽」或按卡片上的按鈕）
    func readAloud(_ card: ReadingCard? = nil) {
        guard let text = (card ?? lastCard)?.text else { return }
        heard = ""
        state = .preparing
        mouth.stop()
        if micTurn != nil { Task { await stopListening() } }
        for sentence in Self.sentences(in: text, final: true).0 { say(sentence) }
        if !mouth.speaking { replyDone() }
    }

    /// 「念給我聽」「唸出來」「讀給我聽」「朗讀」
    static func wantsReading(_ text: String) -> Bool {
        let phrases = ["念給我聽", "唸給我聽", "念出來", "唸出來", "讀給我聽", "讀出來", "朗讀", "念一下", "唸一下", "全部念", "全部唸", "念吧", "唸吧"]
        if phrases.contains(where: text.contains) { return true }
        return text.count <= 6 && ["念", "唸", "讀"].contains(where: text.contains)
    }

    private func say(_ sentence: String) {
        guard AppSettings.shared.speakReplies else { return }
        spokenLines.append(sentence)
        state = .speaking
        mouth.say(sentence)
    }

    /// 她把排好的句子都說完了
    private func mouthIdle() {
        guard state == .speaking else { return }
        if let next = afterSpeaking {
            afterSpeaking = nil
            next()
            return
        }
        if awaitingReply || routing {
            // 後面還有字在來（或 Apple Intelligence 還在聽懂你說的話）
            state = .thinking
            return
        }
        replyDone()
    }

    /// 這一輪結束：危險的確認停下來（一定要在畫面上按），其他都換你說（回答問題、說確認也是用聽的）
    private func replyDone() {
        if let card = pendingCard, card.danger || card.typed != nil {
            state = .paused
            return
        }
        Task { await listen() }
    }

    /// 切成一句一句（句號、問號、驚嘆號、換行；太長的在逗號切）；final 時剩下的也算一句
    static func sentences(in text: String, final: Bool) -> ([String], Int) {
        var out: [String] = []
        var current = ""
        var used = 0
        var pending = 0
        for character in text {
            current.append(character)
            pending += 1
            let end = "。！？!?；\n".contains(character) || (current.count >= 42 && "，、,".contains(character))
            if end {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { out.append(sentence) }
                used += pending
                current = ""
                pending = 0
            }
        }
        if final {
            let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { out.append(rest) }
            used += pending
        }
        return (out, used)
    }

    // MARK: App 裡的指令

    private struct Command {
        var place: VoicePlace
        var site: String
    }

    /// 沒有 Apple Intelligence：短短一句「打開…」才當作指令
    private static func keyword(_ text: String) -> Command? {
        guard text.count <= 18 else { return nil }
        let asks = ["?", "？", "多少", "幾", "怎麼", "為什麼", "有沒有", "幫我", "回覆"]
        if asks.contains(where: text.contains) { return nil }
        let verbs = ["打開", "開啟", "回到", "切到", "去", "到", "看"]
        guard text.count <= 5 || verbs.contains(where: text.contains) else { return nil }
        if text.contains("訂單") { return Command(place: .orders, site: "") }
        if text.contains("收件") || text.contains("客服") || text.contains("詢問") { return Command(place: .inbox, site: "") }
        if text.contains("設定") { return Command(place: .settings, site: "") }
        if text.contains("首頁") || text.contains("今天") { return Command(place: .today, site: "") }
        if text.contains("網站") { return Command(place: .sites, site: "") }
        return nil
    }

    /// 說一句「好，打開…」，說完關掉語音切過去
    private func go(_ command: Command) {
        guard let model else { return }
        let site = command.site.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = site.isEmpty ? nil : model.sites.first { s in
            s.name.contains(site) || site.contains(s.name) || s.host.contains(site.lowercased())
        }
        let line: String
        let action: () -> Void
        switch command.place {
        case .today:
            line = "好，回到今天。"
            action = { model.tab = .xena }
        case .orders:
            guard !model.orderSites.isEmpty else { return speakLocally("你的網站沒有開商店，沒有訂單。") }
            line = "好，打開\(target?.name ?? "")訂單。"
            action = {
                if let target, target.hasOrders { model.ordersSite = target.id }
                model.tab = .orders
            }
        case .inbox:
            line = "好，打開收件匣。"
            action = { model.tab = .inbox }
        case .settings:
            line = "好，打開設定。"
            action = { model.goToAccount() }
        case .sites:
            if let target {
                line = "好，打開\(target.name)。"
                action = { model.open(.site(target.id)) }
            } else {
                line = "好，打開網站。"
                action = { model.goToSites() }
            }
        }
        reply = line
        // 先關掉語音的畫面，再切頁面（設定在手機上是一張卡片，要等語音的畫面收起來）
        let leave = { [weak self] in
            self?.end()
            model.showVoice = false
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                action()
            }
        }
        if AppSettings.shared.speakReplies {
            afterSpeaking = leave
            say(line)
        } else {
            leave()
        }
    }

    // MARK: 示範（截圖）

    private func showDemo() {
        history = [VoiceTurn(id: "demo-0", said: "昨天晨麥手作賣得怎麼樣？", reply: "昨天有 12 筆訂單、收款 18,400 元，比前天多兩成。")]
        said = "這週晨麥手作整體怎麼樣？"
        reply = "這週晨麥手作有 64 筆訂單、收款 102,300 元。"
        readingCard = ReadingCard(
            text: "這週晨麥手作有 64 筆訂單、收款 102,300 元，比上週多 18%。\n\n- 賣最好：手工蛋捲禮盒 41 盒、綜合堅果罐 27 罐\n- 訪客 3,820 人，從 Instagram 來的最多\n- 還有 5 筆等出貨，2 位客人在等回覆\n- 蛋捲禮盒庫存剩 38 盒，照這週的速度大約 6 天賣完",
            title: "晨麥手作這一週",
            points: ["64 筆訂單、收款 102,300 元，比上週多 18%", "手工蛋捲禮盒賣最好，庫存剩 38 盒", "5 筆等出貨、2 位客人在等回覆"]
        )
        state = .speaking
        _ = mouth.voice.begin()
    }
}

/// 太長的回答放的卡片：整段原文＋Apple Intelligence 寫的標題和重點（沒有就只有原文）
struct ReadingCard: Equatable {
    var text: String
    var title = ""
    var points: [String] = []
}

/// 用說的一輪：你說的、她回的（字、長回答卡片、她丟出來的問題和卡片）
struct VoiceTurn: Identifiable, Equatable {
    let id: String
    var said = ""
    var reply = ""
    var card: ReadingCard?
    var items: [ChatItem] = []

    var isEmpty: Bool { said.isEmpty && reply.isEmpty && card == nil && items.isEmpty }
}
