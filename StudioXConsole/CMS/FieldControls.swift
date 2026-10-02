import SwiftUI
import UIKit

// 編輯畫面的欄位：照網站的欄位定義畫。
//   - 內建資料（商品、折價券、橫幅…）：FieldSpec 的型別（string / text / int / ntd / bool / enum / date / stringArray / json）
//   - 內容集合（作品、文章…）：FieldDef 的型別（和後台的編輯表單一樣：markdown、select、tags、object、list…）
// 值一律是 JSONValue（金額是「元」；送出前才轉成網站要的格式）。

// MARK: - 綁定 JSONValue 的小工具

extension Binding where Value == JSONValue {
    /// 物件裡的一個欄位
    func member(_ key: String) -> Binding<JSONValue> {
        Binding(get: { self.wrappedValue[key] ?? .null }, set: { v in
            var o: [String: JSONValue] = [:]
            if case .object(let current) = self.wrappedValue { o = current }
            o[key] = v
            self.wrappedValue = .object(o)
        })
    }

    var text: Binding<String> {
        Binding<String>(get: { self.wrappedValue.string ?? "" }, set: { self.wrappedValue = .string($0) })
    }

    var flag: Binding<Bool> {
        Binding<Bool>(get: { self.wrappedValue.bool ?? false }, set: { self.wrappedValue = .bool($0) })
    }

    var strings: Binding<[String]> {
        Binding<[String]>(get: { self.wrappedValue.array.compactMap(\.string) }, set: { self.wrappedValue = .array($0.map { .string($0) }) })
    }

    var items: Binding<[JSONValue]> {
        Binding<[JSONValue]>(get: { self.wrappedValue.array }, set: { self.wrappedValue = .array($0) })
    }
}

/// 選項的中文（網站的值是英文代號）
enum OptionLabels {
    static func label(field: String, value: String) -> String {
        switch (field, value) {
        case ("status", "draft"): "草稿"
        case ("status", "scheduled"): "排程發布"
        case ("status", "published"): "發布"
        case ("status", "active"): "啟用"
        case ("status", "paused"): "暫停"
        case ("status", "open"): "待回覆"
        case ("status", "answered"): "已回覆"
        case ("status", "closed"): "已結案"
        case ("type", "fixed"): "折抵金額"
        case ("type", "percentage"): "打折（%）"
        case ("type", "free_shipping"): "免運"
        case ("channel", "both"): "線上和門市都能用"
        case ("channel", "online"): "只限線上"
        case ("channel", "in_store"): "只限門市"
        case ("mediaType", "color"): "純色"
        case ("mediaType", "image"): "圖片"
        case ("mediaType", "video"): "影片"
        case ("conditionMode", "AND"): "兩個條件都要達到"
        case ("conditionMode", "OR"): "達到一個就好"
        case ("action", "adopt"): "轉成客服對話"
        case ("action", "ignore"): "收起來（不是客人）"
        case ("action", "restore"): "放回收件匣"
        case ("decision", "approved"): "核准"
        case ("decision", "rejected"): "拒絕"
        case ("category", "order"): "訂單"
        case ("category", "shipping"): "物流"
        case ("category", "refund"): "退款"
        case ("category", "product"): "商品"
        case ("category", "coupon"): "折價券"
        case ("category", "account"): "帳號"
        case ("category", "wholesale"): "批發"
        case ("category", "other"): "其他"
        default: value
        }
    }
}

extension FieldSpec {
    /// 畫面上的標籤：網站的說明拿掉型別提示、英文選項列表；常見的欄位用短的中文
    var displayLabel: String {
        switch key {
        case "status": return "狀態"
        case "publishAt": return "排程發布時間"
        case "slug": return "網址代號"
        case "seo": return "SEO"
        case "i18n": return "翻譯"
        default: break
        }
        var s = label
        // 「類型 fixed/percentage/free_shipping」「通路 both/online/in_store」
        if let r = s.range(of: #"\s+[A-Za-z_]+(\s*/\s*[A-Za-z_]+)+$"#, options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }
        return s
    }
}

// MARK: - 一個欄位（內建資料：FieldSpec）

struct SpecField: View {
    let spec: FieldSpec
    @Binding var value: JSONValue
    var required = false

    @FocusState private var focused: Bool

    var body: some View {
        switch spec.kind {
        case .bool:
            ToggleRow(label: spec.displayLabel, help: spec.help, isOn: $value.flag)
        case .enum:
            ChoiceField(label: spec.displayLabel, help: spec.help, field: spec.key, options: spec.values.map { ($0, OptionLabels.label(field: spec.key, value: $0)) }, value: $value, nullable: spec.nullable)
        case .int, .float, .ntd:
            FieldBlock(label: spec.displayLabel, hint: numberHint, required: required, focused: focused) {
                NumberInput(value: $value, integer: spec.kind == .int, prefix: spec.kind == .ntd ? "NT$" : nil, nullable: spec.nullable)
                    .focused($focused)
            }
        case .date:
            DateField(label: spec.displayLabel, help: spec.help, value: $value, dateOnly: false, nullable: spec.nullable)
        case .stringArray:
            StringListField(label: spec.displayLabel, help: spec.help, values: $value.strings)
        case .json:
            JSONField(label: spec.displayLabel, help: spec.help, value: $value)
        case .text:
            TextBlock(label: spec.displayLabel, help: spec.help, limit: spec.maxLen, required: required, multiline: true, value: $value)
        case .string, .slug, .url:
            TextBlock(label: spec.displayLabel, help: spec.help, limit: spec.maxLen, required: required, multiline: false, value: $value, kind: spec.kind == .url ? .url : spec.kind == .slug ? .slug : .plain)
        }
    }

    private var numberHint: String? {
        var parts: [String] = []
        if let help = spec.help { parts.append(help) }
        if let min = spec.min, let max = spec.max { parts.append("\(min.formatted())～\(max.formatted())") }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }
}

// MARK: - 一個欄位（內容集合：FieldDef，可以一層一層往下）

struct DefField: View {
    let def: FieldDef
    @Binding var value: JSONValue
    /// 欄位路徑（巢狀的 key，給 id 用）
    var depth = 0

    @FocusState private var focused: Bool

    var body: some View {
        switch def.kind {
        case .text:
            TextBlock(label: def.label, help: def.help, limit: def.maxLength, required: def.required, multiline: false, value: $value, placeholder: def.placeholder)
        case .textarea, .html:
            TextBlock(label: def.label, help: def.kind == .html ? [def.help, "可以用 <em> 強調"].compactMap { $0 }.joined(separator: "・") : def.help, limit: def.maxLength, required: def.required, multiline: true, value: $value, placeholder: def.placeholder)
        case .markdown:
            MarkdownField(label: def.label, help: def.help, required: def.required, value: $value.text)
        case .number:
            FieldBlock(label: def.label, hint: def.help, required: def.required, focused: focused) {
                NumberInput(value: $value, integer: false, prefix: nil, nullable: !def.required)
                    .focused($focused)
            }
        case .boolean:
            ToggleRow(label: def.label, help: def.help, isOn: $value.flag)
        case .date:
            DateField(label: def.label, help: def.help, value: $value, dateOnly: true, nullable: !def.required)
        case .url:
            TextBlock(label: def.label, help: def.help, limit: 2000, required: def.required, multiline: false, value: $value, kind: .url, placeholder: def.placeholder)
        case .image:
            ImageURLField(label: def.label, help: def.help, value: $value.text)
        case .color:
            ColorField(label: def.label, value: $value.text)
        case .select:
            ChoiceField(label: def.label, help: def.help, field: def.key, options: def.options.map { ($0.value, $0.label) }, value: $value, nullable: !def.required)
        case .multiselect:
            MultiChoiceField(label: def.label, help: def.help, options: def.options.map { ($0.value, $0.label) }, values: $value.strings)
        case .tags, .lines, .refs:
            StringListField(label: def.label, help: def.kind == .refs ? [def.help, "\(def.collection ?? "") 的網址代號"].compactMap { $0 }.joined(separator: "・") : def.help, values: $value.strings)
        case .images:
            StringListField(label: def.label, help: def.help ?? "圖片網址，一行一張", values: $value.strings)
        case .object:
            ObjectField(def: def, value: $value, depth: depth)
        case .list:
            ListField(def: def, value: $value, depth: depth)
        }
    }
}

/// 一組欄位（object）：標題＋縮排的子欄位
struct ObjectField: View {
    let def: FieldDef
    @Binding var value: JSONValue
    var depth = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                Text(def.label)
                if def.required { Text("*").foregroundStyle(Theme.accent) }
            }
            .textRole(.h4)
            .foregroundStyle(Theme.ink)
            if let help = def.help {
                Text(help).textRole(.xs).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 22) {
                ForEach(def.fields) { sub in
                    DefField(def: sub, value: $value.member(sub.key), depth: depth + 1)
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rule(vertical: true) }
        }
    }
}

/// 多筆（list）：每一筆可以展開編輯、上下移、刪除；最後一個「新增一筆」
struct ListField: View {
    let def: FieldDef
    @Binding var value: JSONValue
    var depth = 0
    @State private var open: Int?

    var body: some View {
        let rows = value.array
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(def.label)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
                Text("\(rows.count) 筆")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            if let help = def.help {
                Text(help).textRole(.xs).foregroundStyle(Theme.muted)
            }
            RuledList {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            withAnimation(Motion.ease) { open = open == index ? nil : index }
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                                Text(summary(row))
                                    .textRole(.small)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text(open == index ? "−" : "+")
                                    .font(.brand(18, .medium))
                                    .foregroundStyle(open == index ? Theme.accent : Theme.ink)
                            }
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.row)

                        if open == index {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(def.fields) { sub in
                                    DefField(def: sub, value: item(index).member(sub.key), depth: depth + 1)
                                }
                                HStack(spacing: 8) {
                                    Button("上移") { move(index, by: -1) }
                                        .buttonStyle(.brand(.ghost, size: .sm))
                                        .disabled(index == 0)
                                    Button("下移") { move(index, by: 1) }
                                        .buttonStyle(.brand(.ghost, size: .sm))
                                        .disabled(index == rows.count - 1)
                                    Spacer()
                                    Button("刪除這筆") { remove(index) }
                                        .buttonStyle(.brand(.danger, size: .sm))
                                }
                            }
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            Button {
                var next = value.array
                next.append(.object([:]))
                value = .array(next)
                withAnimation(Motion.ease) { open = next.count - 1 }
            } label: {
                Text("＋ 新增一筆")
            }
            .buttonStyle(.brand(.ghost, size: .sm))
        }
    }

    private func item(_ index: Int) -> Binding<JSONValue> {
        Binding(get: {
            let rows = value.array
            return rows.indices.contains(index) ? rows[index] : .null
        }, set: { v in
            var rows = value.array
            guard rows.indices.contains(index) else { return }
            rows[index] = v
            value = .array(rows)
        })
    }

    private func move(_ index: Int, by step: Int) {
        var rows = value.array
        let to = index + step
        guard rows.indices.contains(index), rows.indices.contains(to) else { return }
        rows.swapAt(index, to)
        withAnimation(Motion.ease) {
            value = .array(rows)
            open = to
        }
    }

    private func remove(_ index: Int) {
        var rows = value.array
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        withAnimation(Motion.ease) {
            value = .array(rows)
            open = nil
        }
    }

    /// 一筆的摘要：第一個有字的子欄位
    private func summary(_ row: JSONValue) -> String {
        for sub in def.fields {
            if let s = row[sub.key]?.string, !s.isEmpty { return s }
            if let first = row[sub.key]?.array.first?.string, !first.isEmpty { return first }
        }
        return "（空白）"
    }
}

// MARK: - 基本的輸入

enum TextKind { case plain, url, slug }

/// 文字（單行或多行）：底線、字數
struct TextBlock: View {
    let label: String
    var help: String?
    var limit: Int?
    var required = false
    var multiline = false
    @Binding var value: JSONValue
    var kind: TextKind = .plain
    var placeholder: String?

    @FocusState private var focused: Bool

    var body: some View {
        let text = value.string ?? ""
        FieldBlock(label: label, hint: help, count: text.count, limit: limit, required: required, focused: focused) {
            Group {
                if multiline {
                    TextField(placeholder ?? "", text: $value.text, axis: .vertical)
                        .lineLimit(3...14)
                } else {
                    TextField(placeholder ?? "", text: $value.text)
                }
            }
            .focused($focused)
            .fieldText()
            .keyboardType(kind == .url ? .URL : .default)
            .textInputAutocapitalization(kind == .plain ? .sentences : .never)
            .autocorrectionDisabled(kind != .plain)
        }
    }
}

/// 數字：可以帶 NT$；空白＝不設定（可以是空的欄位才行）
struct NumberInput: View {
    @Binding var value: JSONValue
    var integer = false
    var prefix: String?
    var nullable = false

    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            if let prefix {
                Text(prefix).foregroundStyle(Theme.muted)
            }
            TextField(nullable ? "不設定" : "0", text: $text)
                .keyboardType(integer ? .numberPad : .decimalPad)
                .monospacedDigit()
        }
        .fieldText()
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { _, v in
            if Self.parse(text, integer: integer) != v { text = Self.format(v) }
        }
        .onChange(of: text) { _, t in
            let parsed = Self.parse(t, integer: integer)
            if parsed == .null && !nullable && !t.isEmpty { return }
            if parsed != value { value = parsed }
        }
    }

    static func format(_ v: JSONValue) -> String {
        guard let d = v.double else { return "" }
        return d.rounded() == d ? String(Int64(d)) : String(d)
    }

    static func parse(_ t: String, integer: Bool) -> JSONValue {
        let clean = t.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, let d = Double(clean) else { return .null }
        return .number(integer ? d.rounded() : d)
    }
}

/// 開關
struct ToggleRow: View {
    let label: String
    var help: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .textRole(.body)
                    .foregroundStyle(Theme.ink)
                if let help {
                    Text(help)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .tint(Theme.primary)
        .padding(.vertical, 4)
        .haptic(.selection, trigger: isOn)
    }
}

/// 單選：方形的選項（選項少）或選單（選項多）
struct ChoiceField: View {
    let label: String
    var help: String?
    let field: String
    let options: [(String, String)]
    @Binding var value: JSONValue
    var nullable = false

    var body: some View {
        let current = value.string ?? ""
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            if options.count <= 4 {
                FlowLayout(spacing: 8) {
                    ForEach(options, id: \.0) { option in
                        FilterChip(title: option.1, selected: current == option.0) {
                            value = nullable && current == option.0 ? .null : .string(option.0)
                        }
                    }
                }
            } else {
                Menu {
                    if nullable {
                        Button("不設定") { value = .null }
                    }
                    ForEach(options, id: \.0) { option in
                        Button(option.1) { value = .string(option.0) }
                    }
                } label: {
                    HStack {
                        Text(options.first { $0.0 == current }?.1 ?? (current.isEmpty ? "選一個" : current))
                            .foregroundStyle(current.isEmpty ? Theme.muted : Theme.ink)
                        Spacer()
                        HeroIcon("chevron-down", size: 14).foregroundStyle(Theme.muted)
                    }
                    .fieldText()
                    .padding(.bottom, 9)
                    .overlay(alignment: .bottom) { Rule() }
                }
            }
            if let help {
                Text(help).textRole(.xs).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// 多選（multiselect）
struct MultiChoiceField: View {
    let label: String
    var help: String?
    let options: [(String, String)]
    @Binding var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    FilterChip(title: option.1, selected: values.contains(option.0)) {
                        if let i = values.firstIndex(of: option.0) { values.remove(at: i) } else { values.append(option.0) }
                    }
                }
            }
            if let help {
                Text(help).textRole(.xs).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// 日期（只有日期：YYYY-MM-DD；日期時間：ISO 8601，台北時間）
struct DateField: View {
    let label: String
    var help: String?
    @Binding var value: JSONValue
    var dateOnly = false
    var nullable = false

    var body: some View {
        let date = parse(value.string)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
                Spacer()
                if nullable, date != nil {
                    Button("清除") { value = .null }
                        .buttonStyle(.brand(.quiet, size: .sm))
                }
            }
            if let date {
                DatePicker(label, selection: Binding(get: { date }, set: { value = .string(format($0)) }), displayedComponents: dateOnly ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Taipei") ?? .current)
                    .tint(Theme.primary)
            } else {
                Button(nullable ? "設定日期" : "選日期") { value = .string(format(.now)) }
                    .buttonStyle(.brand(.ghost, size: .sm))
            }
            if let help {
                Text(help).textRole(.xs).foregroundStyle(Theme.muted)
            }
        }
    }

    private func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if dateOnly {
            let parts = s.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return Calendar.taipei.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        }
        return JSONValue.string(s).date
    }

    private func format(_ d: Date) -> String {
        if dateOnly {
            let c = Calendar.taipei.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
        }
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}

/// 一串字（標籤、一行一個的清單、參照的網址代號）
struct StringListField: View {
    let label: String
    var help: String?
    @Binding var values: [String]
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .textRole(.small)
                    .foregroundStyle(Theme.muted)
                Text("\(values.count)")
                    .textRole(.xs)
                    .foregroundStyle(Theme.faint)
            }
            if !values.isEmpty {
                RuledList(color: Theme.hair) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("—").foregroundStyle(Theme.accent)
                            TextField("", text: Binding(get: { values.indices.contains(index) ? values[index] : "" }, set: { if values.indices.contains(index) { values[index] = $0 } }), axis: .vertical)
                                .fieldText()
                            Button {
                                withAnimation(Motion.fast) {
                                    if values.indices.contains(index) { values.remove(at: index) }
                                }
                            } label: {
                                HeroIcon("x-mark", size: 14).foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.press)
                            .accessibilityLabel("移除「\(item)」")
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            HStack(spacing: 10) {
                TextField("新增…", text: $draft)
                    .focused($focused)
                    .fieldText()
                    .onSubmit { add() }
                    .submitLabel(.done)
                Button("加入", action: add)
                    .buttonStyle(.brand(.ghost, size: .sm))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.bottom, 9)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? Theme.accent : Theme.line).frame(height: focused ? 1.5 : 1)
            }
            if let help {
                Text(help).textRole(.xs).foregroundStyle(Theme.muted)
            }
        }
    }

    private func add() {
        let parts = draft.split(whereSeparator: { $0 == "\n" || $0 == "、" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        withAnimation(Motion.fast) { values.append(contentsOf: parts) }
        draft = ""
    }
}

/// 長文（Markdown）：編輯／預覽切換，預覽照網站的排版（## 段落標題、清單、粗體、連結）
struct MarkdownField: View {
    let label: String
    var help: String?
    var required = false
    @Binding var value: String
    @State private var preview = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Text(label)
                    if required { Text("*").foregroundStyle(Theme.accent) }
                }
                .textRole(.small)
                .foregroundStyle(Theme.muted)
                Spacer()
                HStack(spacing: 6) {
                    FilterChip(title: "編輯", selected: !preview) { preview = false }
                    FilterChip(title: "預覽", selected: preview) { preview = true }
                }
            }
            if preview {
                MarkdownArticle(text: value)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $value, axis: .vertical)
                    .lineLimit(8...40)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .padding(.bottom, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(focused ? Theme.accent : Theme.line).frame(height: focused ? 1.5 : 1)
                    }
            }
            HStack {
                Text(help ?? "用 ## 分段；圖片用 ![說明](網址 \"圖說\")")
                Spacer()
                Text("\(value.count) 字").monospacedDigit()
            }
            .textRole(.xs)
            .foregroundStyle(Theme.muted)
        }
    }
}

/// Markdown 的文章排版（news/[slug] 的內文：h2 600、行高 1.95；引言左邊一條橘線）
struct MarkdownArticle: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let s):
                    Text(markdown(s))
                        .font(.brand(level == 2 ? 22 : 18, .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 10)
                case .quote(let s):
                    Text(markdown(s))
                        .textRole(.body)
                        .foregroundStyle(Theme.ink2)
                        .padding(.leading, 14)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 3) }
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("—").foregroundStyle(Theme.accent)
                        Text(markdown(s)).foregroundStyle(Theme.ink)
                    }
                    .textRole(.body)
                case .image(let alt, let url):
                    VStack(alignment: .leading, spacing: 6) {
                        RemoteImage(url: URL(string: url), aspect: 1600 / 1000, radius: Metric.radiusLg)
                        if !alt.isEmpty {
                            Text(alt).textRole(.xs).foregroundStyle(Theme.muted)
                        }
                    }
                case .table(let s):
                    Text(s)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink2)
                case .paragraph(let s):
                    Text(markdown(s))
                        .textRole(.body)
                        .lineHeight(.multiple(factor: 1.8))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .tint(Theme.accentText)
        .textSelection(.enabled)
    }

    enum Block {
        case heading(Int, String)
        case quote(String)
        case bullet(String)
        case image(String, String)
        case table(String)
        case paragraph(String)
    }

    /// ![說明](網址 "圖說") → 圖說（沒有就用說明）與網址
    static func image(_ line: String) -> (caption: String, url: String)? {
        guard line.hasPrefix("!["), line.hasSuffix(")"), let close = line.range(of: "](") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        let inside = String(line[close.upperBound..<line.index(before: line.endIndex)])
        let parts = inside.split(separator: " ", maxSplits: 1)
        guard let url = parts.first.map(String.init), !url.isEmpty else { return nil }
        var caption = alt
        if parts.count > 1 {
            let rest = parts[1].trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("\""), rest.hasSuffix("\""), rest.count >= 2 { caption = String(rest.dropFirst().dropLast()) }
        }
        return (caption, url)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var table: [String] = []
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !table.isEmpty { out.append(.table(table.joined(separator: "\n"))); table = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("|") { if !paragraph.isEmpty { flush() }; table.append(line); continue }
            if line.hasPrefix("### ") { flush(); out.append(.heading(3, String(line.dropFirst(4)))); continue }
            if line.hasPrefix("## ") { flush(); out.append(.heading(2, String(line.dropFirst(3)))); continue }
            if line.hasPrefix("> ") { flush(); out.append(.quote(String(line.dropFirst(2)))); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { flush(); out.append(.bullet(String(line.dropFirst(2)))); continue }
            if let image = Self.image(line) {
                flush()
                out.append(.image(image.caption, image.url))
                continue
            }
            if let dot = line.firstIndex(of: "."), dot > line.startIndex, line[..<dot].allSatisfy(\.isNumber), line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                out.append(.bullet(line))
                continue
            }
            paragraph.append(line)
        }
        flush()
        return out
    }
}

/// 圖片網址：網址＋縮圖
struct ImageURLField: View {
    let label: String
    var help: String?
    @Binding var value: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldBlock(label: label, hint: help, focused: focused) {
                TextField("https://…", text: $value)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .fieldText()
            }
            if let url = URL(string: value), value.hasPrefix("http") {
                RemoteImage(url: url, aspect: 16 / 9)
                    .frame(maxWidth: 360)
            }
        }
    }
}

/// 顏色：色票＋色碼
struct ColorField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .textRole(.small)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                ColorPicker(label, selection: Binding(get: { Color(hexString: value) ?? .black }, set: { value = $0.hexString ?? value }), supportsOpacity: false)
                    .labelsHidden()
                TextField("#rrggbb", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fieldText()
                    .monospaced()
            }
            .padding(.bottom, 9)
            .overlay(alignment: .bottom) { Rule() }
        }
    }
}

extension Color {
    /// #rrggbb（存回網站用）
    var hexString: String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
    }
}

/// 其他結構（JSON）：可以直接改，格式不對時不會送出
struct JSONField: View {
    let label: String
    var help: String?
    @Binding var value: JSONValue
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        FieldBlock(label: label, hint: help ?? "JSON 格式", error: invalid ? "格式不對（JSON）" : nil, focused: focused) {
            TextField("", text: $text, axis: .vertical)
                .lineLimit(4...24)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
        }
        .onAppear { text = Self.pretty(value) }
        .onChange(of: value) { _, v in
            // 外面改了值（復原、換圖後重新讀）：畫面上的字跟著換
            let shown = (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? JSONValue.null : nil)
            if shown != v {
                text = Self.pretty(v)
                invalid = false
            }
        }
        .onChange(of: text) { _, t in
            if t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                invalid = false
                if value != .null { value = .null }
                return
            }
            if let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(t.utf8)) {
                invalid = false
                if parsed != value { value = parsed }
            } else {
                invalid = true
            }
        }
    }

    static func pretty(_ v: JSONValue) -> String {
        if v.isNull { return "" }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
