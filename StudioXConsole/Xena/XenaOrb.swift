import SwiftUI

/// Xena 現在的狀態：決定水滴的能量（變形、旋轉、流光、呼吸的速度與幅度）
enum XenaMood: Equatable {
    /// 值班中：靜靜呼吸
    case idle
    /// 在聽你說（打字中、等你確認）
    case listening
    /// 查資料、呼叫工具
    case thinking
    /// 正在回答
    case speaking
    /// 有事要跟你說：光核偏暖
    case alert
    /// 夜班：暗一點、慢一點，還是醒著
    case resting

    var energy: Double {
        switch self {
        case .idle: 0.08
        case .listening: 0.35
        case .thinking: 0.75
        case .speaking: 1
        case .alert: 0.4
        case .resting: 0
        }
    }

    var label: String {
        switch self {
        case .idle: "值班中"
        case .listening: "在聽你說"
        case .thinking: "查資料中…"
        case .speaking: "回覆中…"
        case .alert: "有事想跟你說"
        case .resting: "夜班中"
        }
    }
}

/// Xena 的玻璃水滴（和網頁版同一顆：atelier-cms 的 copilot/orb3d.ts、orb-motion.ts）
///   - 中間一團會發光、會旋轉的彩色光核（粉、青、琥珀、紫四團光）
///   - 左上一扇柔和的窗光、清透的玻璃邊緣（iOS 的 Liquid Glass，會折射後面的畫面）
///   - 底下一圈會呼吸的淡淡光暈；回答時晃得大一點、轉得快一點，回答完「彈」一下（pulse 加一）
struct XenaOrb: View {
    var mood: XenaMood = .idle
    var size: CGFloat = 120
    /// 每加一次就彈一下（回答結束、事情做完）
    var pulse: Int = 0

    @State private var motion = OrbMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: size < 60 ? 1.0 / 30 : nil, paused: reduceMotion)) { context in
            let frame = motion.step(context.date.timeIntervalSinceReferenceDate, mood: mood)
            OrbLayers(frame: frame, size: size, dark: scheme == .dark, glass: !reduceTransparency)
        }
        .frame(width: size * 1.36, height: size * 1.36)
        .onChange(of: pulse) { motion.pop() }
        .accessibilityElement()
        .accessibilityLabel("Xena，\(mood.label)")
    }
}

/// 一格畫面要用的數值
struct OrbFrame {
    var energy: Double
    var swirl: Double
    var morph: Double
    var flow: Double
    var breath: Double
    var pop: Double
    /// 0～1：有事要說時光核偏暖
    var warmth: Double
    /// 0～1：夜班時暗一點
    var rest: Double
}

/// 動態：能量平滑地追向目標值，各種相位用累加的（從回答切回靜止時是慢慢減速，不會跳回原位）。
/// 不是 @Observable：只在畫面每一格裡往前推，不觸發重畫
final class OrbMotion {
    private var last: TimeInterval?
    private var energy = 0.08
    private var warmth = 0.0
    private var rest = 0.0
    private var swirl = Double.random(in: 0...6)
    private var morph = Double.random(in: 0...100)
    private var flow = 0.0
    private var breath = 0.0
    private var popAt: TimeInterval = -10

    func pop() {
        popAt = last ?? 0
    }

    func step(_ t: TimeInterval, mood: XenaMood) -> OrbFrame {
        let dt = min(max(t - (last ?? t), 0), 1.0 / 15)
        last = t
        let k = 1 - exp(-dt * 3.2)
        let warmTarget: Double = mood == .alert ? 1 : 0
        let restTarget: Double = mood == .resting ? 1 : 0
        energy += (mood.energy - energy) * k
        warmth += (warmTarget - warmth) * k
        rest += (restTarget - rest) * k
        swirl += dt * lerp(0.35, 2.6, energy)
        morph += dt * lerp(0.45, 1.5, energy)
        flow += dt * lerp(0.5, 3.8, energy)
        breath += dt * lerp(1.05, 2.1, energy) * (1 - 0.45 * rest)
        let since = t - popAt
        let pop = since >= 0 && since < 1.2 ? sin(min(since / 0.35, 1) * .pi / 2) * exp(-since * 3.2) : 0
        return OrbFrame(energy: energy, swirl: swirl, morph: morph, flow: flow, breath: breath, pop: pop, warmth: warmth, rest: rest)
    }
}

private struct OrbLayers: View {
    let frame: OrbFrame
    let size: CGFloat
    let dark: Bool
    let glass: Bool

    var body: some View {
        let f = frame
        let wobble = lerp(0.012, 0.035, f.energy)
        let sx = 1 + wobble * sin(f.morph * 0.71) + 0.07 * f.pop
        let sy = 1 + wobble * cos(f.morph * 0.53) + 0.07 * f.pop
        let breathe = 0.5 + 0.5 * sin(f.breath)
        ZStack {
            halo(breathe)
            ball
                .scaleEffect(x: sx, y: sy)
        }
    }

    /// 底下一圈會呼吸的光暈：邊緣帶顏色、中間是空的
    private func halo(_ breathe: Double) -> some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [XenaPalette.pink, XenaPalette.violet, XenaPalette.cyan, XenaPalette.amber, XenaPalette.pink],
                    center: .center,
                    angle: .radians(frame.flow * 0.6)
                ),
                lineWidth: size * 0.16
            )
            .frame(width: size * 1.02, height: size * 1.02)
            .blur(radius: size * 0.11)
            .opacity((0.26 + 0.2 * breathe) * (1 - 0.5 * frame.rest) + 0.28 * frame.energy)
            .offset(y: size * 0.04)
    }

    private var ball: some View {
        ZStack {
            // 清透的水
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(dark ? 0.06 : 0.3), .white.opacity(dark ? 0.02 : 0.08)],
                    center: UnitPoint(x: 0.4, y: 0.35),
                    startRadius: 0,
                    endRadius: size * 0.6
                ))
            core
            // 下半部的陰影：有厚度
            Circle()
                .fill(RadialGradient(
                    colors: [.clear, .black.opacity(dark ? 0.4 : 0.14)],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: size * 0.28,
                    endRadius: size * 0.62
                ))
            // 左上一扇柔和的窗光
            Ellipse()
                .fill(.white.opacity(0.85))
                .frame(width: size * 0.34, height: size * 0.19)
                .rotationEffect(.degrees(-32))
                .offset(x: -size * 0.19, y: -size * 0.24)
                .blur(radius: size * 0.03)
            Circle()
                .fill(.white)
                .frame(width: size * 0.06, height: size * 0.06)
                .offset(x: -size * 0.12, y: -size * 0.31)
                .blur(radius: size * 0.006)
                .opacity(0.9)
            // 玻璃邊緣
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.9), .white.opacity(0.05), .white.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.8, size * 0.012)
                )
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .background {
            if glass {
                Color.clear.glassEffect(.clear, in: Circle())
            } else {
                Circle().fill(Brand.sheet)
            }
        }
        .shadow(color: XenaPalette.violet.opacity(0.16 + 0.22 * frame.energy), radius: size * 0.12, y: size * 0.06)
    }

    /// 中間發光的彩色光核：四團顏色在裡面旋轉、被扭成漩渦
    private var core: some View {
        let f = frame
        let warm = f.warmth
        let colors = [
            XenaPalette.pink.mix(with: Brand.accent, by: warm * 0.6),
            XenaPalette.cyan.mix(with: XenaPalette.amber, by: warm * 0.5),
            XenaPalette.amber.mix(with: Brand.accent, by: warm * 0.4),
            XenaPalette.violet.mix(with: XenaPalette.pink, by: warm * 0.4),
        ]
        // 四團光的位置（和 orb3d.ts 的 d1～d4 相同，y 向下）
        let spots: [CGPoint] = [CGPoint(x: -0.42, y: -0.34), CGPoint(x: 0.44, y: -0.3), CGPoint(x: 0.36, y: 0.42), CGPoint(x: -0.38, y: 0.4)]
        return Canvas { ctx, canvas in
            let r = min(canvas.width, canvas.height) / 2
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            ctx.addFilter(.blur(radius: r * 0.22))
            if dark { ctx.blendMode = .plusLighter }
            let a = f.swirl * 0.55
            for (i, spot) in spots.enumerated() {
                let wob = 0.14 * sin(f.morph * 0.9 + Double(i) * 1.7)
                let x = Double(spot.x) * cos(a) - Double(spot.y) * sin(a) + wob
                let y = Double(spot.x) * sin(a) + Double(spot.y) * cos(a) + 0.1 * cos(f.morph * 0.7 + Double(i))
                let blob = r * 0.6
                let px = c.x + CGFloat(x) * r * 0.78
                let py = c.y + CGFloat(y) * r * 0.78
                ctx.fill(
                    Path(ellipseIn: CGRect(x: px - blob, y: py - blob, width: blob * 2, height: blob * 2)),
                    with: .color(colors[i].opacity(0.95))
                )
            }
        }
        .mask {
            RadialGradient(colors: [.black, .black.opacity(0.85), .clear], center: .center, startRadius: 0, endRadius: size * 0.47)
        }
        .saturation(1 - 0.45 * f.rest)
        .opacity(0.8 + 0.2 * f.energy - 0.25 * f.rest)
    }
}

/// 對話裡每一段 Xena 的回答前面的小水滴（靜態，不耗電）
struct OrbDot: View {
    var size: CGFloat = 18

    var body: some View {
        Circle()
            .fill(AngularGradient(colors: [XenaPalette.pink, XenaPalette.violet, XenaPalette.cyan, XenaPalette.amber, XenaPalette.pink], center: .center))
            .blur(radius: size * 0.12)
            .overlay {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.85), .clear], center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.4))
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 30) {
        XenaOrb(mood: .idle, size: 140)
        HStack(spacing: 20) {
            XenaOrb(mood: .speaking, size: 70)
            XenaOrb(mood: .alert, size: 70)
            XenaOrb(mood: .resting, size: 70)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.paper)
}
