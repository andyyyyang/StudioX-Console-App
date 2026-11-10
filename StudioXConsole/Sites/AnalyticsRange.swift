import SwiftUI

// 報表的時間區間：一個網站的概況、流量、營運報表、Google 搜尋用同一個（AppModel.analyticsDays），
// 在哪一頁切，其他頁都跟著變 —— 以前每一頁、甚至同一頁的每一塊各有各的區間，看起來對不上。
// 「今天」是今天 0 點到現在（網站時區），「7 天」是含今天往回 7 天；營運報表也照這個算（ops_report 的 includeToday）。

enum AnalyticsRange {
    static let presets = [1, 7, 30, 90, 365]
    static let standard = 7

    static func title(_ days: Int) -> String {
        days == 1 ? "今天" : days == 365 ? "一年" : "\(days) 天"
    }

    /// 寫在區塊標題裡：今天、最近 7 天
    static func phrase(_ days: Int) -> String {
        days == 1 ? "今天" : days == 365 ? "最近一年" : "最近 \(days) 天"
    }
}

/// 走勢的級距（traffic_report 的 interval）
nonisolated enum TrendInterval: String, CaseIterable, Hashable, Sendable {
    case hour, day, week, month

    var title: String {
        switch self {
        case .hour: "小時"
        case .day: "天"
        case .week: "週"
        case .month: "月"
        }
    }

    /// 走勢的標題：每小時、每天…
    var heading: String { "每\(title)" }

    /// 這段期間能選哪幾種（網站的小時最多到 7 天；一格都不到的不給選）
    static func options(days: Int) -> [TrendInterval] {
        switch days {
        case ...1: [.hour]
        case ...7: [.hour, .day]
        case ...31: [.day, .week]
        default: [.day, .week, .month]
        }
    }

    /// 沒選過時用哪一種：點數適中（今天 24 格、7 天 7 格、90 天 13 格、一年 13 格）
    static func standard(days: Int) -> TrendInterval {
        days <= 1 ? .hour : days <= 31 ? .day : days <= 90 ? .week : .month
    }
}

extension AppModel {
    /// 這個網站現在看的區間（天）
    func analyticsRange(_ site: String) -> Int {
        analyticsDays[site] ?? AnalyticsRange.standard
    }

    func analyticsRangeBinding(_ site: String) -> Binding<Int> {
        Binding(get: { self.analyticsRange(site) }, set: { self.analyticsDays[site] = $0 })
    }
}

/// 報表頁上面的區間：今天、7 天、30 天、90 天、一年（同一個網站的報表頁共用）；下面一行寫實際的日期
struct AnalyticsRangeBar: View {
    let siteID: String
    /// 實際的日期（網站回的，例如 11/4 – 11/10）；還沒拿到就不寫
    var dates: String?
    var note: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        let line = [dates, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "・")
        VStack(alignment: .leading, spacing: 8) {
            FilterBar(items: AnalyticsRange.presets, selection: model.analyticsRangeBinding(siteID), title: AnalyticsRange.title)
            if !line.isEmpty {
                Text(line)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }
        }
    }
}
