import AuthenticationServices
import Observation
import SwiftUI

enum AppTab: Hashable {
    case xena, sites, orders, inbox, account
}

/// 各分頁裡的下一層頁面（site 是網站代號）
enum Route: Hashable {
    case site(String)
    case order(site: String, id: String)
    case thread(site: String, id: String)
    case xenaConversation(site: String, id: String)
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var tone: Tone = .active
}

/// 整個 App 的狀態：登入、這個人可以管理的網站、導覽、Xena
@Observable
final class AppModel {
    enum Phase: Equatable {
        /// 沒登入：歡迎頁
        case welcome
        /// 登入了，正在拿網站清單
        case loading
        case ready
    }

    private(set) var phase: Phase
    private(set) var me: Me?
    private(set) var loadError: String?

    var tab: AppTab = .xena
    var homePath: [Route] = []
    var sitesPath: [Route] = []
    var ordersPath: [Route] = []
    var inboxPath: [Route] = []
    var showXena = false
    var toast: Toast?
    /// 訂單頁現在看的網站與狀態（首頁的「等出貨」點進去會設好）
    var ordersSite: String?
    var ordersStatus = "paid"
    /// Xena 的招呼打過字了（之後回到首頁直接顯示）
    var greeted = false

    @ObservationIgnored let api: ConsoleAPI
    let xena: XenaSession
    let briefing: Briefing

    init() {
        let api = ConsoleAPI()
        self.api = api
        self.xena = XenaSession(api: api)
        self.briefing = Briefing(api: api)
        self.phase = api.isSignedIn ? .loading : .welcome
        api.onSignedOut = { [weak self] in self?.didSignOut(message: "登入已經過期，請重新登入") }
        xena.onDidWrite = { [weak self] in
            Task { await self?.refreshAll() }
        }
    }

    var sites: [SiteSummary] { me?.sites ?? [] }
    var orderSites: [SiteSummary] { sites.filter(\.hasOrders) }

    func site(_ id: String) -> SiteSummary? {
        sites.first { $0.id == id }
    }

    // MARK: 登入

    /// App 打開時：已經登入過就直接拿資料
    func start() async {
        guard phase == .loading else { return }
        await loadMe()
    }

    func signIn(using session: WebAuthenticationSession) async throws {
        try await api.signIn(using: session)
        phase = .loading
        await loadMe()
    }

    func signOut() async {
        await api.signOut()
        didSignOut(message: nil)
    }

    private func didSignOut(message: String?) {
        me = nil
        phase = .welcome
        tab = .xena
        homePath = []
        sitesPath = []
        ordersPath = []
        inboxPath = []
        showXena = false
        greeted = false
        loadError = message
        xena.reset()
        briefing.reset()
    }

    func loadMe() async {
        do {
            me = try await api.me()
            loadError = nil
            phase = .ready
            await briefing.refresh(sites: sites)
        } catch APIError.unauthorized {
            didSignOut(message: "登入已經過期，請重新登入")
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 下拉重新整理、Xena 動手改了東西之後
    func refreshAll() async {
        do {
            me = try await api.me()
        } catch {
            // 拿不到就留著原本的網站清單
        }
        await briefing.refresh(sites: sites)
    }

    // MARK: 導覽

    func open(_ route: Route) {
        showXena = false
        switch route {
        case .site:
            tab = .sites
            sitesPath = [route]
        case .order:
            tab = .orders
            ordersPath = [route]
        case .thread, .xenaConversation:
            tab = .inbox
            inboxPath = [route]
        }
    }

    /// 打開 Xena 接著問一句
    func askXena(_ prompt: String) {
        showXena = true
        xena.send(prompt)
    }

    func show(_ text: String, tone: Tone = .active) {
        toast = Toast(text: text, tone: tone)
    }
}
