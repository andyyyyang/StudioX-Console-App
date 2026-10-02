import SwiftUI

/// 膠囊按鈕（登入畫面的 .au-btn）：深色＝主要動作、玻璃＝次要、紅＝危險
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case dark, light, danger
    }

    var kind: Kind
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 15 : 17, weight: .semibold))
            .tracking(-0.2)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 56)
            .padding(.horizontal, compact ? 14 : 18)
            .foregroundStyle(kind == .light ? Brand.ink : (kind == .danger ? Color.white : Brand.onInk))
            .background {
                switch kind {
                case .dark: Capsule().fill(Brand.ink)
                case .danger: Capsule().fill(Brand.danger)
                case .light: Color.clear.glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillButtonStyle.Kind, compact: Bool = false) -> PillButtonStyle {
        PillButtonStyle(kind: kind, compact: compact)
    }
}

/// 輸入框（登入畫面的 .au-field input）
struct FieldChrome: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .background(Brand.raised.opacity(0.75), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(focused ? Brand.ink.opacity(0.6) : Brand.line, lineWidth: 1)
            }
    }
}

extension View {
    func fieldChrome(focused: Bool = false) -> some View {
        modifier(FieldChrome(focused: focused))
    }

    /// 浮起來的卡片（.au-site）
    func raisedCard(cornerRadius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Brand.raised, in: .rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
    }
}

/// 狀態小膠囊（已付款、等你回覆…）
struct StatusPill: View {
    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.color.opacity(0.12), in: .capsule)
    }
}

/// 網站的圖示：StudioX 用標誌，其他用一個字
struct SiteIcon: View {
    let site: Site
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32)
                .fill(site.tint.opacity(0.18))
            switch site.icon {
            case .mark:
                BrandMark()
                    .foregroundStyle(Brand.ink)
                    .padding(size * 0.2)
            case .letter(let letter):
                Text(letter)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Brand.ink)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 小小的網站名牌
struct SiteChip: View {
    let site: Site

    var body: some View {
        HStack(spacing: 5) {
            SiteIcon(site: site, size: 16)
            Text(site.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(Brand.muted)
        }
    }
}

/// 走勢小線
nonisolated struct Sparkline: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return Path() }
        let span = max(hi - lo, 1)
        var p = Path()
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat((v - lo) / span)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

/// +18% / −4%
struct ChangeLabel: View {
    let change: Double?

    var body: some View {
        if let change {
            Text(percentChange(change))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(change >= 0 ? Brand.success : Brand.danger)
        }
    }
}

/// Xena 說話：一個字一個字打出來（版面一開始就用整句的大小，不會一直長高）
struct TypewriterText: View {
    let text: String
    var animate = true
    var speed: Duration = .milliseconds(32)
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

/// 段落標題
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
            }
        }
    }
}

/// 頭像（名字的第一個字）
struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 40
    var tint: Color = Brand.accent

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .circle)
            .accessibilityHidden(true)
    }
}

/// Markdown（粗體、連結；換行照原樣）
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
