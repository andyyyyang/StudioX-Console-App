import SwiftUI

/// 金鑰庫（console 的 /admin/platform/keys，只有負責人）：AI、寄信、簡訊、金流、LINE…的金鑰。
/// 金鑰本身只存在 console（加密），這裡只看得到片段；新增、換金鑰的欄位是密碼框，送出後就看不到了。
struct KeysView: View {
    @Environment(AppModel.self) private var model
    @State private var load = AdminLoad<KeyVault>()
    @State private var adding = false
    @State private var opened: PlatformKey?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                PageHeader("金鑰庫", eyebrow: "平台管理", subtitle: "金鑰只存在 console（加密），這裡只看得到片段。網站用哪把在「網站服務」指定。") {
                    if load.value != nil {
                        Button { adding = true } label: { AddIconLabel() }
                            .buttonStyle(.plain)
                            .accessibilityLabel("新增金鑰")
                    }
                }
                if let error = load.error {
                    ErrorNote(message: error) { Task { await refresh() } }
                }
                if let vault = load.value {
                    if vault.keys.isEmpty {
                        EmptyState(title: "還沒有金鑰", message: "按右上角的＋新增。")
                    }
                    ForEach(groups(vault), id: \.provider) { g in
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(g.label)
                            RuledList {
                                ForEach(g.keys) { key in
                                    Button { opened = key } label: { keyRow(key) }
                                        .buttonStyle(.row)
                                }
                            }
                        }
                    }
                } else if load.loading {
                    SkeletonRows(rows: 5)
                }
            }
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .refreshable { await Task { await refresh() }.value }
        .brandPage()
        .pageTitle("金鑰庫")
        .task { if load.value == nil { await refresh() } }
        .sheet(isPresented: $adding) {
            if let vault = load.value {
                KeyEditSheet(vault: vault, editing: nil) { await refresh() }
            }
        }
        .sheet(item: $opened) { key in
            if let vault = load.value {
                KeyDetailSheet(vault: vault, key: key) { await refresh() }
            }
        }
    }

    private func groups(_ vault: KeyVault) -> [(provider: String, label: String, keys: [PlatformKey])] {
        let by = Dictionary(grouping: vault.keys, by: \.provider)
        return by.keys.sorted().map { id in (id, vault.provider(id)?.label ?? id, by[id] ?? []) }
    }

    @ViewBuilder
    private func keyRow(_ key: PlatformKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(key.label.isEmpty ? "（沒有名字）" : key.label)
                        .textRole(.body)
                        .foregroundStyle(Theme.ink)
                    if key.disabled { StatusBadge("停用", tone: .neutral) }
                    if key.org != nil { StatusBadge("客戶自己的", tone: .info) }
                }
                Text([key.hint, key.org, key.uses > 0 ? "\(key.uses) 處在用" : "沒有在用", key.lastUsedAt.map { "\($0.relativeText)用過" }].compactMap { $0 }.joined(separator: "・"))
                    .font(.system(size: 12, design: .default))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HeroIcon("chevron-right", size: 13).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private func refresh() async {
        await load.run { KeyVault(try await model.api.admin("platform/keys")) }
    }
}

/// 一把金鑰：測試、編輯、停用、刪除。
/// 刪除收不回來：確認選單＋Face ID（2 分鐘內驗證過就不再跳）；停用改得回來：還有網站在用時問一次，沒在用就直接停
private struct KeyDetailSheet: View {
    let vault: KeyVault
    let key: PlatformKey
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false
    @State private var test: (ok: Bool, message: String)?
    @State private var editing = false
    @State private var confirmDelete = false
    /// 停用還有網站在用的金鑰：問一次
    @State private var confirmDisable = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(vault.provider(key.provider)?.label ?? key.provider)
                        Headline(key.label.isEmpty ? "（沒有名字）" : key.label, role: .h2)
                    }
                    RuledList {
                        if let hint = key.hint { InfoRow(label: "金鑰", value: hint, mono: true) }
                        InfoRow(label: "屬於", value: key.org ?? "StudioX")
                        InfoRow(label: "使用中", value: key.uses > 0 ? "\(key.uses) 處（網站服務或 console）" : "沒有")
                        InfoRow(label: "最近用過", value: key.lastUsedAt?.relativeText ?? "還沒用過")
                        InfoRow(label: "狀態", value: key.disabled ? "停用" : "可以用")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Button(testing ? "測試中…" : "測試這把金鑰") { Task { await runTest() } }
                            .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
                            .disabled(testing)
                        if let test {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                HeroIcon(test.ok ? "check-circle" : "x-circle", size: 15)
                                    .foregroundStyle(test.ok ? Theme.successFG : Theme.dangerFG)
                                Text(test.message)
                                    .textRole(.small)
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button("編輯") { editing = true }
                            .buttonStyle(.brand(.ghost, size: .md))
                        Button(key.disabled ? "啟用" : "停用") {
                            if !key.disabled && key.uses > 0 {
                                confirmDisable = true
                            } else {
                                Task { await toggleDisabled() }
                            }
                        }
                        .buttonStyle(.brand(.ghost, size: .md))
                        Spacer()
                        Button("刪除", role: .destructive) { confirmDelete = true }
                            .buttonStyle(.brand(.quiet, size: .md))
                            .disabled(key.uses > 0)
                    }
                    if key.uses > 0 {
                        Text("還有網站在用的金鑰不能刪；先到「網站服務」換掉，或改成停用。")
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(24)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) {
                KeyEditSheet(vault: vault, editing: key) {
                    await onDone()
                    dismiss()
                }
            }
            .confirmationDialog("刪除「\(key.label)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    Task { await model.verified("刪除金鑰「\(key.label)」") { await delete() } }
                }
            } message: {
                Text("刪掉就救不回來，要用的時候得重新貼一次金鑰。")
            }
            .confirmationDialog("停用「\(key.label)」？", isPresented: $confirmDisable, titleVisibility: .visible) {
                Button("停用", role: .destructive) { Task { await toggleDisabled() } }
            } message: {
                Text("還有 \(key.uses) 處在用這把金鑰：停用後那些服務會停下來，直到你再啟用。")
            }
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        do {
            let r = try await model.api.admin("platform/keys/\(key.id)/test", method: "POST")
            test = (r["ok"]?.bool ?? false, r["message"]?.string ?? "")
        } catch {
            test = (false, error.localizedDescription)
        }
    }

    /// 停用、啟用（改得回來，不用 Face ID）
    private func toggleDisabled() async {
        // PATCH 要帶完整的非密鑰欄位（沒帶的會被當成清掉）：先讀出來再送回去
        let ok = await model.adminRun(key.disabled ? "啟用了" : "停用了") {
            let current = try await model.api.admin("platform/keys/\(key.id)")
            var values: [String: JSONValue] = [:]
            let secrets = Set((vault.provider(key.provider)?.fields ?? []).filter(\.secret).map(\.key))
            for (k, v) in (current["values"] ?? .null).fields where !secrets.contains(k) { values[k] = v }
            _ = try await model.api.admin("platform/keys/\(key.id)", method: "PATCH", body: ["disabled": .bool(!key.disabled), "values": .object(values)])
        }
        if ok {
            await onDone()
            dismiss()
        }
    }

    /// 刪掉（確認過了：確認選單＋Face ID）
    private func delete() async {
        let ok = await model.adminRun("刪掉了") {
            _ = try await model.api.admin("platform/keys/\(key.id)", method: "DELETE")
        }
        if ok {
            await onDone()
            dismiss()
        }
    }
}

/// 新增或編輯一把金鑰：照供應商的欄位畫表單。編輯時密鑰欄位留空＝不變。
/// 按「新增」「儲存」就是確認；只有換掉已經存著的密鑰（舊的救不回來）才再驗證一次 Face ID
private struct KeyEditSheet: View {
    let vault: KeyVault
    /// nil＝新增
    let editing: PlatformKey?
    var onDone: () async -> Void
    @Environment(AppModel.self) private var model
    @State private var provider = ""
    @State private var label = ""
    @State private var orgID = ""
    @State private var values: [String: String] = [:]
    @State private var filled: [String: Bool] = [:]
    @State private var loaded = false

    private var fields: [PlatformField] { vault.provider(provider)?.fields ?? [] }

    /// 編輯時填了新的密鑰、而且原本就存著一把（舊的會被蓋掉）
    private var replacesSecret: Bool {
        fields.contains { f in
            f.secret && filled[f.key] == true && !(values[f.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var valid: Bool {
        guard !provider.isEmpty else { return false }
        return fields.allSatisfy { f in
            f.optional || !(values[f.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty || (editing != nil && f.secret && filled[f.key] == true)
        }
    }

    var body: some View {
        AdminSheet(title: editing == nil ? "新增金鑰" : "編輯金鑰",
                   subtitle: "送出之後金鑰就加密存在 console，這裡和網頁上都只看得到片段。",
                   action: editing == nil ? "新增" : "儲存", disabled: !valid || (editing != nil && !loaded)) {
            if let editing, replacesSecret {
                guard await model.lock.verify("換掉「\(editing.label)」的金鑰") else { return false }
            }
            return await model.adminRun(editing == nil ? "新增了金鑰" : "金鑰存好了") {
                var v: [String: JSONValue] = [:]
                for f in fields {
                    let text = (values[f.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    // 編輯時密鑰留空＝不變；非密鑰欄位一律帶上（沒帶的會被清掉）
                    if f.secret && text.isEmpty { continue }
                    if !f.secret || !text.isEmpty { v[f.key] = .string(text) }
                }
                var body: [String: JSONValue] = ["label": .string(label.trimmingCharacters(in: .whitespaces)), "values": .object(v), "orgId": orgID.isEmpty ? .null : .string(orgID)]
                if let editing {
                    _ = try await model.api.admin("platform/keys/\(editing.id)", method: "PATCH", body: .object(body))
                } else {
                    body["provider"] = .string(provider)
                    _ = try await model.api.admin("platform/keys", method: "POST", body: .object(body))
                }
                await onDone()
            }
        } content: {
            if editing == nil {
                AdminPicker(label: "哪一家的金鑰", selection: $provider, options: vault.providers.map { ($0.id, $0.label) })
            }
            if let note = vault.provider(provider)?.note {
                Text(note)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AdminTextField(label: "名字", text: $label, placeholder: "例如：StudioX 主帳號", hint: "選金鑰的時候看到的名字")
            AdminPicker(label: "屬於", selection: $orgID, options: [("", "StudioX（所有客戶都能指定）")] + vault.orgs.map { ($0.id, "\($0.name) 自己的") },
                        hint: "客戶自己的金鑰只能給他的網站用，而且不計費")
            ForEach(fields) { f in
                field(f)
            }
            if let doc = vault.provider(provider)?.doc {
                Link("到哪裡拿金鑰 ↗", destination: doc)
                    .font(.brand(14, .medium))
                    .foregroundStyle(Theme.accentText)
            }
        }
        .presentationDetents([.large])
        .task {
            if let editing {
                provider = editing.provider
                label = editing.label
                orgID = editing.orgID ?? ""
                if let r = try? await model.api.admin("platform/keys/\(editing.id)") {
                    values = (r["values"] ?? .null).fields.compactMapValues(\.string)
                    filled = (r["filled"] ?? .null).fields.compactMapValues(\.bool)
                    loaded = true
                }
            } else if provider.isEmpty {
                provider = vault.providers.first?.id ?? ""
            }
        }
    }

    @ViewBuilder
    private func field(_ f: PlatformField) -> some View {
        let binding = Binding(get: { values[f.key] ?? "" }, set: { values[f.key] = $0 })
        if !f.options.isEmpty {
            AdminPicker(label: f.label, selection: binding, options: (f.optional ? [("", "（不設定）")] : []) + f.options.map { ($0.value, $0.label) }, hint: f.hint)
        } else {
            let keep = editing != nil && f.secret && filled[f.key] == true
            AdminTextField(label: f.label + (f.optional ? "（選填）" : ""), text: binding,
                           placeholder: keep ? "已設定（留空＝不變）" : (f.placeholder ?? ""), hint: f.hint,
                           required: !f.optional && !keep, secure: f.secret, keyboard: .asciiCapable,
                           multiline: !f.secret && f.key == "serviceAccount")
        }
    }
}
