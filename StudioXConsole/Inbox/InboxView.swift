import SwiftUI

/// 客服收件匣（網站後台的 /admin/inbox，三個網站放在一起）：Xena 轉來的對話、留了聯絡資料的訪客。
/// 狀態：Xena 處理中 → 等你回覆（Xena 繼續幫忙）→ 你接手中（Xena 不再回答）→ 已結案
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .needsYou

    enum Filter: String, CaseIterable, Identifiable {
        case needsYou = "等你"
        case xena = "Xena 處理中"
        case all = "全部"

        var id: Self { self }
    }

    private var list: [Conversation] {
        switch filter {
        case .needsYou: model.conversations.filter { $0.status == .waiting || ($0.status == .human && $0.lastFromVisitor) }
        case .xena: model.conversations.filter { $0.status == .ai }
        case .all: model.conversations
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.inboxPath) {
            List {
                Section {
                    ForEach(list) { conversation in
                        NavigationLink(value: Route.conversation(conversation.id)) {
                            ConversationRow(conversation: conversation)
                        }
                    }
                } header: {
                    Picker("篩選", selection: $filter) {
                        ForEach(Filter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.bottom, 8)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Brand.paper.ignoresSafeArea())
            .overlay {
                if list.isEmpty {
                    ContentUnavailableView("沒有等你的對話", systemImage: "checkmark.bubble", description: Text("Xena 都處理好了。"))
                }
            }
            .animation(.smooth, value: filter)
            .navigationTitle("收件匣")
            .refreshable { await model.refresh() }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InitialAvatar(name: conversation.visitor, size: 40, tint: conversation.status.tone.color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.visitor)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Text(conversation.preview)
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    StatusPill(text: conversation.status.label, tone: conversation.status.tone)
                    StatusPill(text: conversation.category, tone: .muted)
                    if let site = model.site(conversation.siteID) {
                        SiteChip(site: site)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 一段客服對話：看 Xena 跟訪客說了什麼、接手、回覆、交還 Xena、結案
struct ConversationView: View {
    let conversationID: String
    @Environment(AppModel.self) private var model
    @State private var reply = ""
    @State private var sending = false

    var body: some View {
        if let c = model.conversation(conversationID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    triage(c)
                    ForEach(c.lines) { line in
                        LineBubble(line: line)
                    }
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .background(Brand.paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar(c)
            }
            .navigationTitle(c.visitor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if c.status != .ai && c.status != .closed {
                            Button("交還 Xena", systemImage: "arrow.uturn.backward") {
                                Task { await model.setStatus(.ai, conversation: c.id) }
                            }
                        }
                        if c.status != .closed {
                            Button("結案", systemImage: "checkmark.seal") {
                                Task { await model.setStatus(.closed, conversation: c.id) }
                            }
                        }
                        Button("請 Xena 擬回覆", systemImage: "sparkles") {
                            model.askXena("幫我擬一段回覆給\(c.visitor)", site: c.siteID)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        } else {
            ContentUnavailableView("找不到這段對話", systemImage: "bubble.left.and.exclamationmark.bubble.right")
        }
    }

    /// Jev 的分類與判斷（只有後台看得到）
    private func triage(_ c: Conversation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .foregroundStyle(XenaPalette.violet)
            VStack(alignment: .leading, spacing: 2) {
                Text("Jev 分類：\(c.category)")
                    .font(.footnote.weight(.semibold))
                Text(c.humanScore >= 0.8 ? "判斷需要專人（\(Int(c.humanScore * 100))%）" : "Xena 可以自己處理（要找人 \(Int(c.humanScore * 100))%）")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Spacer()
            if let site = model.site(c.siteID) {
                SiteChip(site: site)
            }
        }
        .padding(12)
        .background(XenaPalette.violet.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func bottomBar(_ c: Conversation) -> some View {
        switch c.status {
        case .ai, .waiting:
            HStack(spacing: 10) {
                Button {
                    Task { await model.setStatus(.human, conversation: c.id) }
                } label: {
                    Label("接手對話", systemImage: "person.fill.checkmark")
                }
                .buttonStyle(.pill(.dark, compact: true))
                Button {
                    model.askXena("幫我擬一段回覆給\(c.visitor)", site: c.siteID)
                } label: {
                    Label("請 Xena 擬", systemImage: "sparkles")
                }
                .buttonStyle(.pill(.light, compact: true))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        case .human:
            HStack(alignment: .bottom, spacing: 6) {
                TextField("回覆\(c.visitor)…", text: $reply, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.vertical, 13)
                    .padding(.leading, 18)
                Button {
                    let text = reply
                    reply = ""
                    sending = true
                    Task {
                        await model.reply(text, conversation: c.id)
                        sending = false
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Brand.accent)
                .disabled(sending || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(5)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        case .closed:
            HStack {
                Label("已結案", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Brand.muted)
                Spacer()
                Button("重新打開") {
                    Task { await model.setStatus(.human, conversation: c.id) }
                }
                .buttonStyle(.glass)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

private struct LineBubble: View {
    let line: ChatLine

    var body: some View {
        switch line.author {
        case .visitor:
            HStack {
                Text(line.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Brand.raised, in: .rect(cornerRadius: 18))
                Spacer(minLength: 48)
            }
        case .xena:
            HStack(alignment: .top, spacing: 8) {
                OrbDot(size: 18)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Xena")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                    Text(line.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(XenaPalette.violet.opacity(0.09), in: .rect(cornerRadius: 18))
                }
                Spacer(minLength: 40)
            }
        case .staff(let name):
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                    Text(line.text)
                        .foregroundStyle(Brand.onInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Brand.ink, in: .rect(cornerRadius: 18))
                }
            }
        }
    }
}
