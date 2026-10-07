import Foundation
import Observation

/// 對話裡的一項（和網頁版 lib/copilot/engine.ts 的 ViewItem 相同）
enum ChatItem: Identifiable, Equatable {
    case user(id: String, text: String)
    case assistant(id: String, text: String)
    case notice(id: String, text: String)
    case tool(ToolRecord)
    case confirm(ConfirmCard)
    case cards(CardsItem)
    case ask(AskItem)

    var id: String {
        switch self {
        case .user(let id, _), .assistant(let id, _), .notice(let id, _): id
        case .tool(let t): t.id
        case .confirm(let c): c.id
        case .cards(let c): c.id
        case .ask(let a): a.id
        }
    }
}

/// 和 Xena 的對話（console 的 /api/copilot，和網頁版的 Xena 是同一個、同一份對話紀錄）：
/// 送出一句話、把串流事件接成畫面、處理確認卡片。打開 App 時接著最近的一串。
@Observable
final class XenaSession {
    enum Phase: Equatable {
        case idle
        /// 查資料、呼叫工具
        case thinking
        /// 回答中
        case speaking
        /// 有確認卡片等你按
        case waitingForYou
    }

    static let starters = ["今天有什麼要我注意的？", "有誰在等我回覆？", "昨天賣了多少？", "這週流量怎麼樣？"]

    private(set) var items: [ChatItem] = []
    private(set) var phase: Phase = .idle
    private(set) var threadID: String?
    private(set) var threadTitle: String?
    /// 不能用的原因（方案、設定）
    private(set) var problem: String?
    private(set) var threads: [ThreadSummaryDTO] = []
    /// 每次畫面有變加一：捲到最下面
    private(set) var revision = 0
    /// 回答完、事情做完時加一：水滴彈一下
    private(set) var pulse = 0
    private(set) var deciding: Set<String> = []
    private(set) var loaded = false

    /// 她還在回答時又交代的一句（首頁的「交給 Xena」、別的頁面的「問 Xena」）：這一句答完照順序送出，不會被吃掉
    struct Queued {
        let text: String
        let answering: String?
        /// 真的送出時叫（首頁「交給 Xena」這時才把那件事從清單拿掉）
        let onStart: (() -> Void)?
    }

    private(set) var queue: [Queued] = []

    /// Xena 動手改了東西（確認卡片執行成功）：App 重新拿資料
    @ObservationIgnored var onDidWrite: (() -> Void)?
    /// 危險動作確認前的驗證（AppModel 接到 Face ID）；回 false 就不送出
    @ObservationIgnored var verify: ((String) async -> Bool)?
    /// 還沒同意用雲端 AI 時：先問（AppModel.withCloudAI），同意了才送
    @ObservationIgnored var askConsent: ((@escaping () -> Void) -> Void)?
    @ObservationIgnored private let api: ConsoleAPI
    @ObservationIgnored private var task: Task<Void, Never>?

    init(api: ConsoleAPI) {
        self.api = api
    }

    var isBusy: Bool { phase == .thinking || phase == .speaking }

    var mood: XenaMood {
        switch phase {
        case .idle: .idle
        case .thinking: .thinking
        case .speaking: .speaking
        case .waitingForYou: .listening
        }
    }

    private var hasPendingConfirm: Bool {
        items.contains { item in
            if case .confirm(let card) = item { return card.status == .pending }
            return false
        }
    }

    // MARK: 對話串

    /// 接著最近的一串（網頁上聊到一半的，在 App 裡也看得到）
    func loadLatest() async {
        guard !loaded else { return }
        loaded = true
        do {
            let state = try await api.copilotState()
            problem = state.problem
            // 從別的頁面「問 Xena」已經開始新的一句了：不要用舊的那串蓋掉
            guard items.isEmpty, !isBusy else { return }
            apply(thread: state.thread)
        } catch {
            problem = error.localizedDescription
            // 下次打開再試
            loaded = false
        }
    }

    func open(thread id: String) async {
        stop()
        do {
            apply(thread: try await api.copilotState(thread: id).thread)
        } catch {
            items.append(.notice(id: newID("notice"), text: error.localizedDescription))
        }
        bump()
    }

    func loadThreads() async {
        threads = (try? await api.copilotThreads()) ?? threads
    }

    func deleteThread(_ id: String) async {
        try? await api.deleteThread(id)
        threads.removeAll { $0.id == id }
        if id == threadID { newThread() }
    }

    /// 開新的一串
    func newThread() {
        stop()
        items = []
        threadID = nil
        threadTitle = nil
        phase = .idle
        bump()
    }

    /// 登出
    func reset() {
        queue = []
        newThread()
        threads = []
        problem = nil
        loaded = false
    }

    private func apply(thread: ThreadDTO?) {
        threadID = thread?.id
        threadTitle = thread?.title
        var restored: [ChatItem] = []
        for (i, item) in (thread?.view ?? []).enumerated() {
            switch item {
            case .user(let text): restored.append(.user(id: "u\(i)", text: text))
            case .assistant(let text): restored.append(.assistant(id: "a\(i)", text: text))
            case .tool(let t): restored.append(.tool(t))
            case .confirm(let c): restored.append(.confirm(c))
            case .cards(let c): restored.append(.cards(c))
            case .ask(let a): restored.append(.ask(a))
            case .unknown: break
            }
        }
        items = restored
        phase = hasPendingConfirm ? .waitingForYou : .idle
        bump()
    }

    // MARK: 說話

    /// 說一句話。她還在回答：排在後面，這一句答完再送（不會被吃掉）。
    /// 還沒同意用雲端 AI：先問，同意了才送；不同意就什麼都不做（onStart 也不會叫）。onStart：這一句真的送出時
    func send(_ text: String, answering: String? = nil, onStart: (() -> Void)? = nil) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        guard AppSettings.shared.cloudAIAllowed else {
            askConsent?({ [weak self] in self?.send(text, answering: answering, onStart: onStart) })
            return
        }
        guard !isBusy else {
            // 同一句已經排著了（例如又按了一次）：不重複問
            if queue.contains(where: { $0.text == message }) { return }
            queue.append(Queued(text: message, answering: answering, onStart: onStart))
            bump()
            return
        }
        onStart?()
        if let answering, let i = items.firstIndex(where: { $0.id == answering }), case .ask(var ask) = items[i] {
            ask.answer = message
            items[i] = .ask(ask)
        }
        items.append(.user(id: newID("user"), text: message))
        phase = .thinking
        bump()
        let stream = api.copilotChat(message: message, thread: threadID, answering: answering)
        task = Task { [weak self] in
            do {
                for try await event in stream {
                    self?.apply(event)
                }
            } catch is CancellationError {
                // 使用者按了停止
            } catch {
                self?.items.append(.notice(id: newID("notice"), text: error.localizedDescription))
            }
            self?.finish()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if isBusy { finish() }
    }

    private func apply(_ event: CopilotEvent) {
        switch event {
        case .thread(let id, let title):
            threadID = id
            threadTitle = title
        case .text(let chunk):
            phase = .speaking
            if case .assistant(let id, let text)? = items.last {
                items[items.count - 1] = .assistant(id: id, text: text + chunk)
            } else {
                items.append(.assistant(id: newID("assistant"), text: chunk))
            }
        case .tool(let call):
            phase = .thinking
            items.append(.tool(call))
        case .toolDone(let id, let status, let result, let ms):
            update(tool: id) {
                $0.status = status
                $0.result = result
                $0.ms = ms
            }
        case .confirm(let card):
            items.append(.confirm(card))
        case .cards(let item):
            items.append(.cards(item))
        case .ask(let item):
            items.append(.ask(item))
        case .error(let message):
            items.append(.notice(id: newID("notice"), text: message))
        case .done, .unknown:
            break
        }
        bump()
    }

    private func finish() {
        let wasWorking = isBusy
        phase = hasPendingConfirm ? .waitingForYou : .idle
        if wasWorking { pulse += 1 }
        bump()
        sendQueued()
    }

    /// 排著的下一句：等這一輪（按了停止、換對話串）處理完再送
    private func sendQueued() {
        guard !isBusy, !queue.isEmpty else { return }
        Task { [weak self] in
            await Task.yield()
            guard let self, !self.isBusy, !self.queue.isEmpty else { return }
            let next = self.queue.removeFirst()
            self.send(next.text, answering: next.answering, onStart: next.onStart)
        }
    }

    // MARK: 確認卡片

    /// 確認執行或取消（退款、刪除要打字）。確認碼只在伺服器，App 只送決定
    func decide(_ cardID: String, approve: Bool, typed: String? = nil) {
        guard !deciding.contains(cardID) else { return }
        deciding.insert(cardID)
        bump()
        Task {
            // 退款、刪除這類：確認前再驗證一次（Face ID；設定裡可以關掉）
            if approve, let card = confirmCard(cardID), card.danger || card.typed != nil, let verify {
                guard await verify("確認：\(card.title)") else {
                    deciding.remove(cardID)
                    bump()
                    return
                }
            }
            do {
                let r = try await api.copilotDecide(card: cardID, approve: approve, typed: typed, thread: threadID)
                replace(card: cardID, with: r.card)
                if let tool = r.tool {
                    if let i = items.firstIndex(where: { $0.id == tool.id }) { items[i] = .tool(tool) } else { items.append(.tool(tool)) }
                }
                if let next = r.next { items.append(.confirm(next)) }
                if r.card.status == .done {
                    pulse += 1
                    onDidWrite?()
                }
            } catch {
                update(card: cardID) { $0.result = error.localizedDescription }
            }
            deciding.remove(cardID)
            phase = hasPendingConfirm ? .waitingForYou : .idle
            bump()
        }
    }

    private func update(tool id: String, _ change: (inout ToolRecord) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .tool(var call) = items[i] else { return }
        change(&call)
        items[i] = .tool(call)
    }

    private func confirmCard(_ id: String) -> ConfirmCard? {
        for item in items {
            if case .confirm(let card) = item, card.id == id { return card }
        }
        return nil
    }

    private func update(card id: String, _ change: (inout ConfirmCard) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .confirm(var card) = items[i] else { return }
        change(&card)
        items[i] = .confirm(card)
    }

    private func replace(card id: String, with card: ConfirmCard) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i] = .confirm(card)
    }

    private func bump() {
        revision &+= 1
    }
}

nonisolated func newID(_ prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
}
