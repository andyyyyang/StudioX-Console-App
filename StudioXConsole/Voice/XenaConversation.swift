import AVFoundation
import SwiftUI

/// 跟 Xena 用說的，一來一往：
///   你說（水珠跟著你的音量起伏、字幕邊說邊出字）→ 停一下就當作說完 →
///   「打開訂單」這類 App 裡的指令：手機上的 Apple Intelligence 聽懂就直接切過去（沒有它就看關鍵字）；
///   其他的交給 Xena（和打字同一個 Xena、同一份對話紀錄）→ 她回一句就用 iPhone 的聲音說一句（不等整段），
///   水珠跟著她說的每個字 → 說完換你說。
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
    /// 你說的話（字幕）
    private(set) var heard = ""
    /// Xena 這一次的回答（字幕）
    private(set) var reply = ""
    /// 這一輪她丟出來、要放在畫面上的東西（問題＋選項、資料卡片、確認卡片）
    private(set) var turnItems: [ChatItem] = []
    /// 還沒回答的問題
    private(set) var pendingAsk: AskItem?
    /// 還沒決定的確認卡片
    private(set) var pendingCard: ConfirmCard?
    /// 回答太長：整段放在卡片上給你看（她只說開頭和重點；說「念給我聽」才全部念）
    private(set) var readingCard: String?
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
    /// 這一輪已經說了幾個字；超過就不再往下念，整段改放卡片
    @ObservationIgnored private var spokenChars = 0
    @ObservationIgnored private var overflow = false
    /// 長的回答收尾中（請 Apple Intelligence 濃縮重點）
    @ObservationIgnored private var wrappingUp = false
    /// 一次最多念多少字（大約 15 秒）
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
        #if DEBUG
        if DemoServer.enabled {
            showDemo()
            return
        }
        #endif
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
        reply = ""
        turnItems = []
        pendingAsk = nil
        pendingCard = nil
        watchedCard = nil
        readingCard = nil
        wrappingUp = false
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

    /// 你說完了：App 裡的指令就直接做，其他的交給 Xena
    private func doneTalking() async {
        guard state == .listening else { return }
        state = .thinking
        let text = heard
        await stopListening()
        guard !text.isEmpty else {
            state = .paused
            return
        }
        guard let model else { return }
        // 長的回答放在卡片上：「念給我聽」就全部念
        if readingCard != nil, Self.wantsReading(text) {
            readAloud()
            return
        }
        // 等你決定的確認卡片：「確認」「取消」（危險的不行，要在畫面上按）
        if let card = pendingCard, !card.danger, card.typed == nil, let approve = Self.decision(in: text) {
            watchedCard = card.id
            votedCard = card.id
            model.xena.decide(card.id, approve: approve)
            return
        }
        // 她問你的問題：這句就是答案
        if let ask = pendingAsk {
            send(text, answering: ask.id)
            return
        }
        if let command = await command(for: text) {
            go(command)
            return
        }
        send(text, answering: nil)
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
        spokenChars = 0
        overflow = false
        wrappingUp = false
        readingCard = nil
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
        let yes = ["確認", "確定", "好", "可以", "執行", "對", "沒問題", "同意", "OK", "ok", "要"]
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
            beginTurn()
        }
        let start = userIndex.map { items.index(after: $0) } ?? items.startIndex
        var text = ""
        var shown: [ChatItem] = []
        var ask: AskItem?
        var card: ConfirmCard?
        for item in items[start...] {
            switch item {
            case .assistant(_, let t), .notice(_, let t):
                text += text.isEmpty ? t : "\n" + t
            case .ask(let a):
                shown.append(item)
                if a.answer == nil { ask = a }
            case .confirm(let c):
                shown.append(item)
                if c.status == .pending, card == nil { card = c }
            case .cards:
                shown.append(item)
            default:
                break
            }
        }
        reply = text
        turnItems = shown
        pendingAsk = ask
        pendingCard = card

        // 用說的確認送出去了、卡片還是沒決定（網路、伺服器的問題）：說一聲，換你再說一次
        if let id = votedCard, !session.deciding.contains(id), card?.id == id {
            votedCard = nil
            say("沒有完成，再說一次確認，或按畫面上的按鈕。")
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
            switch decided.status {
            case .done: say(decided.result.map { "好了。\($0)" } ?? "好了，處理完了。")
            case .cancelled: say("好，先不做。")
            case .failed: say("沒有成功。\(decided.result ?? "")")
            case .expired: say("這個確認已經過期了，要的話再跟我說一次。")
            case .pending: break
            }
            if !mouth.speaking { replyDone() }
            return
        }

        guard awaitingReply else { return }
        let finished = !session.isBusy
        if text.count > spokenUpTo {
            let (sentences, used) = Self.sentences(in: String(text.dropFirst(spokenUpTo)), final: finished)
            spokenUpTo += used
            for sentence in sentences { speakOrHold(sentence) }
        }
        guard finished else { return }
        // 太長：整段放卡片，說重點（Apple Intelligence 濃縮）和「可以看卡片、要念就說」
        if overflow {
            guard !wrappingUp, readingCard == nil else { return }
            wrappingUp = true
            readingCard = text
            Task { [weak self] in
                let outline = await XenaLocal.shared.outline(of: text)
                guard let self, self.wrappingUp else { return }
                self.wrappingUp = false
                self.awaitingReply = false
                if let outline { self.say(outline) }
                self.say("詳細的我放在卡片上了，你可以看一下；要我念給你聽，就說「念給我聽」。")
                self.announce(ask: ask, card: card, text: text)
                if !self.mouth.speaking { self.replyDone() }
            }
            return
        }
        awaitingReply = false
        announce(ask: ask, card: card, text: text)
        if !mouth.speaking { replyDone() }
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

    /// 這一輪還在預算內就念；超過了就停（整段等一下放卡片）
    private func speakOrHold(_ sentence: String) {
        guard !overflow else { return }
        if spokenChars > 0 && spokenChars + sentence.count > Self.speechBudget {
            overflow = true
            return
        }
        spokenChars += sentence.count
        say(sentence)
    }

    /// 把卡片上的整段念出來（說「念給我聽」或按卡片上的按鈕）
    func readAloud() {
        guard let text = readingCard else { return }
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
        if awaitingReply {
            // 後面還有字在來
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

    /// 短短一句「打開…」才可能是指令。有 Apple Intelligence 就問它；沒有就看關鍵字
    private func command(for text: String) async -> Command? {
        guard text.count <= 18 else { return nil }
        if XenaLocal.shared.available && AppSettings.shared.aiCommands {
            guard let route = await XenaLocal.shared.route(text) else { return nil }
            return Command(place: route.place, site: route.site)
        }
        return Self.keyword(text)
    }

    private static func keyword(_ text: String) -> Command? {
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
            guard !model.orderSites.isEmpty else { return refuse("你的網站沒有開商店，沒有訂單。") }
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
        case .ask:
            return
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

    private func refuse(_ line: String) {
        reply = line
        state = .speaking
        if AppSettings.shared.speakReplies {
            say(line)
        } else {
            replyDone()
        }
    }

    // MARK: 示範（截圖）

    #if DEBUG
    private func showDemo() {
        heard = "昨天黃毛丫頭賣得怎麼樣？"
        reply = "昨天黃毛丫頭有 12 筆訂單、收款 18,400 元，比前天多兩成。手工蛋捲禮盒賣最好，庫存還剩 38 盒。"
        state = .speaking
        _ = mouth.voice.begin()
    }
    #endif
}
