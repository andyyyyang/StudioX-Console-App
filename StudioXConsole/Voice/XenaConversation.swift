import AVFoundation
import SwiftUI

/// 跟 Xena 用說的，一來一往：
///   你說（水珠跟著你的音量起伏、字幕邊說邊出字）→ 停一下就當作說完 →
///   「打開訂單」這類 App 裡的指令：手機上的 Apple Intelligence 聽懂就直接切過去（沒有它就看關鍵字）；
///   其他的交給 Xena（和打字同一個 Xena、同一份對話紀錄）→ 她回一句就用 iPhone 的聲音說一句（不等整段），
///   水珠跟著她說的每個字 → 說完換你說。
/// 點一下水珠：她在說就停下來換你說；你在說就當作說完了。要動手改東西的事（確認卡片）不用說的確認，停下來讓你按。
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
    /// 要你確認的事（確認卡片的標題）
    private(set) var pendingConfirm: String?
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
        pendingConfirm = nil
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
        pendingConfirm = nil
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
        if let command = await command(for: text) {
            go(command)
            return
        }
        guard let model else { return }
        reply = ""
        spokenUpTo = 0
        awaitingReply = true
        if model.xena.isBusy { model.xena.stop() }
        model.xena.send(text)
    }

    // MARK: Xena 的回答

    /// 對話有變（AppModel.xena.revision）：把新的句子念出來
    func sessionChanged() {
        guard awaitingReply, let session = model?.xena else { return }
        let items = session.items
        guard let start = items.lastIndex(where: { if case .user = $0 { true } else { false } }) else { return }
        var text = ""
        var confirm: String?
        for item in items[items.index(after: start)...] {
            switch item {
            case .assistant(_, let t), .notice(_, let t):
                text += text.isEmpty ? t : "\n" + t
            case .confirm(let card) where card.status == .pending:
                confirm = card.title
            default:
                break
            }
        }
        reply = text
        pendingConfirm = confirm
        let finished = !session.isBusy
        if text.count > spokenUpTo {
            let (sentences, used) = Self.sentences(in: String(text.dropFirst(spokenUpTo)), final: finished)
            spokenUpTo += used
            for sentence in sentences { say(sentence) }
        }
        if finished {
            awaitingReply = false
            if !mouth.speaking { replyDone() }
        }
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

    /// 這一輪結束：有事要你確認就停下來（畫面上按），不然換你說
    private func replyDone() {
        if pendingConfirm != nil {
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
