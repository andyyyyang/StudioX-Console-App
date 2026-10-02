import UIKit
import UserNotifications

/// 系統的通知：Apple 給的 device token、點了通知、App 開著時收到通知。
/// 實際的事交給 PushCenter（登記到 console、打開對應的頁面）。
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// 通知中心只弱參照 delegate：這裡留著它
    private let notifications = NotificationHandler()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 一定要在啟動完成前設好，不然點通知打開 App 的那一則會漏掉
        UNUserNotificationCenter.current().delegate = notifications
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushCenter.shared.didRegister(token: deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushCenter.shared.didFailToRegister(error.localizedDescription)
    }
}

/// 通知中心的 delegate：系統在背景執行緒呼叫，所以不綁主執行緒；只拿出字串，回主執行緒交給 PushCenter
nonisolated final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    /// App 開著的時候收到：照樣跳出橫幅（首頁、收件匣同時重新整理）
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        let payload = PushPayload(notification.request.content.userInfo)
        Task { @MainActor in PushCenter.shared.didReceive(payload) }
        completionHandler([.banner, .list, .sound])
    }

    /// 點了通知：打開對應的頁面（還沒載入好、還沒解鎖就先記著）
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let payload = PushPayload(response.notification.request.content.userInfo)
        let opened = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Task { @MainActor in
            if opened { PushCenter.shared.open(payload) }
            completionHandler()
        }
    }
}
