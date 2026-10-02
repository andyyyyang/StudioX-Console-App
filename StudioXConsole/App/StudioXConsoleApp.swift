import SwiftUI

@main
struct StudioXConsoleApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
                .tint(Theme.primary)
        }
    }
}

/// 沒登入：3D 歡迎頁；登入後：Xena 當店長的主畫面
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
                    .transition(.opacity)
            case .ready:
                MainView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .animation(.smooth(duration: 0.6), value: model.phase)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2.6))
                        if model.toast?.id == toast.id {
                            withAnimation(.smooth) { model.toast = nil }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.toast)
        .task { await model.start() }
    }
}

/// 登入後拿網站清單的那一下
private struct LoadingScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            XenaOrb(mood: model.loadError == nil ? .thinking : .idle, size: 96)
            if let error = model.loadError {
                Text(error)
                    .font(.admBody)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("登出") { Task { await model.signOut() } }
                        .buttonStyle(.adm(.secondary))
                    Button("再試一次") { Task { await model.loadMe() } }
                        .buttonStyle(.adm(.primary))
                }
            } else {
                Text("Xena 正在打開你的網站…")
                    .font(.admBody)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    private var inboxCount: Int {
        model.briefing.awaiting.count + model.briefing.handoffs.count + model.briefing.inquiries.count
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Xena", image: "XenaOrb", value: AppTab.xena) {
                XenaHomeView()
            }
            Tab("網站", image: "hi-globe-alt", value: AppTab.sites) {
                SitesView()
            }
            if !model.orderSites.isEmpty {
                Tab("訂單", image: "hi-shopping-bag", value: AppTab.orders) {
                    OrdersView()
                }
            }
            Tab("收件匣", image: "hi-inbox-stack", value: AppTab.inbox) {
                InboxView()
            }
            .badge(inboxCount)
            Tab("我", image: "hi-user-circle", value: AppTab.account) {
                AccountView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            XenaAccessory()
        }
        .sheet(isPresented: $model.showXena) {
            XenaChatView()
                .presentationDragIndicator(.visible)
        }
    }
}

/// 從哪一頁點進來都一樣的下一層頁面
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .site(let id): SiteDetailView(siteID: id)
        case .order(let site, let id): OrderDetailView(site: site, orderID: id)
        case .thread(let site, let id): SupportThreadView(site: site, threadID: id)
        case .xenaConversation(let site, let id): XenaConversationView(site: site, conversationID: id)
        }
    }
}
