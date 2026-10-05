import SwiftUI

/// 一張訂單：金額、品項、收件、付款、物流與貨態、發票；出貨、完成、取消、退款、確認收款
/// （都先出網站的確認，按了才執行）
struct OrderDetailView: View {
    let site: String
    let orderID: String

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var detail: OrderDetail?
    @State private var error: String?
    @State private var proposal: Proposal?
    @State private var shipping = false
    /// 出貨之後改物流單號（打錯、換一箱寄）
    @State private var editingTracking = false
    @State private var refunding = false
    @State private var working = false
    /// 這個人在這個網站看得到會員、折價券（看不到就不放連結）
    @State private var canOpenMember = true
    @State private var canOpenCoupon = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    if let d = detail {
                        header(d)
                        actions(d)
                        if sizeClass == .regular {
                            HStack(alignment: .top, spacing: 48) {
                                items(d).frame(maxWidth: .infinity, alignment: .topLeading)
                                VStack(alignment: .leading, spacing: 44) {
                                    customer(d)
                                    payment(d)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        } else {
                            items(d)
                            customer(d)
                            payment(d)
                        }
                        links(d)
                    } else if let error {
                        ErrorNote(message: error) { Task { await load() } }
                    } else {
                        SkeletonRows(rows: 6)
                    }
                }
                .pageWidth()
                .padding(.top, 16)
                .padding(.bottom, 64)
            }
            // UI 截圖（-demoScroll amounts）：捲到金額（折扣的名目）與會員
            .task(id: detail != nil) {
                guard DemoServer.screenshots, detail != nil, UserDefaults.standard.string(forKey: "demoScroll") == "amounts" else { return }
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo("amounts", anchor: .top)
            }
        }
        .refreshable { await Task { await load() }.value }
        .brandPage()
        .navigationTitle(detail.map { "#\($0.summary.number)" } ?? "訂單")
        .navigationBarTitleDisplayMode(.inline)
        .xenaFocus("order-\(site)-\(orderID)", prompt: "幫我看一下\(model.site(site)?.name ?? site)的訂單 \(detail?.summary.number ?? orderID)")
        .toolbar { AskXenaToolbar(model: model) }
        .task { await load() }
        .sheet(isPresented: $shipping) {
            ShipSheet { tracking in
                Task { await propose { try await model.api.proposeOrderUpdate(site: site, id: orderID, status: "shipped", trackingNumber: tracking) } }
            }
        }
        .sheet(isPresented: $editingTracking) {
            ShipSheet(editing: detail?.trackingNumber ?? "") { tracking in
                Task { await propose { try await model.api.proposeOrderUpdate(site: site, id: orderID, trackingNumber: tracking ?? "") } }
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
        if let schema = await model.schema(for: site) {
            canOpenMember = schema.entity("user")?.canGet == true
            canOpenCoupon = schema.entity("coupon")?.canGet == true
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

    // MARK: 頁首

    private func header(_ d: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("\(model.site(site)?.name ?? site)・\(d.summary.createdAt?.shortText ?? "")")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                CountUp(value: Double(d.totalCents) / 100, format: { "NT$" + Int($0.rounded()).formatted() })
                    .textRole(.stat)
                    .foregroundStyle(Theme.ink)
                Text("#\(d.summary.number)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                StatusBadge(d.summary.status.label, tone: d.summary.status.tone)
                if let refund = d.summary.refundStatus {
                    StatusBadge(refund == "succeeded" ? "已退款" : refund == "failed" ? "退款失敗" : "退款中", tone: refund == "failed" ? .danger : .neutral)
                }
                if let logistics = d.logisticsStatus {
                    StatusBadge(logistics, tone: logistics.contains("送達") ? .active : .info)
                }
            }
            Text("\(d.summary.customer)・\(d.shippingMethod)")
                .textRole(.lead)
                .foregroundStyle(Theme.ink2)
        }
        .reveal()
    }

    // MARK: 動作

    @ViewBuilder
    private func actions(_ d: OrderDetail) -> some View {
        let status = d.summary.status
        let s = model.site(site)
        let canConfirmTransfer = s?.tools.contains("confirm_bank_transfer") == true && d.bankTransfer?.awaiting == true
        let canRefund = s?.canRefund == true && [.paid, .shipped, .completed].contains(status) && d.refundCents < d.totalCents
        if status == .paid || status == .shipped || status == .pending || status == .awaitingPayment || canConfirmTransfer || canRefund {
            VStack(alignment: .leading, spacing: 10) {
                if status == .paid {
                    Button { shipping = true } label: { Text("標記已出貨") }
                        .buttonStyle(.brand(.accent, size: .lg, fullWidth: true, arrow: true))
                }
                if status == .shipped {
                    Button {
                        Task { await propose { try await model.api.proposeOrderUpdate(site: site, id: orderID, status: "completed") } }
                    } label: { Text("標記已完成") }
                    .buttonStyle(.brand(.primary, size: .lg, fullWidth: true, arrow: true))
                    Button { editingTracking = true } label: { Text(d.trackingNumber == nil ? "補上物流單號" : "改物流單號") }
                        .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
                }
                if canConfirmTransfer {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task { await propose { try await model.api.proposeConfirmTransfer(site: site, orderID: orderID) } }
                        } label: { Text("我在帳上看到這筆錢了，確認收款") }
                        .buttonStyle(.brand(.primary, size: .lg, fullWidth: true))
                        Text("只有看過銀行帳單才按；客人說他匯了、或回報了後五碼都不算。確認後網站會寄確認信給客人、把出貨單寄給網購處理人員。")
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                    }
                }
                HStack(spacing: 10) {
                    if status == .pending || status == .awaitingPayment {
                        Button {
                            Task { await propose { try await model.api.proposeOrderUpdate(site: site, id: orderID, status: "cancelled") } }
                        } label: { Text("取消訂單") }
                        .buttonStyle(.brand(.danger, fullWidth: true))
                    }
                    if canRefund {
                        Button { refunding = true } label: { Text("退款…") }
                            .buttonStyle(.brand(.danger, fullWidth: true))
                    }
                }
            }
            .disabled(working)
        }
    }

    // MARK: 品項與金額

    private func items(_ d: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("品項")
            RuledList {
                ForEach(d.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.name).textRole(.body).foregroundStyle(Theme.ink)
                            if let v = line.variant { Text(v).textRole(.xs).foregroundStyle(Theme.muted) }
                        }
                        Text("× \(line.quantity)").textRole(.small).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(ntd(cents: line.totalCents))
                            .font(.brand(15, .medium).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 12)
                }
            }
            VStack(spacing: 8) {
                amountRow("小計", d.subtotalCents)
                amountRow("運費", d.shippingFeeCents, zero: "免運")
                if d.discounts.isEmpty {
                    if d.discountCents > 0 { amountRow("折扣", -d.discountCents) }
                } else {
                    ForEach(d.discounts) { discountRow($0) }
                }
                if d.refundCents > 0 { amountRow("已退款", -d.refundCents) }
            }
            .id("amounts")
            HStack(alignment: .firstTextBaseline) {
                Text("合計").textRole(.h4)
                Spacer()
                Text(ntd(cents: d.totalCents)).font(.brand(22, .medium).monospacedDigit())
            }
            .foregroundStyle(Theme.ink)
            .padding(.top, 4)
        }
    }

    private func amountRow(_ label: String, _ cents: Int, zero: String? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(cents == 0 && zero != nil ? zero ?? "" : (cents < 0 ? "−" + ntd(cents: -cents) : ntd(cents: cents)))
                .monospacedDigit()
        }
        .textRole(.small)
        .foregroundStyle(Theme.ink2)
    }

    /// 一筆折扣：名稱、折價碼・優惠，金額；點了看那張折價券（誰用過、還剩幾次）
    @ViewBuilder
    private func discountRow(_ x: OrderDiscount) -> some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: 8) {
            HeroIcon(x.type == "free_shipping" ? "truck" : x.personalized ? "sparkles" : "ticket", size: 14)
                .foregroundStyle(Theme.accentText)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            VStack(alignment: .leading, spacing: 2) {
                Text(x.title)
                    .foregroundStyle(Theme.ink)
                if !x.detail.isEmpty {
                    Text(x.detail)
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            Text("−" + ntd(cents: x.cents))
                .monospacedDigit()
            if x.couponID != nil && canOpenCoupon {
                HeroIcon("chevron-right", size: 12)
                    .foregroundStyle(Theme.faint)
            }
        }
        .textRole(.small)
        .foregroundStyle(Theme.ink2)
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)

        if let id = x.couponID, canOpenCoupon {
            NavigationLink(value: Route.record(site: site, entity: "coupon", id: id)) { label }
                .buttonStyle(.row)
                .accessibilityHint("看這張折價券")
        } else {
            label
        }
    }

    // MARK: 收件

    private func customer(_ d: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("收件")
            RuledList(color: Theme.hair) {
                memberRow(d)
                infoRow("姓名", d.summary.customer)
                if !d.phone.isEmpty, let tel = URL(string: "tel:\(d.phone.filter { $0.isNumber || $0 == "+" })") {
                    Button { openURL(tel) } label: { infoRow("電話", d.phone, link: true) }
                        .buttonStyle(.row)
                }
                if let email = d.email, let mail = URL(string: "mailto:\(email)") {
                    Button { openURL(mail) } label: { infoRow("Email", email, link: true, oneLine: true) }
                        .buttonStyle(.row)
                }
                infoRow(d.shippingMethod, d.address)
                if let code = d.cvsPaymentNo { infoRow("7-11 取貨單號", code) }
                if let note = d.note { infoRow("備註", note) }
            }
        }
    }

    /// 下單的會員：頭像、名字、等級、買過幾次；點了看會員頁（消費、分群、其他訂單、發折價券）
    @ViewBuilder
    private func memberRow(_ d: OrderDetail) -> some View {
        if let m = d.member {
            let facts = [
                m.tier,
                m.paidOrderCount > 0 ? "買過 \(m.paidOrderCount) 次" : nil,
                m.lifetimeSpendCents > 0 ? "累積 " + ntd(cents: m.lifetimeSpendCents) : nil,
            ].compactMap { $0 }
            let label = HStack(spacing: 12) {
                Avatar(name: m.name ?? m.email ?? "?", size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.name ?? m.email ?? "會員")
                        .textRole(.body)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(facts.isEmpty ? "會員" : facts.joined(separator: "・"))
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if canOpenMember {
                    Text("會員頁")
                        .textRole(.xs)
                        .foregroundStyle(Theme.accentText)
                    HeroIcon("chevron-right", size: 12)
                        .foregroundStyle(Theme.accentText)
                }
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)

            if canOpenMember {
                NavigationLink(value: Route.member(site: site, id: m.id)) { label }
                    .buttonStyle(.row)
                    .accessibilityHint("打開會員頁")
            } else {
                label
            }
        } else if d.isGuest {
            infoRow("會員", "訪客結帳（沒有登入會員）")
        }
    }

    // MARK: 付款、物流、發票

    private func payment(_ d: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("付款・物流・發票")
            RuledList(color: Theme.hair) {
                infoRow("付款", d.paymentLabel + (d.summary.paidAt.map { "・\($0.shortText) 付款" } ?? ""))
                if let b = d.bankTransfer {
                    VStack(alignment: .leading, spacing: 4) {
                        infoRow("客人回報", "\(b.name ?? "—")・後五碼 \(b.last5 ?? "—")")
                        Text(b.awaiting ? "這是客人說的，還沒對帳" + (b.deadline.map { "・\($0.shortText) 前沒收到會自動取消" } ?? "") : "已確認收款")
                            .textRole(.xs)
                            .foregroundStyle(b.awaiting ? Theme.warningFG : Theme.successFG)
                            .padding(.bottom, 8)
                    }
                }
                if let tracking = d.trackingNumber { infoRow("物流單號", tracking) }
                if let logistics = d.logisticsStatus {
                    infoRow("貨態", logistics + (d.logisticsUpdatedAt.map { "・\($0.shortText)" } ?? ""))
                }
                if let waybill = d.waybillURL {
                    Button { openURL(waybill) } label: { infoRow("託運單", "打開 PDF", link: true) }
                        .buttonStyle(.row)
                }
                if let invoice = d.invoiceNumber { infoRow("發票號碼", invoice) }
                if let text = d.invoiceText { infoRow("發票", text) }
                if let note = d.refundNote { infoRow("退款備註", note) }
            }
        }
    }

    @ViewBuilder
    private func links(_ d: OrderDetail) -> some View {
        HStack(spacing: 10) {
            if let track = d.trackURL {
                ShareLink(item: track, subject: Text("訂單 #\(d.summary.number) 的追蹤頁")) {
                    Text("分享追蹤頁")
                }
                .buttonStyle(.brand(.ghost, fullWidth: true))
            }
            if let slip = d.packingSlipURL {
                Button { openURL(slip) } label: { Text("出貨單 ↗") }
                    .buttonStyle(.brand(.ghost, fullWidth: true))
            }
        }
    }

    /// oneLine：Email 這類不能斷行的（iPad 的窄欄放不下時先縮小一點，再不行中間省略，不會拆成三行）
    private func infoRow(_ label: String, _ text: String, link: Bool = false, oneLine: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .textRole(.xs)
                .foregroundStyle(Theme.muted)
                .frame(width: 84, alignment: .leading)
            Text(text)
                .textRole(.body)
                .foregroundStyle(link ? Theme.accentText : Theme.ink)
                .lineLimit(oneLine ? 1 : nil)
                .minimumScaleFactor(oneLine ? 0.8 : 1)
                // 中間省略只給一行的（多行的文字用了會被擠成一行，例如地址）
                .truncationMode(oneLine ? .middle : .tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}

/// 標記出貨：可以順便填物流單號
private struct ShipSheet: View {
    /// 已經出貨、改單號：現在的單號（nil＝標記出貨）
    var editing: String?
    var onSubmit: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tracking = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Headline(editing == nil ? "Mark as *shipped*" : "Tracking *number*", role: .h2)
                FieldBlock(label: "物流單號（選填）", hint: "黑貓的單號填了之後，網站每 15 分鐘自動更新貨態", focused: focused) {
                    TextField("例如黑貓的託運單號", text: $tracking)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .fieldText()
                }
                Text("下一步會出網站的確認，按了才會改。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("下一步") {
                    let t = tracking.trimmingCharacters(in: .whitespaces)
                    dismiss()
                    onSubmit(t.isEmpty ? nil : t)
                }
                .buttonStyle(.brand(.accent, size: .lg, fullWidth: true, arrow: true))
            }
            .padding(24)
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(380)])
        .onAppear {
            if let editing, tracking.isEmpty { tracking = editing }
            focused = true
        }
    }
}

/// 退款：金額（元，預設全額退剩下的）與備註
private struct RefundSheet: View {
    let totalCents: Int
    var onSubmit: (Int?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""
    @FocusState private var focused: Int?

    private var maxNtd: Int { Int((Double(totalCents) / 100).rounded()) }

    /// 只收半形數字；空白＝全額退剩下的
    private var typed: Int? {
        let t = amount.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(t)
    }

    /// 金額有填就要在 1 到剩下的金額之間（填錯不會變成全額退款）
    private var valid: Bool {
        let t = amount.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        guard let n = typed else { return false }
        return n >= 1 && n <= maxNtd
    }

    /// 部分退款的金額；全額（空白或等於剩下的金額）送 nil
    private var partial: Int? {
        guard let n = typed, n < maxNtd else { return nil }
        return n
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Headline("*Refund*", role: .h2)
                FieldBlock(label: "退多少（元）", hint: "空白＝全額退剩下的 NT$\(maxNtd.formatted())", error: valid ? nil : "請填 1 到 \(maxNtd) 之間的整數", focused: focused == 0) {
                    HStack(spacing: 6) {
                        Text("NT$").foregroundStyle(Theme.muted)
                        TextField("\(maxNtd)", text: $amount)
                            .keyboardType(.numberPad)
                            .focused($focused, equals: 0)
                    }
                    .fieldText()
                }
                FieldBlock(label: "備註（選填）", focused: focused == 1) {
                    TextField("例如：延誤補償", text: $note)
                        .focused($focused, equals: 1)
                        .fieldText()
                }
                Text("下一步會出網站的確認，要打「退款」才會執行；金額超過門檻還要店主的驗證碼。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("下一步") {
                    dismiss()
                    onSubmit(partial, note.trimmingCharacters(in: .whitespaces))
                }
                .buttonStyle(.brand(.danger, size: .lg, fullWidth: true))
                .disabled(!valid)
            }
            .padding(24)
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
