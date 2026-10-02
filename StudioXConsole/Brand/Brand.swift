import SwiftUI
import UIKit

/// StudioX 的品牌色：和 atelier-cms 登入畫面（src/app/_components/auth/AuthScreen.tsx）的 CSS 變數一致，深淺色跟著系統
enum Brand {
    /// 品牌橘（--accent）
    static let accent = Color(hex: 0xFF5A1F)
    /// 底色（--bg）
    static let paper = Color(light: 0xF2F0EB, dark: 0x0D0D0C)
    /// 面板、卡片（--sheet）
    static let sheet = Color(light: 0xFAF9F6, dark: 0x151513)
    /// 主要文字（--ink）
    static let ink = Color(light: 0x0F0F0E, dark: 0xF2F0EB)
    /// 深色按鈕上的字（--btn-dark-ink）
    static let onInk = Color(light: 0xFFFFFF, dark: 0x0F0F0E)
    /// 次要文字（--muted）
    static let muted = Color(light: 0x77746D, dark: 0x8F8C85)
    /// 分隔線（--line）
    static let line = Color(light: 0x0F0F0E, dark: 0xF2F0EB, opacity: 0.1)
    /// 白色按鈕、浮起來的卡片（--btn-light）
    static let raised = Color(light: 0xFFFFFF, dark: 0x232320)
    /// 錯誤（--danger）
    static let danger = Color(light: 0xC2410C, dark: 0xFB923C)
    static let success = Color(light: 0x15803D, dark: 0x4ADE80)
}

/// Xena 水滴裡的四團光：和 orb3d.ts 光核的顏色相同
enum XenaPalette {
    static let pink = Color(red: 1, green: 0.42, blue: 0.82)
    static let cyan = Color(red: 0.25, green: 0.8, blue: 1)
    static let amber = Color(red: 1, green: 0.6, blue: 0.25)
    static let violet = Color(red: 0.52, green: 0.36, blue: 1)
}

extension UIColor {
    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// 深淺色各一個值
    nonisolated init(light: UInt32, dark: UInt32, opacity: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light, alpha: opacity)
        })
    }
}

nonisolated func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

extension Date {
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"
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
    /// 10月2日 星期五
    var dayTitle: String { Self.dayTitle.string(from: self) }
}

extension Int {
    /// NT$8,460
    var ntd: String { "NT$" + formatted(.number) }
}
