import SwiftUI

/// Xena 現在在做什麼：決定水珠的能量（和網頁版一樣只有「靜靜呼吸」與「正在回答」兩端，中間平滑過渡）
enum XenaMood: Equatable {
    case idle
    /// 在等你（打字中、有確認卡片等你按）
    case listening
    /// 查資料、呼叫工具
    case thinking
    /// 回答中、說話中
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

/// Xena 說話的聲音：一個字一個字跟著打字機（TypewriterText 的 voice），水珠跟著鼓起、亮一下；
/// 標點、空白是換氣（停一下）。只有「在不在說話」會讓畫面重畫，每個字的大小直接給水珠讀（不經過 SwiftUI）
@Observable
final class XenaVoice {
    private(set) var speaking = false
    @ObservationIgnored private var level = 0.0
    @ObservationIgnored private var at: TimeInterval = 0
    @ObservationIgnored private var turn = 0

    /// 開始說一句話（回傳這一句的編號，說完用它 end）
    func begin() -> Int {
        turn += 1
        speaking = true
        return turn
    }

    /// 說完了；已經換成下一句就不管
    func end(_ id: Int) {
        guard id == turn else { return }
        speaking = false
        level = 0
    }

    /// 說出一個字
    func say(_ character: Character) {
        at = Date.timeIntervalSinceReferenceDate
        level = character.isWhitespace || character.isPunctuation ? 0 : Double.random(in: 0.45...1)
    }

    /// 這一刻的音量（超過 0.14 秒沒有新的字就是停了）
    func level(at now: TimeInterval) -> Double {
        speaking && now - at < 0.14 ? level : 0
    }
}

/// Xena 的 3D 水珠：studiox.tw 的 Xena 介紹頁同一顆（studio_website 的 orb3d.ts、orb.ts），
/// 著色器在 XenaOrb.metal，這裡照網頁的節奏推動它：
///   只有一個「能量」（0 靜靜呼吸、1 正在回答）平滑地追目標；變形、光核旋轉、流光、呼吸的速度都由能量內插、相位累加，
///   所以說完話是慢慢減速停下來，不會跳。出場像一滴水冒出來（從一個點長大、稍微超過再彈回、從下面浮上來），
///   回答完、事情做完 pulse 加一：彈一下。給了 voice 就跟著每個字鼓起來（像在說話）。減少動態時停住。
struct XenaOrb: View {
    var mood: XenaMood = .idle
    /// 水珠的框（輪廓大約是框的 94%；光暈畫在外面，整個畫布是 1.8 倍，排版只佔 1.2 倍）
    var size: CGFloat = 120
    var pulse: Int = 0
    var voice: XenaVoice?
    /// 水珠後面的底色：折射過去的顏色要和外面接得起來
    var backdrop: Color = Theme.page
    /// 後面有 XenaLight 的話是它的半徑（點），水珠裡看得到同一團光
    var light: CGFloat = 0

    static let canvas: CGFloat = 1.8

    @State private var motion = OrbMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let canvas = size * Self.canvas
        let lively = mood != .idle || voice?.speaking == true
        // 靜靜呼吸的動作很慢，每秒 30 格就很順；說話、回答時 60 格
        TimelineView(.animation(minimumInterval: lively ? 1.0 / 60 : 1.0 / 30, paused: reduceMotion)) { context in
            let f = motion.step(context.date.timeIntervalSinceReferenceDate, target: mood.energy, voice: voice, reduced: reduceMotion)
            Rectangle()
                .colorEffect(ShaderLibrary.xenaOrb(
                    .float2(canvas, canvas),
                    .float4(f.time, f.morph, f.swirl, f.flow),
                    .float4(f.energy, f.breath, f.grow, f.halo),
                    .float4(1 + f.stretch, 1 - f.stretch, f.haloScale, light > 0 ? light / (canvas / 2) : 0),
                    .color(backdrop),
                    .float(displayScale)
                ))
                .offset(y: f.lift + f.rise * size * 0.12)
        }
        .frame(width: canvas, height: canvas)
        .padding(-size * (Self.canvas - 1.2) / 2)
        .onChange(of: pulse) { motion.pulse() }
        .accessibilityElement()
        .accessibilityLabel("Xena，\(voice?.speaking == true ? "說話中" : mood.label)")
    }
}

/// 一格要用的數值（著色器的參數）
struct OrbFrame {
    var time: Double
    var morph: Double
    /// 弧度
    var swirl: Double
    var flow: Double
    var energy: Double
    var breath: Double
    var stretch: Double
    var grow: Double
    var halo: Double
    var haloScale: Double
    /// 往上下的位移（點）：說話時輕輕浮動
    var lift: Double
    /// 出場時從下面浮上來（1 → 0，乘上大小的 12%）
    var rise: Double
}

/// orb.ts 的 animateOrbs：能量平滑追目標，各種相位累加（速度變了也不會跳）。
/// 不是 @Observable：只在每一格裡往前推
final class OrbMotion {
    private var origin: TimeInterval?
    private var last: Double?
    private var enterAt: Double?
    private var energy = 0.0
    private var morph = Double.random(in: 0..<100)
    /// 度（和網頁一樣），交出去時換成弧度
    private var swirl = 0.0
    private var flow = 0.0
    private var breath = 0.0
    private var pulseAt = -10.0
    private var voice = 0.0

    func pulse() {
        pulseAt = last ?? 0
    }

    func step(_ now: TimeInterval, target: Double, voice speaker: XenaVoice?, reduced: Bool) -> OrbFrame {
        // 時間從第一格開始算（著色器用 Float，數字要小）
        let start = origin ?? now
        origin = start
        let t = now - start
        let dt = min(max(t - (last ?? t), 0), 1.0 / 20)
        last = t

        // 出場：光核一開始轉得快、比較亮（能量先衝到 0.9 再慢慢降回來），帶一下彈跳
        if enterAt == nil {
            enterAt = t + 0.1
            if !reduced {
                energy = max(energy, 0.9)
                pulseAt = t + 0.1
            }
        }

        // 說話：每個字鼓起來很快、停下來慢一點收
        let said = reduced ? 0 : speaker?.level(at: now) ?? 0
        voice += (said - voice) * (1 - exp(-dt * (said > voice ? 22 : 9)))
        let v = voice
        let goal = max(target, speaker?.speaking == true ? 0.85 : 0)

        if !reduced {
            // 能量平滑追向目標：加速快一點，減速慢一點（停下來比較有餘韻）
            let rate = goal > energy ? 4.0 : 1.6
            energy += (goal - energy) * (1 - exp(-dt * rate))
            morph += dt * lerp(0.55, 2.4, energy)
            swirl = (swirl + dt * lerp(10, 260, energy)).truncatingRemainder(dividingBy: 360)
            flow = (flow + dt * lerp(26, 420, energy)).truncatingRemainder(dividingBy: 360)
            breath = (breath + dt * lerp(1.65, 5.2, energy)).truncatingRemainder(dividingBy: 2 * .pi)
        }

        // 呼吸：0 ~ 1；收尾彈跳：衰減的正弦
        let b = (sin(breath) + 1) / 2
        let since = t - pulseAt
        let pop = since >= 0 && since < 1.2 ? exp(-since * 5) * sin(since * 16) : 0
        let e = t - (enterAt ?? t)
        let grow = reduced ? 1 : e < 0 ? 0 : e > 2 ? 1 : 1 - exp(-6.5 * e) * cos(11 * e)
        let rise = reduced ? 0 : e < 0 ? 1 : e > 1 ? 0 : pow(1 - e, 3)
        let lift = reduced ? 0 : energy * sin(t * 5.5) * 1.5

        return OrbFrame(
            time: t.truncatingRemainder(dividingBy: 3600),
            morph: morph,
            swirl: swirl * .pi / 180,
            flow: flow * .pi / 180,
            energy: energy,
            breath: b,
            // 液體的拉伸：水平、垂直此消彼長；說話時往上下拉長一點（像張嘴）
            stretch: sin(morph * 1.3) * lerp(0.02, 0.04, energy) + pop * 0.08 - v * 0.035,
            grow: grow * (1 + 0.045 * v),
            halo: 0.45 + 0.3 * energy + b * (0.45 - 0.15 * energy) + 0.3 * v,
            haloScale: 0.9 + b * 0.16 + energy * 0.08 + max(pop, 0) * 0.15 + 0.12 * v,
            lift: lift - v * 2,
            rise: rise
        )
    }
}

/// 水珠後面那團 Xena 的光（介紹頁的 .xh__light：紫 → 粉 → 透明）。XenaOrb 的 light 給同一個半徑，水珠裡才接得起來
struct XenaLight: View {
    var radius: CGFloat

    var body: some View {
        RadialGradient(
            stops: [
                .init(color: Color(red: 132 / 255, green: 92 / 255, blue: 1).opacity(0.2), location: 0),
                .init(color: Color(red: 1, green: 107 / 255, blue: 209 / 255).opacity(0.07), location: 0.45),
                .init(color: Color(red: 1, green: 107 / 255, blue: 209 / 255).opacity(0), location: 0.7),
            ],
            center: .center,
            startRadius: 0,
            endRadius: radius
        )
        .frame(width: radius * 2, height: radius * 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

nonisolated func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

#Preview {
    VStack(spacing: 24) {
        XenaOrb(mood: .idle, size: 160, light: 400)
            .background { XenaLight(radius: 400) }
        XenaOrb(mood: .speaking, size: 64)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .brandPage()
}
