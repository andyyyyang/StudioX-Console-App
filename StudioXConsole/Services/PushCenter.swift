import Observation
import SwiftUI
import UIKit
import UserNotifications

/// 通知：
///   - 允許通知之後向 Apple 拿 device token，登記到 console（/api/app/devices）。每次回到 App 都重拿一次（token 可能換）
///   - 誰收到什麼由各網站決定（職能、自己在網站的通知設定，和瀏覽器推播同一套）；這裡可以關掉整個網站的通知
///   - 點了通知：打開網站給的後台路徑對應的頁面（AppModel.open(_: PushPayload)）
///   - 登出時從 console 移除這台裝置
@Observable
final class PushCenter {
    static let shared = PushCenter()

    enum Permission: Equatable {
        case unknown, notDetermined, denied, allowed
    }

    private(set) var permission: Permission = .unknown
    /// Apple 給這台裝置的 token（16 進位）
    private(set) var token: String?
    /// console 那邊這台裝置的登記（關掉了哪些網站）
    private(set) var device: PushDevice?
    /// console 有沒有設定好 APNs（nil：還沒問過）
    private(set) var configured: Bool?
    /// 登記不了的原因（模擬器、沒網路、console 還沒更新…）
    private(set) var problem: String?
    /// 點了通知、等主畫面好了（載入完、解鎖）要打開的地方
    var pending: PushPayload?
    /// App 開著時收到通知：首頁和收件匣重新整理
    private(set) var receivedTick = 0

    @ObservationIgnored var api: ConsoleAPI?

    private init() {}

    /// sandbox（Xcode 直接裝、模擬器）或 production（TestFlight、App Store）：看簽章裡的 aps-environment。
    /// App Store 和 TestFlight 的版本沒有 embedded.mobileprovision，一律是 production
    nonisolated static let environment: String = {
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return "production" }
        let text = String(decoding: data, as: UTF8.self)
        guard let key = text.range(of: "<key>aps-environment</key>"),
              let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
              let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex) else { return "production" }
        return text[open.upperBound..<close.lowerBound] == "development" ? "sandbox" : "production"
        #endif
    }()

    // MARK: 權限、token

    /// 登入後、回到 App：看權限，允許了就向 Apple 拿 token（拿到後 didRegister 會登記到 console）
    func refresh() async {
        permission = await Self.currentPermission()
        if permission == .allowed {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// 第一次：問要不要允許通知
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { @Sendable ok, _ in
                continuation.resume(returning: ok)
            }
        }
        await refresh()
        return granted
    }

    private static func currentPermission() async -> Permission {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
            // 系統在背景執行緒回呼：明確標成 @Sendable，只把狀態（enum）帶回來
            UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        switch status {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    func didRegister(token: String) {
        self.token = token
        Task { await sync() }
    }

    func didFailToRegister(_ message: String) {
        problem = message
    }

    /// 把這台裝置登記到 console（登入著才登記；同一台換帳號會改掛到現在的人）
    func sync() async {
        guard let api, api.isSignedIn, let token else { return }
        do {
            let r = try await api.registerDevice(token: token, environment: Self.environment, name: UIDevice.current.name)
            configured = r.configured
            device = r.device
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// 登出（或登入過期）：這台裝置不要再收到這個帳號的通知。
    /// 還登入著就請 console 移除；另外一律向 Apple 取消這台的通知代碼——
    /// 登入已經過期、或還沒拿到代碼就登出時沒辦法叫 console，之後 console 送過來 Apple 會回「已失效」，console 就刪掉這台。
    /// 鎖定畫面上已經跳出來的通知也清掉。下次登入會重新拿代碼、重新登記
    func unregister() async {
        if let token, let api, api.isSignedIn {
            await api.removeDevice(token: token)
        }
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        token = nil
        device = nil
        configured = nil
        pending = nil
        setBadge(0)
    }

    // MARK: 設定

    func isMuted(_ site: String) -> Bool {
        device?.mutedSites.contains(site) ?? false
    }

    /// 關掉／打開某個網站的通知（先改畫面，失敗再改回來）
    func setMuted(_ site: String, _ muted: Bool) async throws {
        guard let api, let token, var next = device else { return }
        let before = next
        next.mutedSites = muted ? Array(Set(next.mutedSites + [site])).sorted() : next.mutedSites.filter { $0 != site }
        device = next
        do {
            let r = try await api.setMutedSites(token: token, sites: next.mutedSites)
            configured = r.configured
            if let d = r.device { device = d }
        } catch {
            device = before
            throw error
        }
    }

    func sendTest() async throws {
        guard let api, let token else { throw APIError.tool("這台裝置還沒拿到通知代碼") }
        try await api.testPush(token: token)
    }

    // MARK: 收到、點了通知

    func didReceive(_ payload: PushPayload) {
        receivedTick += 1
    }

    func open(_ payload: PushPayload) {
        pending = payload
    }

    /// App 圖示上的數字＝收件匣在等的（客人在等回覆、轉真人、新的詢問）
    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count), withCompletionHandler: nil)
    }
}
