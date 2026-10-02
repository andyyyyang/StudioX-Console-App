import SwiftUI

/// 登入畫面的玻璃標誌：三塊 Liquid Glass 積木（大三角形、方塊的兩個半邊）各自掛在彈簧上，
/// 自己在「散開漂浮」與「貼齊組合」之間循環，每次離開哪幾塊、方向、距離、翻面與停留時間都是隨機的
/// （和 studiox.tw 首頁的 3D 玻璃 Logo 同一個玩法，見 atelier-cms 的 auth/logo3d.ts）。
///   - 拖著可以轉，一拖就立刻組合起來
///   - 減少動態：停在組合好的樣子；減少透明度：改用平面標誌
struct GlassMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var pieces: [Drift] = MarkPart.allCases.map { _ in Drift() }
    @State private var tilt: CGSize = .zero
    @State private var dragging = false
    @State private var bob = false

    /// 一塊積木離開原位多少（位移以標誌邊長為單位）
    struct Drift: Equatable {
        var offset: CGSize = .zero
        var angle: Double = 0
        var flip: Double = 0
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                if reduceTransparency {
                    BrandMark()
                        .foregroundStyle(Brand.ink)
                } else {
                    ForEach(MarkPart.allCases) { part in
                        piece(part, side: side)
                    }
                }
            }
            .frame(width: side, height: side)
            .rotation3DEffect(.degrees(clamp(tilt.width * 0.18)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(clamp(-tilt.height * 0.18)), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .offset(y: bob ? -side * 0.022 : side * 0.022)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .gesture(drag)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { bob = true }
        }
        .task(id: reduceMotion) { await drift() }
        .accessibilityElement()
        .accessibilityLabel("StudioX")
    }

    @ViewBuilder
    private func piece(_ part: MarkPart, side: CGFloat) -> some View {
        let d = pieces[part.rawValue]
        let shape = part.shape(corner: 1.1)
        Color.clear
            .glassEffect(glass(for: part), in: shape)
            .overlay {
                // 柔光箱的長條反光（左上）＋邊緣才出現的彩虹色散
                shape
                    .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.5)))
                    .blendMode(.plusLighter)
                    .opacity(0.5)
                shape
                    .stroke(
                        AngularGradient(
                            colors: [XenaPalette.cyan, XenaPalette.violet, XenaPalette.pink, XenaPalette.amber, .white, XenaPalette.cyan],
                            center: part.anchor
                        ),
                        lineWidth: max(1, side * 0.007)
                    )
                    .blur(radius: side * 0.004)
                    .opacity(0.6)
            }
            .frame(width: side, height: side)
            .rotation3DEffect(.degrees(d.flip), axis: (x: 1, y: -1, z: 0), anchor: part.anchor, perspective: 0.6)
            .rotationEffect(.degrees(d.angle), anchor: part.anchor)
            .offset(x: d.offset.width * side, y: d.offset.height * side)
    }

    private func glass(for part: MarkPart) -> Glass {
        switch part {
        case .accentHalf: .clear.tint(Brand.accent.opacity(0.85))
        default: .clear.tint(Brand.ink.opacity(0.06))
        }
    }

    private func clamp(_ deg: CGFloat) -> Double {
        Double(min(max(deg, -28), 28))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    withAnimation(.spring(duration: 0.6, bounce: 0.3)) { pieces = pieces.map { _ in Drift() } }
                }
                tilt = value.translation
            }
            .onEnded { _ in
                dragging = false
                withAnimation(.spring(duration: 1.1, bounce: 0.45)) { tilt = .zero }
            }
    }

    private func drift() async {
        pieces = pieces.map { _ in Drift() }
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.6...4.8)))
            if Task.isCancelled { break }
            if dragging { continue }
            withAnimation(.spring(duration: 1.8, bounce: 0.25)) { pieces = Self.scatter() }
            try? await Task.sleep(for: .seconds(Double.random(in: 1.6...3.2)))
            withAnimation(.spring(duration: 0.9, bounce: 0.38)) { pieces = pieces.map { _ in Drift() } }
        }
    }

    /// 這一輪離開哪幾塊（至少一塊）、往哪飄、飄多遠、要不要翻面
    private static func scatter() -> [Drift] {
        var leaving = MarkPart.allCases.map { _ in Bool.random() }
        if !leaving.contains(true) { leaving[Int.random(in: 0..<leaving.count)] = true }
        return MarkPart.allCases.map { part in
            guard leaving[part.rawValue] else { return Drift() }
            let out = part.outward
            let heading = atan2(Double(out.dy), Double(out.dx)) + Double.random(in: -0.7...0.7)
            let distance = Double.random(in: 0.07...0.18)
            return Drift(
                offset: CGSize(width: cos(heading) * distance, height: sin(heading) * distance),
                angle: Double.random(in: -22...22),
                flip: Bool.random() ? Double.random(in: -55...55) : 0
            )
        }
    }
}

/// 背景慢慢飄的幾團色光（品牌橘＋ Xena 的顏色）：讓玻璃有東西可以折射
struct AmbientField: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private let blobs: [(color: Color, speed: Double, radius: Double)] = [
        (Brand.accent, 0.11, 0.42),
        (XenaPalette.pink, 0.08, 0.36),
        (XenaPalette.cyan, 0.07, 0.4),
        (XenaPalette.violet, 0.095, 0.34),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let m = max(size.width, size.height)
                ctx.addFilter(.blur(radius: m * 0.09))
                for (i, blob) in blobs.enumerated() {
                    let phase = Double(i) * 1.9
                    let x = size.width * (0.5 + 0.38 * sin(t * blob.speed + phase))
                    let y = size.height * (0.42 + 0.34 * cos(t * blob.speed * 0.8 + phase * 1.3))
                    let r = m * blob.radius * 0.5
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(blob.color.opacity((scheme == .dark ? 0.32 : 0.22) * intensity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Brand.paper.ignoresSafeArea()
        AmbientField().ignoresSafeArea()
        GlassMark().padding(60)
    }
}
