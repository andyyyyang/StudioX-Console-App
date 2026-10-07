import AuthenticationServices
import Observation
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case xena, sites, orders, inbox, account, search
    /// iPad 的側欄：直接打開某個網站（網站代號）
    case site(String)
    /// iPad 的側欄：StudioX Console 的平台管理（後台人員才有）
    case console
}

/// 平台管理（console 自己的管理後台）的頁面
enum ConsolePage: Hashable {
    case home
    /// 客戶與網站
    case customers
    /// 一個網站：設定、成員、邀請（console 的網站 id）
    case site(String)
    /// 客戶的申請（方案、服務）
    case requests
    /// 網站服務：每個網站開了哪些服務
    case services
    /// 一個網站的服務
    case siteServices(String)
    /// 金鑰庫
    case keys
    /// 用量（寄信、簡訊、AI）
    case usage
    /// 帳單
    case billing
    /// 方案（客戶訂了哪個方案）
    case plans
    /// 價目
    case pricing
    /// 後台人員
    case team
    /// 操作紀錄
    case audit
    /// Xena AI：開關、外部 AI 連接器、呼叫紀錄
    case xena
}

/// 各分頁裡的下一層頁面（site 是網站代號）
enum Route: Hashable {
    case site(String)
    case order(site: String, id: String)
    case thread(site: String, id: String)
    case xenaConversation(site: String, id: String)
    /// 專案詢問（網站聯絡表單送來的）
    case inquiry(site: String, id: String)
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
    /// 營運報表（訂單、收款、會員）
    case report(site: String)
    /// 會員
    case member(site: String, id: String)
    /// 平台管理（不屬於任何一個網站）
    case console(ConsolePage)

    var site: String {
        switch self {
        case .site(let s): s
        case .order(let s, _), .thread(let s, _), .xenaConversation(let s, _), .inquiry(let s, _), .collection(let s, _), .record(let s, _, _),
             .create(let s, _), .member(let s, _): s
        case .traffic(let s), .searchConsole(let s), .report(let s): s
        case .console: ""
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
    var showAccount = false {
        didSet {
            guard showAccount, deckSheet != nil else { return }
            showAccount = false
            afterClosingDeck { $0.showAccount = true }
        }
    }
    /// iPad：每個網站自己的一疊頁面
    var sitePaths: [String: [Route]] = [:]
    /// iPad 側欄「平台管理」左邊選的那一頁（深連結、通知打開的也選在這裡）
    var consoleSection: ConsolePage = .customers
    /// iPad 側欄「平台管理」裡的下一層
    var consolePath: [Route] = []
    var showXena = false {
        didSet {
            guard showXena else { return }
            if deckSheet != nil {
                showXena = false
                afterClosingDeck { $0.showXena = true }
            } else if !AppSettings.shared.cloudAIAllowed {
                // 第一次：先說明會交給雲端 AI 什麼、同意了才打開
                showXena = false
                withCloudAI { [weak self] in self?.showXena = true }
            }
        }
    }
    /// 用說的跟 Xena 聊（整個畫面）
    var showVoice = false {
        didSet {
            guard showVoice else { return }
            if deckSheet != nil {
                showVoice = false
                afterClosingDeck { $0.showVoice = true }
            } else if !AppSettings.shared.cloudAIAllowed {
                showVoice = false
                withCloudAI { [weak self] in self?.showVoice = true }
            }
        }
    }
    /// 雲端 AI 的說明與同意（CloudAIConsentSheet）；同意了才做 pendingCloudAI 裡的事
    var showAIConsent = false
    @ObservationIgnored private var pendingCloudAI: [() -> Void] = []
    /// 首頁狀況卡片打開的 sheet（今天的總覽，或一個網站）
    var deckSheet: DeckSheet?
    /// 開著幾個對話畫面（客服對話、客服信）：開著時收起 tab bar 上面的 Xena，回覆框貼著畫面底部
    var openChats = 0
    var toast: Toast?
    /// 觸覺回饋（RootView 的 sensoryFeedback 看這幾個數字）
    private(set) var successTick = 0
    private(set) var warningTick = 0
    private(set) var errorTick = 0
    /// 訂單頁現在看的網站與狀態（首頁的「等出貨」點進去會設好）。網站記在這台裝置：下次打開還是看這個網站
    var ordersSite: String? = UserDefaults.standard.string(forKey: AppModel.ordersSiteKey) {
        didSet { UserDefaults.standard.set(ordersSite, forKey: Self.ordersSiteKey) }
    }
    var ordersStatus = "paid"
    nonisolated static let ordersSiteKey = "orders.site"
    /// 首頁 Xena 已經說過的那段話（同一段話回到首頁不再重說一次）
    var spokenReport: String?
    /// 現在在看的網站、訂單：按「問問Xena」時第一個建議就是問這個（.xenaFocus）
    var xenaFocus: XenaFocus?
    /// Apple Intelligence 寫好的首頁開場白（照資料拼的那句 → 她會說的話；寫不出來或數字對不上就是原句）
    var greetings: [String: String] = [:]
    /// 寬的畫面（iPad 的一般寬度）：網站直接放在側欄
    var regular = false

    /// 別的頁面要收件匣搜這個（會員頁「看這位的客服紀錄」、搜尋頁）；收件匣拿去用了就清掉
    var inboxSearch: String?
    /// iPad：收件匣、訂單右邊打開的是哪一個（左邊清單標起來；通知、首頁點進來也是選這一個，不另外推一頁）
    var inboxPicked: Route?
    var ordersPicked: String?

    @ObservationIgnored let api: ConsoleAPI
    let xena: XenaSession
    /// 用說的（耳朵、嘴巴、一來一往）
    let conversation = XenaConversation()
    let briefing: Briefing
    /// 收件匣的全部紀錄（第一次打開才載）
    let inboxHistory: InboxHistory
    /// 通知（Apple 的 token、登記到 console、點通知打開的頁面）
    let push = PushCenter.shared
    /// Face ID 鎖
    let lock = AppLock()
    @ObservationIgnored private var schemaTasks: [String: Task<SiteSchema?, Never>] = [:]

    init() {
        let api = ConsoleAPI()
        self.api = api
        self.xena = XenaSession(api: api)
        self.briefing = Briefing(api: api)
        self.inboxHistory = InboxHistory(api: api)
        self.phase = api.isSignedIn ? .loading : .welcome
        api.onSignedOut = { [weak self] in self?.didSignOut(message: "登入已經過期，請重新登入") }
        xena.onDidWrite = { [weak self] in
            Task { await self?.refreshAll() }
        }
        xena.verify = { [weak self] reason in
            await self?.lock.verify(reason) ?? false
        }
        xena.askConsent = { [weak self] action in
            self?.withCloudAI(action)
        }
        push.api = api
        conversation.attach(self)
        conversation.mouth.fetchCloud = { [api] text in
            try? await api.speech(text, voice: AppSettings.shared.cloudVoice.rawValue)
        }
        // 還沒登入：歡迎頁不用鎖
        if !api.isSignedIn { lock.reset() }
        // UI 截圖：水珠不動、照參數顯示鎖定畫面
        if DemoServer.screenshots {
            if UserDefaults.standard.bool(forKey: "demoLock") { lock.showDemoLock() } else { lock.reset() }
            XenaOrb.frozen = true
        }
    }

    var sites: [SiteSummary] { me?.sites ?? [] }
    var orderSites: [SiteSummary] { sites.filter(\.hasOrders) }
    /// 平台管理（console 的後台人員）：能用哪些
    var consoleCaps: Set<String> { me?.consoleCaps ?? [] }
    var canManageConsole: Bool { consoleCaps.contains("console.read") || consoleCaps.contains("platform.read") || consoleCaps.contains("users.level") }
    func can(_ cap: String) -> Bool { consoleCaps.contains(cap) }
    var supportSites: [SiteSummary] { sites.filter(\.hasSupport) }
    /// 收件匣裡有東西的網站（客服信，或 Xena 對話、詢問）
    var inboxSites: [SiteSummary] { sites.filter { $0.hasSupport || $0.tools.contains("list") } }

    /// 訂單頁看的網站：上次選的（還是有商店的網站的話），不然是第一個有商店的
    var currentOrdersSite: SiteSummary? {
        let picked = ordersSite
        return orderSites.first { $0.id == picked } ?? orderSites.first
    }

    func site(_ id: String) -> SiteSummary? {
        sites.first { $0.id == id }
    }

    /// 打開收件匣、搜這個字（手機回到收件匣第一層；iPad 右邊不動）
    func openInboxHistory(search: String) {
        showXena = false
        showAccount = false
        inboxSearch = search
        inboxPath = []
        tab = .inbox
    }

    /// 收件匣的數字（客人在等回覆＋需要專人看的 Xena 對話＋新的詢問）：專人已經回過、客人還沒再說話的不算
    var inboxCount: Int {
        briefing.awaiting.count + briefing.handoffs.filter(\.attention).count + briefing.live.filter(\.attention).count + briefing.inquiries.count
    }

    // MARK: 登入

    /// App 打開時：已經登入過就直接拿資料（不用等載入動畫演完：那是剛登入時的歡迎）
    func start() async {
        guard phase == .loading else { return }
        await loadMe()
        if DemoServer.screenshots { openDemoScreen() }
    }

    /// 示範模式的截圖：-demoTab、-demoRoute 打開指定的畫面
    private func openDemoScreen() {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "demoTab") {
        case "sites": goToSites()
        case "orders": tab = .orders
        case "inbox": tab = .inbox
        case "account": goToAccount()
        case "search": tab = .search
        default: break
        }
        let shop = "chenmai.studiox.tw"
        switch defaults.string(forKey: "demoRoute") {
        case "site": open(.site(shop))
        case "traffic": open(.traffic(site: shop))
        case "order": open(.order(site: shop, id: "o1"))
        case "member": open(.member(site: shop, id: "u1"))
        case "thread": open(.thread(site: shop, id: "t1"))
        case "line": open(.xenaConversation(site: shop, id: "yc1"))
        case "products": open(.collection(site: shop, entity: "product"))
        case "shipped": open(.order(site: shop, id: "o3"))
        case "linepush": open(.collection(site: shop, entity: "line_campaign"))
        case "campaign": open(.record(site: shop, entity: "campaign", id: "sc1"))
        case "pending": open(.collection(site: shop, entity: "pending_notification"))
        case "report": open(.report(site: shop))
        case "console": open(.console(.home))
        case "console-site": open(.console(.site("s1")))
        case "console-services": open(.console(.siteServices("s1")))
        case "console-billing": open(.console(.billing))
        case "product": open(.record(site: shop, entity: "product", id: "p1"))
        case "xena": showXena = true
        default: break
        }
        if defaults.bool(forKey: "demoVoice") { showVoice = true }
        // 首頁卡片打開的 sheet：today 或網站代號（等首頁出現在畫面上才開得起來）
        if let sheet = defaults.string(forKey: "demoSheet") {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.deckSheet = DeckSheet(id: sheet)
            }
        }
    }

    /// 歡迎頁的「先看看示範」：不用登入，用假的網站資料逛一遍（登出就結束）
    func enterDemo() async {
        api.enterDemo()
        lock.reset()
        phase = .loading
        await loadMe(minimumDuration: .milliseconds(1200))
    }

    /// 現在是示範模式（設定頁的登出改成「離開示範模式」）
    var isDemo: Bool { DemoServer.enabled }

    func signIn(using session: WebAuthenticationSession) async throws {
        try await api.signIn(using: session)
        lock.reset()
        phase = .loading
        await loadMe(minimumDuration: .milliseconds(1900))
    }

    func signOut() async {
        // 先從 console 移除這台裝置（登出之後就沒有 token 可以叫 API 了）
        await push.unregister()
        await api.signOut()
        didSignOut(message: nil)
    }

    /// 刪除帳號：先用 Face ID 驗證（設定裡有開「重要動作再驗證」時），console 刪掉之後這台裝置照登出清乾淨。
    /// 回傳 false＝驗證沒過、什麼都沒做；失敗丟錯（例如平台管理者不能在 App 刪）
    func deleteAccount() async throws -> Bool {
        // 一定跳 Face ID（不吃 2 分鐘的寬限）；設定關掉、裝置沒密碼時照舊直接過（前面已經有確認選單）
        guard await lock.confirm("刪除 StudioX 帳號") != false else { return false }
        try await api.deleteAccount()
        // 帳號、裝置、登入在 console 都刪掉了，這裡只要清掉本機的（先登出，推播就只清本機、不再叫 API）
        await api.signOut()
        await push.unregister()
        didSignOut(message: nil)
        return true
    }

    private func didSignOut(message: String?) {
        deckSheet = nil
        conversation.end()
        showVoice = false
        greetings = [:]
        me = nil
        phase = .welcome
        tab = .xena
        homePath = []
        sitesPath = []
        ordersPath = []
        inboxPath = []
        inboxPicked = nil
        ordersPicked = nil
        accountPath = []
        searchPath = []
        sitePaths = [:]
        consoleSection = .customers
        consolePath = []
        // 記住的網站是這個帳號的：換人登入從頭來
        ordersSite = nil
        UserDefaults.standard.removeObject(forKey: ComposeEmailView.siteKey)
        showXena = false
        showAccount = false
        spokenReport = nil
        loadError = message
        schemas = [:]
        schemaErrors = [:]
        schemaTasks.values.forEach { $0.cancel() }
        schemaTasks = [:]
        xena.reset()
        briefing.reset()
        inboxHistory.reset()
        lock.reset()
        // 登入過期：token 已經沒了、叫不了 console；unregister 會向 Apple 取消這台的通知代碼，console 下次送就知道它失效了
        Task { await push.unregister() }
    }

    /// 設定裡「打開 App 先看」的那一頁（沒有商店就從今天開始）
    private var startTab: AppTab {
        switch AppSettings.shared.startTab {
        case .today: .xena
        case .sites: regular ? (sites.first.map { AppTab.site($0.id) } ?? .xena) : .sites
        case .orders: orderSites.isEmpty ? .xena : .orders
        case .inbox: .inbox
        }
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
            if phase != .ready { tab = startTab }
            phase = .ready
            await push.refresh()
            await briefing.refresh(sites: sites)
        } catch APIError.unauthorized {
            didSignOut(message: "登入已經過期，請重新登入")
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 下拉重新整理、Xena 動手改了東西之後
    func refreshAll() async {
        // 下拉重新整理：用新的連線（App 放著一陣子後，舊的連線可能已經斷了，第一次會等到逾時）
        await api.freshConnections()
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
        deckSheet = nil
        showXena = false
        showAccount = false
        switch route {
        case .order(let site, let id):
            tab = .orders
            if regular {
                // iPad：在左邊的清單選起來、右邊打開（沒有多一個「返回」）
                ordersSite = site
                ordersPicked = id
                ordersPath = []
            } else {
                ordersPath = [route]
            }
        case .thread, .xenaConversation, .inquiry:
            tab = .inbox
            if regular {
                inboxPicked = route
                inboxPath = []
            } else {
                inboxPath = [route]
            }
        case .site(let id):
            if regular {
                tab = .site(id)
                sitePaths[id] = []
            } else {
                tab = .sites
                sitesPath = [route]
            }
        case .console(let page):
            if regular {
                // 側欄選到那一頁（網站、網站服務是「客戶與網站」「網站服務」底下的一層）
                tab = .console
                if let section = Self.sidebarSection(for: page) {
                    consoleSection = section
                    consolePath = section == page ? [] : [route]
                } else {
                    consolePath = []
                }
            } else {
                // 手機：網站 → 平台管理 →（客戶與網站、網站服務）→ 這一頁，返回的路和 iPad 側欄一樣
                tab = .sites
                if page == .home {
                    sitesPath = [route]
                } else if let section = Self.sidebarSection(for: page), section != page {
                    sitesPath = [.console(.home), .console(section), route]
                } else {
                    sitesPath = [.console(.home), route]
                }
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

    /// 平台管理的一頁在 iPad 側欄是哪一項（nil：總覽，側欄本身就是）
    static func sidebarSection(for page: ConsolePage) -> ConsolePage? {
        switch page {
        case .home: return nil
        case .site: return .customers
        case .siteServices: return .services
        default: return page
        }
    }

    /// 收件匣的「要你處理」：回到清單第一層、選好篩選（iPad 右邊開著的不動）
    func openNeedsYou() {
        showXena = false
        showAccount = false
        inboxPath = []
        inboxHistory.showNeedsYou(sites: sites)
        tab = .inbox
    }

    /// 訂單清單：那個網站、那個狀態（nil＝不變），回到清單第一層
    func openOrders(site: String, status: String? = nil) {
        showXena = false
        showAccount = false
        ordersSite = site
        if let status { ordersStatus = status }
        ordersPath = []
        ordersPicked = nil
        tab = orderSites.isEmpty ? .xena : .orders
    }

    // MARK: 通知打開的頁面

    /// 點了通知要去的地方（網站給的後台路徑對應到 App 的頁面）
    enum PushLink: Equatable {
        case route(Route)
        /// 訂單清單（那個網站）
        case orders(site: String)
        /// 收件匣
        case inbox
        case home
    }

    /// 網站的後台路徑 → App 的頁面。對不到的打開那個網站；不知道是哪個網站就回首頁
    static func link(site: String?, url: String?) -> PushLink {
        guard let site else { return .home }
        guard let url, let c = URLComponents(string: url) else { return .route(.site(site)) }
        var q: [String: String] = [:]
        for item in c.queryItems ?? [] where q[item.name] == nil {
            if let value = item.value, !value.isEmpty { q[item.name] = value }
        }
        let parts = c.path.split(separator: "/").map(String.init)
        guard parts.first == "admin" else { return .route(.site(site)) }
        let section = parts.count > 1 ? parts[1] : ""
        let sub = parts.count > 2 ? parts[2] : nil
        switch section {
        case "support":
            // 黃毛丫頭的 Xena 對話（/admin/support/xena?c=；官網和 LINE 來的都是）：在 App 裡打開那一段
            if sub == "xena" {
                if let id = q["c"] { return .route(.xenaConversation(site: site, id: id)) }
                return .inbox
            }
            if let id = q["thread"] { return .route(.thread(site: site, id: id)) }
            return .inbox
        case "orders":
            if let id = sub ?? q["id"] { return .route(.order(site: site, id: id)) }
            return .orders(site: site)
        case "inbox":
            if let id = q["c"] { return .route(.xenaConversation(site: site, id: id)) }
            if let run = q["run"] { return .route(.record(site: site, entity: "automation_run", id: run)) }
            if let id = q["inquiry"] { return .route(.inquiry(site: site, id: id)) }
            return .inbox
        case "automations":
            if let run = q["run"] { return .route(.record(site: site, entity: "automation_run", id: run)) }
            if let id = sub { return .route(.record(site: site, entity: "automation", id: id)) }
            return .route(.collection(site: site, entity: "automation"))
        case "products", "categories":
            return .route(.collection(site: site, entity: "product"))
        default:
            return .route(.site(site))
        }
    }

    /// 點了通知：打開對應的頁面，順便重新整理首頁與收件匣
    func open(_ payload: PushPayload) {
        guard phase == .ready else { return }
        deckSheet = nil
        // 網站已經不在清單裡（被移出、停用）：回首頁
        let site = payload.site.flatMap { self.site($0) == nil ? nil : $0 }
        switch Self.link(site: site, url: payload.url) {
        case .route(let route):
            if case .order = route, orderSites.isEmpty {
                open(.site(route.site))
            } else {
                open(route)
            }
        case .orders(let site):
            openOrders(site: site)
        case .inbox:
            openNeedsYou()
        case .home:
            showXena = false
            showAccount = false
            tab = .xena
        }
        Task { await briefing.refresh(sites: sites) }
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

    /// 卡片的 sheet 開著時要打開別的畫面：先收起來，等它收好再打開（兩個 sheet 不能同時開）
    private func afterClosingDeck(_ present: @escaping @MainActor (AppModel) -> Void) {
        deckSheet = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            if let self { present(self) }
        }
    }

    /// 首頁「要處理」的一件事：直接去處理（從卡片的 sheet 按的，先收起來）。
    /// 收件匣的事打開「要你處理」；只有一件的直接打開那一段對話、那張訂單
    func handle(_ action: AttentionItem.Action) {
        if deckSheet != nil {
            afterClosingDeck { $0.handle(action) }
            return
        }
        switch action {
        case .inbox:
            openNeedsYou()
        case .orders(let site, let status):
            openOrders(site: site, status: status)
        case .open(let route):
            if case .order(let site, _) = route {
                // 返回時是那個網站的「等出貨」
                openOrders(site: site, status: "paid")
            } else {
                openNeedsYou()
            }
            open(route)
        case .askXena(let prompt):
            askXena(prompt)
        }
    }

    /// 等你決定的一件事：交給 Xena（帶著交代，她先查、給方案）、不用了、之後再說
    func decide(_ decision: Decision, _ action: Decision.Action) {
        switch action {
        case .accept:
            if deckSheet != nil {
                afterClosingDeck { $0.handOff(decision) }
            } else {
                handOff(decision)
            }
        case .later:
            briefing.decide(decision, action)
            show("好，一週後再提醒你", tone: .neutral)
        case .dismiss:
            briefing.decide(decision, action)
            show("好，這件不做", tone: .neutral)
        }
    }

    /// 交給 Xena：真的送出去了（或排在她正在回答的那句後面）才從清單拿掉、告訴 console；
    /// 還沒同意用雲端 AI、按了「先不要」，這件就留在清單上
    private func handOff(_ decision: Decision) {
        askXena(decision.prompt) { [weak self] in
            self?.briefing.decide(decision, .accept)
        }
    }

    /// 要把資料交給雲端 AI 的事（Xena 對話、擬回覆、Xena 分析、雲端語音）：同意過就直接做，
    /// 沒有就先跳說明（App Review 5.1.2(i)），同意了才做；不同意就不做
    func withCloudAI(_ action: @escaping () -> Void) {
        if AppSettings.shared.cloudAIAllowed {
            action()
            return
        }
        pendingCloudAI.append(action)
        guard !showAIConsent else { return }
        if showAccount {
            // 設定頁（sheet）開著：先收起來再問
            showAccount = false
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                self?.showAIConsent = true
            }
        } else if deckSheet != nil {
            afterClosingDeck { $0.showAIConsent = true }
        } else {
            showAIConsent = true
        }
    }

    /// 說明頁按了同意／先不要（往下滑掉也算先不要）
    func answerCloudAI(_ granted: Bool) {
        let actions = pendingCloudAI
        pendingCloudAI = []
        showAIConsent = false
        guard granted else {
            if !actions.isEmpty { show("沒問題，Xena 先不用。之後可以在「設定 → AI 與隱私」打開", tone: .neutral) }
            return
        }
        AppSettings.shared.cloudAIConsent = true
        // 等說明頁收起來再打開 Xena（同一時間只能有一個畫面蓋上來）
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            for action in actions { action() }
        }
    }

    /// 打開 Xena 接著問一句（她還在回答就排在後面，答完再問）。onStart：這一句真的送出時
    func askXena(_ prompt: String, onStart: (() -> Void)? = nil) {
        showXena = true
        xena.send(prompt, onStart: onStart)
    }

    func show(_ text: String, tone: Tone = .active) {
        toast = Toast(text: text, tone: tone)
        switch tone {
        case .danger: errorTick += 1
        case .warning: warningTick += 1
        default: successTick += 1
        }
    }

    /// 寬窄切換（iPad 分割畫面、台前調度）：網站的頁面搬到對應的地方
    func setRegular(_ value: Bool) {
        guard value != regular else { return }
        regular = value
        if value {
            // 手機的「網站」分頁 → 側欄的那個網站
            if tab == .sites, case .console? = sitesPath.first {
                // 手機的「網站 → 平台管理 → 某一頁」→ 側欄的「平台管理」選那一頁
                let rest = Array(sitesPath.dropFirst())
                if case .console(let page)? = rest.first, let section = Self.sidebarSection(for: page) {
                    consoleSection = section
                    consolePath = section == page ? Array(rest.dropFirst()) : rest
                } else {
                    consolePath = rest
                }
                tab = .console
            } else if tab == .sites {
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
        } else if tab == .console {
            sitesPath = [.console(.home), .console(consoleSection)] + consolePath
            tab = .sites
        } else if tab == .account {
            // 手機的分頁列沒有「我」：改成從首頁打開
            tab = .xena
            showAccount = true
        }
    }
}

/// 畫面上正在看的東西（哪一頁設的、要問 Xena 的那一句）
struct XenaFocus: Equatable {
    let id: String
    let prompt: String
}

extension View {
    /// 這一頁在畫面上時，「問問Xena」打開的對話第一個建議就是 prompt（離開這一頁就拿掉，被下一頁換掉的不會誤刪）
    func xenaFocus(_ id: String, prompt: String) -> some View {
        modifier(XenaFocusModifier(id: id, prompt: prompt))
    }
}

private struct XenaFocusModifier: ViewModifier {
    let id: String
    let prompt: String
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .onAppear { model.xenaFocus = XenaFocus(id: id, prompt: prompt) }
            .onChange(of: prompt) { _, value in
                if model.xenaFocus?.id == id { model.xenaFocus = XenaFocus(id: id, prompt: value) }
            }
            .onDisappear {
                if model.xenaFocus?.id == id { model.xenaFocus = nil }
            }
    }
}

/// 首頁狀況卡片打開的 sheet：今天的總覽，或一個網站（id 是網站代號）
struct DeckSheet: Identifiable, Hashable {
    let id: String
    static let today = DeckSheet(id: "today")
}
