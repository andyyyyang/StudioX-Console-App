import SwiftUI

// 編輯時的即時預覽：照網站上的樣子畫，欄位一改就跟著變。

// MARK: - 商店橫幅（黃毛丫頭的 shop_banner：純色／圖片／影片底、小標、標題、副標）

struct BannerPreview: View {
    let values: [String: JSONValue]
    @State private var english = false

    var body: some View {
        let v = { (k: String) in values[k]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        let suffix = english ? "En" : "Zh"
        let bg = v("bgColor").flatMap(Color.init(hexString:)) ?? Theme.inverse
        let fg = v("textColor").flatMap(Color.init(hexString:)) ?? .white
        let media = v("mediaType") ?? "color"
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow("預覽・商店頁的橫幅")
                Spacer()
                HStack(spacing: 6) {
                    FilterChip(title: "中", selected: !english) { english = false }
                    FilterChip(title: "EN", selected: english) { english = true }
                }
            }
            ZStack(alignment: .bottomLeading) {
                bg
                if media == "image", let url = v("imageUrl").flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { bg }
                } else if media == "video", let url = v("videoPosterUrl").flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { bg }
                    Text("▶︎ 影片")
                        .textRole(.xs)
                        .foregroundStyle(fg)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let eyebrow = v("eyebrow\(suffix)") {
                        Text(eyebrow)
                            .font(.brand(12, .semibold))
                            .tracking(0.6)
                    }
                    Text(v("title\(suffix)") ?? "標題")
                        .font(.brand(26, .semibold))
                        .tracking(-0.6)
                        .lineLimit(2)
                    if let sub = v("subtitle\(suffix)") {
                        Text(sub)
                            .font(.brand(14, .medium))
                            .opacity(0.9)
                    }
                }
                .foregroundStyle(fg)
                .padding(20)
            }
            .aspectRatio(16 / 7, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Metric.radiusLg, style: .continuous))
            .overlay(alignment: .topLeading) {
                if values["isActive"]?.bool == false {
                    StatusBadge("停用中・網站上看不到", tone: .neutral)
                        .padding(10)
                }
            }
            .animation(Motion.ease, value: values)
        }
    }
}

// MARK: - 折價券（票券的樣子：左邊折扣、右邊碼與條件）

struct CouponTicket: View {
    let values: [String: JSONValue]

    var body: some View {
        let type = values["type"]?.string ?? "fixed"
        let value = values["value"]?.double ?? 0
        let active = values["isActive"]?.bool ?? true
        let discount: String = switch type {
        case "percentage": "\(value.formatted(.number.precision(.fractionLength(0...1))))%"
        case "free_shipping": "免運"
        default: "NT$\(Int(value.rounded()).formatted())"
        }
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(type == "percentage" ? "OFF" : type == "free_shipping" ? "FREE" : "折抵")
                    .font(.brand(11, .semibold))
                    .tracking(1)
                    .opacity(0.8)
                Text(discount)
                    .font(.brand(34, .semibold))
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: value))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(18)
            .frame(width: 140, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(active ? Theme.accent : Theme.muted)

            // 撕線
            VStack(spacing: 5) {
                ForEach(0..<9, id: \.self) { _ in
                    Rectangle().fill(Theme.line).frame(width: 1, height: 5)
                }
            }
            .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(values["code"]?.string.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "自動產生")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                if let name = values["name"]?.string, !name.isEmpty {
                    Text(name)
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                }
                Text(conditions)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Metric.radiusLg, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Metric.radiusLg, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        .opacity(active ? 1 : 0.7)
        .animation(Motion.ease, value: values)
        .accessibilityElement(children: .combine)
    }

    private var conditions: String {
        var out: [String] = []
        if let min = values["minimumOrder"]?.double, min > 0 { out.append("滿 NT$\(Int(min).formatted())") }
        switch values["channel"]?.string {
        case "online": out.append("只限線上")
        case "in_store": out.append("只限門市")
        default: break
        }
        if let date = values["expiresAt"]?.date { out.append("\(date.dayText) 到期") }
        if let limit = values["usageLimit"]?.int { out.append("可用 \(limit) 次") }
        if values["isActive"]?.bool == false { out.append("停用中") }
        return out.isEmpty ? "沒有使用條件" : out.joined(separator: "・")
    }
}

// MARK: - Google 搜尋結果的樣子（標題、網址、描述；太長會被截掉）

struct SerpPreview: View {
    let title: String
    let description: String
    let url: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let host = URL(string: url)?.host() ?? url
        let path = URL(string: url)?.path() ?? ""
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("預覽・Google 搜尋結果")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.press)
                        .frame(width: 26, height: 26)
                        .overlay { Text(String(host.prefix(1)).uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(host)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                        Text(([host] + path.split(separator: "/").map(String.init)).joined(separator: " › "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Text(title.isEmpty ? "（還沒有標題）" : title)
                    .font(.system(size: 19))
                    .foregroundStyle(colorScheme == .dark ? Color(hex: 0x99C3FF) : Color(hex: 0x1A0DAB))
                    .lineLimit(1)
                Text(description.isEmpty ? "（還沒有描述：Google 會自己從頁面上抓一段）" : description)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Metric.radiusLg))
            .overlay { RoundedRectangle(cornerRadius: Metric.radiusLg).strokeBorder(Theme.line, lineWidth: 1) }

            HStack(spacing: 16) {
                lengthNote("標題", count: title.count, ideal: 30, max: 60)
                lengthNote("描述", count: description.count, ideal: 120, max: 160)
            }
        }
        .animation(Motion.ease, value: title + description)
    }

    /// 中文標題 30 字內、描述 80–120 字最好（Google 大約用畫面寬度截斷）
    private func lengthNote(_ name: String, count: Int, ideal: Int, max: Int) -> some View {
        let tone: Tone = count == 0 ? .neutral : count <= ideal ? .active : count <= max ? .warning : .danger
        let text = count == 0 ? "\(name)沒填" : count <= ideal ? "\(name) \(count) 字・剛好" : "\(name) \(count) 字・可能會被截掉"
        return StatusBadge(text, tone: tone)
    }
}

// MARK: - 商品卡（商店的格狀清單）

struct ProductCard: View {
    let row: RecordSummary

    var body: some View {
        let raw = row.raw
        let stock = raw["stock"]?.int
        let published = raw["isPublished"]?.bool ?? true
        VStack(alignment: .leading, spacing: 10) {
            RemoteImage(url: row.image, aspect: 1)
                .overlay(alignment: .topLeading) {
                    if !published {
                        StatusBadge("未上架", tone: .neutral).padding(8)
                    } else if let stock, stock <= 0 {
                        StatusBadge("沒有庫存", tone: .danger).padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text(raw["priceLabel"]?.string ?? "")
                        .font(.brand(15, .medium).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if let stock {
                        Text("庫存 \(stock)")
                            .textRole(.xs)
                            .foregroundStyle(stock <= 5 ? Theme.dangerFG : Theme.muted)
                    }
                }
            }
        }
        .opacity(published ? 1 : 0.65)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
