import Foundation

// MARK: - 通知（/api/app/devices、/api/app/notifications）

/// console 那邊這台裝置的登記
struct PushDevice: Equatable {
    let id: String
    let environment: String
    /// 關掉通知的網站（網站代號）
    var mutedSites: [String]
    let lastSuccessAt: Date?

    init?(_ json: JSONValue?) {
        guard let json, let id = json["id"]?.string else { return nil }
        self.id = id
        environment = json["environment"]?.string ?? "production"
        mutedSites = json["mutedSites"]?.array.compactMap(\.string) ?? []
        lastSuccessAt = json["lastSuccessAt"]?.date
    }
}

/// 登記、改設定之後 console 回的：這台裝置，和伺服器有沒有設定好推播
struct PushRegistration {
    let configured: Bool
    let device: PushDevice?

    init(_ json: JSONValue) {
        configured = json["configured"]?.bool ?? false
        device = PushDevice(json["device"])
    }
}

/// 他在某個網站的個人通知設定（和網站後台「通知設定 → 手機推播」同一份）
struct NotificationPrefs: Equatable {
    struct Group: Identifiable, Equatable {
        let id: String
        let label: String
    }

    struct Event: Identifiable, Equatable {
        let id: String
        let group: String
        let label: String
        let hint: String
        let urgent: Bool
        var on: Bool
        let byDefault: Bool
    }

    /// 勿擾時段（台北時間，從午夜起算的分鐘）
    struct Quiet: Equatable {
        var start: Int
        var end: Int
        var allowUrgent: Bool
    }

    /// 網站有沒有個人通知設定（沒有的話照職能通知）
    let supported: Bool
    let groups: [Group]
    var events: [Event]
    var quiet: Quiet?
    var preview: Bool

    init(_ json: JSONValue) {
        supported = json["supported"]?.bool ?? false
        groups = json["groups"]?.array.compactMap { (g: JSONValue) -> Group? in
            g["key"]?.string.map { Group(id: $0, label: g["label"]?.string ?? $0) }
        } ?? []
        events = json["events"]?.array.compactMap { (e: JSONValue) -> Event? in
            guard let key = e["key"]?.string else { return nil }
            return Event(
                id: key,
                group: e["group"]?.string ?? "",
                label: e["label"]?.string ?? key,
                hint: e["hint"]?.string ?? "",
                urgent: e["urgent"]?.bool ?? false,
                on: e["on"]?.bool ?? false,
                byDefault: e["byDefault"]?.bool ?? false
            )
        } ?? []
        if let q = json["quiet"], let start = q["start"]?.int, let end = q["end"]?.int {
            quiet = Quiet(start: start, end: end, allowUrgent: q["allowUrgent"]?.bool ?? true)
        } else {
            quiet = nil
        }
        preview = json["preview"]?.bool ?? false
    }
}

/// 通知帶來的資料（網站代號、後台路徑、哪一類）。系統在背景執行緒交給我們，所以只放字串
nonisolated struct PushPayload: Equatable, Sendable {
    let site: String?
    let url: String?
    let event: String?

    init(_ info: [AnyHashable: Any]) {
        site = info["site"] as? String
        url = info["url"] as? String
        event = info["event"] as? String
    }
}
