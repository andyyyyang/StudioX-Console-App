import SwiftUI
import UIKit

// 後台的元件（atelier-cms 的 src/app/admin/_ui/）：按鈕、狀態標籤、卡片、欄位、空狀態。
// 顏色一律用 Theme 的角色變數，不在頁面裡寫色碼。

// MARK: - 按鈕（button-style.ts：後台唯一的按鈕規格）

/// 主要（橘色實心）、次要（白色玻璃＋細框）、透明、危險（紅字淡底）
struct AdmButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, ghost, danger }
    /// sm 28／md 32／lg 40；手機上主要動作用 touch（44，手指好按）
    enum Size { case sm, md, lg, touch }

    var variant: Variant = .primary
    var size: Size = .touch
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    private var height: CGFloat {
        switch size {
        case .sm: 28
        case .md: 32
        case .lg: 40
        case .touch: 44
        }
    }
    private var radius: CGFloat { size == .sm ? Metric.radiusSm : Metric.radiusMd }
    private var font: Font {
        switch size {
        case .sm: .system(size: 12, weight: .semibold)
        case .md: .system(size: 13, weight: .semibold)
        case .lg: .system(size: 14, weight: .semibold)
        case .touch: .system(.subheadline, weight: .semibold)
        }
    }
    private var padding: CGFloat {
        switch size {
        case .sm: 10
        case .md: 12
        case .lg, .touch: 16
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(font)
            .lineLimit(1)
            .labelStyle(AdmLabelStyle(gap: size == .sm ? 6 : 8))
            .padding(.horizontal, padding)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .foregroundStyle(foreground(pressed: configuration.isPressed))
            .background { background(shape: shape, pressed: configuration.isPressed) }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            // 按下微縮、放開帶一點回彈（.admin-btn）
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: configuration.isPressed)
    }

    private func foreground(pressed: Bool) -> Color {
        switch variant {
        case .primary: Theme.onPrimary
        case .secondary, .ghost: Theme.ink
        case .danger: Theme.dangerFG
        }
    }

    @ViewBuilder
    private func background(shape: RoundedRectangle, pressed: Bool) -> some View {
        switch variant {
        case .primary:
            shape.fill(pressed ? Theme.primaryPressed : Theme.primary)
                .overlay(shape.inset(by: 0.5).stroke(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                .shadow(color: Theme.primary.opacity(0.35), radius: 1, y: 1)
        case .secondary:
            shape.fill(Theme.surface.opacity(pressed ? 0.7 : 0.9))
                .overlay(shape.strokeBorder(Theme.secondaryBorder, lineWidth: 1))
                .overlay(shape.inset(by: 1).stroke(LinearGradient(colors: [Theme.highlight, .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
        case .ghost:
            shape.fill(pressed ? Theme.hover : .clear)
        case .danger:
            shape.fill(Theme.dangerFG.opacity(pressed ? 0.14 : 0.09))
                .overlay(shape.strokeBorder(Theme.dangerFG.opacity(0.18), lineWidth: 1))
        }
    }
}

extension ButtonStyle where Self == AdmButtonStyle {
    static func adm(_ variant: AdmButtonStyle.Variant = .primary, size: AdmButtonStyle.Size = .touch, fullWidth: Bool = false) -> AdmButtonStyle {
        AdmButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

/// 圖示＋字的間距（按鈕裡的 Label）
struct AdmLabelStyle: LabelStyle {
    var gap: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: gap) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - 圖示（後台用的 Heroicons，24 outline，template）

/// `HeroIcon("globe-alt")` ＝ Assets 裡的 hi-globe-alt（和後台側欄同一套圖示）
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

// MARK: - 狀態標籤（StatusBadge.tsx）

enum Tone: String, Hashable, Sendable {
    /// 主色（強調、推薦、使用中）
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
        case .gold: Theme.accent
        case .active: Theme.successFG
        case .danger: Theme.dangerFG
        case .warning: Theme.warningFG
        case .info: Theme.infoFG
        case .neutral: Theme.ink.opacity(0.55)
        }
    }

    var background: Color {
        switch self {
        case .gold: Theme.accent.opacity(0.14)
        case .active: Theme.successFG.opacity(0.14)
        case .danger: Theme.dangerFG.opacity(0.14)
        case .warning: Theme.warningFG.opacity(0.16)
        case .info: Theme.infoFG.opacity(0.14)
        case .neutral: Theme.ink.opacity(0.08)
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

struct StatusBadge: View {
    let text: String
    var tone: Tone = .neutral

    init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.22)
            .lineLimit(1)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(tone.background, in: .capsule)
    }
}

// MARK: - 卡片（手機版：實心、細框、沒有陰影；mobile-css.ts）

struct AdmCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Metric.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.card, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    /// 一張卡片（列自己有內距的清單用 padding: 0）
    func admCard(padding: CGFloat = 16) -> some View {
        modifier(AdmCard(padding: padding))
    }

    /// 頁面底色（--page-bg）
    func admPage() -> some View {
        background(Theme.page.ignoresSafeArea())
    }
}

/// 欄位標籤（tokens.text.label：11 / 600 / 0.04em / 大寫、次要色）
struct FieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.admLabel)
            .tracking(0.44)
            .foregroundStyle(Theme.inkMuted)
    }
}

/// 段落標題：左邊標題、右邊一句說明或按鈕
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.admSection)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            trailing
                .font(.admMeta)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// 頁面的大標題（頁首 h1：22 / 650）
struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.admTitle)
                .tracking(-0.33)
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.admMeta)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - 輸入框（styles.input：細框、圓角 8、焦點是橘色的框）

struct AdmField: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .font(.system(.body, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.surface.opacity(0.8), in: .rect(cornerRadius: Metric.radiusMd, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.radiusMd, style: .continuous)
                    .strokeBorder(focused ? Theme.primary : Theme.fieldBorder, lineWidth: 1)
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: Metric.radiusMd + 3, style: .continuous)
                        .stroke(Theme.focus, lineWidth: 3)
                        .padding(-3)
                }
            }
    }
}

extension View {
    func admField(focused: Bool = false) -> some View {
        modifier(AdmField(focused: focused))
    }
}

// MARK: - 空狀態、錯誤、載入中（EmptyState.tsx、Spinner.tsx）

struct EmptyState: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            HeroIcon(icon, size: 28)
                .foregroundStyle(Theme.faint)
            Text(title)
                .font(.admCardTitle)
                .foregroundStyle(Theme.ink)
            if let message {
                Text(message)
                    .font(.admMeta)
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }
}

/// 拿不到資料：說明＋重試
struct ErrorNote: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HeroIcon("exclamation-circle", size: 18)
                .foregroundStyle(Theme.dangerFG)
            Text(message)
                .font(.admMeta)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("重試", action: retry)
                    .buttonStyle(.adm(.secondary, size: .sm))
            }
        }
        .padding(12)
        .background(Theme.dangerFG.opacity(0.08), in: .rect(cornerRadius: Metric.radiusLg, style: .continuous))
    }
}

struct LoadingRow: View {
    var text = "載入中…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.admMeta)
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - 網站圖示（console 網站選擇器的 .au-site-icon）

struct SiteIconView: View {
    let site: SiteSummary
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        ZStack {
            if let image = site.iconImage {
                if site.iconFill {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.surfaceSoft
                    Image(uiImage: image).resizable().scaledToFit().padding(size * 0.18)
                }
            } else {
                Theme.surfaceSoft
                Text(String(site.name.prefix(1)))
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

// MARK: - 小東西

/// 最近 7 天的小折線（網站選擇器的 Spark）
nonisolated struct Sparkline: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let top = max(values.max() ?? 1, 1)
        var p = Path()
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - 1 - (rect.height - 2) * CGFloat(v / top)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

/// 和前一期比：+18% / −4%（伺服器給的是百分比）
struct ChangeLabel: View {
    let percent: Double?

    var body: some View {
        if let percent {
            let n = Int(percent.rounded())
            Text(n >= 0 ? "+\(n)%" : "−\(abs(n))%")
                .font(.system(.caption, weight: .semibold).monospacedDigit())
                .foregroundStyle(n >= 0 ? Theme.successFG : Theme.dangerFG)
        }
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
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Theme.accent)
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

/// Xena 說話：一個字一個字打出來（版面一開始就用整句的大小，不會一直長高）
struct TypewriterText: View {
    let text: String
    var animate = true
    var speed: Duration = .milliseconds(28)
    var onFinish: (() -> Void)?

    @State private var shown = 0

    var body: some View {
        Text(text)
            .opacity(0)
            .overlay(alignment: .topLeading) {
                Text(String(text.prefix(animate ? shown : text.count)))
            }
            .accessibilityElement()
            .accessibilityLabel(text)
            .task(id: text) {
                guard animate else { return }
                shown = 0
                let total = text.count
                while shown < total {
                    try? await Task.sleep(for: speed)
                    if Task.isCancelled { return }
                    shown += 1
                }
                onFinish?()
            }
    }
}

/// Markdown（粗體、連結、程式碼；換行照原樣）
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
