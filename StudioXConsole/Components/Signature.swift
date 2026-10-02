import SwiftUI

// studiox.tw 的招牌元件，原生的版本：跑馬燈、點陣底紋、柔光、裁切記號、超大字標、載入動畫、閱讀進度。

// MARK: - 跑馬燈（Marquee.astro：反白的帶、一般字與襯線斜體交錯、橘色 ✳ 隔開、慢慢往左跑）

struct Marquee: View {
    struct Item: Hashable {
        var text: String
        /// 襯線斜體
        var serif = false
    }

    let items: [Item]
    /// 每秒跑幾點（網站一圈 42 秒）
    var speed: Double = 34

    @State private var stripWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let size: CGFloat = sizeClass == .regular ? 40 : 24
        TimelineView(.animation(paused: reduceMotion || stripWidth == 0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let loop = stripWidth > 0 ? stripWidth / speed : 1
            let x = stripWidth > 0 ? -CGFloat(t.truncatingRemainder(dividingBy: loop) / loop) * stripWidth : 0
            HStack(spacing: 0) {
                strip(size: size)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
                strip(size: size)
            }
            .offset(x: x)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, sizeClass == .regular ? 26 : 18)
        .clipped()
        .background(Theme.inverse)
        .accessibilityElement()
        .accessibilityLabel(items.map(\.text).joined(separator: "，"))
    }

    private func strip(size: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item.text)
                    .font(item.serif ? .serif(size * 1.06, italic: true) : .brand(size, .medium))
                    .tracking(item.serif ? 0 : -0.03 * size)
                    .foregroundStyle(Theme.onInverse)
                Text("✳")
                    .font(.brand(size * 0.6, .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, size * 0.7)
            }
        }
        .fixedSize()
        .lineLimit(1)
    }
}

// MARK: - 點陣底紋（PageHeroFull：28px 一點、往外淡掉）

struct DotGrid: View {
    var spacing: CGFloat = 28
    var opacity: Double = 0.22
    /// 從中間往外淡掉
    var fade = true

    var body: some View {
        let step = spacing
        let ink = Theme.ink.opacity(opacity)
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: -0.7, y: -0.7, width: 1.4, height: 1.4))
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(ink))
                    x += step
                }
                y += step
            }
        }
        .mask {
            if fade {
                RadialGradient(colors: [.black, .black.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 420)
            } else {
                Color.black
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 柔光（Hero 的兩團光：品牌橘＋紫，14 秒慢慢飄）

struct Glow: View {
    var size: CGFloat = 320
    @State private var drift = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.22))
                .frame(width: size, height: size)
                .blur(radius: size * 0.2)
                .offset(x: drift ? size * 0.2 : -size * 0.12, y: drift ? -size * 0.1 : size * 0.06)
            Circle()
                .fill(Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255).opacity(0.16))
                .frame(width: size * 0.95, height: size * 0.95)
                .blur(radius: size * 0.2)
                .offset(x: drift ? -size * 0.22 : size * 0.16, y: drift ? size * 0.12 : -size * 0.04)
        }
        .opacity(colorScheme == .dark ? 0.9 : 0.45)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

// MARK: - 裁切記號（PageHeroFull 四個角的 +）

struct CropMarks: View {
    var inset: CGFloat = 12
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            mark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            mark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            mark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            mark.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .padding(inset)
        .opacity(0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var mark: some View {
        ZStack {
            Rectangle().fill(Theme.ink).frame(width: size, height: 1)
            Rectangle().fill(Theme.ink).frame(width: 1, height: size)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 超大字標（頁尾的 studiox.：貼滿寬度、字距 −0.065em、橘色的點）

struct Wordmark: View {
    var text = "studiox"
    var color: Color = Theme.ink

    var body: some View {
        Text("\(Text(text).foregroundStyle(color))\(Text(".").foregroundStyle(Theme.accent))")
            .font(.brand(400, .semibold))
            .tracking(-0.065 * 400)
            .lineLimit(1)
            .minimumScaleFactor(0.02)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("studiox")
    }
}

// MARK: - 載入動畫（Loader.astro：兩塊標誌轉 180° 卡上去、字一個一個升起、000→100、橘色的條）

struct BrandLoader: View {
    var caption: String?

    @State private var assembled = false
    @State private var letters = 0
    @State private var progress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let word = Array("studiox")

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            HStack(alignment: .bottom, spacing: 18) {
                ZStack {
                    MarkPiece(points: MarkPiece.triangle)
                        .fill(Theme.ink)
                        .rotationEffect(.degrees(assembled ? 0 : -180))
                        .offset(x: assembled ? 0 : -10, y: assembled ? 0 : -10)
                    MarkPiece(points: MarkPiece.inkHalf)
                        .fill(Theme.ink)
                        .rotationEffect(.degrees(assembled ? 0 : 180))
                        .offset(x: assembled ? 0 : 12, y: assembled ? 0 : 12)
                    MarkPiece(points: MarkPiece.accentHalf)
                        .fill(Theme.accent)
                        .rotationEffect(.degrees(assembled ? 0 : 180))
                        .offset(x: assembled ? 0 : 12, y: assembled ? 0 : 12)
                }
                .frame(width: 64, height: 64)

                HStack(spacing: 0) {
                    ForEach(Array(word.enumerated()), id: \.offset) { i, ch in
                        let up = i < letters
                        Text(String(ch))
                            .visualEffect { content, proxy in content.offset(y: up ? 0 : proxy.size.height) }
                            .opacity(up ? 1 : 0)
                            .animation(Motion.ease, value: up)
                    }
                    Text(".")
                        .foregroundStyle(Theme.accent)
                        .opacity(letters >= word.count ? 1 : 0)
                        .animation(Motion.ease, value: letters)
                }
                .font(.brand(56, .semibold, relativeTo: .largeTitle))
                .tracking(-0.06 * 56)
                .foregroundStyle(Theme.ink)
                .mask(Rectangle().padding(.vertical, -4))
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(caption ?? "")
                        .textRole(.small)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    CountUp(value: progress, format: { String(format: "%03d", Int($0)) })
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * progress / 100, height: 3)
                }
                .frame(height: 3)
                .background(Theme.hair)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.page.ignoresSafeArea())
        .accessibilityElement()
        .accessibilityLabel(caption ?? "載入中")
        .task {
            if reduceMotion {
                assembled = true
                letters = word.count
                progress = 100
                return
            }
            withAnimation(Motion.snap) { assembled = true }
            withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 1.8)) { progress = 100 }
            try? await Task.sleep(for: .milliseconds(550))
            for i in 1...word.count {
                letters = i
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }
}

// MARK: - 閱讀進度（文章頁上緣 2px 的橘線）

struct ReadingProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Theme.accent)
                .frame(width: geo.size.width * min(max(progress, 0), 1))
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
