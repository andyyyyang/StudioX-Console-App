import SwiftUI

/// 客服對話的回覆建議：輸入框上面幾句可以直接用的下一句，點了放進輸入框（看過、改過才送）。
///
/// 省錢的分工——客人每一句 Jev 都先看過（網站那邊，一句不到一分錢的零頭）：
///   quick：打招呼、道謝、補資料這類，iPhone 上的 Apple Intelligence 想（免費、資料不出手機）
///   xena：要查訂單、商品、報價、客人紀錄的，才請 console 的 Xena 分析這位客人（客人同一句話只算一次額度，
///         換一批由 Apple Intelligence 照她的分析改寫，不再花錢）
/// 設定「只用 Apple Intelligence」就不自動叫 Xena；任何時候都可以按「請 Xena 分析」。
struct ReplySuggestions: Equatable {
    enum Source: Equatable { case local, xena }

    /// 客人最後一句（換了才重想）
    var key = ""
    /// 現在這幾句是誰想的
    var source: Source?
    var loading: Source?
    /// Xena 的客戶分析（一兩句）與回覆用得到的事實
    var brief = ""
    var facts: [String] = []
    var replies: [String] = []
    var note: String?
    /// 專人按了收起來（客人再說話才會再出現）
    var hidden = false

    var analyzed: Bool { !brief.isEmpty || !facts.isEmpty }

    /// 等專人回的客人那幾句：專人最後一次說話之後客人說的（最多最近 4 句）。
    /// 只在等專人、專人接手中時；最後說話的是專人（已經回了）就是 nil
    static func waiting(_ d: XenaConversationDetail) -> [XenaConversationMessage]? {
        guard d.status == "waiting" || d.status == "human" else { return nil }
        let said = d.messages.filter { $0.role != "event" }
        guard let last = said.last, last.role != "staff" else { return nil }
        let sinceStaff = said.reversed().prefix { $0.role != "staff" }
        let visitor = sinceStaff.filter { $0.role == "user" }
        return visitor.isEmpty ? nil : Array(visitor.prefix(4).reversed())
    }

    /// 這幾句 Jev 有沒有說要 Xena 查資料
    static func needsXena(_ run: [XenaConversationMessage]) -> Bool {
        run.contains { $0.jevAssist == "xena" }
    }

    static func key(_ run: [XenaConversationMessage]) -> String {
        guard let last = run.last else { return "" }
        return "\(last.id)|\(last.at?.timeIntervalSince1970 ?? 0)"
    }

    /// 給手機上的模型看的對話：最近 12 句、每句 220 字內；照片、檔案的網址拿掉
    static func transcript(_ d: XenaConversationDetail) -> String {
        d.messages
            .filter { $0.role != "event" }
            .suffix(12)
            .compactMap { m -> String? in
                let text = m.content
                    .replacingOccurrences(of: #"(?m)^(\[[^\]\n]+\][^\n]*?)\s*https?://\S+$"#, with: "$1", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let who = switch m.role {
                case "user": "客人"
                case "staff": "專人"
                default: "Xena"
                }
                return "\(who)：\(String(text.prefix(220)))"
            }
            .joined(separator: "\n")
    }
}

/// 輸入框上面的建議列：誰想的、Xena 的客戶分析、三句下一句（左右滑）、換一批、請 Xena 分析、收起來
struct ReplySuggestionsBar: View {
    let state: ReplySuggestions
    /// 這台 iPhone 能用 Apple Intelligence（換一批在手機上想）
    let local: Bool
    let pick: (String) -> Void
    let again: () -> Void
    let askXena: () -> Void
    let hide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                badge
                Spacer(minLength: 6)
                if state.loading == nil {
                    if local, !state.replies.isEmpty {
                        Button(action: again) {
                            Label("換一批", systemImage: "arrow.clockwise")
                        }
                        .accessibilityHint("用 iPhone 上的 Apple Intelligence 換三句，不花錢")
                    }
                    if !state.analyzed {
                        Button(action: askXena) {
                            Label("請 Xena 分析", systemImage: "sparkles")
                        }
                        .accessibilityHint("Xena 看這位客人的訂單和之前的對話再建議，算一則 Xena 的額度")
                    }
                }
                Button(action: hide) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("收起回覆建議")
            }
            .font(.brand(12, .medium))
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderless)
            .tint(Theme.ink2)

            if !state.brief.isEmpty {
                Text(state.brief)
                    .textRole(.xs)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Xena 的客戶分析：\(state.brief)")
            }

            if !state.replies.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(state.replies, id: \.self) { reply in
                            Button { pick(reply) } label: {
                                Text(reply)
                                    .textRole(.small)
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(4)
                                    .frame(width: 230, alignment: .topLeading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Theme.bubbleIn.opacity(0.7), in: .rect(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(state.source == .xena ? Theme.bubbleXena.opacity(0.35) : Theme.hair)
                                    }
                            }
                            .buttonStyle(.press)
                            .accessibilityHint("放進輸入框")
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .opacity(state.loading == nil ? 1 : 0.45)
            } else if let note = state.note, state.loading == nil {
                Text(note)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 4)
        .animation(Motion.fast, value: state)
    }

    @ViewBuilder
    private var badge: some View {
        if let loading = state.loading {
            HStack(spacing: 6) {
                if loading == .xena {
                    XenaOrb(mood: .thinking, size: 14)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(loading == .xena ? "Xena 看一下這位客人…" : "想幾句回覆…")
                    .textRole(.xs)
                    .foregroundStyle(Theme.ink2)
            }
        } else if state.source == .xena || state.analyzed {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.bubbleXena)
                Text(state.source == .xena ? "Xena 看過這位客人" : "照 Xena 的分析換一批")
                    .textRole(.xs)
                    .foregroundStyle(Theme.ink2)
            }
        } else if state.source == .local {
            HStack(spacing: 5) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                Text("Apple Intelligence・在手機上想的")
                    .textRole(.xs)
                    .foregroundStyle(Theme.ink2)
            }
        } else {
            Text("回覆建議")
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
        }
    }
}
