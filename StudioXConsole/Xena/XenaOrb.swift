import SwiftUI

/// Xena 現在在做什麼：決定水滴的速度（和網頁版一樣只有「靜靜呼吸」與「正在回答」兩種，中間平滑過渡）
enum XenaMood: Equatable {
    case idle
    /// 在等你（打字中、有確認卡片等你按）
    case listening
    /// 查資料、呼叫工具
    case thinking
    /// 回答中
    case speaking

    var energy: Double {
        switch self {
        case .idle: 0
        case .listening: 0.35
        case .thinking, .speaking: 1
        }
    }

    var label: String {
        switch self {
        case .idle: "值班中"
        case .listening: "在等你"
        case .thinking: "查資料中…"
        case .speaking: "回覆中…"
        }
    }
}

/// Xena 的玻璃水滴：和後台右下角那顆同一個樣子（atelier-cms 的 copilot/styles.ts 的 ORB_BALL_CSS）。
/// 五層圖（光暈、水珠、光核、邊緣的流光、玻璃的柔光）是直接從那份 CSS 畫出來的（Assets 的 Xena/），
/// 這裡只負責照網頁的節奏動：
///   靜靜呼吸：光暈與光核 3.8 秒一次、水珠 9 秒變形一輪、流光 14 秒轉一圈（很淡）
///   正在回答：光暈與光核 1.1 秒、水珠 2.4 秒、光核 2.2 秒轉一圈、流光 1.1 秒一圈（全亮）
/// 兩種之間用「能量」平滑過渡、相位累加，切換時不會跳。回答完、事情做完 pulse 加一：彈一下。
/// 出場像一滴水冒出來（從一個點長大、稍微超過再彈回）。減少動態時停住。
struct XenaOrb: View {
    var mood: XenaMood = .idle
    /// 水珠的直徑（光暈在外面，整個畫框是 1.7 倍）
    var size: CGFloat = 120
    var pulse: Int = 0

    @State private var motion = OrbMotion()
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: size < 48 ? 1.0 / 30 : nil, paused: reduceMotion)) { context in
            OrbLayers(frame: motion.step(context.date.timeIntervalSinceReferenceDate, energy: mood.energy), size: size)
        }
        .frame(width: size * OrbLayers.canvas, height: size * OrbLayers.canvas)
        .scaleEffect(entered || reduceMotion ? 1 : 0.01)
        .offset(y: entered || reduceMotion ? 0 : size * 0.12)
        .onAppear {
            guard !entered else { return }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.55)) { entered = true }
        }
        .onChange(of: pulse) { motion.pop() }
        .accessibilityElement()
        .accessibilityLabel("Xena，\(mood.label)")
    }
}

/// 一格要用的數值
struct OrbFrame {
    var haloScale: Double
    var haloOpacity: Double
    var morphX: Double
    var morphY: Double
    var glowScale: Double
    var glowOpacity: Double
    var swirl: Double
    var flow: Double
    var flowOpacity: Double
    var pop: Double
}

/// 能量平滑追目標，各動畫的相位用累加的（速度變了也不會跳）。不是 @Observable：只在每一格裡往前推
final class OrbMotion {
    private var last: TimeInterval?
    private var energy = 0.0
    private var halo = 0.0
    private var morph = Double.random(in: 0...1)
    private var swirl = Double.random(in: 0...(2 * .pi))
    private var flow = Double.random(in: 0...(2 * .pi))
    private var popAt: TimeInterval = -10

    func pop() {
        popAt = last ?? 0
    }

    func step(_ t: TimeInterval, energy target: Double) -> OrbFrame {
        let dt = min(max(t - (last ?? t), 0), 1.0 / 15)
        last = t
        energy += (target - energy) * (1 - exp(-dt * 3))
        let e = energy
        // 一輪幾秒（ease-in-out 的呼吸用 sin 近似）
        halo += dt / lerp(3.8, 1.1, e)
        morph += dt / lerp(9, 2.4, e)
        swirl += dt * 2 * .pi / lerp(18, 2.2, e)
        flow += dt * 2 * .pi / lerp(14, 1.1, e)

        let breathe = 0.5 - 0.5 * cos(halo * 2 * .pi)
        // cp-morph：0% (1,1) → 25% (1.015,.985) → 50% (.99,1.015) → 75% (1.01,.99)
        let m = morph * 2 * .pi
        let since = t - popAt
        let pop = since >= 0 && since < 1.2 ? sin(min(since / 0.3, 1) * .pi / 2) * exp(-since * 3.5) : 0
        return OrbFrame(
            haloScale: lerp(0.96, 1.04, breathe),
            haloOpacity: lerp(0.6, 1, breathe),
            morphX: 1 + 0.0125 * sin(m),
            morphY: 1 - 0.0125 * sin(m) + 0.0025 * sin(2 * m),
            glowScale: lerp(0.97, 1.02, breathe),
            glowOpacity: lerp(0.85, 1, breathe),
            swirl: swirl,
            flow: flow,
            flowOpacity: lerp(0.35, 1, e),
            pop: pop
        )
    }
}

private struct OrbLayers: View {
    /// 圖的畫布是水珠的幾倍大（光暈在 CSS 裡是 inset -32%，再留一點模糊的空間）
    static let canvas: CGFloat = 1.7

    let frame: OrbFrame
    let size: CGFloat

    var body: some View {
        let f = frame
        let bump = 1 + 0.08 * f.pop
        ZStack {
            layer("halo")
                .scaleEffect(f.haloScale)
                .opacity(f.haloOpacity)
            ZStack {
                layer("ball")
                layer("core")
                    .rotationEffect(.radians(f.swirl))
                    .scaleEffect(f.glowScale)
                    .opacity(f.glowOpacity)
                layer("flow")
                    .rotationEffect(.radians(f.flow))
                    .opacity(f.flowOpacity)
                    .blendMode(.screen)
                layer("glass")
            }
            .scaleEffect(x: f.morphX * bump, y: f.morphY * bump)
        }
        .frame(width: size * Self.canvas, height: size * Self.canvas)
    }

    private func layer(_ name: String) -> some View {
        Image("Xena/orb-\(name)")
            .resizable()
            .interpolation(.high)
            .frame(width: size * Self.canvas, height: size * Self.canvas)
    }
}

/// 小小的 Xena（對話裡的頭像、清單）：後台側欄的 OrbIcon（Assets 的 XenaOrb）
struct OrbIcon: View {
    var size: CGFloat = 20

    var body: some View {
        Image("XenaOrb")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            // 圖的畫布 100、水珠 76：放大到水珠剛好是 size
            .frame(width: size * 100 / 76, height: size * 100 / 76)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

nonisolated func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

#Preview {
    VStack(spacing: 24) {
        XenaOrb(mood: .idle, size: 132)
        HStack(spacing: 24) {
            XenaOrb(mood: .thinking, size: 64)
            OrbIcon(size: 28)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .admPage()
}
