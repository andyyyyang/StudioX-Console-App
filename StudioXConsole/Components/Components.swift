import SwiftUI
import UIKit

// StudioX 的元件（studiox.tw 的 global.css ＋ 後台的狀態色）。
// 顏色一律用 Theme、字一律用 TextRole，不在頁面裡寫色碼與字級。

// MARK: - 按鈕（.btn）

/// 按鈕：墨色實心、方角 5、字重 500、後面一個 →。按下時品牌橘從下往上填滿、箭頭轉 −45°（global.css 的 .btn）
struct BrandButtonStyle: ButtonStyle {
    enum Variant {
        /// 墨色實心（主要動作）
        case primary
        /// 品牌橘實心（一個畫面最多一個：登入、確認執行）
        case accent
        /// 透明＋細框（.btn--ghost）
        case ghost
        /// 只有字
        case quiet
        /// 危險（退款、刪除、取消訂單）
        case danger
    }

    enum Size {
        /// 34（.btn--sm）
        case sm
        /// 44
        case md
        /// 52：頁面底部的主要動作
        case lg

        var height: CGFloat {
            switch self {
            case .sm: 34
            case .md: 44
            case .lg: 52
            }
        }

        var font: CGFloat {
            switch self {
            case .sm: 13.5
            case .md: 15
            case .lg: 16
            }
        }

        var padding: CGFloat {
            switch self {
            case .sm: 12
            case .md: 18
            case .lg: 22
            }
        }
    }

    var variant: Variant = .primary
    var size: Size = .md
    var fullWidth = false
    /// 後面的 →
    var arrow = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: Metric.radiusSm, style: .continuous)
        HStack(spacing: 8) {
            configuration.label
                .labelStyle(BrandLabelStyle())
            if arrow {
                Text("→")
                    .rotationEffect(.degrees(pressed ? -45 : 0))
                    .offset(x: pressed ? 3 : 0)
            }
        }
        .font(.brand(size.font, .medium, relativeTo: .callout))
        .lineLimit(1)
        .padding(.horizontal, size.padding)
        .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.height)
        .foregroundStyle(foreground(pressed: pressed))
        .background {
            ZStack {
                background
                // 按下時從下往上填滿（.btn::before）
                if let fill {
                    let up = pressed
                    fill.visualEffect { content, proxy in
                        content.offset(y: up ? 0 : proxy.size.height * 1.01)
                    }
                }
            }
            .clipShape(shape)
        }
        .overlay {
            if let border { shape.strokeBorder(border, lineWidth: 1) }
        }
        .contentShape(.hoverEffect, shape)
        .contentShape(shape)
        .hoverEffect(.highlight)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(pressed ? Motion.fast : Motion.ease, value: pressed)
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .primary: Theme.ink
        case .accent: Theme.accent
        case .ghost, .quiet: Color.clear
        case .danger: Theme.dangerFG.opacity(0.08)
        }
    }

    /// 按下時填滿的顏色
    private var fill: Color? {
        switch variant {
        case .primary: Theme.accent
        case .accent: Theme.ink
        case .ghost: Theme.ink
        case .quiet: Theme.press
        case .danger: Theme.dangerFG
        }
    }

    private var border: Color? {
        switch variant {
        case .ghost: Theme.line
        case .danger: Theme.dangerFG.opacity(0.3)
        default: nil
        }
    }

    private func foreground(pressed: Bool) -> Color {
        switch variant {
        case .primary: Theme.page
        case .accent: Theme.onAccent
        case .ghost: pressed ? Theme.page : Theme.ink
        case .quiet: Theme.ink
        case .danger: pressed ? Theme.onAccent : Theme.dangerFG
        }
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static func brand(_ variant: BrandButtonStyle.Variant = .primary, size: BrandButtonStyle.Size = .md, fullWidth: Bool = false, arrow: Bool = false) -> BrandButtonStyle {
        BrandButtonStyle(variant: variant, size: size, fullWidth: fullWidth, arrow: arrow)
    }
}

/// 按鈕裡的圖示＋字
struct BrandLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
            configuration.title
        }
    }
}

/// 方形的圖示鈕（頁首的 44×44 方框、圓角 5）
struct SquareIconButtonStyle: ButtonStyle {
    var size: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(configuration.isPressed ? Theme.press : .clear, in: .rect(cornerRadius: Metric.radiusSm))
            .overlay { RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(Theme.line, lineWidth: 1) }
            .contentShape(.rect)
            .animation(Motion.fast, value: configuration.isPressed)
    }
}

// MARK: - 標籤、篩選、箭頭

/// 篩選用的方形小標籤：選到的墨色實心（作品列表的篩選）
struct FilterChip: View {
    let title: String
    var count: Int?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(selected ? Theme.page.opacity(0.7) : Theme.muted)
                }
            }
            .font(.brand(13.5, .medium, relativeTo: .subheadline))
            .foregroundStyle(selected ? Theme.page : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(selected ? Theme.ink : .clear, in: .rect(cornerRadius: Metric.radiusSm))
            .overlay { RoundedRectangle(cornerRadius: Metric.radiusSm).strokeBorder(selected ? Theme.ink : Theme.line, lineWidth: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .haptic(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 一排篩選（可以橫向捲）
struct FilterBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var count: (Item) -> Int? = { _ in nil }
    /// 左右的留白（放在 pageWidth 裡面時是 0）
    var inset: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    FilterChip(title: title(item), count: count(item), selected: item == selection) {
                        withAnimation(Motion.ease) { selection = item }
                    }
                }
            }
            .padding(.horizontal, inset)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// 細框的小標籤（.chip：圓角 4、13px）
struct Chip: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.brand(12.5, .medium, relativeTo: .caption))
            .foregroundStyle(Theme.ink2)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay { RoundedRectangle(cornerRadius: Metric.chip).strokeBorder(Theme.line, lineWidth: 1) }
    }
}

/// 品牌橘的方塊箭頭（.arrow-dot、卡片右上角的 ↗）
struct ArrowTile: View {
    var glyph = "↗"
    var size: CGFloat = 26
    var active = true

    var body: some View {
        Text(glyph)
            .font(.brand(size * 0.55, .medium))
            .foregroundStyle(active ? Theme.onAccent : Theme.ink)
            .frame(width: size, height: size)
            .background(active ? Theme.accent : Theme.press, in: .rect(cornerRadius: Metric.radiusSm))
            .accessibilityHidden(true)
    }
}

// MARK: - 圖示（Heroicons 24 outline，和後台側欄同一套）

/// `HeroIcon("globe-alt")`＝Assets 裡的 hi-globe-alt
struct HeroIcon: View {
    let name: String
    var size: CGFloat = 20

    init(_ name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("hi-\(name)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - 狀態（只表示狀態；後台的 StatusBadge 色）

enum Tone: String, Hashable, Sendable {
    /// 品牌橘（強調、待處理的重點）
    case gold
    /// 成功、已完成
    case active
    case danger
    /// 警告、等待中
    case warning
    case info
    case neutral

    var foreground: Color {
        switch self {
        case .gold: Theme.accentText
        case .active: Theme.successFG
        case .danger: Theme.dangerFG
        case .warning: Theme.warningFG
        case .info: Theme.infoFG
        case .neutral: Theme.muted
        }
    }

    var dot: Color {
        switch self {
        case .gold: Theme.accent
        case .active: Theme.live
        default: foreground
        }
    }

    var background: Color {
        switch self {
        case .gold: Theme.accentSoft
        case .active: Theme.successFG.opacity(0.11)
        case .danger: Theme.dangerFG.opacity(0.11)
        case .warning: Theme.warningFG.opacity(0.13)
        case .info: Theme.infoFG.opacity(0.11)
        case .neutral: Theme.press
        }
    }

    /// Xena 卡片的 tone（ok / warn / bad / info / muted）
    init(card: String) {
        switch card {
        case "ok": self = .active
        case "warn": self = .warning
        case "bad": self = .danger
        case "info": self = .info
        default: self = .neutral
        }
    }
}

/// 狀態標籤：小圓點＋字、淡底、方角
struct StatusBadge: View {
    let text: String
    var tone: Tone = .neutral

    init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tone.dot).frame(width: 5, height: 5)
            Text(text)
        }
        .font(.brand(12, .medium, relativeTo: .caption))
        .foregroundStyle(tone.foreground)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tone.background, in: .rect(cornerRadius: Metric.chip))
    }
}

/// 在線的綠點（會呼吸）
struct LiveDot: View {
    var color: Color = Theme.live
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .background {
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(on ? 2.6 : 1)
                    .opacity(on ? 0 : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { on = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 卡片（.panel）與細線

/// 卡片：細框、圓角 8、上緣淡漸層與一條亮線（global.css 的 .panel）
struct Panel: ViewModifier {
    var padding: CGFloat = 20
    var radius: CGFloat = Metric.radius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(LinearGradient(stops: [.init(color: Theme.panelTop, location: 0), .init(color: Theme.surface, location: 0.6)], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                shape.strokeBorder(Theme.line, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                // 上緣的亮線（inset 1px）
                Rectangle()
                    .fill(Theme.panelHighlight)
                    .frame(height: 1)
                    .padding(.horizontal, radius)
                    .padding(.top, 1)
            }
    }
}

extension View {
    /// 一張卡片（列自己有內距的清單用 padding: 0）
    func panel(padding: CGFloat = 20, radius: CGFloat = Metric.radius) -> some View {
        modifier(Panel(padding: padding, radius: radius))
    }

    /// 頁面的底（--bg）
    func brandPage() -> some View {
        background(Theme.page.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            // 導覽容器（NavigationStack、iPad 分欄的每一欄）本身的底也是暖紙色：推頁、分欄之間不會露出系統的黑／白
            .containerBackground(Theme.page, for: .navigation)
    }

    /// iPad 的分欄（NavigationSplitView）整個的底：欄與欄之間、浮起來的側欄四周也是暖紙色
    func brandSplitView() -> some View {
        containerBackground(Theme.page, for: .navigationSplitView)
    }

    /// iPad 分欄的左欄（欄裡已經有大標：Your inbox、Orders）：導覽列整條拿掉——不再重複寫一次小標題，
    /// 收合鈕在這條導覽列上，也一起不見（上面的分頁列已經有側欄鈕）。
    /// 不用 toolbar(removing: .sidebarToggle)：它會讓 navigationSplitViewColumnWidth 失效，左欄變回系統預設的 320 點
    func splitListColumn() -> some View {
        toolbar(.hidden, for: .navigationBar)
    }

    /// 頁面內容的左右留白與最大寬度（iPad 上置中、不貼滿）
    func pageWidth(_ max: CGFloat = Metric.page) -> some View {
        modifier(PageWidth(maxWidth: max))
    }
}

struct PageWidth: ViewModifier {
    var maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, sizeClass == .regular ? Metric.gutterWide : Metric.gutter)
            .frame(maxWidth: .infinity)
    }
}

/// 一條細線（--line）
struct Rule: View {
    var color: Color = Theme.line
    var vertical = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? 1 / displayScale : nil, height: vertical ? nil : 1 / displayScale)
            .accessibilityHidden(true)
    }
}

/// 細線分隔的清單：每一列上面一條線、最後再一條（網站的服務、作品列表）
struct RuledList<Content: View>: View {
    var color: Color = Theme.line
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    Rule(color: color)
                    row
                }
            }
            Rule(color: color)
        }
    }
}

// MARK: - 區塊標題（SectionHead.astro）

/// 區塊標題：英文大字＋襯線強調詞，旁邊一句中文說明、右邊一個動作。
/// `SectionHead("Needs *you*", aside: "要你處理的事")`
struct SectionHead<Action: View>: View {
    let title: String
    var aside: String?
    var role: TextRole = .h2
    var action: Action

    @Environment(\.horizontalSizeClass) private var sizeClass

    init(_ title: String, aside: String? = nil, role: TextRole = .h2, @ViewBuilder action: () -> Action) {
        self.title = title
        self.aside = aside
        self.role = role
        self.action = action()
    }

    var body: some View {
        if sizeClass == .regular {
            HStack(alignment: .lastTextBaseline, spacing: 24) {
                Headline(title, role: role)
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 10) {
                    if let aside {
                        Text(aside)
                            .textRole(.small)
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 340, alignment: .trailing)
                    }
                    action
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Headline(title, role: role)
                if aside != nil || Action.self != EmptyView.self {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if let aside {
                            Text(aside)
                                .textRole(.small)
                                .foregroundStyle(Theme.ink2)
                        }
                        Spacer(minLength: 8)
                        action
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

extension SectionHead where Action == EmptyView {
    init(_ title: String, aside: String? = nil, role: TextRole = .h2) {
        self.title = title
        self.aside = aside
        self.role = role
        self.action = EmptyView()
    }
}

/// 「全部 →」那種小連結（.link-underline）
struct MoreLink: View {
    let title: String
    let action: () -> Void

    init(_ title: String = "全部", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) { MoreLinkLabel(title: title) }
            .buttonStyle(.press)
    }
}

/// 「全部 →」的樣子（NavigationLink 也用：在哪一疊頁面裡就往下推）
struct MoreLinkLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text("→")
        }
        .font(.brand(13.5, .medium, relativeTo: .subheadline))
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rule(color: Theme.ink) }
    }
}

/// 小標（欄位、分類；網站的小字原則：只放有用的資訊）
struct Eyebrow: View {
    let text: String
    var dot: Color? = Theme.accent

    init(_ text: String, dot: Color? = Theme.accent) {
        self.text = text
        self.dot = dot
    }

    var body: some View {
        HStack(spacing: 7) {
            if let dot {
                Rectangle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text)
                .textRole(.label)
                .foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - 數字

/// 數字跑上去（Stats 的 count-up；iOS 用數字滾動）。只在第一次出現、或數字變了的時候跑
struct CountUp: View {
    let value: Double
    var format: (Double) -> String = { String(Int($0.rounded())) }

    @State private var shown: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(format(shown ?? 0))
            .contentTransition(.numericText(value: shown ?? 0))
            .accessibilityLabel(format(value))
            .onAppear { go(to: value) }
            .onChange(of: value) { _, v in go(to: v) }
    }

    private func go(to v: Double) {
        if reduceMotion || shown == v {
            shown = v
            return
        }
        if shown == nil { shown = 0 }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(Motion.count) { shown = v }
        }
    }
}

/// 一格數字：大數字在上、說明在下（Stats.astro）
struct Stat: View {
    let value: Double
    let label: String
    var format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0))) }
    /// 放不下時的短寫法（金額：NT$1.3萬）；放得下照完整的寫
    var compact: ((Double) -> String)?
    /// 和前一期比（%）
    var change: Double?
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let compact {
                    // 完整的放得下就寫完整的；放不下寫短的（NT$1.3萬）；還放不下就用小一號的字（不會截成「NT$1…」）
                    ViewThatFits(in: .horizontal) {
                        CountUp(value: value, format: format)
                            .lineLimit(1)
                            .fixedSize()
                        CountUp(value: value, format: compact)
                            .lineLimit(1)
                            .fixedSize()
                        CountUp(value: value, format: compact)
                            .font(.brand(26, .medium).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                } else {
                    CountUp(value: value, format: format)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .textRole(.stat)
            .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Text(label)
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
                ChangeLabel(percent: change)
            }
            if let note {
                Text(note)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 細線隔開的數字（手機兩欄、iPad 四欄；格子之間是直線）
struct StatGrid<Content: View>: View {
    var columns: Int?
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let n = max(1, columns ?? (sizeClass == .regular ? 4 : 2))
        Group(subviews: content) { cells in
            let rows = stride(from: 0, to: cells.count, by: n).map { Array(cells[$0..<min($0 + n, cells.count)]) }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Rule()
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                            if i > 0 { Rule(vertical: true) }
                            cell
                                .padding(.vertical, 20)
                                .padding(.leading, i == 0 ? 0 : 16)
                                .padding(.trailing, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(row.count..<n, id: \.self) { _ in
                            Rule(vertical: true)
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Rule()
            }
        }
    }
}

/// 和前一期比：↑ 18% / ↓ 4%（伺服器給的是百分比）
struct ChangeLabel: View {
    let percent: Double?

    var body: some View {
        if let percent {
            let n = Int(percent.rounded())
            Text(n == 0 ? "持平" : n > 0 ? "↑ \(n)%" : "↓ \(abs(n))%")
                .font(.brand(12, .medium, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(n == 0 ? Theme.muted : n > 0 ? Theme.successFG : Theme.dangerFG)
                .accessibilityLabel(n == 0 ? "和前一期持平" : n > 0 ? "比前一期多 \(n)%" : "比前一期少 \(abs(n))%")
        }
    }
}

// MARK: - 輸入框（ContactForm：只有底線，焦點時變品牌橘）

/// 一個欄位：標籤、輸入、說明與字數
struct FieldBlock<Content: View>: View {
    let label: String
    var hint: String?
    var count: Int?
    var limit: Int?
    var required = false
    var error: String?
    var focused = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                if required {
                    Text("*").foregroundStyle(Theme.accent)
                }
            }
            .textRole(.small)
            .foregroundStyle(Theme.muted)

            content
                .padding(.bottom, 9)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(error != nil ? Theme.dangerFG : focused ? Theme.accent : Theme.line)
                        .frame(height: focused || error != nil ? 1.5 : 1)
                        .animation(Motion.fast, value: focused)
                }

            if hint != nil || limit != nil || error != nil {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let error {
                        Text(error).foregroundStyle(Theme.dangerFG)
                    } else if let hint {
                        Text(hint).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    if let limit, let count {
                        Text("\(count) / \(limit)")
                            .monospacedDigit()
                            .foregroundStyle(count > limit ? Theme.dangerFG : Theme.faint)
                    }
                }
                .textRole(.xs)
            }
        }
    }
}

/// 輸入框的字
extension View {
    func fieldText() -> some View {
        font(.brand(16.5, .regular, relativeTo: .body))
            .foregroundStyle(Theme.ink)
            .tint(Theme.primary)
    }
}

// MARK: - 空狀態、錯誤、載入中

struct EmptyState: View {
    var glyph = "✳"
    let title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(glyph)
                .font(.brand(22, .medium))
                .foregroundStyle(Theme.accent)
            Text(title)
                .textRole(.h4)
                .foregroundStyle(Theme.ink)
            if let message {
                Text(message)
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 28)
    }
}

/// 拿不到資料：說明＋重試
struct ErrorNote: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Theme.dangerFG).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(message)
                .textRole(.small)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("重試", action: retry)
                    .buttonStyle(.brand(.ghost, size: .sm))
            }
        }
        .padding(14)
        .overlay { RoundedRectangle(cornerRadius: Metric.radius).strokeBorder(Theme.dangerFG.opacity(0.28), lineWidth: 1) }
    }
}

/// 載入中：幾條會閃的灰條（不用轉圈圈）
struct SkeletonRows: View {
    var rows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                Rule()
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(Theme.press).frame(width: [180, 220, 150, 200][i % 4], height: 12)
                    Capsule().fill(Theme.press).frame(width: [110, 90, 130, 100][i % 4], height: 9)
                }
                .padding(.vertical, 18)
            }
            Rule()
        }
        .shimmer()
        .accessibilityLabel("載入中")
    }
}

struct LoadingRow: View {
    var text = "載入中…"

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text)
                .textRole(.small)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }
}

/// 閃一道光（載入中）
struct Shimmer: ViewModifier {
    @State private var x: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    let at = x
                    LinearGradient(colors: [.clear, Theme.page.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                        .visualEffect { c, proxy in c.offset(x: at * proxy.size.width) }
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { x = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - 網站圖示（console 網站選擇器：44px、圓角 14）

struct SiteIconView: View {
    let site: SiteSummary
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        ZStack {
            if let image = site.iconImage {
                if site.iconFill {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.surface
                    Image(uiImage: image).resizable().scaledToFit().padding(size * 0.18)
                }
            } else {
                Theme.surface
                Text(String(site.name.prefix(1)))
                    .font(.brand(size * 0.42, .medium))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - 小東西

/// 小折線（網站選擇器的 Spark）
nonisolated struct Sparkline: Shape {
    var values: [Double]
    /// 收成一塊面積（底下填色）
    var closed = false

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let top = max(values.max() ?? 1, 1)
        var p = Path()
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - 1 - (rect.height - 2) * CGFloat(v / top)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}

/// 折線＋淡淡的面積
struct SparkView: View {
    let values: [Double]
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Sparkline(values: values, closed: true)
                .fill(LinearGradient(colors: [color.opacity(0.18), color.opacity(0)], startPoint: .top, endPoint: .bottom))
            Sparkline(values: values)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// 頭像：圖片或名字的第一個字
struct Avatar: View {
    let name: String
    var imageURL: URL?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Theme.accentSoft)
            Text(String(name.prefix(1)).uppercased())
                .font(.brand(size * 0.42, .medium))
                .foregroundStyle(Theme.accentText)
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// 網路上的圖（商品、封面）：方角 8、細框，載入時是淡底
struct RemoteImage: View {
    let url: URL?
    var aspect: CGFloat? = 4 / 3
    var radius: CGFloat = Metric.radius
    var contentMode: ContentMode = .fill

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: Motion.ease)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                            .transition(.opacity)
                    case .failure:
                        Theme.pageAlt.overlay { Text("✳").font(.brand(18)).foregroundStyle(Theme.faint) }
                    default:
                        Theme.pageAlt.shimmer()
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Xena 說話：一個字一個字打出來。整句一開始就排好（還沒說到的字是透明的），
/// 置中、換行都不會跳，版面也不會一直長高。
/// 給了 voice：每個字讓水珠鼓一下，標點停一下（像換氣），說完 voice 就安靜下來
struct TypewriterText: View {
    let text: String
    var animate = true
    var speed: Duration = .milliseconds(26)
    /// 開始說之前等多久（例如等標題升起來）
    var delay: Duration = .zero
    var voice: XenaVoice?
    var onFinish: (() -> Void)?

    @State private var shown = 0

    var body: some View {
        Text(display)
            .accessibilityElement()
            .accessibilityLabel(text)
            .task(id: text) {
                guard animate else { return }
                shown = 0
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                    if Task.isCancelled { return }
                }
                // 換了一句話時，上一句被取消的收尾不會把這一句的聲音關掉
                let turn = voice?.begin()
                defer { if let turn { voice?.end(turn) } }
                for character in text {
                    try? await Task.sleep(for: speed + pause())
                    if Task.isCancelled { return }
                    shown += 1
                    voice?.say(character)
                }
                if let turn { voice?.end(turn) }
                onFinish?()
            }
    }

    private var display: AttributedString {
        let count = animate ? min(shown, text.count) : text.count
        var said = AttributedString(String(text.prefix(count)))
        var rest = AttributedString(String(text.dropFirst(count)))
        rest.foregroundColor = Color.clear
        said.append(rest)
        return said
    }

    /// 說話的節奏：逗號短停、句號長停（只有給了 voice 才停，一般的打字機照原本的速度）
    private func pause() -> Duration {
        guard voice != nil, shown > 0 else { return .zero }
        let previous = text[text.index(text.startIndex, offsetBy: shown - 1)]
        switch previous {
        case "，", "、", "；", "：", ",", ";": return .milliseconds(170)
        case "。", "！", "？", "…", ".", "!", "?", "\n": return .milliseconds(320)
        default: return .zero
        }
    }
}

/// Markdown（粗體、連結、程式碼；換行照原樣）
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}

