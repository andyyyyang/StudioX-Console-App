import SwiftUI
import UIKit

/// StudioX 後台配色標準（atelier-cms 的 src/app/admin/_ui/theme.ts，所有後台共用一份）。
/// 這裡的色碼一對一照抄那份檔案的「角色變數」；亮色、暗色各自選色，跟著裝置設定切換。
/// 規則和網頁一樣：主色是品牌橘、只用在主要動作與選取；其他一律中性灰；狀態色只表示狀態、一定配文字或圖示。
enum Theme {
    // MARK: 主色（橘）

    /// --adm-primary：主要按鈕的底、開關打開、勾選、選取中
    static let primary = Color(light: 0xCB3E01, dark: 0xFF6A33)
    /// --adm-primary-hover：按住
    static let primaryPressed = Color(light: 0x9F2E00, dark: 0xFF8250)
    /// --adm-on-primary：主要按鈕上的字
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x18181B)
    /// --adm-accent：強調的文字與圖示、使用中的標籤
    static let accent = Color(light: 0xB83700, dark: 0xFF8250)
    /// --adm-accent-soft：選取中的列、強調卡片的淡底
    static let accentSoft = Color(light: .rgb(0xFEF7F4), dark: .rgba(255, 106, 51, 0.14))
    /// --adm-focus：焦點框
    static let focus = Color(light: .rgba(255, 90, 31, 0.4), dark: .rgba(255, 130, 80, 0.45))

    // MARK: 文字與底

    /// --color-ink：主要文字
    static let ink = Color(light: 0x18181B, dark: 0xEDEDEF)
    /// --color-ink-muted：次要文字
    static let inkMuted = Color(light: 0x71717A, dark: 0xA1A1AA)
    /// --adm-icon：一般圖示
    static let icon = Color(light: 0x52525B, dark: 0xA1A1AA)
    /// --adm-faint：最淡的提示（不放重要資訊）
    static let faint = Color(light: 0xA1A1AA, dark: 0x71717A)
    /// --adm-on-ink：深色底上的字
    static let onInk = Color(light: 0xFFFFFF, dark: 0x18181B)
    /// --adm-surface：卡片、輸入框、表格
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C1F)
    /// --color-surface-soft：稍深的底
    static let surfaceSoft = Color(light: 0xF4F4F5, dark: 0x1F1F23)
    /// --color-surface-elevated：浮起來的底
    static let surfaceElevated = Color(light: 0xFFFFFF, dark: 0x232327)
    /// --page-bg：最底層（暖灰）
    static let page = Color(light: 0xEBE8E5, dark: 0x0C0C0E)
    /// --adm-sheet-bg：底部面板（實心）
    static let sheet = Color(light: 0xFAFAFA, dark: 0x1E1E21)

    // MARK: 表面

    /// --adm-hair：細線、分隔線
    static let hair = Color(light: .rgba(0, 0, 0, 0.06), dark: .rgba(255, 255, 255, 0.08))
    /// 輸入框的框（tokens.border.field：ink 12%）
    static let fieldBorder = Color(light: .rgba(24, 24, 27, 0.12), dark: .rgba(237, 237, 239, 0.12))
    /// --adm-btn2-border：次要按鈕的框
    static let secondaryBorder = Color(light: .rgba(0, 0, 0, 0.10), dark: .rgba(255, 255, 255, 0.10))
    /// --adm-highlight：表面頂端的亮邊
    static let highlight = Color(light: .rgba(255, 255, 255, 0.9), dark: .rgba(255, 255, 255, 0.07))
    /// --adm-hover：按下的底
    static let hover = Color(light: .rgba(0, 0, 0, 0.04), dark: .rgba(255, 255, 255, 0.05))
    /// Xena 對話裡的淡底（copilot 的 --cp-soft）
    static let soft = Color(light: .rgba(0, 0, 0, 0.045), dark: .rgba(255, 255, 255, 0.06))
    /// Xena 對話裡的線（--cp-line）
    static let line = Color(light: .rgba(0, 0, 0, 0.08), dark: .rgba(255, 255, 255, 0.09))

    // MARK: 狀態（只表示狀態，配文字或圖示）

    static let successFG = Color(light: 0x166534, dark: 0x4ADE80)
    static let warningFG = Color(light: 0x854D0E, dark: 0xFACC15)
    static let dangerFG = Color(light: 0xBE123C, dark: 0xFB7185)
    static let infoFG = Color(light: 0x1D4ED8, dark: 0x60A5FA)

    // MARK: 圖表（資料標記，順序固定、跟著「東西」走）

    static let chart: [Color] = [
        Color(light: 0xE64700, dark: 0xE64700),
        Color(light: 0x2A78D6, dark: 0x3987E5),
        Color(light: 0x1BAF7A, dark: 0x199E70),
        Color(light: 0x4A3AA7, dark: 0x9085E9),
        Color(light: 0xEDA100, dark: 0xC98500),
    ]

    // MARK: 品牌（對外頁面：登入、歡迎頁；AuthScreen.tsx）

    /// 品牌橘（Logo 的摺角）
    static let brandOrange = Color(hex: 0xFF5A1F)
    /// 對外頁面的底（--bg）
    static let paper = Color(light: 0xF2F0EB, dark: 0x0D0D0C)
    /// 對外頁面的字（--ink）
    static let paperInk = Color(light: 0x0F0F0E, dark: 0xF2F0EB)
}

/// 尺寸（tokens.ts）：圓角、間距。手機版的卡片圓角是 14（mobile-css.ts）
enum Metric {
    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 8
    static let radiusLg: CGFloat = 10
    static let radiusXl: CGFloat = 12
    /// 手機的卡片
    static let card: CGFloat = 14
    /// Xena 的卡片（.cp-card）
    static let xenaCard: CGFloat = 16
    /// 頁面左右留白（手機版 --admin-pad）
    static let gutter: CGFloat = 16
}

extension Font {
    /// 頁首標題（tokens.text.h1：22 / 650 / -0.015em）
    static let admTitle = Font.system(.title2, weight: .semibold)
    /// 段落標題（h2：16 / 650）
    static let admSection = Font.system(.callout, weight: .semibold)
    /// 卡片標題
    static let admCardTitle = Font.system(.subheadline, weight: .semibold)
    /// 內文（後台的字重是 500–650）
    static let admBody = Font.system(.subheadline, weight: .medium)
    /// 說明、時間
    static let admMeta = Font.system(.footnote, weight: .medium)
    /// 欄位標籤（tokens.text.label：11 / 600 / 0.04em / 大寫）
    static let admLabel = Font.system(.caption2, weight: .semibold)
    /// 數字（等寬）
    static let admNumber = Font.system(.title3, weight: .semibold).monospacedDigit()
}

// MARK: - 顏色的寫法

/// 亮色或暗色的一個值：#rrggbb 或 rgba()
nonisolated struct RGBA: Sendable {
    var r: Double, g: Double, b: Double, a: Double

    nonisolated static func rgb(_ hex: UInt32) -> RGBA {
        RGBA(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255, a: 1)
    }

    nonisolated static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> RGBA {
        RGBA(r: r / 255, g: g / 255, b: b / 255, a: a)
    }

    nonisolated var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
}

extension Color {
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        let c = RGBA.rgb(hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: opacity)
    }

    /// 亮色、暗色各一個色碼
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(light: .rgb(light), dark: .rgb(dark))
    }

    nonisolated init(light: RGBA, dark: RGBA) {
        let l = light.uiColor, d = dark.uiColor
        self.init(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? d : l })
    }
}

extension Date {
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private static let dayTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    /// 15:40
    var clockText: String { Self.clock.string(from: self) }
    /// 今天的只寫時間，其他寫日期＋時間
    var shortText: String { Calendar.current.isDateInToday(self) ? Self.clock.string(from: self) : Self.monthDay.string(from: self) }
    /// 10月2日 星期五
    var dayTitle: String { Self.dayTitle.string(from: self) }
}
