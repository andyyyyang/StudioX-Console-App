import SwiftUI

// 報表的時間區間：一個網站的概況、流量、營運報表、Google 搜尋用同一個（AppModel.analyticsRanges），
// 在哪一頁切，其他頁都跟著變 —— 以前每一頁、甚至同一頁的每一塊各有各的區間，看起來對不上。
// 「今天」是今天 0 點到現在（網站時區），「7 天」是含今天往回 7 天；營運報表也照這個算（ops_report 的 includeToday）。
// 也可以自訂起訖（10/1 – 10/15）：網站的 traffic_report、ops_report、search_report 收 from／to（YYYY-MM-DD）。

enum AnalyticsRange {
    static let presets = [1, 7, 30, 90, 365]
    static let standard = 7
    /// 自訂最長幾天（網站的上限）
    static let maxCustomDays = 366
    /// 最早能選到哪一天（網站的瀏覽紀錄留 400 天）
    static let retentionDays = 399

    static func title(_ days: Int) -> String {
        days == 1 ? "今天" : days == 365 ? "一年" : "\(days) 天"
    }

    /// 寫在區塊標題裡：今天、最近 7 天
    static func phrase(_ days: Int) -> String {
        days == 1 ? "今天" : days == 365 ? "最近一年" : "最近 \(days) 天"
    }
}

/// 一個網站報表看的期間：含今天往回幾天，或自訂起訖（台北的日期，兩天都算）
struct ReportRange: Equatable {
    var days: Int
    var from: Date?
    var to: Date?

    static let standard = ReportRange(days: AnalyticsRange.standard)

    static func last(_ days: Int) -> ReportRange { ReportRange(days: days) }

    /// 自訂起訖：順序反了對調、結束日不超過今天、最長 366 天（太長從結束日往回截）
    static func custom(from a: Date, to b: Date) -> ReportRange {
        let cal = Calendar.taipei
        let today = cal.startOfDay(for: .now)
        var start = cal.startOfDay(for: min(a, b))
        let end = min(cal.startOfDay(for: max(a, b)), today)
        if start > end { start = end }
        var days = (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        if days > AnalyticsRange.maxCustomDays {
            days = AnalyticsRange.maxCustomDays
            start = cal.date(byAdding: .day, value: -(days - 1), to: end) ?? start
        }
        return ReportRange(days: days, from: start, to: end)
    }

    var isCustom: Bool { from != nil && to != nil }

    /// 給網站的參數：自訂的帶 from／to（也帶 days，舊版網站不認得 from／to 時至少長度對）
    var args: [String: JSONValue] {
        var a: [String: JSONValue] = ["days": .number(Double(days))]
        if let from, let to {
            a["from"] = .string(Self.ymd(from))
            a["to"] = .string(Self.ymd(to))
        }
        return a
    }

    /// .task(id:) 用：期間變了就重新拿
    var key: String {
        if let from, let to { return "\(Self.ymd(from))~\(Self.ymd(to))" }
        return "\(days)"
    }

    /// 選單、按鈕上的字：今天、7 天、10/1 – 10/15
    var title: String { isCustom ? dates : AnalyticsRange.title(days) }

    /// 區塊標題裡：今天、最近 7 天、10/1 – 10/15
    var phrase: String { isCustom ? dates : AnalyticsRange.phrase(days) }

    /// 10/1 – 10/15（同一天只寫一天、跨年寫年份）
    var dates: String {
        guard let from, let to else { return "" }
        let cal = Calendar.taipei
        let withYear = cal.component(.year, from: from) != cal.component(.year, from: to)
        let f = { (d: Date) -> String in
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return (withYear ? "\(c.year ?? 0)/" : "") + "\(c.month ?? 0)/\(c.day ?? 0)"
        }
        return Self.ymd(from) == Self.ymd(to) ? f(to) : "\(f(from)) – \(f(to))"
    }

    /// 最後一天是今天（數字算到現在）
    var endsToday: Bool {
        guard let to else { return true }
        return Calendar.taipei.isDate(to, inSameDayAs: .now)
    }

    static func ymd(_ d: Date) -> String {
        let c = Calendar.taipei.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
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
    /// 這個網站現在看的期間
    func reportRange(_ site: String) -> ReportRange {
        analyticsRanges[site] ?? .standard
    }

    /// 這個網站現在看幾天（自訂的是起訖的天數）
    func analyticsRange(_ site: String) -> Int {
        reportRange(site).days
    }

    func setReportRange(_ site: String, _ range: ReportRange) {
        withAnimation(Motion.ease) { analyticsRanges[site] = range }
    }
}

/// 自訂起訖的選單項目值：0（不會和天數撞）
private let customItem = 0

/// 報表頁上面的區間：今天、7 天、30 天、90 天、一年、自訂（同一個網站的報表頁共用）；下面一行寫實際的日期
struct AnalyticsRangeBar: View {
    let siteID: String
    /// 實際的日期（網站回的，例如 11/4 – 11/10）；還沒拿到就不寫
    var dates: String?
    var note: String?
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        let range = model.reportRange(siteID)
        let line = [range.isCustom ? nil : dates, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "・")
        VStack(alignment: .leading, spacing: 8) {
            FilterBar(
                items: AnalyticsRange.presets + [customItem],
                selection: Binding(
                    get: { range.isCustom ? customItem : range.days },
                    set: { v in
                        if v == customItem { picking = true } else { model.setReportRange(siteID, .last(v)) }
                    }
                ),
                title: { $0 == customItem ? (range.isCustom ? range.dates : "自訂…") : AnalyticsRange.title($0) }
            )
            if !line.isEmpty {
                Text(line)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }
        }
        .sheet(isPresented: $picking) { CustomRangeSheet(siteID: siteID) }
    }
}

/// 自訂起訖：選開始與結束的日期（最早 400 天前、最晚今天、最長 366 天）
struct CustomRangeSheet: View {
    let siteID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var from = Date.now
    @State private var to = Date.now

    var body: some View {
        let cal = Calendar.taipei
        let today = cal.startOfDay(for: .now)
        let earliest = cal.date(byAdding: .day, value: -AnalyticsRange.retentionDays, to: today) ?? today
        let preview = ReportRange.custom(from: from, to: to)
        NavigationStack {
            Form {
                Section {
                    DatePicker("開始", selection: $from, in: earliest...today, displayedComponents: .date)
                    DatePicker("結束", selection: $to, in: earliest...today, displayedComponents: .date)
                } footer: {
                    Text("\(preview.dates)，共 \(preview.days) 天" + (preview.endsToday ? "（今天算到現在）" : "") + "。最長 \(AnalyticsRange.maxCustomDays) 天；流量最早看得到 \(AnalyticsRange.retentionDays + 1) 天前。")
                }
                Section {
                    ForEach(Self.shortcuts(today: today), id: \.0) { s in
                        Button(s.0) {
                            from = s.1
                            to = s.2
                        }
                        .foregroundStyle(Theme.ink)
                    }
                } header: {
                    Text("常用")
                }
            }
            .environment(\.timeZone, cal.timeZone)
            .navigationTitle("自訂期間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用") {
                        model.setReportRange(siteID, preview)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // 從現在看的期間開始改
            let r = model.reportRange(siteID)
            to = r.to ?? today
            from = r.from ?? (cal.date(byAdding: .day, value: -(r.days - 1), to: today) ?? today)
        }
    }

    /// 常用的幾段：昨天、上週（一到日）、這個月、上個月
    static func shortcuts(today: Date) -> [(String, Date, Date)] {
        let cal = Calendar.taipei
        var out: [(String, Date, Date)] = []
        if let y = cal.date(byAdding: .day, value: -1, to: today) { out.append(("昨天", y, y)) }
        var iso = cal
        iso.firstWeekday = 2
        if let thisWeek = iso.dateInterval(of: .weekOfYear, for: today)?.start,
           let lastStart = cal.date(byAdding: .day, value: -7, to: thisWeek),
           let lastEnd = cal.date(byAdding: .day, value: -1, to: thisWeek) {
            out.append(("上週", lastStart, lastEnd))
        }
        if let monthStart = cal.dateInterval(of: .month, for: today)?.start {
            out.append(("這個月", monthStart, today))
            if let prevEnd = cal.date(byAdding: .day, value: -1, to: monthStart),
               let prevStart = cal.dateInterval(of: .month, for: prevEnd)?.start {
                out.append(("上個月", prevStart, prevEnd))
            }
        }
        return out
    }
}

/// 導覽列上的區間（與級距）選單：頁面往下捲、上面的區間列看不到時也能直接換（導覽列一直在）。
/// 按下去：今天／7 天…／自訂期間；有走勢的頁面再加上每小時／每天／每週／每月
struct AnalyticsRangeMenu: View {
    let siteID: String
    /// 走勢的級距（流量頁才有）；nil＝這頁沒有走勢可以換
    var interval: Binding<TrendInterval>?
    var intervals: [TrendInterval] = []
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        let range = model.reportRange(siteID)
        Menu {
            Section("時間區間") {
                Picker("時間區間", selection: Binding(
                    get: { range.isCustom ? customItem : range.days },
                    set: { v in if v != customItem { model.setReportRange(siteID, .last(v)) } }
                )) {
                    ForEach(AnalyticsRange.presets, id: \.self) { d in
                        Text(AnalyticsRange.title(d)).tag(d)
                    }
                    if range.isCustom {
                        Text(range.dates).tag(customItem)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Button("自訂期間…") { picking = true }
            }
            if let interval, intervals.count > 1 {
                Section("走勢") {
                    Picker("走勢", selection: interval) {
                        ForEach(intervals, id: \.self) { o in
                            Text(o.heading).tag(o)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label(range))
                    .font(.brand(15, .semibold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                HeroIcon("chevron-down", size: 12)
            }
            .foregroundStyle(Theme.ink)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("時間區間：\(label(range))")
        .haptic(.selection, trigger: range.key)
        .sheet(isPresented: $picking) { CustomRangeSheet(siteID: siteID) }
    }

    private func label(_ range: ReportRange) -> String {
        if let interval, intervals.count > 1 {
            return "\(range.title)・\(interval.wrappedValue.heading)"
        }
        return range.title
    }
}

/// 報表頁的導覽列：右上角的區間選單（AnalyticsRangeMenu）
struct AnalyticsRangeToolbar: ToolbarContent {
    let siteID: String
    var interval: Binding<TrendInterval>?
    var intervals: [TrendInterval] = []

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            AnalyticsRangeMenu(siteID: siteID, interval: interval, intervals: intervals)
        }
    }
}
