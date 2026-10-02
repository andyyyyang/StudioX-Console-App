import SwiftUI

/// 網站的寫入一律兩步驟（和 AI 連接器、網頁版 Xena 同一個規則）：
/// 第一次送出只拿到網站寫的標題與內容（這張卡），使用者看過按「確認執行」才用同一組參數加確認碼真的送出。
/// 退款、刪除這類要打字確認；退款、折價券超過門檻還要店主的驗證碼（網站會寄給店主）。
struct ConfirmSheet: View {
    @State var proposal: Proposal
    var siteName: String
    var onDone: (JSONValue) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var ownerCode = ""
    @State private var busy = false
    @State private var error: String?
    @State private var succeeded = false
    @State private var failed = 0
    @FocusState private var focused: Bool

    private var needsOwner: Bool { proposal.ownerRequestID != nil }

    private var canConfirm: Bool {
        if needsOwner { return ownerCode.trimmingCharacters(in: .whitespaces).count >= 4 }
        guard let word = proposal.typed else { return true }
        return typed.trimmingCharacters(in: .whitespaces) == word
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Eyebrow(needsOwner ? "需要店主核准" : proposal.danger ? "要動手了，先跟你確認" : "確認一下", dot: proposal.danger ? Theme.dangerFG : Theme.accent)
                    Headline(proposal.ownerTitle ?? proposal.title, role: .h2)
                    DetailLines(text: proposal.ownerDetail ?? proposal.detail)

                    if needsOwner {
                        FieldBlock(label: "店主的驗證碼", hint: "網站已經把 6 位數的核准碼寄給店主", focused: focused) {
                            TextField("6 位數", text: $ownerCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .focused($focused)
                                .fieldText()
                        }
                    } else if let word = proposal.typed {
                        FieldBlock(label: "輸入「\(word)」確認", focused: focused) {
                            TextField(word, text: $typed)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focused)
                                .fieldText()
                        }
                    }

                    if let error {
                        ErrorNote(message: error)
                    }
                }
                .padding(24)
                .frame(maxWidth: Metric.readable, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { Theme.sheet.ignoresSafeArea() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    Button("取消") { dismiss() }
                        .buttonStyle(.brand(.ghost, size: .lg, fullWidth: true))
                        .disabled(busy)
                    Button {
                        Task { await run() }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                            Text(needsOwner ? "送出驗證碼" : "確認執行")
                        }
                    }
                    .buttonStyle(.brand(proposal.danger ? .danger : .accent, size: .lg, fullWidth: true))
                    .disabled(!canConfirm || busy)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.sheet)
                .overlay(alignment: .top) { Rule() }
            }
            .navigationTitle(siteName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
        .haptic(.success, trigger: succeeded)
        .haptic(.error, trigger: failed)
        .onAppear { if proposal.typed != nil || needsOwner { focused = true } }
    }

    private func run() async {
        // 退款、刪除這類：確認前再驗證一次（Face ID；在「我 → 安全」可以關掉）。店主驗證碼那一步不用再驗
        if !needsOwner && (proposal.danger || proposal.typed != nil) {
            guard await model.lock.verify("確認：\(proposal.title)") else { return }
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let outcome = try await model.api.confirm(proposal, typed: typed, ownerCode: ownerCode)
            switch outcome {
            case .done(let result):
                succeeded = true
                onDone(result)
                dismiss()
            case .needsOwner(let next):
                withAnimation(Motion.ease) { proposal = next }
                focused = true
            }
        } catch {
            failed += 1
            self.error = error.localizedDescription
        }
    }
}

/// 網站寫的確認內容：一行一件事；「欄位：舊 → 新」的舊值畫刪除線、新值用墨色
private struct DetailLines: View {
    let text: String

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Color.clear.frame(height: 10)
                } else if let change = Change(line) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(change.field)
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(change.old)
                                .strikethrough(true, color: Theme.muted)
                                .foregroundStyle(Theme.muted)
                            Text("→").foregroundStyle(Theme.accent)
                            Text(change.new)
                                .foregroundStyle(Theme.ink)
                        }
                        .textRole(.body)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rule(color: Theme.hair) }
                } else {
                    Text(line)
                        .textRole(.body)
                        .foregroundStyle(Theme.ink2)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// 「名稱（中）：舊的 → 新的」
    struct Change {
        let field: String
        let old: String
        let new: String

        init?(_ line: String) {
            guard let colon = line.firstIndex(of: "："), let arrow = line.range(of: " → ") else { return nil }
            guard colon < arrow.lowerBound else { return nil }
            field = String(line[..<colon])
            old = String(line[line.index(after: colon)..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
            new = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
    }
}

extension View {
    /// 有提案就跳出確認；執行成功後呼叫 onDone
    func confirmSheet(_ proposal: Binding<Proposal?>, siteName: @escaping (String) -> String, onDone: @escaping (JSONValue) -> Void) -> some View {
        sheet(item: proposal) { p in
            ConfirmSheet(proposal: p, siteName: siteName(p.site), onDone: onDone)
        }
    }
}

/// 畫面上方的一句提示（反白的小條）
struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(toast.tone == .danger ? Theme.dangerFG : toast.tone == .warning ? Theme.warningFG : Theme.accent)
                .frame(width: 7, height: 7)
            Text(toast.text)
                .textRole(.small)
                .foregroundStyle(Theme.onInverse)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.inverse, in: .rect(cornerRadius: Metric.radius))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}
