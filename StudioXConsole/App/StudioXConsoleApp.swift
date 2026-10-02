import SwiftUI

@main
struct StudioXConsoleApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
                .tint(Brand.accent)
        }
    }
}

/// 沒登入：玻璃登入畫面；登入後：Xena 當店長的主畫面
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .signedOut:
                LoginView()
                    .transition(.opacity)
            case .signedIn:
                MainView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .animation(.smooth(duration: 0.6), value: model.phase)
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Xena", systemImage: "sparkles", value: AppTab.xena) {
                XenaHomeView()
            }
            Tab("網站", systemImage: "square.grid.2x2", value: AppTab.sites) {
                SitesView()
            }
            Tab("收件匣", systemImage: "tray.full", value: AppTab.inbox) {
                InboxView()
            }
            .badge(model.waitingCount)
            Tab("我", systemImage: "person.crop.circle", value: AppTab.account) {
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
        case .order(let id): OrderDetailView(orderID: id)
        case .conversation(let id): ConversationView(conversationID: id)
        }
    }
}
