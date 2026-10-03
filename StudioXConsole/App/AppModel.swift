import AuthenticationServices
import Observation
import SwiftUI
import UIKit

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
    var showAccount = false {
        didSet {
            guard showAccount, deckSheet != nil else { return }
            showAccount = false
            afterClosingDeck { $0.showAccount = true }
        }
    }
    /// iPad：每個網站自己的一疊頁面
    var sitePaths: [String: [Route]] = [:]
    var showXena = false {
        didSet {
            guard showXena, deckSheet != nil else { return }
            showXena = false
            afterClosingDeck { $0.showXena = true }
        }
    }
    /// 用說的跟 Xena 聊（整個畫面）
    var showVoice = false {
        didSet {
            guard showVoice, deckSheet != nil else { return }
            showVoice = false
            afterClosingDeck { $0.showVoice = true }
        }
    }
    /// 首頁狀況卡片打開的 sheet（今天的總覽，或一個網站）
    var deckSheet: DeckSheet?
    var toast: Toast?
    /// 觸覺回饋（RootView 的 sensoryFeedback 看這幾個數字）
    private(set) var successTick = 0
    private(set) var warningTick = 0
    private(set) var errorTick = 0
    /// 訂單頁現在看的網站與狀態（首頁的「等出貨」點進去會設好）
    var ordersSite: String?
    var ordersStatus = "paid"
    /// 首頁 Xena 已經說過的那段話（同一段話回到首頁不再重說一次）
    var spokenReport: String?
    /// 現在在看的網站、訂單：按「問問Xena」時第一個建議就是問這個（.xenaFocus）
    var xenaFocus: XenaFocus?
    /// Apple Intelligence 寫好的首頁開場白（照資料拼的那句 → 她會說的話；寫不出來或數字對不上就是原句）
    var greetings: [String: String] = [:]
    /// 寬的畫面（iPad 的一般寬度）：網站直接放在側欄
    var regular = false

    /// 收件匣現在看的分段（support、handoffs、inquiries、mailbox；點通知會設好）
    var inboxSegment = "support"

    @ObservationIgnored let api: ConsoleAPI
    let xena: XenaSession
    /// 用說的（耳朵、嘴巴、一來一往）
    let conversation = XenaConversation()
    let briefing: Briefing
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
        self.phase = api.isSignedIn ? .loading : .welcome
        api.onSignedOut = { [weak self] in self?.didSignOut(message: "登入已經過期，請重新登入") }
        xena.onDidWrite = { [weak self] in
            Task { await self?.refreshAll() }
        }
        xena.verify = { [weak self] reason in
            await self?.lock.verify(reason) ?? false
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
    var supportSites: [SiteSummary] { sites.filter(\.hasSupport) }

    func site(_ id: String) -> SiteSummary? {
        sites.first { $0.id == id }
    }

    /// 收件匣的數字（客人在等回覆＋需要專人看的 Xena 對話＋新的詢問）：專人已經回過、客人還沒再說話的不算
    var inboxCount: Int {
        briefing.awaiting.count + briefing.handoffs.filter(\.attention).count + briefing.inquiries.count
    }

    // MARK: 登入

    /// App 打開時：已經登入過就直接拿資料
    func start() async {
        guard phase == .loading else { return }
        await loadMe(minimumDuration: .milliseconds(1900))
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
        case "thread": open(.thread(site: shop, id: "t1"))
        case "line": open(.xenaConversation(site: shop, id: "yc1"))
        case "products": open(.collection(site: shop, entity: "product"))
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
        guard await lock.verify("刪除 StudioX 帳號") else { return false }
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
        accountPath = []
        searchPath = []
        sitePaths = [:]
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
        inboxSegment = "support"
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

    // MARK: 通知打開的頁面

    /// 點了通知要去的地方（網站給的後台路徑對應到 App 的頁面）
    enum PushLink: Equatable {
        case route(Route)
        /// 訂單清單（那個網站）
        case orders(site: String)
        /// 收件匣的某個分段
        case inbox(String)
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
                return .inbox("handoffs")
            }
            if let id = q["thread"] { return .route(.thread(site: site, id: id)) }
            return .inbox("support")
        case "orders":
            if let id = sub ?? q["id"] { return .route(.order(site: site, id: id)) }
            return .orders(site: site)
        case "inbox":
            if let id = q["c"] { return .route(.xenaConversation(site: site, id: id)) }
            if let run = q["run"] { return .route(.record(site: site, entity: "automation_run", id: run)) }
            if q["inquiry"] != nil { return .inbox("inquiries") }
            return .inbox("support")
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
            showXena = false
            showAccount = false
            ordersSite = site
            ordersPath = []
            tab = orderSites.isEmpty ? .xena : .orders
        case .inbox(let segment):
            showXena = false
            showAccount = false
            inboxSegment = segment
            inboxPath = []
            tab = .inbox
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

    /// 打開 Xena 接著問一句
    /// 卡片的 sheet 開著時要打開別的畫面：先收起來，等它收好再打開（兩個 sheet 不能同時開）
    private func afterClosingDeck(_ present: @escaping @MainActor (AppModel) -> Void) {
        deckSheet = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            if let self { present(self) }
        }
    }

    /// 首頁「需要你決定」的一件事：直接去處理（從卡片的 sheet 按的，先收起來）
    func handle(_ action: AttentionItem.Action) {
        if deckSheet != nil {
            afterClosingDeck { $0.handle(action) }
            return
        }
        switch action {
        case .inbox:
            tab = .inbox
        case .inboxSegment(let segment):
            inboxSegment = segment
            tab = .inbox
        case .orders(let site, let status):
            ordersSite = site
            ordersStatus = status
            tab = .orders
        case .askXena(let prompt):
            askXena(prompt)
        }
    }

    func askXena(_ prompt: String) {
        showXena = true
        xena.send(prompt)
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
