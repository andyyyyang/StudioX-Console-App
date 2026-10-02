import AuthenticationServices
import Observation
import SwiftUI

enum AppTab: Hashable {
    case xena, sites, orders, inbox, account, search
    /// iPad 的側欄：直接打開某個網站（網站代號）
    case site(String)
}

/// 各分頁裡的下一層頁面（site 是網站代號）
enum Route: Hashable {
    case site(String)
    case order(site: String, id: String)
    case thread(site: String, id: String)
    case xenaConversation(site: String, id: String)
    /// 一種資料的清單（商品、折價券、文章…；entity 是網站的實體代號）
    case collection(site: String, entity: String)
    /// 一筆資料（id 是 nil：單一頁面或設定）
    case record(site: String, entity: String, id: String?)
    /// 新增一筆
    case create(site: String, entity: String)
    /// 流量的完整報表
    case traffic(site: String)
    /// Google 搜尋成效
    case searchConsole(site: String)
    /// 會員
    case member(site: String, id: String)

    var site: String {
        switch self {
        case .site(let s): s
        case .order(let s, _), .thread(let s, _), .xenaConversation(let s, _), .collection(let s, _), .record(let s, _, _),
             .create(let s, _), .member(let s, _): s
        case .traffic(let s), .searchConsole(let s): s
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var tone: Tone = .active
}

/// 整個 App 的狀態：登入、這個人可以管理的網站、各網站的欄位定義、導覽、Xena
@Observable
final class AppModel {
    enum Phase: Equatable {
        /// 沒登入：歡迎頁
        case welcome
        /// 登入了，正在拿網站清單（品牌的載入動畫）
        case loading
        case ready
    }

    private(set) var phase: Phase
    private(set) var me: Me?
    private(set) var loadError: String?
    /// 各網站的資料與欄位定義（/api/app/schema）
    private(set) var schemas: [String: SiteSchema] = [:]
    private(set) var schemaErrors: [String: String] = [:]

    var tab: AppTab = .xena
    var homePath: [Route] = []
    var sitesPath: [Route] = []
    var ordersPath: [Route] = []
    var inboxPath: [Route] = []
    var accountPath: [Route] = []
    var searchPath: [Route] = []
    /// 手機上「我」不在分頁列：從首頁右上角的頭像打開
    var showAccount = false
    /// iPad：每個網站自己的一疊頁面
    var sitePaths: [String: [Route]] = [:]
    var showXena = false
    var toast: Toast?
    /// 訂單頁現在看的網站與狀態（首頁的「等出貨」點進去會設好）
    var ordersSite: String?
    var ordersStatus = "paid"
    /// Xena 的招呼打過字了（之後回到首頁直接顯示）
    var greeted = false
    /// 寬的畫面（iPad 的一般寬度）：網站直接放在側欄
    var regular = false

    @ObservationIgnored let api: ConsoleAPI
    let xena: XenaSession
    let briefing: Briefing
    @ObservationIgnored private var schemaTasks: [String: Task<SiteSchema?, Never>] = [:]

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
    var supportSites: [SiteSummary] { sites.filter(\.hasSupport) }

    func site(_ id: String) -> SiteSummary? {
        sites.first { $0.id == id }
    }

    /// 收件匣的數字（客人在等回覆＋轉給專人＋新的詢問）
    var inboxCount: Int {
        briefing.awaiting.count + briefing.handoffs.count + briefing.inquiries.count
    }

    // MARK: 登入

    /// App 打開時：已經登入過就直接拿資料
    func start() async {
        guard phase == .loading else { return }
        await loadMe(minimumDuration: .milliseconds(1900))
    }

    func signIn(using session: WebAuthenticationSession) async throws {
        try await api.signIn(using: session)
        phase = .loading
        await loadMe(minimumDuration: .milliseconds(1900))
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
        accountPath = []
        searchPath = []
        sitePaths = [:]
        showXena = false
        showAccount = false
        greeted = false
        loadError = message
        schemas = [:]
        schemaErrors = [:]
        schemaTasks.values.forEach { $0.cancel() }
        schemaTasks = [:]
        xena.reset()
        briefing.reset()
    }

    /// 拿網站清單。剛登入時讓載入動畫至少演完（標誌卡上去、字升起來、000→100）
    func loadMe(minimumDuration: Duration = .zero) async {
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let next = try await api.me()
            let left = minimumDuration - (clock.now - started)
            if left > .zero { try? await Task.sleep(for: left) }
            me = next
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

    // MARK: 欄位定義

    /// 某個網站的資料與欄位定義（快取；同時要的只拿一次）
    func schema(for site: String, reload: Bool = false) async -> SiteSchema? {
        if !reload, let hit = schemas[site] { return hit }
        if let running = schemaTasks[site] { return await running.value }
        let api = api
        let task = Task<SiteSchema?, Never> {
            do {
                let s = try await api.schema(site: site)
                schemas[site] = s
                schemaErrors[site] = nil
                return s
            } catch {
                schemaErrors[site] = error.localizedDescription
                return nil
            }
        }
        schemaTasks[site] = task
        let value = await task.value
        schemaTasks[site] = nil
        return value
    }

    // MARK: 導覽

    /// 打開一個頁面：iPad 上網站相關的頁面打開在那個網站裡；手機上打開在對應的分頁
    func open(_ route: Route) {
        showXena = false
        showAccount = false
        switch route {
        case .order:
            tab = .orders
            ordersPath = [route]
        case .thread, .xenaConversation:
            tab = .inbox
            inboxPath = [route]
        case .site(let id):
            if regular {
                tab = .site(id)
                sitePaths[id] = []
            } else {
                tab = .sites
                sitesPath = [route]
            }
        default:
            if regular {
                tab = .site(route.site)
                sitePaths[route.site] = [route]
            } else {
                tab = .sites
                sitesPath = [.site(route.site), route]
            }
        }
    }

    /// 「我」：iPad 是側欄的一項；手機從首頁的頭像打開
    func goToAccount() {
        guard phase == .ready else { return }
        if regular { tab = .account } else { showAccount = true }
    }

    /// 「網站」：手機是網站分頁；iPad 是側欄的第一個網站
    func goToSites() {
        guard phase == .ready else { return }
        if regular, let first = sites.first {
            tab = .site(first.id)
        } else {
            tab = .sites
        }
    }

    /// 打開 Xena 接著問一句
    func askXena(_ prompt: String) {
        showXena = true
        xena.send(prompt)
    }

    func show(_ text: String, tone: Tone = .active) {
        toast = Toast(text: text, tone: tone)
        switch tone {
        case .danger: Haptics.error()
        case .warning: Haptics.warning()
        default: Haptics.success()
        }
    }

    /// 寬窄切換（iPad 分割畫面、台前調度）：網站的頁面搬到對應的地方
    func setRegular(_ value: Bool) {
        guard value != regular else { return }
        regular = value
        if value {
            // 手機的「網站」分頁 → 側欄的那個網站
            if tab == .sites {
                if case .site(let id)? = sitesPath.first {
                    sitePaths[id] = Array(sitesPath.dropFirst())
                    tab = .site(id)
                } else {
                    // 「網站」分頁在側欄是收起來的：改到第一個網站
                    tab = sites.first.map { AppTab.site($0.id) } ?? .xena
                }
            }
        } else if case .site(let id) = tab {
            sitesPath = [.site(id)] + (sitePaths[id] ?? [])
            tab = .sites
        } else if tab == .account {
            // 手機的分頁列沒有「我」：改成從首頁打開
            tab = .xena
            showAccount = true
        }
    }
}
