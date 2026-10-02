import SwiftUI

/// StudioX 標誌的幾何：32 單位的方格，大三角形＋方塊，方塊沿對角線一半是品牌橘。
/// 和 atelier-cms 的 lib/brand-mark.ts、studiox.tw 的 Logo 相同。
enum MarkPart: Int, CaseIterable, Identifiable {
    case triangle, inkHalf, accentHalf

    var id: Int { rawValue }

    private static let s0: CGFloat = 16.849

    var points: [CGPoint] {
        let s0 = Self.s0
        switch self {
        case .triangle: return [CGPoint(x: 2, y: 2), CGPoint(x: 30, y: 2), CGPoint(x: 2, y: 30)]
        case .inkHalf: return [CGPoint(x: s0, y: s0), CGPoint(x: 30, y: s0), CGPoint(x: 30, y: 30)]
        case .accentHalf: return [CGPoint(x: s0, y: s0), CGPoint(x: 30, y: 30), CGPoint(x: s0, y: 30)]
        }
    }

    /// 重心（0～1，給旋轉當支點）
    var anchor: UnitPoint {
        let p = points
        let x = p.map(\.x).reduce(0, +) / CGFloat(p.count)
        let y = p.map(\.y).reduce(0, +) / CGFloat(p.count)
        return UnitPoint(x: x / 32, y: y / 32)
    }

    /// 從標誌中心往外的方向（散開時往這邊飄）
    var outward: CGVector {
        let a = anchor
        let dx = a.x - 0.5
        let dy = a.y - 0.5
        let len = max(hypot(dx, dy), 0.0001)
        return CGVector(dx: dx / len, dy: dy / len)
    }

    func shape(corner: CGFloat = 0.35) -> MarkPiece {
        MarkPiece(points: points, corner: corner)
    }
}

/// 標誌的一塊：方格座標的多邊形，角落稍微圓角，置中縮放到畫框
nonisolated struct MarkPiece: Shape {
    var points: [CGPoint]
    /// 圓角（方格單位）
    var corner: CGFloat = 0.35

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 32
        let ox = rect.midX - 16 * s
        let oy = rect.midY - 16 * s
        let pts = points.map { CGPoint(x: ox + $0.x * s, y: oy + $0.y * s) }
        guard let first = pts.first, let last = pts.last, pts.count > 2 else { return Path() }
        var p = Path()
        p.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in pts.indices {
            p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % pts.count], radius: corner * s)
        }
        p.closeSubpath()
        return p
    }
}

/// 平面版標誌：主體跟著前景色，摺角是品牌橘
struct BrandMark: View {
    var body: some View {
        ZStack {
            MarkPart.triangle.shape()
            MarkPart.inkHalf.shape()
            MarkPart.accentHalf.shape().fill(Brand.accent)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 大字品牌名：撐滿寬度，字距收緊（和登入畫面的 .au-word 一樣）
struct Wordmark: View {
    var text = "StudioX"

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width * 0.25, 150)
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .tracking(-size * 0.05)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Brand.ink)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(3.1, contentMode: .fit)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(spacing: 24) {
        Wordmark()
        BrandMark().frame(width: 120)
    }
    .padding()
    .background(Brand.paper)
}
