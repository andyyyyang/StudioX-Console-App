import PhotosUI
import SwiftUI
import UIKit

/// 圖片（商品、組合、文章封面、作品封面）：第一張是主圖。
///   - 上傳：從相簿選（可以一次選好幾張），App 縮到長邊 2400、轉 JPEG，用網站的一次性上傳連結送過去
///     （和手機上點連結上傳同一條路：存恢復點、通知店主、稽核）
///   - 移除、換主圖：網站列出前後張數讓你確認
struct ImageGallery: View {
    let site: String
    let entity: String
    let id: String
    var single = false
    @Binding var images: [String]

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var picked: [PhotosPickerItem] = []
    @State private var uploading = 0
    @State private var uploaded = 0
    @State private var proposal: Proposal?
    @State private var viewing: String?

    var body: some View {
        // PhotosPicker 的 label 是 @Sendable：先把要顯示的字算好，裡面不讀畫面的狀態
        let pickTitle = uploading > 0 ? "上傳中 \(uploaded)/\(uploading)…" : single && !images.isEmpty ? "換一張" : "＋ 上傳"
        let emptyAspect: CGFloat = single ? 1600 / 840 : 4 / 3
        let accent = Theme.accent, muted = Theme.muted, line = Theme.line
        let glyphFont = Font.brand(22), smallFont = Font.brand(13.5, .regular, relativeTo: .subheadline)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(single ? "封面" : "圖片・\(images.count) 張（第一張是主圖）")
                Spacer()
                PhotosPicker(selection: $picked, maxSelectionCount: single ? 1 : 10, matching: .images) {
                    Text(pickTitle)
                }
                .buttonStyle(.brand(.ghost, size: .sm))
                .disabled(uploading > 0 || id.isEmpty)
            }

            if images.isEmpty {
                PhotosPicker(selection: $picked, maxSelectionCount: single ? 1 : 10, matching: .images) {
                    VStack(spacing: 8) {
                        Text("✳").font(glyphFont).foregroundStyle(accent)
                        Text("還沒有圖片，點這裡從相簿選")
                            .font(smallFont)
                            .foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(emptyAspect, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                }
                .buttonStyle(.press)
                .disabled(uploading > 0 || id.isEmpty)
            } else if single, let first = images.first {
                RemoteImage(url: URL(string: first), aspect: 1600 / 840, radius: Metric.radiusLg)
                    .onTapGesture { viewing = first }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(images.enumerated()), id: \.element) { index, url in
                            RemoteImage(url: URL(string: url), aspect: 1)
                                .frame(width: sizeClass == .regular ? 220 : 150)
                                .overlay(alignment: .topLeading) {
                                    if index == 0 { StatusBadge("主圖", tone: .gold).padding(8) }
                                }
                                .contextMenu {
                                    Button("看大圖") { viewing = url }
                                    if index > 0 {
                                        Button("設成主圖") { Task { await propose(setCover: url) } }
                                    }
                                    Button("移除", role: .destructive) { Task { await propose(remove: url) } }
                                }
                                .onTapGesture { viewing = url }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                Text("長按圖片可以設成主圖或移除。")
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await upload(items) }
        }
        .confirmSheet($proposal, siteName: { model.site($0)?.name ?? $0 }) { result in
            if let list = result["images"]?.array {
                withAnimation(Motion.ease) { images = list.compactMap { $0["url"]?.string ?? $0.string } }
            }
            model.show("圖片已更新")
        }
        .sheet(item: Binding(get: { viewing.map(ViewingImage.init) }, set: { viewing = $0?.url })) { item in
            ImageViewer(url: URL(string: item.url))
        }
    }

    private struct ViewingImage: Identifiable {
        let url: String
        var id: String { url }
    }

    // MARK: 上傳

    private func upload(_ items: [PhotosPickerItem]) async {
        uploading = items.count
        uploaded = 0
        defer {
            uploading = 0
            picked = []
        }
        for item in items {
            do {
                guard let raw = try await item.loadTransferable(type: Data.self), let jpeg = Self.prepare(raw) else {
                    model.show("讀不到這張圖片", tone: .danger)
                    continue
                }
                let next = try await model.api.uploadImage(site: site, entity: entity, id: id, data: jpeg, mime: "image/jpeg")
                uploaded += 1
                withAnimation(Motion.ease) { images = next }
            } catch {
                model.show(error.localizedDescription, tone: .danger)
                return
            }
        }
        model.show(uploaded == 1 ? "已上傳 1 張圖片" : "已上傳 \(uploaded) 張圖片")
    }

    /// 長邊最多 2400、JPEG（網站的上限是 5MB）
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2400 / max(longest, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.86, 0.78, 0.68, 0.55] {
            if let jpeg = resized.jpegData(compressionQuality: quality), jpeg.count < 4_800_000 { return jpeg }
        }
        return nil
    }

    // MARK: 移除、換主圖（要確認）

    private func propose(remove url: String) async {
        do {
            let outcome = try await model.api.proposeImages(site: site, entity: entity, id: id, remove: [url])
            if case .needsConfirmation(let p) = outcome { proposal = p }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }

    private func propose(setCover url: String) async {
        do {
            let outcome = try await model.api.proposeImages(site: site, entity: entity, id: id, setCover: url)
            if case .needsConfirmation(let p) = outcome { proposal = p }
        } catch {
            model.show(error.localizedDescription, tone: .danger)
        }
    }
}

/// 看大圖（可以縮放）
struct ImageViewer: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation(Motion.spring) { scale = 1 } })
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
                if let url {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: url)
                    }
                }
            }
        }
    }
}
