import SwiftUI

/// 網站的寫入一律兩步驟（和 AI 連接器、網頁版 Xena 同一個規則）：
/// 第一次送出只拿到網站寫的標題與內容（這張卡），使用者看過按「確認執行」才用同一組參數加確認碼真的送出。
/// 退款、刪除這類要打字確認；退款、折價券超過門檻還要店主的驗證碼（網站會寄給店主）。
/// 回覆、接手、結案、封存這類改得回來的，按鈕本身就是確認（Proposal.confirmedByTap），不會跳這張卡。
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

    var body: some View {
        NavigationStack {
            ScrollView {
                ProposalForm(proposal: proposal, typed: $typed, ownerCode: $ownerCode, focused: $focused, error: error)
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
                            Text(proposal.needsOwner ? "送出驗證碼" : "確認執行")
                        }
                    }
                    .buttonStyle(.brand(proposal.danger ? .danger : .accent, size: .lg, fullWidth: true))
                    .disabled(!proposal.canConfirm(typed: typed, ownerCode: ownerCode) || busy)
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
        .onAppear { if proposal.typed != nil || proposal.needsOwner { focused = true } }
    }

    private func run() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            // 退款、刪除這類：確認前再驗證一次（Face ID；2 分鐘內驗證過就不再跳）。nil＝驗證沒過
            guard let outcome = try await model.confirm(proposal, typed: typed, ownerCode: ownerCode) else { return }
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

/// 確認卡的內容：網站寫的標題與內容、要打的字或店主的驗證碼、出錯的原因（ConfirmSheet 和出貨卡共用）
struct ProposalForm: View {
    let proposal: Proposal
    @Binding var typed: String
    @Binding var ownerCode: String
    var focused: FocusState<Bool>.Binding
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Eyebrow(proposal.needsOwner ? "需要店主核准" : proposal.danger ? "要動手了，先跟你確認" : "確認一下", dot: proposal.danger ? Theme.dangerFG : Theme.accent)
            Headline(proposal.ownerTitle ?? proposal.title, role: .h2)
            DetailLines(text: proposal.ownerDetail ?? proposal.detail)

            if proposal.needsOwner {
                FieldBlock(label: "店主的驗證碼", hint: "網站已經把 6 位數的核准碼寄給店主", focused: focused.wrappedValue) {
                    TextField("6 位數", text: $ownerCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused(focused)
                        .fieldText()
                }
            } else if let word = proposal.typed {
                FieldBlock(label: "輸入「\(word)」確認", focused: focused.wrappedValue) {
                    TextField(word, text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused(focused)
                        .fieldText()
                }
            }

            if let error {
                ErrorNote(message: error)
            }
        }
    }
}

extension Proposal {
    /// 退款超過門檻：要店主的驗證碼（確認之後才會出現）
    var needsOwner: Bool { ownerRequestID != nil }

    /// 按「確認執行」之前要再驗證一次（Face ID）：網站標危險的、要打字的；店主驗證碼那一步不用再驗
    var needsVerify: Bool { !needsOwner && (danger || typed != nil) }

    /// 按鈕本身就算確認了，不用再跳確認卡：網站沒標危險、不用打字、不用店主驗證碼。
    /// 只給改得回來的動作用（回覆、接手、交給 Xena、結案、重新開啟、封存），見 ConsoleAPI.confirmOnTap
    var confirmedByTap: Bool { !danger && typed == nil && !needsOwner }

    /// 「確認執行」按得下去了沒（打的字對、驗證碼填了）
    func canConfirm(typed text: String, ownerCode: String) -> Bool {
        if needsOwner { return ownerCode.trimmingCharacters(in: .whitespaces).count >= 4 }
        guard let word = typed else { return true }
        return text.trimmingCharacters(in: .whitespaces) == word
    }
}

extension AppModel {
    /// 確認卡的「確認執行」：退款、刪除這類先驗證一次（Face ID）再送出。回 nil＝驗證沒過，什麼都沒做
    func confirm(_ p: Proposal, typed: String, ownerCode: String) async throws -> ConsoleAPI.ConfirmOutcome? {
        if p.needsVerify {
            guard await lock.verify("確認：\(p.title)") else { return nil }
        }
        return try await api.confirm(p, typed: typed, ownerCode: ownerCode)
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
