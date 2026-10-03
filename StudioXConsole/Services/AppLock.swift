import LocalAuthentication
import Observation
import SwiftUI

/// Face ID（或 Touch ID、Optic ID；沒有生物辨識就用裝置密碼）：
///   - 鎖住 App：打開 App、離開超過設定的時間回來，要先解鎖
///   - 退款、刪除、店主核准這類動作，確認前再驗證一次
///   - 切換 App 時畫面蓋起來（多工畫面看不到訂單、客人資料）
/// 設定存在這台裝置（UserDefaults），登出不會清掉。
@Observable
final class AppLock {
    enum Timeout: Int, CaseIterable, Identifiable {
        case immediately = 0
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900
        case oneHour = 3600

        var id: Self { self }

        var label: String {
            switch self {
            case .immediately: "立刻"
            case .oneMinute: "1 分鐘後"
            case .fiveMinutes: "5 分鐘後"
            case .fifteenMinutes: "15 分鐘後"
            case .oneHour: "1 小時後"
            }
        }
    }

    /// 這台裝置能用的解鎖方式
    enum Method: Equatable {
        case faceID, touchID, opticID, passcode
        /// 裝置沒設密碼：不能鎖
        case unavailable

        var name: String {
            switch self {
            case .faceID: "Face ID"
            case .touchID: "Touch ID"
            case .opticID: "Optic ID"
            case .passcode, .unavailable: "裝置密碼"
            }
        }

        var symbol: String {
            switch self {
            case .faceID: "faceid"
            case .touchID: "touchid"
            case .opticID: "opticid"
            case .passcode, .unavailable: "lock"
            }
        }
    }

    private enum Key {
        static let enabled = "lock.enabled"
        static let timeout = "lock.timeout"
        static let confirm = "lock.confirmDangerous"
    }

    /// 鎖住 App（預設開）
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Key.enabled) }
    }

    /// 離開多久回來要解鎖
    var timeout: Timeout {
        didSet { UserDefaults.standard.set(timeout.rawValue, forKey: Key.timeout) }
    }

    /// 退款、刪除這類動作確認前再驗證一次（預設開）
    var confirmDangerous: Bool {
        didSet { UserDefaults.standard.set(confirmDangerous, forKey: Key.confirm) }
    }

    /// 現在鎖著（主畫面蓋著解鎖畫面）
    private(set) var locked: Bool
    /// 正在跳 Face ID（這時候 App 會變成 inactive，不要蓋遮罩）
    private(set) var authenticating = false
    /// 剛鎖上、還沒自動跳過 Face ID（打開 App、離開太久回來時各跳一次；取消了就等他按「解鎖」，不會一直跳）
    @ObservationIgnored private var promptPending = false
    private(set) var method: Method = .unavailable
    @ObservationIgnored private var leftAt: Date?

    init() {
        let defaults = UserDefaults.standard
        enabled = (defaults.object(forKey: Key.enabled) as? Bool) ?? true
        timeout = defaults.object(forKey: Key.timeout) == nil ? .oneMinute : Timeout(rawValue: defaults.integer(forKey: Key.timeout)) ?? .oneMinute
        confirmDangerous = (defaults.object(forKey: Key.confirm) as? Bool) ?? true
        locked = false
        method = Self.availableMethod()
        // 打開 App：設定要鎖、裝置也能鎖，就先鎖著
        locked = enabled && method != .unavailable
        promptPending = locked
    }

    /// 能不能鎖（裝置有設密碼）
    var available: Bool { method != .unavailable }

    static func availableMethod() -> Method {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .unavailable }
        // biometryType 要在 canEvaluatePolicy 之後才有值
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        case .none: return .passcode
        @unknown default: return .passcode
        }
    }

    // MARK: 進出 App

    /// 離開 App（進背景）。跳 Face ID 時只會 inactive、不會進背景；跳到一半滑回主畫面也算離開
    func didLeave() {
        if leftAt == nil { leftAt = .now }
    }

    /// 回到 App：離開超過設定的時間就鎖
    func didReturn() {
        method = Self.availableMethod()
        defer { leftAt = nil }
        guard enabled, available, !locked, let leftAt else { return }
        if Date.now.timeIntervalSince(leftAt) >= Double(timeout.rawValue) {
            locked = true
            promptPending = true
        }
    }

    /// 剛鎖上：自動跳一次 Face ID（回 true 一次）。取消之後回到 App 不會再自動跳
    func takePrompt() -> Bool {
        guard locked, promptPending else { return false }
        promptPending = false
        return true
    }

    /// 示範模式的截圖：顯示鎖定畫面（模擬器沒有 Face ID 也照樣顯示）
    func showDemoLock() {
        method = .faceID
        locked = true
        promptPending = false
    }

    /// 登入、登出：登入的人剛驗證過，不用再鎖
    func reset() {
        locked = false
        promptPending = false
        leftAt = nil
    }

    // MARK: 驗證

    /// 解鎖。取消或失敗就繼續鎖著
    func unlock() async {
        guard locked else { return }
        if await authenticate(reason: "解鎖 StudioX") {
            withAnimation(Motion.ease) { locked = false }
        }
    }

    /// 退款、刪除這類動作確認前：設定關掉或裝置沒密碼就直接通過
    func verify(_ reason: String) async -> Bool {
        guard confirmDangerous, available else { return true }
        return await authenticate(reason: reason)
    }

    /// 打開「鎖住 App」之前先驗證一次（確定這個人解得開）
    func enable() async -> Bool {
        guard available else { return false }
        let ok = await authenticate(reason: "用\(method.name)鎖住 StudioX")
        if ok { enabled = true }
        return ok
    }

    /// 放寬「離開多久要解鎖」也要驗證；改短不用
    func setTimeout(_ value: Timeout) async {
        guard value.rawValue > timeout.rawValue, available else {
            timeout = value
            return
        }
        if await authenticate(reason: "放寬 StudioX 的鎖定時間") {
            timeout = value
        }
    }

    /// 關掉保護之前也要驗證（借手機的人不能自己關掉）
    func turnOff(_ setting: ReferenceWritableKeyPath<AppLock, Bool>) async {
        guard available else {
            self[keyPath: setting] = false
            return
        }
        if await authenticate(reason: "關閉 StudioX 的保護") {
            self[keyPath: setting] = false
        }
    }

    private func authenticate(reason: String) async -> Bool {
        guard !authenticating else { return false }
        authenticating = true
        defer { authenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        let ok = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // 系統在背景執行緒回呼：明確標成 @Sendable，不會被當成主執行緒的程式
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { @Sendable ok, _ in
                continuation.resume(returning: ok)
            }
        }
        // 驗證完才放掉 context（放掉會取消驗證）
        context.invalidate()
        return ok
    }
}
