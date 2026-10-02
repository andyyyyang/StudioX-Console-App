import SwiftUI

/// 一張訂單：品項、金額、收件、付款、物流；出貨、完成、取消、退款（都先出網站的確認，按了才執行）
struct OrderDetailView: View {
    let site: String
    let orderID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var detail: OrderDetail?
    @State private var error: String?
    @State private var proposal: Proposal?
    @State private var shipping = false
    @State private var refunding = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let d = detail {
                    header(d)
                    actions(d)
                    items(d)
                    customer(d)
                    payment(d)
                    links(d)
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                } else {
                    LoadingRow().admCard(padding: 0)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await load() }
        .admPage()
        .navigationTitle(detail.map { "#\($0.summary.number)" } ?? "訂單")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.askXena("幫我看一下\(model.site(site)?.name ?? site)的訂單 \(detail?.summary.number ?? orderID)")
                } label: { HeroIcon("sparkles") }
                .accessibilityLabel("問 Xena")
            }
        }
        .task { await load() }
        .sheet(isPresented: $shipping) {
            ShipSheet { tracking in
                Task { await propose { try await model.api.proposeOrderUpdate(site: site, id: orderID, status: "shipped", trackingNumber: tracking) } }
            }
        }
        .sheet(isPresented: $refunding) {
            RefundSheet(totalCents: (detail?.totalCents ?? 0) - (detail?.refundCents ?? 0)) { amount, note in
                Task { await propose { try await model.api.proposeRefund(site: site, id: orderID, amountNtd: amount, note: note) } }
            }
        }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            model.show(result["refundLabel"]?.string.map { "已退款 \($0)" } ?? "已更新訂單")
            Task {
                await load()
                await model.refreshAll()
            }
        }
    }

    private func load() async {
        error = nil
        do {
            detail = try await model.api.order(site: site, id: orderID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func propose(_ make: () async throws -> ConsoleAPI.WriteOutcome) async {
        working = true
        defer { working = false }
        do {
            let outcome = try await make()
            switch outcome {
            case .needsConfirmation(let p): proposal = p
            case .done:
                model.show("已更新訂單")
                await load()
            }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    // MARK: 區塊

    private func header(_ d: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(d.summary.status.label, tone: d.summary.status.tone)
                if let refund = d.summary.refundStatus {
                    StatusBadge(refund == "succeeded" ? "已退款" : refund == "failed" ? "退款失敗" : "退款中", tone: refund == "failed" ? .danger : .neutral)
                }
                Spacer()
                Text(d.summary.createdAt?.shortText ?? "")
                    .font(.admMeta)
                    .foregroundStyle(Theme.inkMuted)
            }
            Text(ntd(cents: d.totalCents))
                .font(.system(.largeTitle, weight: .semibold).monospacedDigit())
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
            Text("\(d.summary.customer)・\(d.shippingMethod)")
                .font(.admBody)
                .foregroundStyle(Theme.inkMuted)
        }
        .admCard()
    }

    @ViewBuilder
    private func actions(_ d: OrderDetail) -> some View {
        let status = d.summary.status
        let s = model.site(site)
        VStack(spacing: 10) {
            if status == .paid {
                Button { shipping = true } label: {
                    Label { Text("標記已出貨") } icon: { HeroIcon("truck", size: 18) }
                }
                .buttonStyle(.adm(.primary, fullWidth: true))
            }
            if status == .shipped {
                Button {
                    Task { await propose { try await model.api.proposeOrderUpdate(site: site, id: orderID, status: "completed") } }
                } label: {
                    Label { Text("標記已完成") } icon: { HeroIcon("check-circle", size: 18) }
                }
                .buttonStyle(.adm(.primary, fullWidth: true))
            }
            HStack(spacing: 10) {
                if status == .pending || status == .awaitingPayment {
                    Button {
                        Task { await propose { try await model.api.proposeOrderUpdate(site: site, id: orderID, status: "cancelled") } }
                    } label: { Text("取消訂單") }
                    .buttonStyle(.adm(.danger, fullWidth: true))
                }
                if s?.canRefund == true, [.paid, .shipped, .completed].contains(status), d.refundCents < d.totalCents {
                    Button { refunding = true } label: {
                        Label { Text("退款…") } icon: { HeroIcon("arrow-uturn-left", size: 16) }
                    }
                    .buttonStyle(.adm(.danger, fullWidth: true))
                }
            }
        }
        .disabled(working)
    }

    private func items(_ d: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("品項")
            ForEach(d.lines) { line in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.name).font(.admBody).foregroundStyle(Theme.ink)
                        if let v = line.variant { Text(v).font(.admMeta).foregroundStyle(Theme.inkMuted) }
                    }
                    Text("× \(line.quantity)").font(.admMeta).foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Text(ntd(cents: line.totalCents)).font(.system(.subheadline).monospacedDigit()).foregroundStyle(Theme.ink)
                }
            }
            Divider().overlay(Theme.hair)
            amountRow("小計", d.subtotalCents)
            amountRow("運費", d.shippingFeeCents, zero: "免運")
            if d.discountCents > 0 { amountRow("折扣", -d.discountCents) }
            if d.refundCents > 0 { amountRow("已退款", -d.refundCents) }
            HStack {
                Text("合計").font(.admCardTitle)
                Spacer()
                Text(ntd(cents: d.totalCents)).font(.system(.headline).monospacedDigit())
            }
            .foregroundStyle(Theme.ink)
        }
        .admCard()
    }

    private func amountRow(_ label: String, _ cents: Int, zero: String? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(cents == 0 && zero != nil ? zero! : (cents < 0 ? "−" + ntd(cents: -cents) : ntd(cents: cents)))
                .monospacedDigit()
        }
        .font(.admMeta)
        .foregroundStyle(Theme.inkMuted)
    }

    private func customer(_ d: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("收件")
            infoRow("user", d.summary.customer)
            if !d.phone.isEmpty, let tel = URL(string: "tel:\(d.phone.filter { $0.isNumber || $0 == "+" })") {
                Button { openURL(tel) } label: { infoRow("phone", d.phone, tappable: true) }
                    .buttonStyle(.plain)
            }
            if let email = d.email, let mail = URL(string: "mailto:\(email)") {
                Button { openURL(mail) } label: { infoRow("envelope", email, tappable: true) }
                    .buttonStyle(.plain)
            }
            infoRow("map-pin", d.address)
            if let note = d.note { infoRow("document-text", note) }
        }
        .admCard()
    }

    private func payment(_ d: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("付款與物流")
            infoRow("credit-card", d.paymentLabel + (d.summary.paidAt.map { "・\($0.shortText) 付款" } ?? ""))
            if let b = d.bankTransfer {
                VStack(alignment: .leading, spacing: 4) {
                    infoRow("banknotes", "客人回報：\(b.name ?? "—")・後五碼 \(b.last5 ?? "—")")
                    Text(b.awaiting ? "這是客人說的，還沒對帳。確認收款請在後台看過銀行帳單再按。" : "已確認收款")
                        .font(.admMeta)
                        .foregroundStyle(b.awaiting ? Theme.warningFG : Theme.successFG)
                        .padding(.leading, 30)
                }
            }
            if let tracking = d.summary.trackingNumber, !tracking.isEmpty {
                infoRow("truck", "物流單號 \(tracking)")
            }
            if let invoice = d.invoiceNumber { infoRow("receipt-refund", "發票 \(invoice)") }
        }
        .admCard()
    }

    @ViewBuilder
    private func links(_ d: OrderDetail) -> some View {
        HStack(spacing: 10) {
            if let track = d.trackURL {
                ShareLink(item: track, subject: Text("訂單 #\(d.summary.number) 的追蹤頁")) {
                    Label { Text("分享追蹤頁") } icon: { HeroIcon("link", size: 16) }
                }
                .buttonStyle(.adm(.secondary, size: .lg, fullWidth: true))
            }
            if let slip = d.packingSlipURL {
                Button { openURL(slip) } label: {
                    Label { Text("出貨單") } icon: { HeroIcon("printer", size: 16) }
                }
                .buttonStyle(.adm(.secondary, size: .lg, fullWidth: true))
            }
        }
    }

    private func infoRow(_ icon: String, _ text: String, tappable: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            HeroIcon(icon, size: 18)
                .foregroundStyle(Theme.icon)
                .frame(width: 20)
            Text(text)
                .font(.admBody)
                .foregroundStyle(tappable ? Theme.accent : Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 標記出貨：可以順便填物流單號
private struct ShipSheet: View {
    var onSubmit: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tracking = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("物流單號（選填）")
                TextField("例如黑貓的託運單號", text: $tracking)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .admField(focused: focused)
                Text("下一步會出網站的確認，按了才會改。")
                    .font(.admMeta)
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
                Button("下一步") {
                    let t = tracking.trimmingCharacters(in: .whitespaces)
                    dismiss()
                    onSubmit(t.isEmpty ? nil : t)
                }
                .buttonStyle(.adm(.primary, fullWidth: true))
            }
            .padding(20)
            .background(Theme.sheet.ignoresSafeArea())
            .navigationTitle("標記已出貨")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(300)])
        .onAppear { focused = true }
    }
}

/// 退款：金額（元，預設全額退剩下的）與備註
private struct RefundSheet: View {
    let totalCents: Int
    var onSubmit: (Int?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""

    private var maxNtd: Int { Int((Double(totalCents) / 100).rounded()) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("退多少（元）")
                TextField("全額 \(maxNtd)", text: $amount)
                    .keyboardType(.numberPad)
                    .admField()
                FieldLabel("備註（選填）")
                TextField("例如：延誤補償", text: $note)
                    .admField()
                Text("下一步會出網站的確認，要打「退款」才會執行；金額超過門檻還要店主的驗證碼。")
                    .font(.admMeta)
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
                Button("下一步") {
                    let value = Int(amount.filter(\.isNumber))
                    dismiss()
                    onSubmit(value.flatMap { $0 > 0 && $0 < maxNtd ? $0 : nil }, note.trimmingCharacters(in: .whitespaces))
                }
                .buttonStyle(.adm(.danger, fullWidth: true))
            }
            .padding(20)
            .background(Theme.sheet.ignoresSafeArea())
            .navigationTitle("退款")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
