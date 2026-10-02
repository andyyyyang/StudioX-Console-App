import SwiftUI

@main
struct StudioXConsoleApp: App {
    @State private var model = AppModel()

    init() {
        BrandFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
                .tint(Theme.primary)
        }
        .commands {
            // iPad 的鍵盤與選單列：⌘1–⌘5 切換、⌘K 找 Xena、⌘R 重新整理
            CommandMenu("前往") {
                Button("Xena") { model.tab = .xena }
                    .keyboardShortcut("1")
                Button("網站") { model.goToSites() }
                    .keyboardShortcut("2")
                Button("訂單") { model.tab = .orders }
                    .keyboardShortcut("3")
                    .disabled(model.orderSites.isEmpty)
                Button("收件匣") { model.tab = .inbox }
                    .keyboardShortcut("4")
                Button("我") { model.goToAccount() }
                    .keyboardShortcut("5")
                Button("搜尋") { model.tab = .search }
                    .keyboardShortcut("f")
                Divider()
                Button("和 Xena 說話") { model.showXena = true }
                    .keyboardShortcut("k")
                Button("重新整理") { Task { await model.refreshAll() } }
                    .keyboardShortcut("r")
            }
        }
    }
}

/// 沒登入：3D 歡迎頁；登入後：品牌的載入動畫 → Xena 當店長的主畫面
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .welcome:
                WelcomeView()
                    .transition(.opacity)
            case .loading:
                LoadingScreen()
                    // 載入完：整片像布幕一樣往上收（Loader 的 translateY(-100%)，1 秒 ease-in-out）
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top)))
                    .zIndex(1)
            case .ready:
                MainView()
                    .transition(.opacity)
            }
        }
        .animation(.timingCurve(0.65, 0, 0.35, 1, duration: 1), value: model.phase)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2.6))
                        if model.toast?.id == toast.id {
                            withAnimation(Motion.spring) { model.toast = nil }
                        }
                    }
            }
        }
        .animation(Motion.spring, value: model.toast)
        .sensoryFeedback(.success, trigger: model.successTick)
        .sensoryFeedback(.warning, trigger: model.warningTick)
        .sensoryFeedback(.error, trigger: model.errorTick)
        .task { await model.start() }
    }
}

/// 登入後拿網站清單的那一下：studiox.tw 的載入動畫；拿不到時說明＋重試
private struct LoadingScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.loadError {
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                XenaOrb(mood: .idle, size: 72)
                Headline("Something's *off*.", role: .h1)
                Text(error)
                    .textRole(.lead)
                    .foregroundStyle(Theme.ink2)
                HStack(spacing: 10) {
                    Button("再試一次") { Task { await model.loadMe() } }
                        .buttonStyle(.brand(.primary, arrow: true))
                    Button("登出") { Task { await model.signOut() } }
                        .buttonStyle(.brand(.ghost))
                }
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background { Theme.page.ignoresSafeArea() }
        } else {
            BrandLoader(caption: "Xena 正在打開你的網站")
        }
    }
}

/// 主畫面：手機是底部分頁；iPad 是可以收合的側欄，每個網站直接列在側欄裡（TabSection）
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var model = model
        let regular = sizeClass == .regular
        TabView(selection: $model.tab) {
            Tab("Xena", image: "XenaOrb", value: AppTab.xena) {
                XenaHomeView()
            }
            Tab("網站", image: "hi-globe-alt", value: AppTab.sites) {
                SitesView()
            }
            .hidden(regular)
            if !model.orderSites.isEmpty {
                Tab("訂單", image: "hi-shopping-bag", value: AppTab.orders) {
                    OrdersView()
                }
            }
            Tab("收件匣", image: "hi-inbox-stack", value: AppTab.inbox) {
                InboxView()
            }
            .badge(model.inboxCount)
            Tab("我", image: "hi-user-circle", value: AppTab.account) {
                AccountView()
            }
            .hidden(!regular)
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
            TabSection("網站") {
                ForEach(model.sites) { site in
                    Tab(site.name, image: site.hasOrders ? "hi-building-storefront" : "hi-globe-alt", value: AppTab.site(site.id)) {
                        SiteWorkspace(siteID: site.id)
                    }
                }
            }
            .hidden(!regular)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewSidebarHeader {
            HStack(spacing: 10) {
                BrandMark()
                    .foregroundStyle(Theme.ink)
                    .frame(width: 22, height: 22)
                Text("\(Text("studiox").foregroundStyle(Theme.ink))\(Text(".").foregroundStyle(Theme.accent))")
                    .font(.brand(22, .semibold))
                    .tracking(-0.9)
            }
            .padding(.vertical, 6)
            .accessibilityElement()
            .accessibilityLabel("StudioX")
        }
        .tabViewBottomAccessory {
            XenaAccessory()
        }
        .sheet(isPresented: $model.showXena) {
            XenaChatView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $model.showAccount) {
            AccountView()
                .presentationDragIndicator(.visible)
        }
        .onChange(of: regular, initial: true) { _, value in
            model.setRegular(value)
        }
    }
}

/// 從哪一頁點進來都一樣的下一層頁面
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .site(let id): SiteHomeView(siteID: id)
        case .order(let site, let id): OrderDetailView(site: site, orderID: id)
        case .thread(let site, let id): SupportThreadView(site: site, threadID: id)
        case .xenaConversation(let site, let id): XenaConversationView(site: site, conversationID: id)
        case .collection(let site, let entity): CollectionView(site: site, entity: entity)
        case .record(let site, let entity, let id): RecordView(site: site, entity: entity, id: id)
        case .create(let site, let entity): RecordEditor(site: site, entity: entity, mode: .create)
        case .traffic(let site): TrafficView(siteID: site)
        case .searchConsole(let site): SearchConsoleView(siteID: site)
        case .member(let site, let id): MemberView(site: site, memberID: id)
        }
    }
}
