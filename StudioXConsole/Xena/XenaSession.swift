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

/// 一串和 Xena 的對話：送出一句話、把串流事件接成畫面、處理確認卡片
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

    static let starters = ["今天營收多少？", "有誰在等我回覆？", "把已付款的訂單改成備貨中", "這週流量怎麼樣？"]

    private(set) var items: [ChatItem] = []
    private(set) var phase: Phase = .idle
    private(set) var suggestions: [String] = XenaSession.starters
    /// 每次畫面有變（新事件、字多了）加一：捲到最下面
    private(set) var revision = 0
    /// 回答完、事情做完時加一：水滴彈一下
    private(set) var pulse = 0
    /// 正在送出確認的卡片
    private(set) var deciding: Set<String> = []
    private(set) var threadID: String?

    private let backend: any ConsoleBackend
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 做完事（確認卡片執行完、回答結束）：App 重新拿資料
    @ObservationIgnored var onChange: (() -> Void)?

    init(backend: any ConsoleBackend) {
        self.backend = backend
    }

    var isBusy: Bool { phase == .thinking || phase == .speaking }

    private var hasPendingConfirm: Bool {
        items.contains { item in
            if case .confirm(let card) = item { return card.status == .pending }
            return false
        }
    }

    func send(_ text: String, answering: String? = nil, siteID: String? = nil) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isBusy else { return }
        if let answering, let i = items.firstIndex(where: { $0.id == answering }), case .ask(var ask) = items[i] {
            ask.answer = message
            items[i] = .ask(ask)
        }
        items.append(.user(id: newID("user"), text: message))
        suggestions = []
        phase = .thinking
        bump()
        let stream = backend.chat(XenaRequest(message: message, threadID: threadID, answering: answering, siteID: siteID))
        task = Task { [weak self] in
            do {
                for try await event in stream {
                    self?.apply(event)
                }
            } catch {
                self?.items.append(.notice(id: newID("notice"), text: "連線中斷了，再試一次？"))
            }
            self?.finish()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        finish()
    }

    /// 開新的一串
    func reset() {
        task?.cancel()
        task = nil
        items = []
        threadID = nil
        phase = .idle
        suggestions = Self.starters
        bump()
    }

    func decide(_ cardID: String, approve: Bool, typed: String? = nil) {
        guard !deciding.contains(cardID) else { return }
        deciding.insert(cardID)
        bump()
        Task {
            do {
                let r = try await backend.decide(cardID, approve: approve, typed: typed)
                updateConfirm(cardID) {
                    $0.status = r.status
                    $0.result = r.result
                }
                if let follow = r.followUp {
                    items.append(.assistant(id: newID("assistant"), text: follow))
                }
                if r.status == .done { pulse += 1 }
            } catch {
                // 卡片留著，可以再按一次
                updateConfirm(cardID) { $0.result = error.localizedDescription }
            }
            deciding.remove(cardID)
            phase = hasPendingConfirm ? .waitingForYou : .idle
            bump()
            onChange?()
        }
    }

    private func apply(_ event: CopilotEvent) {
        switch event {
        case .thread(let id, _):
            threadID = id
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
            if let i = items.firstIndex(where: { $0.id == id }), case .tool(var call) = items[i] {
                call.status = status
                call.result = result
                call.ms = ms
                items[i] = .tool(call)
            }
        case .confirm(let card):
            items.append(.confirm(card))
        case .cards(let item):
            items.append(.cards(item))
        case .ask(let item):
            items.append(.ask(item))
        case .suggestions(let list):
            suggestions = list
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
        if suggestions.isEmpty && !hasPendingConfirm && !items.contains(where: { if case .ask(let a) = $0 { return a.answer == nil }; return false }) {
            suggestions = Self.starters
        }
        bump()
        onChange?()
    }

    private func updateConfirm(_ id: String, _ change: (inout ConfirmCard) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .confirm(var card) = items[i] else { return }
        change(&card)
        items[i] = .confirm(card)
    }

    private func bump() {
        revision &+= 1
    }
}
