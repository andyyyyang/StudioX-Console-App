import Foundation

/// StudioX 官方帳號（LINE）和這個帳號的狀態（/api/app/line）
nonisolated struct LineStatus: Equatable, Sendable {
    /// 網站的通知從 LINE 傳：全部／只有緊急的／不要
    enum Notify: String, CaseIterable, Identifiable, Sendable {
        case all, urgent, off
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "全部"
            case .urgent: "只有緊急的"
            case .off: "不要"
            }
        }
    }

    /// console 設定好了官方帳號（沒有的話設定頁不顯示 LINE）
    var available: Bool
    var linked: Bool
    var displayName: String?
    /// 還是官方帳號的好友（封鎖了、或用 LINE 登入綁定但還沒加好友就是 false）
    var following: Bool
    var notify: Notify
    var oaId: String?
    var addFriendURL: URL?

    init(_ json: JSONValue) {
        available = json["available"]?.bool ?? false
        linked = json["linked"]?.bool ?? false
        displayName = json["displayName"]?.string
        following = json["following"]?.bool ?? false
        notify = Notify(rawValue: json["notify"]?.string ?? "") ?? .all
        oaId = json["oaId"]?.string
        addFriendURL = json["addFriendUrl"]?.string.flatMap(URL.init(string:))
    }
}
