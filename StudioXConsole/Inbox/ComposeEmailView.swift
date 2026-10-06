import SwiftUI

/// 寫一封新信（收件匣右上角的筆）：從哪個網站寄、收件人、主旨、內文；
/// 「Xena 照重點寫」把內文當重點寫成一封信，「潤飾」把寫好的改得更自然。信末自動附上你的簽名（下面看得到）。
/// 按寄出先跳確認（收件人、主旨、全文、簽名都攤開）；寄出後開成一條客服信，對方回信會接回那條對話，
/// 同一個網站的客服人員都看得到、都能回。只列網站後台有寄信功能（send_email）的網站。
struct ComposeEmailView: View {
    var initialSite: String?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var site = ""
    @State private var toAddress = ""
    @State private var toName = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var signature: [String] = []
    @State private var signatureError: String?
    @State private var drafting = false
    @State private var working = false
    @State private var proposal: Proposal?
    @State private var editingSignature = false
    @FocusState private var focus: Field?

    private enum Field { case to, name, subject, body }

    private var sites: [SiteSummary] { model.sites.filter { $0.tools.contains("send_email") } }

    private static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var emailOK: Bool {
        Self.clean(toAddress).range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    private var valid: Bool {
        !site.isEmpty && emailOK && !Self.clean(subject).isEmpty && subject.count <= 120 && !Self.clean(bodyText).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if sites.isEmpty {
                        EmptyState(title: "還沒有可以寄信的網站", message: "網站後台要開客服功能、更新到新的版本，才能從 App 寄信。")
                    } else {
                        form
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationTitle("寫信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        send()
                    } label: {
                        if working { ProgressView() } else { Text("寄出").fontWeight(.semibold) }
                    }
                    .disabled(!valid || working || drafting)
                }
            }
            .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
                done(result)
            }
            .sheet(isPresented: $editingSignature, onDismiss: { Task { await loadSignature() } }) {
                SignatureEditor()
            }
            .task {
                if site.isEmpty {
                    site = initialSite.flatMap { id in sites.contains { $0.id == id } ? id : nil } ?? sites.first?.id ?? ""
                }
                await loadSignature()
                if toAddress.isEmpty { focus = .to }
            }
            .onChange(of: site) { _, _ in
                Task { await loadSignature() }
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        if sites.count > 1 {
            FieldBlock(label: "從哪個網站寄") {
                Picker("網站", selection: $site) {
                    ForEach(sites) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .tint(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        FieldBlock(label: "收件人 Email", required: true, error: toAddress.isEmpty || emailOK ? nil : "Email 格式不太對", focused: focus == .to) {
            TextField("name@example.com", text: $toAddress)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .to)
                .fieldText()
        }
        FieldBlock(label: "怎麼稱呼（選填）", hint: "收件匣裡會用這個名字", focused: focus == .name) {
            TextField("例如：王先生", text: $toName)
                .focused($focus, equals: .name)
                .fieldText()
        }
        FieldBlock(label: "主旨", count: subject.count, limit: 120, required: true, focused: focus == .subject) {
            TextField("例如：品牌網站提案的下一步", text: $subject)
                .focused($focus, equals: .subject)
                .fieldText()
        }
        FieldBlock(label: "內文", hint: "不用署名，信末會自動附上你的簽名", required: true, focused: focus == .body) {
            TextField("想跟對方說什麼…也可以只寫幾個重點，再按「Xena 照重點寫」", text: $bodyText, axis: .vertical)
                .lineLimit(6...18)
                .focused($focus, equals: .body)
                .fieldText()
        }
        HStack(spacing: 10) {
            Button { xena(polish: false) } label: { Text("✦ Xena 照重點寫") }
                .buttonStyle(.brand(.ghost, size: .sm))
            Button { xena(polish: true) } label: { Text("潤飾") }
                .buttonStyle(.brand(.ghost, size: .sm))
            if drafting { ProgressView().controlSize(.small) }
        }
        .disabled(drafting || Self.clean(bodyText).isEmpty)
        signatureCard
        Text("寄出後會開成一條客服信：對方直接回信就會回到收件匣，同一個網站的客服人員都看得到、都能回。")
            .textRole(.xs)
            .foregroundStyle(Theme.muted)
    }

    /// 信末的簽名（這個網站寄出時的樣子）
    private var signatureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("簽名").textRole(.small).foregroundStyle(Theme.muted)
                Spacer()
                Button("修改職稱與電話") { editingSignature = true }
                    .buttonStyle(.brand(.ghost, size: .sm))
            }
            if signature.isEmpty {
                Text(signatureError ?? "讀取中…")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            } else {
                SignatureLines(lines: signature)
            }
        }
    }

    private func loadSignature() async {
        guard !site.isEmpty else { return }
        signatureError = nil
        do {
            signature = try await model.api.emailSignature(site: site)
        } catch {
            signature = []
            signatureError = "讀不到簽名：\(error.localizedDescription)"
        }
    }

    /// Xena 把內文當重點寫成一封信，或潤飾寫好的內文；放回內文，不會自己寄
    private func xena(polish: Bool) {
        guard !drafting, !site.isEmpty else { return }
        let input = bodyText
        drafting = true
        Task {
            defer { drafting = false }
            do {
                let text = try await model.api.replyDraft(
                    site: site, id: "", polish: polish, text: input, kind: "compose",
                    to: (name: Self.clean(toName), subject: Self.clean(subject))
                )
                withAnimation(Motion.ease) { bodyText = bodyText == input ? text : bodyText + "\n\n" + text }
            } catch {
                model.show(error.localizedDescription, tone: .danger)
            }
        }
    }

    private func send() {
        guard valid, !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let outcome = try await model.api.proposeSendEmail(
                    site: site, to: Self.clean(toAddress), name: Self.clean(toName),
                    subject: Self.clean(subject), body: Self.clean(bodyText)
                )
                switch outcome {
                case .needsConfirmation(let p): proposal = p
                case .done(let result): done(result)
                }
            } catch {
                model.show(error.localizedDescription, tone: .danger)
            }
        }
    }

    /// 寄出了：關掉、打開那條客服信
    private func done(_ result: JSONValue) {
        if let error = result["emailError"]?.string, !error.isEmpty {
            model.show("存進客服信了，但信沒寄出：\(error)", tone: .danger)
        } else {
            model.show("已寄出")
        }
        let thread = result["threadId"]?.string
        let from = site
        dismiss()
        Task {
            await model.refreshAll()
            if let thread, !thread.isEmpty { model.open(.thread(site: from, id: thread)) }
        }
    }
}

/// 簽名的幾行：名字｜職稱（粗）、品牌、聯絡方式（淡），左邊一條墨色線（和信裡一樣）
struct SignatureLines: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let last = index == lines.count - 1 && lines.count > 1
                Text(line)
                    .textRole(last ? .xs : .small)
                    .fontWeight(index == 0 ? .semibold : .regular)
                    .foregroundStyle(last ? Theme.muted : Theme.ink)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.ink).frame(width: 2)
        }
    }
}

/// 自己寄信時的簽名：職稱、直撥電話（名字是 StudioX 帳號的名字）。存在 StudioX 帳號，
/// 從每個網站寄出的信都帶這一份；品牌、Email、網址是各網站自己的。
struct SignatureEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: MySignature?
    @State private var title = ""
    @State private var phone = ""
    @State private var error: String?
    @State private var saving = false

    private var preview: [String] {
        let name = loaded?.name ?? ""
        let t = title.trimmingCharacters(in: .whitespaces)
        let p = phone.trimmingCharacters(in: .whitespaces)
        return [
            name.isEmpty ? "（帳號還沒有名字）" : (t.isEmpty ? name : "\(name)｜\(t)"),
            "網站的品牌名稱",
            [p.isEmpty ? "網站的電話" : p, "網站的 Email", "網址"].joined(separator: " · "),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("回覆客服信、回覆專案詢問、寫新信時，信末都會附上這份簽名。名字是你 StudioX 帳號的名字；品牌、Email、網址是每個網站自己的。")
                        .textRole(.small)
                        .foregroundStyle(Theme.muted)
                    if let error {
                        ErrorNote(message: error) { Task { await load() } }
                    }
                    FieldBlock(label: "職稱", hint: "例如：專案經理、客服主任", count: title.count, limit: 40) {
                        TextField("選填", text: $title).fieldText()
                    }
                    FieldBlock(label: "直撥電話", hint: "選填；沒填就用網站的電話", count: phone.count, limit: 30) {
                        TextField("例如：0912 345 678", text: $phone)
                            .keyboardType(.phonePad)
                            .fieldText()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("看起來像這樣").textRole(.small).foregroundStyle(Theme.muted)
                        SignatureLines(lines: preview)
                    }
                }
                .padding(20)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationTitle("寄信的簽名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("儲存").fontWeight(.semibold) }
                    }
                    .disabled(saving || loaded == nil || title.count > 40 || phone.count > 30)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        error = nil
        do {
            let s = try await model.api.mySignature()
            loaded = s
            title = s.title
            phone = s.phone
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            loaded = try await model.api.saveSignature(title: title, phone: phone)
            model.show("簽名已更新，之後從每個網站寄的信都會帶這份簽名")
            dismiss()
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }
}
