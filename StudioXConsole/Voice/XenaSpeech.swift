import AVFoundation
import Speech

// 跟 Xena 用說的：耳朵（麥克風 → 字）和嘴巴（字 → iPhone 的中文聲音）。全部在 iPhone 上處理，不經過第三方。

// MARK: - 耳朵

/// 麥克風 → 字。iOS 26 的 SpeechAnalyzer（裝置上的新模型，邊說邊出字）；
/// 這台 iPhone 不支援這個語言時改用 SFSpeechRecognizer（能在裝置上辨識就在裝置上）。
/// 音訊在錄音的執行緒上處理（不在主執行緒），所以這個類別不屬於 MainActor
nonisolated final class XenaEar: @unchecked Sendable {
    nonisolated enum Failure: LocalizedError {
        case microphoneDenied
        case speechDenied
        case unsupported
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "沒有麥克風的權限：到 iPhone 的「設定 → StudioX」打開麥克風。"
            case .speechDenied: "沒有語音辨識的權限：到 iPhone 的「設定 → StudioX」打開語音辨識。"
            case .unsupported: "這台 iPhone 不支援中文語音辨識。"
            case .noMicrophone: "找不到麥克風。"
            }
        }
    }

    private let audio = AVAudioEngine()
    private let lock = NSLock()
    private var _level: Float = 0
    private var analyzer: AnalyzerEngine?
    private var legacy: LegacyEngine?
    private var running = false

    /// 這一次用的是不是新的 SpeechAnalyzer（設定頁顯示用）
    private(set) var usesAnalyzer = false

    /// 現在的音量（0…1）
    var level: Float {
        lock.withLock { _level }
    }

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// 開始聽：onText(到目前為止聽到的整句, 是不是已經確定)
    func start(locale: Locale, onText: @escaping @Sendable (String, Bool) -> Void) async throws {
        await stop()
        if let engine = try? await AnalyzerEngine.make(locale: locale) {
            try await engine.begin(onText: onText)
            set(analyzer: engine, legacy: nil)
            usesAnalyzer = true
        } else if let engine = LegacyEngine(locale: locale) {
            guard await LegacyEngine.authorize() else { throw Failure.speechDenied }
            engine.begin(onText: onText)
            set(analyzer: nil, legacy: engine)
            usesAnalyzer = false
        } else {
            throw Failure.unsupported
        }

        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            await stop()
            throw Failure.noMicrophone
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        audio.prepare()
        do {
            try audio.start()
        } catch {
            await stop()
            throw error
        }
        running = true
    }

    /// 不聽了（已經聽到的字不會再變）
    func stop() async {
        if running {
            audio.inputNode.removeTap(onBus: 0)
            audio.stop()
            running = false
        }
        let (analyzer, legacy) = lock.withLock {
            _level = 0
            let engines = (self.analyzer, self.legacy)
            self.analyzer = nil
            self.legacy = nil
            return engines
        }
        await analyzer?.end()
        legacy?.end()
    }

    private func set(analyzer: AnalyzerEngine?, legacy: LegacyEngine?) {
        lock.withLock {
            self.analyzer = analyzer
            self.legacy = legacy
        }
    }

    /// 錄音的執行緒：算音量、交給辨識
    private func process(_ buffer: AVAudioPCMBuffer) {
        if let samples = buffer.floatChannelData?[0] {
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = (sum / Float(max(count, 1))).squareRoot()
            let db = 20 * log10(max(rms, 0.000_001))
            // -50 dB（安靜）… -12 dB（大聲說話）→ 0…1
            let value = max(0, min(1, (db + 50) / 38))
            lock.withLock { _level = value }
        }
        let (analyzer, legacy) = lock.withLock { (self.analyzer, self.legacy) }
        analyzer?.feed(buffer)
        legacy?.feed(buffer)
    }
}

/// iOS 26 的 SpeechAnalyzer＋SpeechTranscriber（progressiveTranscription：邊說邊出字，確定了再定稿）
nonisolated final class AnalyzerEngine: @unchecked Sendable {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let inputs: AsyncStream<AnalyzerInput>
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var results: Task<Void, Never>?

    private init(transcriber: SpeechTranscriber, format: AVAudioFormat) {
        self.transcriber = transcriber
        self.format = format
        self.analyzer = SpeechAnalyzer(modules: [transcriber])
        let stream = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputs = stream.stream
        continuation = stream.continuation
    }

    /// 這台 iPhone 支援這個語言才建；第一次用會下載語言模型（之後就在裝置上）
    static func make(locale: Locale) async throws -> AnalyzerEngine? {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return nil }
        return AnalyzerEngine(transcriber: transcriber, format: format)
    }

    func begin(onText: @escaping @Sendable (String, Bool) -> Void) async throws {
        let transcriber = transcriber
        results = Task {
            var settled = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        settled += text
                        onText(settled, true)
                    } else {
                        onText(settled + text, false)
                    }
                }
            } catch {
                // 停止、取消：已經聽到的字照樣用
            }
        }
        try await analyzer.start(inputSequence: inputs)
    }

    /// 錄音的執行緒：轉成模型要的格式送進去
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func end() async {
        continuation.finish()
        await analyzer.cancelAndFinishNow()
        results?.cancel()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) let source = buffer
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return source
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }
}

/// 舊的 SFSpeechRecognizer（SpeechAnalyzer 不支援這個語言時）
nonisolated final class LegacyEngine: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    init?(locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { return nil }
        self.recognizer = recognizer
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
    }

    static func authorize() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func begin(onText: @escaping @Sendable (String, Bool) -> Void) {
        task = recognizer.recognitionTask(with: request) { @Sendable result, _ in
            guard let result else { return }
            onText(result.bestTranscription.formattedString, result.isFinal)
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func end() {
        request.endAudio()
        task?.cancel()
        task = nil
    }
}

// MARK: - 嘴巴

/// 字 → 聲音。一句一句排隊說（Xena 回一句就說一句，不用等整段），說完全部叫 onIdle。
///   - iPhone 內建（預設、免費）：AVSpeechSynthesizer，挑最好的中文聲音（下載過「加強／高品質」就用那個），每說到一個字水珠鼓一下
///   - 雲端自然語音（設定裡選）：經 console 轉成聲音（AVAudioPlayer 播），水珠跟著聲音的大小動；拿不到就改用 iPhone 的聲音
@Observable
final class XenaMouth {
    private(set) var speaking = false
    /// 說到哪一句（字幕用）
    private(set) var current = ""
    @ObservationIgnored let voice = XenaVoice()
    @ObservationIgnored var onIdle: (() -> Void)?
    /// 雲端的聲音（AppModel 接到 ConsoleAPI.speech）
    @ObservationIgnored var fetchCloud: ((String) async -> Data?)?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let listener = MouthListener()
    @ObservationIgnored private let clipListener = ClipListener()
    @ObservationIgnored private var lines: [Line] = []
    @ObservationIgnored private var playing: Line?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var meter: Task<Void, Never>?
    @ObservationIgnored private var turn: Int?

    private final class Line {
        let text: String
        var audio: Task<Data?, Never>?
        init(text: String) { self.text = text }
    }

    init() {
        synthesizer.delegate = listener
        listener.mouth = self
        clipListener.mouth = self
    }

    // MARK: 聲音的清單

    /// Xena 預設的聲音（iPhone「朗讀內容」裡可以免費下載）：先 Han、再 Lilian；同名的挑品質最好的
    static let preferredNames = ["Han", "Lilian"]

    /// iPhone 上可以用的中文聲音：台灣的加強／高品質最先，再來是其他地區的高品質、加強，最後才是精簡版
    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") }
            .sorted { a, b in
                let (ra, rb) = (rank(a), rank(b))
                return ra != rb ? ra > rb : a.name < b.name
            }
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        let taiwan = voice.language == "zh-TW"
        switch voice.quality {
        case .premium: return taiwan ? 6 : 5
        case .enhanced: return taiwan ? 5 : 3
        default: return taiwan ? 2 : 1
        }
    }

    /// 設定裡選的聲音；沒選（或選的被刪了）：有 Han 就用 Han、再來 Lilian，都沒有就用最好的那個
    static func chosenVoice() -> AVSpeechSynthesisVoice? {
        let id = AppSettings.shared.voiceID
        if !id.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: id) { return voice }
        let all = voices
        for name in preferredNames {
            if let voice = all.first(where: { $0.name.hasPrefix(name) }) { return voice }
        }
        return all.first ?? AVSpeechSynthesisVoice(language: "zh-TW")
    }

    /// 現在用的是不是精簡版（聽起來比較機械；設定頁、語音畫面提醒可以免費換）
    static var usingCompactVoice: Bool {
        AppSettings.shared.voiceSource == .iphone && (chosenVoice()?.quality ?? .default) == .default
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        let region = switch voice.language {
        case "zh-TW": "台灣"
        case "zh-HK": "香港"
        default: "中國"
        }
        let quality = switch voice.quality {
        case .premium: "高品質"
        case .enhanced: "加強"
        default: "精簡"
        }
        return "\(voice.name)（\(region)・\(quality)）"
    }

    // MARK: 說

    /// 排一句話（Markdown、網址、NT$ 先整理成說得出口的樣子）
    func say(_ text: String) {
        let spoken = Self.speakable(text)
        guard !spoken.isEmpty else { return }
        let line = Line(text: spoken)
        if AppSettings.shared.voiceSource == .cloud, let fetch = fetchCloud {
            // 先開始轉（前一句還在說的時候這一句就準備好）
            line.audio = Task { await fetch(spoken) }
        }
        lines.append(line)
        if !speaking {
            speaking = true
            turn = voice.begin()
        }
        if playing == nil { Task { await next() } }
    }

    /// 馬上停（你插話、關掉語音）
    func stop() {
        lines.forEach { $0.audio?.cancel() }
        lines = []
        playing?.audio?.cancel()
        playing = nil
        meter?.cancel()
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func next() async {
        guard playing == nil else { return }
        guard !lines.isEmpty else {
            finish()
            return
        }
        let line = lines.removeFirst()
        playing = line
        current = line.text
        if let task = line.audio {
            let data = await task.value
            guard playing === line else { return }
            if let data, let clip = try? AVAudioPlayer(data: data) {
                play(clip)
                return
            }
        }
        guard playing === line else { return }
        speakOnPhone(line.text)
    }

    private func speakOnPhone(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.chosenVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(AppSettings.shared.pace.speechRate)
        utterance.pitchMultiplier = 1.04
        utterance.postUtteranceDelay = 0.06
        synthesizer.speak(utterance)
    }

    private func play(_ clip: AVAudioPlayer) {
        clip.delegate = clipListener
        clip.enableRate = true
        clip.rate = Float(AppSettings.shared.pace.speechRate)
        clip.isMeteringEnabled = true
        clip.prepareToPlay()
        player = clip
        clip.play()
        // 水珠跟著聲音的大小
        meter?.cancel()
        meter = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player, player.isPlaying else { return }
                player.updateMeters()
                let db = Double(player.averagePower(forChannel: 0))
                self.voice.hear(max(0, min(1, (db + 42) / 36)))
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    fileprivate func started(_ text: String) {
        current = text
    }

    fileprivate func spoke(_ character: Character) {
        voice.say(character)
    }

    /// 一句說完（iPhone 的聲音或雲端的聲音）
    fileprivate func lineFinished() {
        guard playing != nil else { return }
        meter?.cancel()
        player = nil
        playing = nil
        Task { await next() }
    }

    private func finish() {
        guard speaking else { return }
        speaking = false
        if let turn { voice.end(turn) }
        turn = nil
        onIdle?()
    }

    /// 說出口的樣子：拿掉 Markdown 符號、網址念「連結」、NT$1,200 念「1200 元」
    static func speakable(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "連結", options: .regularExpression)
        s = s.replacingOccurrences(of: #"NT\$\s?([\d,]+)"#, with: "$1 元", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d),(\d{3})"#, with: "$1$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[*_`#>|]+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\s*[-•]\s+"#, with: "", options: [.regularExpression])
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// AVSpeechSynthesizer 的回呼可能不在主執行緒：收到就交回主執行緒
nonisolated private final class MouthListener: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    weak var mouth: XenaMouth?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        let mouth = mouth
        Task { @MainActor in mouth?.started(text) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let text = utterance.speechString as NSString
        guard characterRange.location < text.length else { return }
        let piece = text.substring(with: NSRange(location: characterRange.location, length: min(1, text.length - characterRange.location)))
        guard let character = piece.first else { return }
        let mouth = mouth
        Task { @MainActor in mouth?.spoke(character) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let mouth = mouth
        Task { @MainActor in mouth?.lineFinished() }
    }
}

/// 雲端聲音（AVAudioPlayer）播完
nonisolated private final class ClipListener: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    weak var mouth: XenaMouth?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let mouth = mouth
        Task { @MainActor in mouth?.lineFinished() }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let mouth = mouth
        Task { @MainActor in mouth?.lineFinished() }
    }
}
