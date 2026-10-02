import SwiftUI

/// 網站的寫入一律兩步驟（和 AI 連接器、網頁版 Xena 同一個規則）：
/// 第一次送出只拿到網站寫的標題與內容（這張卡），使用者看過按「確認執行」才用同一組參數加確認碼真的送出。
/// 退款、刪除這類要打字確認；退款超過門檻還要店主的驗證碼（網站會寄給店主）。
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
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        HeroIcon(proposal.danger ? "exclamation-triangle" : "hand-raised", size: 16)
                        Text(needsOwner ? "需要店主核准" : "要動手了，先跟你確認")
                            .font(.admLabel)
                            .tracking(0.44)
                    }
                    .foregroundStyle(proposal.danger ? Theme.dangerFG : Theme.accent)

                    Text(proposal.ownerTitle ?? proposal.title)
                        .font(.admTitle)
                        .foregroundStyle(Theme.ink)
                    Text(proposal.ownerDetail ?? proposal.detail)
                        .font(.admBody)
                        .foregroundStyle(Theme.inkMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .admCard(padding: 14)

                    if needsOwner {
                        FieldLabel("店主的驗證碼")
                        TextField("店主收到的 6 位數", text: $ownerCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focused)
                            .admField(focused: focused)
                    } else if let word = proposal.typed {
                        FieldLabel("輸入「\(word)」確認")
                        TextField(word, text: $typed)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .admField(focused: focused)
                    }

                    if let error {
                        ErrorNote(message: error)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.sheet.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    Button("取消") { dismiss() }
                        .buttonStyle(.adm(.secondary, fullWidth: true))
                        .disabled(busy)
                    Button {
                        Task { await run() }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().controlSize(.small).tint(proposal.danger ? Theme.dangerFG : Theme.onPrimary) }
                            Text("確認執行")
                        }
                    }
                    .buttonStyle(.adm(proposal.danger ? .danger : .primary, fullWidth: true))
                    .disabled(!canConfirm || busy)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.sheet)
            }
            .navigationTitle(siteName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
    }

    private func run() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let outcome = try await model.api.confirm(proposal, typed: typed, ownerCode: ownerCode)
            switch outcome {
            case .done(let result):
                onDone(result)
                dismiss()
            case .needsOwner(let next):
                withAnimation(.smooth) { proposal = next }
                focused = true
            }
        } catch {
            self.error = error.localizedDescription
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

/// 畫面上方的一句提示（Toast.tsx）
struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            HeroIcon(toast.tone == .danger ? "exclamation-circle" : "check-circle", size: 18)
                .foregroundStyle(toast.tone.foreground)
            Text(toast.text)
                .font(.admBody)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Theme.surfaceElevated, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.hair))
        .shadow(color: .black.opacity(0.16), radius: 21, y: 18)
        .padding(.horizontal, 24)
    }
}
