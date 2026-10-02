import SwiftUI

/// 跟 Xena 的對話（從任何地方都叫得出來：底部小條、首頁的水滴、各頁的 ✨）
struct XenaChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let bottomID = "bottom"

    private var session: XenaSession { model.xena }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if session.items.isEmpty {
                            emptyHero
                        }
                        ForEach(session.items) { item in
                            ChatItemView(item: item)
                                .id(item.id)
                        }
                        if session.phase == .thinking {
                            ThinkingRow()
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.revision) {
                    withAnimation(.smooth(duration: 0.25)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .background {
                ZStack {
                    Brand.paper
                    AmbientField(intensity: 0.3)
                }
                .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        XenaOrb(mood: model.xenaMood, size: 22, pulse: session.pulse)
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Xena")
                                .font(.headline)
                            Text(model.xenaMood.label)
                                .font(.caption2)
                                .foregroundStyle(Brand.muted)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        session.reset()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(session.items.isEmpty)
                    .accessibilityLabel("新的對話")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("關閉")
                }
            }
        }
    }

    private var emptyHero: some View {
        VStack(spacing: 16) {
            XenaOrb(mood: model.xenaMood, size: 110, pulse: session.pulse)
            Text("我是 Xena，你的店長。\n問我任何網站的事，或請我動手處理——動手之前我一定先問你。")
                .font(.system(size: 16))
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 12)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if !session.suggestions.isEmpty && !session.isBusy {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(session.suggestions, id: \.self) { suggestion in
                            Button(suggestion) { session.send(suggestion) }
                                .buttonStyle(.glass)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 6) {
                TextField("跟 Xena 說…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.vertical, 13)
                    .padding(.leading, 18)
                Button {
                    if session.isBusy { session.stop() } else { send() }
                } label: {
                    Image(systemName: session.isBusy ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Brand.accent)
                .disabled(!session.isBusy && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(5)
                .accessibilityLabel(session.isBusy ? "停止" : "送出")
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .animation(.smooth(duration: 0.25), value: session.suggestions)
    }

    private func send() {
        let text = draft
        draft = ""
        session.send(text)
    }
}

/// 對話裡的一項
struct ChatItemView: View {
    let item: ChatItem
    @Environment(AppModel.self) private var model

    var body: some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(Brand.onInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Brand.ink, in: .rect(cornerRadius: 20))
            }
        case .assistant(_, let text):
            HStack(alignment: .top, spacing: 10) {
                OrbDot(size: 18)
                    .padding(.top, 2)
                Text(markdown(text))
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .foregroundStyle(Brand.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .notice(_, let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Brand.danger)
        case .tool(let call):
            ToolRow(call: call)
        case .confirm(let card):
            ConfirmCardView(card: card, busy: model.xena.deciding.contains(card.id)) { approve, typed in
                model.xena.decide(card.id, approve: approve, typed: typed)
            }
        case .cards(let cards):
            CardsRow(item: cards)
        case .ask(let ask):
            AskView(ask: ask, disabled: model.xena.isBusy) { answer in
                model.xena.send(answer, answering: ask.id)
            }
        }
    }
}

/// 一次工具呼叫：轉圈 → 打勾（和網頁版逐筆顯示的一樣）
private struct ToolRow: View {
    let call: ToolRecord

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch call.status {
                case .running:
                    ProgressView().controlSize(.mini)
                case .ok:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success)
                case .error:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.danger)
                case .proposed:
                    Image(systemName: "hand.raised.circle.fill").foregroundStyle(Brand.accent)
                }
            }
            .font(.footnote)
            .frame(width: 16, height: 16)
            Text(call.label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Brand.ink)
            if let result = call.result, call.status != .running {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            if call.status == .proposed {
                Text("等你確認")
                    .font(.caption)
                    .foregroundStyle(Brand.accent)
            }
            if let ms = call.ms {
                Text(ms < 1000 ? "\(ms) ms" : "\((Double(ms) / 1000).formatted(.number.precision(.fractionLength(1)))) 秒")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Brand.line.opacity(0.7), in: .capsule)
        .padding(.leading, 28)
    }
}

/// 要動手之前的確認卡片：寫入一律兩步驟（和 MCP、網頁版的 Xena 同一個規則）。
/// 退款、刪除這類不能復原的，要打字確認
struct ConfirmCardView: View {
    let card: ConfirmCard
    var busy = false
    var onDecide: (Bool, String?) -> Void

    @State private var typed = ""

    private var typedOK: Bool {
        guard let word = card.typed else { return true }
        return typed.trimmingCharacters(in: .whitespaces) == word
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: card.danger ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                    .foregroundStyle(card.danger ? Brand.danger : Brand.accent)
                Text(card.status == .pending ? "要動手了，先跟你確認" : "確認卡片")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
            Text(card.title)
                .font(.system(size: 17, weight: .semibold))
            Text(card.detail)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)

            switch card.status {
            case .pending:
                if let word = card.typed {
                    TextField("輸入「\(word)」確認", text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldChrome()
                }
                HStack(spacing: 10) {
                    Button {
                        onDecide(true, card.typed == nil ? nil : typed)
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(card.danger ? Color.white : Brand.onInk) }
                            Text("確認執行")
                        }
                    }
                    .buttonStyle(.pill(card.danger ? .danger : .dark, compact: true))
                    .disabled(busy || !typedOK)
                    Button("取消") { onDecide(false, nil) }
                        .buttonStyle(.pill(.light, compact: true))
                        .disabled(busy)
                }
                if let error = card.result {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Brand.danger)
                }
            case .done:
                Label(card.result ?? "完成", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.success)
            case .cancelled:
                Label(card.result ?? "已取消", systemImage: "xmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            case .failed:
                Label(card.result ?? "沒有成功", systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Brand.danger)
            case .expired:
                Label(card.result ?? "這張確認卡過期了", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.sheet, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(card.status == .pending ? (card.danger ? Brand.danger : Brand.accent).opacity(0.45) : Brand.line, lineWidth: 1)
        }
        .animation(.smooth(duration: 0.3), value: card)
    }
}

/// Xena 做的卡片：一筆一張，點了到那一頁
private struct CardsRow: View {
    let item: CardsItem
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = item.title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                    .padding(.leading, 28)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(item.cards, id: \.self) { card in
                        Button {
                            switch card.entity {
                            case "order": model.open(.order(card.id))
                            case "support_thread": model.open(.conversation(card.id))
                            default: break
                            }
                        } label: {
                            EntityCardView(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 28)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

private struct EntityCardView: View {
    let card: EntityCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.kind)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                Spacer()
                if let badge = card.badge {
                    StatusPill(text: badge.label, tone: Tone(rawValue: badge.tone) ?? .muted)
                }
            }
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            ForEach(card.fields.prefix(2), id: \.self) { field in
                Text("\(field.label)：\(field.value)")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
        }
        .frame(width: 220, alignment: .leading)
        .raisedCard(cornerRadius: 18, padding: 14)
    }
}

/// Xena 問你（選一個）
private struct AskView: View {
    let ask: AskItem
    var disabled = false
    var onAnswer: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ask.question)
                .font(.subheadline.weight(.semibold))
            if let answer = ask.answer {
                Label(answer, systemImage: "checkmark")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            } else {
                ForEach(ask.options, id: \.self) { option in
                    Button {
                        onAnswer(option)
                    } label: {
                        Text(option)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.glass)
                    .disabled(disabled)
                }
            }
        }
        .padding(.leading, 28)
    }
}

/// Xena 在查資料
private struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            OrbDot(size: 18)
            Text("想一下…")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .phaseAnimator([0.4, 1.0]) { content, phase in
                    content.opacity(phase)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
        }
    }
}

/// 底部常駐的 Xena 小條（tab bar 上面）：水滴＋輪播她正在看著的事，點了打開對話
struct XenaAccessory: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showXena = true
        } label: {
            HStack(spacing: 8) {
                XenaOrb(mood: model.xenaMood, size: 20, pulse: model.xena.pulse)
                    .frame(width: 28, height: 28)
                TimelineView(.periodic(from: .now, by: 4)) { context in
                    let lines = model.tickerLines
                    let index = lines.isEmpty ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 4) % lines.count
                    Text(lines.isEmpty ? "Xena 值班中" : lines[index])
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(.smooth, value: index)
                }
                Spacer(minLength: 0)
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.accent)
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Xena：\(model.tickerLines.first ?? "值班中")")
    }
}
