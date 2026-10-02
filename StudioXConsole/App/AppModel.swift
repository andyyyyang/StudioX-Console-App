import SwiftUI
import Observation

enum AppTab: Hashable {
    case xena, sites, inbox, account
}

/// 各分頁裡的下一層頁面
enum Route: Hashable {
    case site(String)
    case order(String)
    case conversation(String)
}

/// 整個 App 的狀態：登入、各網站的資料、Xena
@Observable
final class AppModel {
    enum Phase: Equatable {
        case signedOut, signedIn
    }

    var phase: Phase = .signedOut
    var user: StaffUser?
    var tab: AppTab = .xena
    var showXena = false
    var homePath: [Route] = []
    var sitesPath: [Route] = []
    var inboxPath: [Route] = []
    /// Xena 的招呼打過字了（之後回到首頁直接顯示，不再一個字一個字打）
    var greeted = false

    private(set) var sites: [Site] = []
    private(set) var orders: [Order] = []
    private(set) var conversations: [Conversation] = []
    private(set) var notes: [XenaNote] = []
    private(set) var shiftLog: [ShiftEntry] = []

    let xena: XenaSession
    private let backend: any ConsoleBackend

    init(backend: any ConsoleBackend = DemoConsole()) {
        self.backend = backend
        self.xena = XenaSession(backend: backend)
        xena.onChange = { [weak self] in
            Task { await self?.refresh() }
        }
    }

    // MARK: - 登入

    func signIn(_ method: SignInMethod) async throws {
        let user = try await backend.signIn(method)
        await refresh()
        self.user = user
        phase = .signedIn
    }

    func signOut() {
        phase = .signedOut
        user = nil
        tab = .xena
        showXena = false
        homePath = []
        sitesPath = []
        inboxPath = []
        greeted = false
        xena.reset()
    }

    func refresh() async {
        do {
            sites = try await backend.sites()
            orders = try await backend.orders()
            conversations = try await backend.conversations()
            notes = try await backend.notes()
            shiftLog = try await backend.shiftLog()
        } catch {
            // 拿不到就留著上一次的資料
        }
    }

    // MARK: - 查詢

    func site(_ id: String?) -> Site? {
        guard let id else { return nil }
        return sites.first { $0.id == id }
    }

    func order(_ id: String) -> Order? { orders.first { $0.id == id } }
    func conversation(_ id: String) -> Conversation? { conversations.first { $0.id == id } }
    func orders(for siteID: String) -> [Order] { orders.filter { $0.siteID == siteID } }

    /// 等你回覆的對話（收件匣的數字）
    var waitingCount: Int {
        conversations.filter { $0.status == .waiting || ($0.status == .human && $0.lastFromVisitor) }.count
    }

    /// 還沒處理的 Xena 筆記
    var openNotes: [XenaNote] { notes.filter { $0.resolution == nil } }
    var doneNotes: [XenaNote] { notes.filter { $0.resolution != nil } }

    // MARK: - Xena

    var xenaMood: XenaMood {
        switch xena.phase {
        case .thinking: return .thinking
        case .speaking: return .speaking
        case .waitingForYou: return .listening
        case .idle:
            if openNotes.contains(where: { $0.kind == .attention }) { return .alert }
            let hour = Calendar.current.component(.hour, from: .now)
            return hour < 6 ? .resting : .idle
        }
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = user?.name ?? ""
        let hello = switch hour {
        case 5..<11: "早安"
        case 11..<14: "午安"
        case 14..<18: "下午好"
        case 18..<23: "晚上好"
        default: "這麼晚還在忙"
        }
        let recent = orders.filter { $0.placedAt > Date.now.addingTimeInterval(-24 * 3600) }
        let replied = conversations.filter { $0.lines.contains { $0.author == .xena } }.count
        let decisions = openNotes.filter { $0.kind != .insight }.count
        var text = "\(hello)，\(name)。過去 24 小時三個網站都平安，黃毛丫頭來了 \(recent.count) 筆訂單，我回了 \(replied) 位訪客。"
        text += decisions > 0 ? "有 \(decisions) 件事要你決定 👇" : "目前沒有要你決定的事，我繼續看著 ☕️"
        return text
    }

    /// 底部小條輪播的一句話
    var tickerLines: [String] {
        var lines = ["值班中 · 看著 \(sites.count) 個網站"]
        if waitingCount > 0 { lines.append("\(waitingCount) 段對話等你回覆") }
        let paid = orders.filter { $0.status == .paid }.count
        if paid > 0 { lines.append("\(paid) 筆訂單可以備貨了") }
        let live = sites.reduce(0) { $0 + $1.stats.live }
        if live > 0 { lines.append("現在 \(live) 人在你的網站上") }
        return lines
    }

    /// 打開 Xena 接著問一句
    func askXena(_ prompt: String, site: String? = nil) {
        showXena = true
        xena.send(prompt, siteID: site)
    }

    /// 到某一頁（Xena 的卡片、首頁的筆記點進去）
    func open(_ route: Route) {
        showXena = false
        switch route {
        case .site:
            tab = .sites
            sitesPath = [route]
        case .order(let id):
            tab = .sites
            if let o = order(id) { sitesPath = [.site(o.siteID), route] } else { sitesPath = [] }
        case .conversation:
            tab = .inbox
            inboxPath = [route]
        }
    }

    /// 首頁筆記上的確認卡片：按下確認或取消
    func decideNote(_ note: XenaNote, approve: Bool) async {
        guard let card = note.proposal else { return }
        _ = try? await backend.decide(card.id, approve: approve, typed: nil)
        await refresh()
    }

    // MARK: - 客服

    func setStatus(_ status: ConversationStatus, conversation id: String) async {
        try? await backend.setStatus(status, conversation: id)
        await refresh()
    }

    func reply(_ text: String, conversation id: String) async {
        try? await backend.reply(text, conversation: id, as: user?.name ?? "我")
        await refresh()
    }
}
