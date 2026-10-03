import SwiftUI
import UIKit

@main
struct StudioXConsoleApp: App {
    /// 通知：Apple 給的 device token、點了通知（AppDelegate.swift）
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .appSettingsAppearance()
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
                Button("設定") { model.goToAccount() }
                    .keyboardShortcut(",")
                Button("搜尋") { model.tab = .search }
                    .keyboardShortcut("f")
                Divider()
                Button("問問Xena") { model.showXena = true }
                    .keyboardShortcut("k")
                Button("用說的問Xena") { model.showVoice = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("重新整理") { Task { await model.refreshAll() } }
                    .keyboardShortcut("r")
            }
        }
    }
}

/// 沒登入：3D 歡迎頁；登入後：品牌的載入動畫 → Xena 當店長的主畫面
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Face ID 的鎖定畫面、切換 App 的遮罩（自己的視窗，蓋得住 sheet）
    @State private var cover = LockWindow()

    /// 要不要蓋住：鎖著、在背景，或切到別的 App／拉下通知中心（跳 Face ID 的那一下不算，但跳到一半進背景還是要蓋）
    private var covered: Bool {
        guard model.phase != .welcome else { return false }
        return model.lock.locked || scenePhase == .background || (scenePhase == .inactive && !model.lock.authenticating)
    }

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
        .haptic(.success, trigger: model.successTick)
        .haptic(.warning, trigger: model.warningTick)
        .haptic(.error, trigger: model.errorTick)
        .background {
            // 視窗本身也塗成暖紙色：狀態列後面、iPad 分欄之間、轉場的一瞬間都不會露出純黑／純白
            Theme.page.ignoresSafeArea()
            WindowPaint()
            SceneProbe { cover.scene = $0 }
        }
        .onChange(of: covered, initial: true) { _, value in
            cover.show(value, model: model)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                model.lock.didLeave()
            case .active:
                model.lock.didReturn()
                // 剛鎖上才自動跳 Face ID；取消了就停在鎖定畫面，等他按「解鎖」或登出
                if model.lock.takePrompt() { Task { await model.lock.unlock() } }
                // 回到 App：之後的請求開新的連線（舊的可能在背景時被網路斷了，不然第一個請求會等到逾時）；
                // 重拿通知的 token（可能換了）、在設定裡打開了通知
                if model.phase == .ready {
                    Task {
                        await model.api.freshConnections()
                        await model.push.refresh()
                    }
                }
            default:
                break
            }
        }
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
            Tab("今天", image: "hi-home", value: AppTab.xena) {
                XenaHomeView().tabPage()
            }
            Tab("網站", image: "hi-globe-alt", value: AppTab.sites) {
                SitesView().tabPage()
            }
            .hidden(regular)
            if !model.orderSites.isEmpty {
                Tab("訂單", image: "hi-shopping-bag", value: AppTab.orders) {
                    OrdersView().tabPage()
                }
            }
            Tab("收件匣", image: "hi-inbox-stack", value: AppTab.inbox) {
                InboxView().tabPage()
            }
            .badge(model.inboxCount)
            Tab("設定", image: "hi-cog-6-tooth", value: AppTab.account) {
                AccountView().tabPage()
            }
            .hidden(!regular)
            Tab(value: AppTab.search, role: .search) {
                SearchView().tabPage()
            }
            TabSection("網站") {
                ForEach(model.sites) { site in
                    Tab(site.name, image: site.hasOrders ? "hi-building-storefront" : "hi-globe-alt", value: AppTab.site(site.id)) {
                        SiteWorkspace(siteID: site.id).tabPage()
                    }
                }
            }
            .hidden(!regular)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewSidebarHeader {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    BrandMark()
                        .foregroundStyle(Theme.ink)
                        .frame(width: 22, height: 22)
                    Text("\(Text("studiox").foregroundStyle(Theme.ink))\(Text(".").foregroundStyle(Theme.accent))")
                        .font(.brand(22, .semibold))
                        .tracking(-0.9)
                }
                .accessibilityElement()
                .accessibilityLabel("StudioX")
                // iPad：Xena 的狀態放在這裡（手機在 tab bar 上面）
                XenaSidebarStatus()
            }
            .padding(.vertical, 6)
        }
        // 手機：tab bar 上面的 Xena。首頁本身就有會動的水滴，那一頁不重複出現；對話畫面（回覆框在底部）也收起來
        .tabViewBottomAccessory(isEnabled: !regular && model.tab != .xena && model.openChats == 0) {
            XenaAccessory()
        }
        // iPad：整條太搶眼，改成右下角一顆小水珠（狀態在側欄上面）；同樣首頁、對話畫面不出現
        .overlay(alignment: .bottomTrailing) {
            if regular && model.tab != .xena && model.openChats == 0 {
                XenaFloatingButton()
                    .padding(.trailing, 28)
                    .padding(.bottom, 24)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(Motion.spring, value: regular && model.tab != .xena && model.openChats == 0)
        .sheet(isPresented: $model.showXena) {
            XenaChatView()
                .presentationDragIndicator(.visible)
        }
        // 用說的：整個畫面
        .fullScreenCover(isPresented: $model.showVoice) {
            XenaVoiceView()
        }
        .sheet(isPresented: $model.showAccount) {
            AccountView()
                .presentationDragIndicator(.visible)
        }
        .onChange(of: regular, initial: true) { _, value in
            model.setRegular(value)
        }
        // 點了通知：打開對應的頁面（冷啟動的那一則等主畫面好了才開）
        .onChange(of: model.push.pending, initial: true) { _, payload in
            guard let payload else { return }
            model.push.pending = nil
            model.open(payload)
        }
        // App 開著時收到通知：首頁、收件匣跟著更新
        .onChange(of: model.push.receivedTick) {
            Task { await model.briefing.refresh(sites: model.sites) }
        }
        // App 圖示上的數字＝收件匣在等的
        .onChange(of: model.inboxCount, initial: true) { _, count in
            model.push.setBadge(count)
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
        case .inquiry(let site, let id): InquiryView(site: site, inquiryID: id)
        case .collection(let site, let entity): CollectionView(site: site, entity: entity)
        case .record(let site, let entity, let id): RecordView(site: site, entity: entity, id: id)
        case .create(let site, let entity): RecordEditor(site: site, entity: entity, mode: .create)
        case .traffic(let site): TrafficView(siteID: site)
        case .searchConsole(let site): SearchConsoleView(siteID: site)
        case .member(let site, let id): MemberView(site: site, memberID: id)
        }
    }
}

/// 把這個畫面所在的視窗塗成暖紙色（狀態列後面、iPad 分欄之間、轉場時露出來的地方）。
/// 只塗主畫面自己的視窗：鎖定畫面在另一個透明的視窗，不能動它
struct WindowPaint: UIViewRepresentable {
    func makeUIView(context: Context) -> PaintView {
        let view = PaintView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PaintView, context: Context) {}

    final class PaintView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.backgroundColor = Theme.pageUIColor
        }
    }
}

private extension View {
    /// 分頁的底（TabView 每一頁後面）：暖紙色
    func tabPage() -> some View {
        containerBackground(Theme.page, for: .tabView)
    }
}
