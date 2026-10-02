import SwiftUI

/// 首頁就是 Xena：24 小時值班的店長。
///   - 上面：水滴＋她跟你打招呼（一個字一個字打出來）
///   - 「需要你看一下」：她主動找你的事。要動手改的，按「交給 Xena」先出確認卡片，你確認了她才做
///   - 「我值班時做了這些」：昨晚到現在的值班紀錄（你確認的事也會記進來）
struct XenaHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    presence
                    if !model.openNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "需要你看一下", trailing: "\(model.openNotes.count) 件")
                            ForEach(model.openNotes) { note in
                                NoteCard(note: note)
                                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96))))
                            }
                        }
                    }
                    if !model.doneNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "處理好了")
                            ForEach(model.doneNotes) { note in
                                DoneNoteRow(note: note)
                            }
                        }
                    }
                    shiftLog
                    asks
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
                .animation(.smooth(duration: 0.45), value: model.notes)
            }
            .scrollIndicators(.hidden)
            .background {
                ZStack {
                    Brand.paper
                    AmbientField(intensity: 0.45)
                }
                .ignoresSafeArea()
            }
            .navigationTitle(Date.now.dayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showXena = true
                    } label: {
                        Image(systemName: "text.bubble")
                    }
                    .accessibilityLabel("跟 Xena 說話")
                }
            }
            .refreshable { await model.refresh() }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private var presence: some View {
        VStack(spacing: 14) {
            Button {
                model.showXena = true
            } label: {
                XenaOrb(mood: model.xenaMood, size: 132, pulse: model.xena.pulse)
            }
            .buttonStyle(.plain)
            .accessibilityHint("打開對話")

            VStack(spacing: 4) {
                Text("Xena")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.8)
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.xenaMood == .resting ? XenaPalette.violet : Brand.success)
                        .frame(width: 7, height: 7)
                    Text("店長 · \(model.xenaMood.label) · 24 小時在線")
                }
                .font(.footnote)
                .foregroundStyle(Brand.muted)
            }

            TypewriterText(text: model.greeting, animate: !model.greeted, speed: .milliseconds(30)) {
                model.greeted = true
            }
            .font(.system(size: 17))
            .foregroundStyle(Brand.ink)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var shiftLog: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "我值班時做了這些", trailing: "過去 14 小時")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.shiftLog.enumerated()), id: \.element.id) { index, entry in
                    ShiftRow(entry: entry, isLast: index == model.shiftLog.count - 1)
                }
            }
            .raisedCard(cornerRadius: 24, padding: 18)
        }
    }

    private var asks: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "你也可以問我")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(["今天營收多少？", "有誰在等我回覆？", "這週流量怎麼樣？", "幫博信國際起草一篇新消息", "你是誰？"], id: \.self) { prompt in
                        Button(prompt) { model.askXena(prompt) }
                            .buttonStyle(.glass)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

/// Xena 主動找你的一件事
private struct NoteCard: View {
    let note: XenaNote
    @Environment(AppModel.self) private var model
    @State private var confirming = false
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: note.kind.symbol)
                    .foregroundStyle(note.kind.tone.color)
                if let site = model.site(note.siteID) {
                    SiteChip(site: site)
                }
                Spacer()
                Text(note.at, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Text(note.title)
                .font(.system(size: 17, weight: .semibold))
            Text(note.body)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let card = note.proposal {
                if confirming {
                    ConfirmCardView(card: card, busy: busy) { approve, _ in
                        busy = true
                        Task {
                            await model.decideNote(note, approve: approve)
                            busy = false
                            confirming = false
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.smooth) { confirming = true }
                        } label: {
                            Label("交給 Xena", systemImage: "sparkles")
                        }
                        .buttonStyle(.pill(.dark, compact: true))
                        Button("看訂單") {
                            if let first = model.orders.first(where: { $0.status == .paid }) {
                                model.open(.order(first.id))
                            }
                        }
                        .buttonStyle(.pill(.light, compact: true))
                    }
                    .padding(.top, 4)
                }
            } else if let prompt = note.prompt {
                Button {
                    model.askXena(prompt, site: note.siteID)
                } label: {
                    Label(note.promptLabel ?? "問 Xena", systemImage: "sparkles")
                }
                .buttonStyle(.pill(.light, compact: true))
                .padding(.top, 4)
            }
        }
        .padding(18)
        .background(Brand.sheet.opacity(0.92), in: .rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(note.kind == .attention ? Brand.accent.opacity(0.35) : Brand.line, lineWidth: 1)
        }
    }
}

private struct DoneNoteRow: View {
    let note: XenaNote
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(color: Brand.muted)
                    .foregroundStyle(Brand.muted)
                Text(note.resolution ?? "")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
            }
            Spacer(minLength: 0)
            if let site = model.site(note.siteID) {
                SiteIcon(site: site, size: 22)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct ShiftRow: View {
    let entry: ShiftEntry
    let isLast: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.at.clockText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Brand.muted)
                .frame(width: 40, alignment: .trailing)
                .padding(.top, 2)
            VStack(spacing: 0) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.tone.color)
                    .frame(width: 24, height: 24)
                    .background(entry.tone.color.opacity(0.12), in: .circle)
                if !isLast {
                    Rectangle()
                        .fill(Brand.line)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let site = model.site(entry.siteID) {
                    SiteChip(site: site)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, isLast ? 0 : 16)
            Spacer(minLength: 0)
        }
    }
}
