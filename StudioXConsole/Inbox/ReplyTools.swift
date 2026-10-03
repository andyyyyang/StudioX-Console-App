import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// 客服對話（Xena 對話）輸入列左邊的「＋」：Xena 擬回覆、潤飾、交給 Xena；附照片、拍照、檔案；
// 折價券、發專屬折價券、商品卡片、行銷卡片；常用回覆、訂單進度；會員資料。
// 附的東西排在輸入框上面一排（照片一選就開始傳到網站），按送出時跟文字一起交給網站的 reply_xena。

// MARK: - 回覆裡附的東西

/// 輸入框上面一排：照片、檔案、行銷卡片、商品卡片
struct ReplyExtras {
    var files: [StagedFile] = []
    var card: StaffCard?
    var products: [ProductPick] = []

    var isEmpty: Bool { files.isEmpty && card == nil && products.isEmpty }
    var uploading: Bool { files.contains { $0.state == .uploading } }
    var failed: Bool { files.contains { $0.failure != nil } }
    var uploaded: [UploadedAttachment] {
        files.compactMap { f -> UploadedAttachment? in
            if case .ready(let a) = f.state { return a }
            return nil
        }
    }

    /// 只附東西沒打字時，送出中的泡泡寫這一句
    var summary: String {
        let photos = files.filter(\.isImage).count
        let docs = files.count - photos
        return [
            photos > 0 ? "照片 \(photos) 張" : nil,
            docs > 0 ? "檔案 \(docs) 個" : nil,
            card.map { "卡片「\($0.title)」" },
            products.isEmpty ? nil : "商品 \(products.count) 樣",
        ]
        .compactMap { $0 }
        .joined(separator: "、")
    }
}

/// 一個要附的照片或檔案：一選就開始傳到網站，傳好才送得出去
struct StagedFile: Identifiable {
    enum State: Equatable { case uploading, ready(UploadedAttachment), failed(String) }

    let id = UUID()
    var name: String
    var mime: String
    var data: Data
    var thumbnail: UIImage?
    var state: State = .uploading

    var isImage: Bool { mime.hasPrefix("image/") }
    var failure: String? {
        if case .failed(let message) = state { return message }
        return nil
    }
}

/// 推薦的商品（網站認得的商品代號）
struct ProductPick: Identifiable, Hashable {
    var id: String
    var name: String
    var price: String?
    var image: URL?
}

// MARK: - 照片、檔案的處理

nonisolated enum ReplyMedia {
    /// 照片轉成 JPEG：LINE 的圖片訊息只收 JPEG／PNG、預覽圖 1MB 以內——長邊最多 2048，壓到 limit 以內
    static func jpeg(from data: Data, limit: Int) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        for edge in [2048.0, 1600, 1280, 1024] {
            let scaled = scaled(image, maxEdge: edge)
            for quality in [0.82, 0.72, 0.62, 0.5] {
                if let d = scaled.jpegData(compressionQuality: quality), d.count <= limit { return d }
            }
        }
        return nil
    }

    private static func scaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        // 不用縮也重畫一次：把相機的方向轉正
        let k = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// 可以附的檔案（網站也只收這些：PDF、Office、Apple 的文件、文字檔、ZIP、照片）
    static let fileTypes: [UTType] = {
        let extra = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key"].compactMap { UTType(filenameExtension: $0) }
        return [.pdf, .plainText, .commaSeparatedText, .zip, .image] + extra
    }()

    /// 檔名的類型（application/pdf…）
    static func mime(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType ?? "application/octet-stream"
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - 「＋」的選單

/// 選單打開的 sheet
enum ReplySheet: String, Identifiable {
    case coupons, issue, products, card, saved
    var id: String { rawValue }
}

enum ReplyTool: Hashable {
    case xenaDraft, xenaPolish, release, suggest
    case photos, camera, files
    case coupon, issueCoupon, products, card
    case saved, track
    case member
}

/// 選單上哪些能用（看網站支援什麼、這段對話的客人是誰）
struct ReplyMenuOptions {
    var hasDraft = false
    var canRelease = false
    /// 客人有新的話等專人回（可以叫出回覆建議）
    var canSuggest = false
    /// 照片、檔案的上限；nil＝網站還沒有檔案空間
    var attach: AttachLimits?
    var room = 4
    var coupons = false
    var issueCoupon = false
    var products = false
    var card = true
    var orders = false
    var member = false
}

struct ReplyMenuSheet: View {
    let options: ReplyMenuOptions
    let choose: (ReplyTool) -> Void
    @Environment(\.dismiss) private var dismiss

    private var camera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Xena 幫你") {
                        tile(.xenaDraft, "sparkles", options.hasDraft ? "照我寫的重點擬" : "擬一段回覆", tint: Theme.bubbleXena,
                             caption: options.hasDraft ? "把你打的當重點" : "讀完整段對話")
                        tile(.xenaPolish, "wand.and.stars", "潤飾我寫的", tint: Theme.bubbleXena,
                             caption: options.hasDraft ? nil : "先打一段", enabled: options.hasDraft)
                        if options.canSuggest {
                            tile(.suggest, "text.bubble", "回覆建議", tint: Theme.bubbleXena,
                                 caption: options.hasDraft ? "輸入框空的時候" : "三句下一句", enabled: !options.hasDraft)
                        }
                        if options.canRelease {
                            tile(.release, "arrow.uturn.backward.circle", "交給 Xena 回答", tint: Theme.bubbleXena, caption: "她接著回客人")
                        }
                    }
                    section("附上") {
                        let attach = options.attach != nil && options.room > 0
                        let off: String? = options.attach == nil ? "還沒有空間" : options.room > 0 ? nil : "最多 \(options.attach?.max ?? 4) 個"
                        tile(.photos, "photo.on.rectangle", "照片", tint: Theme.chart[1], caption: off, enabled: attach)
                        if camera {
                            tile(.camera, "camera", "拍照", tint: Theme.chart[1], caption: off, enabled: attach)
                        }
                        tile(.files, "doc", "檔案", tint: Theme.chart[1], caption: off, enabled: attach)
                        if options.coupons {
                            tile(.coupon, "ticket", "折價券", tint: Theme.chart[0], caption: "附上現有的")
                        }
                        if options.issueCoupon {
                            tile(.issueCoupon, "gift", "發專屬券", tint: Theme.chart[0], caption: "給這位會員")
                        }
                        if options.products {
                            tile(.products, "bag", "商品", tint: Theme.chart[0], caption: "商品卡片")
                        }
                        if options.card {
                            tile(.card, "rectangle.portrait.on.rectangle.portrait", "行銷卡片", tint: Theme.chart[0], caption: "大圖、按鈕")
                        }
                    }
                    section("快速") {
                        tile(.saved, "text.bubble", "常用回覆", tint: Theme.chart[2])
                        if options.orders {
                            tile(.track, "shippingbox", "訂單進度", tint: Theme.chart[2], caption: "附上追蹤頁")
                        }
                        if options.member {
                            tile(.member, "person.crop.circle", "會員資料", tint: Theme.chart[4])
                        }
                    }
                    if options.attach == nil {
                        Text("這個網站還沒有放照片、檔案的空間，請 StudioX 幫網站開主機的檔案空間，開好就能傳。")
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(20)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationTitle("加到回覆裡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { HeroIcon("x-mark") }
                        .accessibilityLabel("關閉")
                }
            }
        }
        // iPad 的表單視窗一半高度放不下：直接整張
        .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78, maximum: 120), spacing: 6, alignment: .top)], alignment: .leading, spacing: 16) {
                content()
            }
        }
    }

    private func tile(_ tool: ReplyTool, _ icon: String, _ title: String, tint: Color, caption: String? = nil, enabled: Bool = true) -> some View {
        Button { choose(tool) } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(enabled ? tint : Theme.faint)
                    .frame(width: 56, height: 56)
                    .background((enabled ? tint : Theme.muted).opacity(0.13), in: .rect(cornerRadius: 16, style: .continuous))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(enabled ? Theme.ink : Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(PressScale(scale: 0.94))
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 輸入框上面：Xena 在寫、附的東西

struct ReplyAccessory: View {
    @Binding var extras: ReplyExtras
    let drafting: Bool
    let retry: (StagedFile.ID) -> Void
    let editCard: () -> Void
    let editProducts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if drafting {
                HStack(spacing: 8) {
                    XenaOrb(mood: .thinking, size: 16)
                    Text("Xena 正在讀對話、寫回覆…")
                        .textRole(.xs)
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.horizontal, 6)
                .transition(.opacity)
            }
            if !extras.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(extras.files) { file in
                            fileChip(file)
                        }
                        if let card = extras.card {
                            chip(icon: "rectangle.portrait.on.rectangle.portrait", title: card.title, detail: card.couponCode.map { "優惠碼 \($0)" } ?? "行銷卡片", action: editCard) {
                                extras.card = nil
                            }
                        }
                        if !extras.products.isEmpty {
                            chip(icon: "bag", title: "商品 \(extras.products.count) 樣", detail: extras.products.map(\.name).joined(separator: "、"), action: editProducts) {
                                extras.products = []
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.fast, value: drafting)
    }

    @ViewBuilder
    private func fileChip(_ file: StagedFile) -> some View {
        if file.isImage {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb = file.thumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Theme.soft
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .overlay { status(file) }
                .onTapGesture { if file.failure != nil { retry(file.id) } }
                remove(file.id)
            }
            .accessibilityLabel(file.failure.map { "照片沒傳上去：\($0)" } ?? "照片")
        } else {
            chip(icon: "doc", title: file.name, detail: file.failure ?? ReplyMedia.size(file.data.count), failed: file.failure != nil, uploading: file.state == .uploading) {
                if file.failure != nil { retry(file.id) }
            } remove: {
                extras.files.removeAll { $0.id == file.id }
            }
        }
    }

    @ViewBuilder
    private func status(_ file: StagedFile) -> some View {
        switch file.state {
        case .uploading:
            ZStack {
                Color.black.opacity(0.35)
                ProgressView().controlSize(.small).tint(.white)
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
        case .failed:
            ZStack {
                Color.black.opacity(0.5)
                Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
        case .ready:
            EmptyView()
        }
    }

    private func remove(_ id: StagedFile.ID) -> some View {
        Button {
            withAnimation(Motion.fast) { extras.files.removeAll { $0.id == id } }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.black.opacity(0.6), in: .circle)
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
        .accessibilityLabel("拿掉")
    }

    private func chip(icon: String, title: String, detail: String, failed: Bool = false, uploading: Bool = false, action: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Group {
                        if uploading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: failed ? "arrow.clockwise" : icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(failed ? Theme.dangerFG : Theme.accentText)
                        }
                    }
                    .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(failed ? Theme.dangerFG : Theme.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 170, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(Motion.fast) { remove() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("拿掉")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 7)
        .background(Theme.bubbleIn, in: .rect(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 拍照

struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            done(nil)
        }
    }
}

// MARK: - 折價券

/// 附上一張現有的折價券：做成行銷卡片（標題、說明、優惠碼、按鈕），附上之後還可以改
struct CouponPickerSheet: View {
    let site: String
    let pick: (StaffCard) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [RecordSummary]?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("選一張啟用中的折價券，會做成一張卡片附在回覆裡（LINE 上是品牌樣式的卡片，客人可以直接複製優惠碼）。")
                        .textRole(.small)
                        .foregroundStyle(Theme.ink2)
                    if let rows {
                        if rows.isEmpty {
                            EmptyState(title: "沒有啟用中的折價券", message: "可以在「網站 → 折價券」新增一張。")
                        } else {
                            RuledList {
                                ForEach(rows) { row in
                                    Button { choose(row) } label: {
                                        CouponRow(row: row)
                                            .padding(.vertical, 12)
                                            .contentShape(.rect)
                                    }
                                    .buttonStyle(.row)
                                }
                            }
                        }
                    } else if let error {
                        ErrorNote(message: error) { Task { await load() } }
                    } else {
                        SkeletonRows(rows: 4)
                    }
                }
                .padding(20)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationTitle("附上折價券")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            rows = try await model.api.list(site: site, entity: "coupon", filters: ["activeOnly": true]).rows
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func choose(_ row: RecordSummary) {
        let r = row.raw
        let code = r["code"]?.string ?? row.title
        let name = r["name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let offer = r["discountLabel"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let note = r["description"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        pick(StaffCard(
            title: name ?? offer.map { "\($0) 優惠" } ?? "專屬優惠",
            body: note ?? "結帳時輸入優惠碼就能使用\(offer.map { "，\($0)" } ?? "")。",
            couponCode: code,
            buttonLabel: "去逛逛",
            url: model.site(site)?.url
        ))
        dismiss()
    }
}

// MARK: - 商品

/// 推薦商品：選 1–10 樣，LINE 上是左右滑的商品卡片，官網上是一串連結
struct ProductPickerSheet: View {
    let site: String
    let initial: [ProductPick]
    let done: ([ProductPick]) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var rows: [RecordSummary]?
    @State private var error: String?
    @State private var picked: [ProductPick] = []

    var body: some View {
        NavigationStack {
            List {
                if let rows {
                    ForEach(rows) { row in
                        let pick = Self.pick(row)
                        let on = picked.contains { $0.id == pick.id }
                        Button { toggle(pick) } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: pick.image) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Theme.soft
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pick.name).textRole(.body).foregroundStyle(Theme.ink).lineLimit(2)
                                    if let price = pick.price { Text(price).textRole(.xs).foregroundStyle(Theme.muted) }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(on ? Theme.primary : Theme.faint)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                } else if let error {
                    ErrorNote(message: error) { Task { await load() } }
                        .listRowBackground(Color.clear)
                } else {
                    SkeletonRows(rows: 5)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { Theme.sheet.ignoresSafeArea() }
            .searchable(text: $query, prompt: "找商品")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 300))
                await load()
            }
            .navigationTitle(picked.isEmpty ? "推薦商品" : "推薦商品（\(picked.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        done(picked)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { picked = initial }
    }

    private static func pick(_ row: RecordSummary) -> ProductPick {
        let r = row.raw
        let slug = r["slug"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? row.id
        return ProductPick(id: slug, name: row.title, price: r["priceLabel"]?.string ?? row.subtitle, image: row.image)
    }

    private func toggle(_ pick: ProductPick) {
        if let i = picked.firstIndex(where: { $0.id == pick.id }) {
            picked.remove(at: i)
        } else if picked.count < 10 {
            picked.append(pick)
        } else {
            model.show("一次最多推薦 10 樣", tone: .warning)
        }
    }

    private func load() async {
        error = nil
        do {
            rows = try await model.api.list(site: site, entity: "product", query: query, filters: ["publishedOnly": true]).rows
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 行銷卡片

/// 寫一張行銷卡片（大圖、標題、說明、優惠碼、按鈕）：LINE 上照網站品牌畫成卡片，官網上換成一段文字
struct CardEditorSheet: View {
    let initial: StaffCard?
    let siteURL: URL?
    let save: (StaffCard?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var coupon = ""
    @State private var button = ""
    @State private var link = ""
    @State private var image = ""

    private func https(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("https://"), let url = URL(string: t) else { return nil }
        return url
    }

    private var linkOK: Bool { link.trimmingCharacters(in: .whitespaces).isEmpty || https(link) != nil }
    private var imageOK: Bool { image.trimmingCharacters(in: .whitespaces).isEmpty || https(image) != nil }
    private var valid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && title.count <= 40 && linkOK && imageOK }

    private var card: StaffCard {
        StaffCard(
            title: title.trimmingCharacters(in: .whitespaces),
            body: text.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: https(image),
            couponCode: coupon.trimmingCharacters(in: .whitespaces).uppercased(),
            buttonLabel: button.trimmingCharacters(in: .whitespaces),
            url: https(link) ?? siteURL
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                        StaffCardView(card: card)
                            .frame(maxWidth: 300)
                            .frame(maxWidth: .infinity)
                    }
                    FieldBlock(label: "標題", required: true, error: title.count > 40 ? "最多 40 字" : nil) {
                        TextField("例如：中秋禮盒 9 折", text: $title).fieldText()
                    }
                    FieldBlock(label: "說明", hint: "兩三句講好處") {
                        TextField("例如：中秋前下單，3 盒以上打 9 折，寄台北隔天到。", text: $text, axis: .vertical)
                            .lineLimit(2...6)
                            .fieldText()
                    }
                    FieldBlock(label: "優惠碼", hint: "要是網站上真的存在、啟用中的") {
                        TextField("例如：MOON10", text: $coupon)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .fieldText()
                    }
                    FieldBlock(label: "按鈕的字", hint: "最多 20 字") {
                        TextField("去看看", text: $button).fieldText()
                    }
                    FieldBlock(label: "按鈕打開的網址", hint: "沒填就是網站首頁", error: linkOK ? nil : "要是 https:// 開頭的網址") {
                        TextField(siteURL?.absoluteString ?? "https://", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .fieldText()
                    }
                    FieldBlock(label: "大圖網址（選填）", hint: "https 的 JPEG／PNG；商品圖可以從商品頁複製圖片網址", error: imageOK ? nil : "要是 https:// 開頭的網址") {
                        TextField("https://", text: $image)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .fieldText()
                    }
                    if initial != nil {
                        Button("拿掉這張卡片", role: .destructive) {
                            save(nil)
                            dismiss()
                        }
                        .buttonStyle(.brand(.ghost, fullWidth: true))
                    }
                }
                .padding(20)
            }
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationTitle(initial == nil ? "行銷卡片" : "改卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("附上") {
                        save(card)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
        }
        .onAppear {
            guard let c = initial else { return }
            title = c.title
            text = c.body ?? ""
            coupon = c.couponCode ?? ""
            button = c.buttonLabel ?? ""
            link = c.url?.absoluteString ?? ""
            image = c.imageURL?.absoluteString ?? ""
        }
    }
}

// MARK: - 常用回覆

/// 常用回覆：存在這台裝置上；點一下放進輸入框（不會直接送出），可以把正在寫的存起來、往左滑刪掉
struct SavedRepliesSheet: View {
    let current: String
    let insert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("savedReplies") private var stored = ""

    private static let starters = [
        "不好意思讓你久等了，我是真人客服，馬上幫你確認！",
        "收到，我確認好之後馬上回覆你，請稍等一下 🙏",
        "謝謝你的耐心！之後有任何問題都可以直接在這裡問我們。",
    ]

    private var replies: [String] {
        guard let data = stored.data(using: .utf8), let list = try? JSONDecoder().decode([String].self, from: data) else { return Self.starters }
        return list
    }

    private func write(_ list: [String]) {
        if let data = try? JSONEncoder().encode(list), let s = String(data: data, encoding: .utf8) { stored = s }
    }

    private var draft: String { current.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if !draft.isEmpty && !replies.contains(draft) {
                    Section {
                        Button {
                            write([draft] + replies)
                        } label: {
                            Label("把正在寫的存成常用回覆", systemImage: "plus.circle")
                                .foregroundStyle(Theme.accentText)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                Section {
                    ForEach(replies, id: \.self) { reply in
                        Button {
                            insert(reply)
                            dismiss()
                        } label: {
                            Text(reply)
                                .textRole(.body)
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        var list = replies
                        list.remove(atOffsets: offsets)
                        write(list)
                    }
                } footer: {
                    Text("點一下放進輸入框，改好再送出。往左滑可以刪掉。只存在這台裝置上。")
                        .textRole(.xs)
                        .foregroundStyle(Theme.muted)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { Theme.sheet.ignoresSafeArea() }
            .navigationTitle("常用回覆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } }
            }
        }
        .presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
    }
}
