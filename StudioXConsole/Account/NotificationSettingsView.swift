import SwiftUI
import UIKit

/// 通知：這台裝置收不收、哪些網站要收，和自己在各網站的通知設定（哪些事、勿擾時段、訊息預覽）。
/// 誰收到什麼是網站決定的（和瀏覽器推播同一套），這裡改的就是網站後台「通知設定 → 手機推播」那一份。
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// 各網站的個人通知設定（nil：還在讀；supported＝false：照職能通知）
    @State private var prefs: [String: NotificationPrefs] = [:]
    @State private var testing = false
    @State private var error: String?

    var body: some View {
        let push = model.push
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow("通知")
                    Headline("Stay *in the loop*.", role: .h1)
                    Text("網站有需要你處理的事，Xena 會從這裡告訴你：客人在等回覆、對話轉給專人、等你決定的自動化。內容和網站後台的手機推播一樣。")
                        .textRole(.lead)
                        .foregroundStyle(Theme.ink2)
                }
                .reveal()

                status(push)

                if push.permission == .allowed && push.device != nil {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHead("Your *sites*", aside: "關掉的網站，這台裝置就不會收到它的通知。", role: .h3)
                        RuledList {
                            ForEach(model.sites) { site in
                                siteRow(site)
                            }
                        }
                    }
                }

                if let error {
                    ErrorNote(message: error)
                }
            }
            .frame(maxWidth: Metric.readable, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .brandPage()
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            // 從「設定」打開通知回來
            if phase == .active { Task { await push.refresh() } }
        }
    }

    // MARK: 這台裝置

    @ViewBuilder
    private func status(_ push: PushCenter) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            switch push.permission {
            case .unknown:
                LoadingRow()
            case .notDetermined:
                statusLine("還沒打開通知", tone: .warning, detail: "打開之後，客人在等、有事要你決定時會跳出來。")
                Button("打開通知") { Task { await push.requestPermission() } }
                    .buttonStyle(.brand(.accent, size: .lg, fullWidth: true))
            case .denied:
                statusLine("通知被關掉了", tone: .danger, detail: "到「設定 → 通知 → StudioX」打開「允許通知」。")
                Button("打開設定") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.brand(.primary, size: .lg, fullWidth: true, arrow: true))
            case .allowed:
                if push.configured == false {
                    statusLine("伺服器還沒設定推播", tone: .warning, detail: "StudioX 設定好 Apple 推播金鑰之後，這台裝置就會開始收到通知，不用重新設定。")
                } else if let device = push.device {
                    statusLine("這台裝置會收到通知", tone: .active, detail: device.lastSuccessAt.map { "上次送達 \($0.relativeText)" } ?? "還沒有送過通知。")
                } else if let problem = push.problem {
                    statusLine("還沒登記好", tone: .warning, detail: problem)
                } else {
                    statusLine("正在登記這台裝置…", tone: .info, detail: nil)
                }
                if push.device != nil && push.configured != false {
                    Button {
                        Task { await sendTest() }
                    } label: {
                        HStack(spacing: 8) {
                            if testing { ProgressView().controlSize(.small) }
                            Text("送一則測試通知")
                        }
                    }
                    .buttonStyle(.brand(.ghost, size: .lg, fullWidth: true))
                    .disabled(testing)
                }
            }
        }
        .panel()
    }

    private func statusLine(_ title: String, tone: Tone, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(tone.foreground).frame(width: 8, height: 8)
                Text(title)
                    .textRole(.h4)
                    .foregroundStyle(Theme.ink)
            }
            if let detail {
                Text(detail)
                    .textRole(.small)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    // MARK: 網站

    private func siteRow(_ site: SiteSummary) -> some View {
        let push = model.push
        let on = Binding(
            get: { !push.isMuted(site.id) },
            set: { value in
                Task {
                    do {
                        try await push.setMuted(site.id, !value)
                    } catch {
                        model.show(error.localizedDescription, tone: .danger)
                    }
                }
            }
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SiteIconView(site: site, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name).textRole(.h4).foregroundStyle(Theme.ink)
                    Text(site.host).textRole(.xs).foregroundStyle(Theme.muted)
                }
                Spacer()
                Toggle("收到\(site.name)的通知", isOn: on)
                    .labelsHidden()
                    .tint(Theme.primary)
            }
            if on.wrappedValue {
                if let p = prefs[site.id] {
                    if p.supported {
                        NavigationLink {
                            SiteNotificationPrefsView(site: site, prefs: p) { prefs[site.id] = $0 }
                        } label: {
                            HStack {
                                Text(Self.summary(p))
                                    .textRole(.small)
                                    .foregroundStyle(Theme.ink2)
                                Spacer()
                                Text("設定 →").textRole(.small).foregroundStyle(Theme.accentText)
                            }
                            .padding(.leading, 46)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.row)
                    } else {
                        Text("照你在這個網站的職能通知。")
                            .textRole(.xs)
                            .foregroundStyle(Theme.muted)
                            .padding(.leading, 46)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .sensoryFeedback(.selection, trigger: on.wrappedValue)
    }

    /// 「5 種通知・勿擾 22:00–08:00」
    static func summary(_ p: NotificationPrefs) -> String {
        let quiet = p.quiet.map { "勿擾 \(clock($0.start))–\(clock($0.end))" } ?? "沒有勿擾時段"
        return "\(p.events.filter(\.on).count) 種通知・\(quiet)"
    }

    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    // MARK: 讀、測試

    private func load() async {
        await model.push.refresh()
        await withTaskGroup(of: (String, NotificationPrefs?).self) { group in
            for site in model.sites {
                let api = model.api
                let id = site.id
                group.addTask { (id, try? await api.notificationPrefs(site: id)) }
            }
            for await (id, p) in group {
                prefs[id] = p ?? NotificationPrefs(.null)
            }
        }
    }

    private func sendTest() async {
        testing = true
        error = nil
        defer { testing = false }
        do {
            try await model.push.sendTest()
            model.show("測試通知送出了，幾秒內會跳出來")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 自己在某個網站的通知設定：哪些事要通知、勿擾時段、訊息預覽（存在網站，改了就生效）
struct SiteNotificationPrefsView: View {
    let site: SiteSummary
    @State var prefs: NotificationPrefs
    var onChange: (NotificationPrefs) -> Void

    @Environment(AppModel.self) private var model
    @State private var saving = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(site.name)
                    Headline("What *matters*.", role: .h1)
                    Text("和網站後台「通知設定 → 手機推播」是同一份：瀏覽器和 App 都照這裡。")
                        .textRole(.lead)
                        .foregroundStyle(Theme.ink2)
                }
                .reveal()

                ForEach(prefs.groups) { group in
                    let events = prefs.events.filter { $0.group == group.id }
                    if !events.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHead(group.label, role: .h3)
                            RuledList {
                                ForEach(events) { event in
                                    eventRow(event)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHead("Quiet *hours*", aside: "這段時間只送緊急的（台北時間）。", role: .h3)
                    RuledList {
                        ToggleRow(label: "勿擾時段", isOn: quietOn)
                            .padding(.vertical, 10)
                        if let quiet = prefs.quiet {
                            HStack {
                                Text("從").textRole(.body).foregroundStyle(Theme.ink2)
                                DatePicker("從", selection: minuteBinding(\.start), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                Text("到").textRole(.body).foregroundStyle(Theme.ink2)
                                DatePicker("到", selection: minuteBinding(\.end), displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                Spacer()
                            }
                            .environment(\.timeZone, Calendar.taipei.timeZone)
                            .padding(.vertical, 12)
                            ToggleRow(label: "緊急的照樣通知", help: "物流異常這類不處理會出事的。", isOn: Binding(
                                get: { quiet.allowUrgent },
                                set: { value in
                                    prefs.quiet?.allowUrgent = value
                                    save(["quiet": quietJSON])
                                }
                            ))
                            .padding(.vertical, 10)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHead("*Preview*", role: .h3)
                    RuledList {
                        ToggleRow(label: "顯示訊息預覽", help: "通知裡帶客人訊息的前幾個字。鎖定畫面上旁邊的人也看得到。", isOn: Binding(
                            get: { prefs.preview },
                            set: { value in
                                prefs.preview = value
                                save(["preview": .bool(value)])
                            }
                        ))
                        .padding(.vertical, 10)
                    }
                }
            }
            .frame(maxWidth: Metric.readable, alignment: .leading)
            .pageWidth()
            .padding(.top, 16)
            .padding(.bottom, 64)
        }
        .brandPage()
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if saving > 0 {
                ToolbarItem(placement: .topBarTrailing) { ProgressView().controlSize(.small) }
            }
        }
    }

    private func eventRow(_ event: NotificationPrefs.Event) -> some View {
        let on = Binding(
            get: { prefs.events.first { $0.id == event.id }?.on ?? false },
            set: { value in
                guard let i = prefs.events.firstIndex(where: { $0.id == event.id }) else { return }
                prefs.events[i].on = value
                save(["events": .object([event.id: .bool(value)])])
            }
        )
        return Toggle(isOn: on) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(event.label)
                        .textRole(.body)
                        .foregroundStyle(Theme.ink)
                    if event.urgent { StatusBadge("緊急", tone: .danger) }
                }
                Text(event.hint)
                    .textRole(.xs)
                    .foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.primary)
        .padding(.vertical, 14)
        .sensoryFeedback(.selection, trigger: on.wrappedValue)
    }

    // MARK: 勿擾時段

    private var quietOn: Binding<Bool> {
        Binding(
            get: { prefs.quiet != nil },
            set: { value in
                // 打開時預設 22:00–08:00
                prefs.quiet = value ? (prefs.quiet ?? NotificationPrefs.Quiet(start: 22 * 60, end: 8 * 60, allowUrgent: true)) : nil
                save(["quiet": quietJSON])
            }
        )
    }

    private var quietJSON: JSONValue {
        guard let q = prefs.quiet else { return .null }
        return ["start": .number(Double(q.start)), "end": .number(Double(q.end)), "allowUrgent": .bool(q.allowUrgent)]
    }

    /// 分鐘（台北時間，從午夜起算）↔ DatePicker 的時間
    private func minuteBinding(_ key: WritableKeyPath<NotificationPrefs.Quiet, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = prefs.quiet?[keyPath: key] ?? 0
                return Calendar.taipei.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.taipei.dateComponents([.hour, .minute], from: date)
                prefs.quiet?[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                save(["quiet": quietJSON], debounced: true)
            }
        )
    }

    // MARK: 存

    /// 依序存（後一個等前一個），網站回的不會被比較早的回覆蓋掉
    @State private var queue: Task<Void, Never>? = nil
    /// 勿擾時間轉輪：停下來才存
    @State private var debounce: Task<Void, Never>? = nil
    @State private var generation = 0

    /// 只送改的欄位；網站回來的是存好的整份
    private func save(_ set: JSONValue, debounced: Bool = false) {
        onChange(prefs)
        guard debounced else { return enqueue(set) }
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            enqueue(set)
        }
    }

    private func enqueue(_ set: JSONValue) {
        generation += 1
        let mine = generation
        let previous = queue
        queue = Task {
            await previous?.value
            saving += 1
            defer { saving -= 1 }
            do {
                let saved = try await model.api.notificationPrefs(site: site.id, set: set)
                // 後面還有要存的：先不用網站回的蓋掉畫面
                if mine == generation, saved.supported {
                    prefs = saved
                    onChange(saved)
                }
            } catch {
                model.show(error.localizedDescription, tone: .danger)
            }
        }
    }
}
