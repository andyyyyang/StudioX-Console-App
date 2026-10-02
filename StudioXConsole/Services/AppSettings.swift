import SwiftUI

/// 「設定」頁可以微調的東西（存在這台裝置）：外觀、字的大小、Xena 怎麼說話、首頁放哪些、打開 App 先看哪一頁、觸覺回饋。
/// 通知、Face ID 有自己的地方（PushCenter、AppLock），這裡只放 App 自己的偏好。
/// 任何畫面直接讀 AppSettings.shared（@Observable，讀了就會跟著更新）
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
        var label: String {
            switch self {
            case .system: "跟著系統"
            case .light: "淺色"
            case .dark: "深色"
            }
        }
        var scheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum TextSize: String, CaseIterable, Identifiable {
        case small, standard, large, larger
        var id: Self { self }
        var label: String {
            switch self {
            case .small: "小"
            case .standard: "標準"
            case .large: "大"
            case .larger: "特大"
            }
        }
        /// 標準：跟著系統的「文字大小」（整個範圍都可以）；其他固定在一個大小
        var range: ClosedRange<DynamicTypeSize> {
            switch self {
            case .small: .medium ... .medium
            case .standard: .xSmall ... .accessibility5
            case .large: .xLarge ... .xLarge
            case .larger: .xxLarge ... .xxLarge
            }
        }
    }

    /// 首頁的 Xena 什麼時候開口說今天的狀況
    enum Greeting: String, CaseIterable, Identifiable {
        case launch, daily, quiet
        var id: Self { self }
        var label: String {
            switch self {
            case .launch: "每次打開"
            case .daily: "每天一次"
            case .quiet: "不用說"
            }
        }
        var help: String {
            switch self {
            case .launch: "每次打開 App，她都一個字一個字跟你說今天的狀況。"
            case .daily: "每天第一次打開時說，之後直接顯示。"
            case .quiet: "直接顯示文字，水珠照樣在呼吸。"
            }
        }
    }

    enum Pace: String, CaseIterable, Identifiable {
        case slow, normal, fast
        var id: Self { self }
        var label: String {
            switch self {
            case .slow: "慢"
            case .normal: "正常"
            case .fast: "快"
            }
        }
        /// iPhone 的聲音說話時的速度（乘在系統預設的語速上）
        var speechRate: Double {
            switch self {
            case .slow: 0.86
            case .normal: 1.0
            case .fast: 1.14
            }
        }
        /// 一個字多久
        var perCharacter: Duration {
            switch self {
            case .slow: .milliseconds(62)
            case .normal: .milliseconds(42)
            case .fast: .milliseconds(24)
            }
        }
    }

    /// Xena 開口用的聲音
    enum VoiceSource: String, CaseIterable, Identifiable {
        case iphone, cloud
        var id: Self { self }
        var label: String {
            switch self {
            case .iphone: "iPhone 內建（免費）"
            case .cloud: "雲端自然語音"
            }
        }
    }

    /// 雲端自然語音的三種（console 的 /api/app/tts）
    enum CloudVoice: String, CaseIterable, Identifiable {
        case warm, bright, calm
        var id: Self { self }
        var label: String {
            switch self {
            case .warm: "溫暖"
            case .bright: "明亮"
            case .calm: "沉穩"
            }
        }
    }

    /// 打開 App 先看哪一頁
    enum StartTab: String, CaseIterable, Identifiable {
        case today, sites, orders, inbox
        var id: Self { self }
        var label: String {
            switch self {
            case .today: "今天"
            case .sites: "網站"
            case .orders: "訂單"
            case .inbox: "收件匣"
            }
        }
    }

    /// 首頁可以收起來的區塊
    enum HomeSection: String, CaseIterable, Identifiable {
        case cards, attention
        var id: Self { self }
        var label: String {
            switch self {
            case .cards: "狀況卡片"
            case .attention: "需要你決定的事"
            }
        }
    }

    var appearance: Appearance { didSet { save(appearance.rawValue, "appearance") } }
    var textSize: TextSize { didSet { save(textSize.rawValue, "textSize") } }
    var greeting: Greeting { didSet { save(greeting.rawValue, "xena.greeting") } }
    var pace: Pace { didSet { save(pace.rawValue, "xena.pace") } }
    /// Xena 的水珠會動（關掉：停在同一個樣子，比較省電）
    var orbMotion: Bool { didSet { save(orbMotion, "xena.orbMotion") } }
    var haptics: Bool { didSet { save(haptics, "haptics") } }
    var startTab: StartTab { didSet { save(startTab.rawValue, "startTab") } }
    /// 收起來的首頁區塊
    var hiddenSections: Set<HomeSection> { didSet { save(hiddenSections.map(\.rawValue).sorted(), "home.hidden") } }
    /// 「每天一次」：今天說過了沒（yyyy-MM-dd，台北時間）
    var greetedDay: String { didSet { save(greetedDay, "xena.greetedDay") } }
    /// 用說的時，Xena 用 iPhone 的聲音開口回答
    var speakReplies: Bool { didSet { save(speakReplies, "voice.speakReplies") } }
    /// Xena 的聲音（AVSpeechSynthesisVoice 的 identifier；空的＝自動挑最好的中文聲音）
    var voiceID: String { didSet { save(voiceID, "voice.id") } }
    /// iPhone 內建（免費，預設）或雲端自然語音
    var voiceSource: VoiceSource { didSet { save(voiceSource.rawValue, "voice.source") } }
    var cloudVoice: CloudVoice { didSet { save(cloudVoice.rawValue, "voice.cloud") } }
    /// Apple Intelligence（手機上的模型）寫首頁的開場白
    var aiGreeting: Bool { didSet { save(aiGreeting, "ai.greeting") } }
    /// Apple Intelligence 聽懂「打開訂單」這類指令，馬上在手機上做，不用等雲端的 Xena
    var aiCommands: Bool { didSet { save(aiCommands, "ai.commands") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: "settings.\(key)").flatMap(T.init(rawValue:)) ?? fallback
        }
        appearance = value("appearance", Appearance.system)
        textSize = value("textSize", TextSize.standard)
        greeting = value("xena.greeting", Greeting.launch)
        pace = value("xena.pace", Pace.normal)
        orbMotion = defaults.object(forKey: "settings.xena.orbMotion") as? Bool ?? true
        haptics = defaults.object(forKey: "settings.haptics") as? Bool ?? true
        startTab = value("startTab", StartTab.today)
        hiddenSections = Set((defaults.stringArray(forKey: "settings.home.hidden") ?? []).compactMap(HomeSection.init(rawValue:)))
        greetedDay = defaults.string(forKey: "settings.xena.greetedDay") ?? ""
        speakReplies = defaults.object(forKey: "settings.voice.speakReplies") as? Bool ?? true
        voiceID = defaults.string(forKey: "settings.voice.id") ?? ""
        voiceSource = value("voice.source", VoiceSource.iphone)
        cloudVoice = value("voice.cloud", CloudVoice.warm)
        aiGreeting = defaults.object(forKey: "settings.ai.greeting") as? Bool ?? true
        aiCommands = defaults.object(forKey: "settings.ai.commands") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: "settings.\(key)")
    }

    func shows(_ section: HomeSection) -> Bool {
        !hiddenSections.contains(section)
    }

    func setShows(_ section: HomeSection, _ on: Bool) {
        if on { hiddenSections.remove(section) } else { hiddenSections.insert(section) }
    }

    /// 今天（台北時間）
    static var today: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    /// 首頁的 Xena 這一次要不要開口說（說過的同一段話不重說；「每天一次」今天說過就不說）
    func shouldSpeak(_ text: String, spoken: String?) -> Bool {
        guard text != spoken else { return false }
        switch greeting {
        case .launch: return true
        case .daily: return greetedDay != Self.today
        case .quiet: return false
        }
    }

    /// 回到預設值（通知、Face ID 不受影響）
    func reset() {
        appearance = .system
        textSize = .standard
        greeting = .launch
        pace = .normal
        orbMotion = true
        haptics = true
        startTab = .today
        hiddenSections = []
        speakReplies = true
        voiceID = ""
        voiceSource = .iphone
        cloudVoice = .warm
        aiGreeting = true
        aiCommands = true
    }

    var isDefault: Bool {
        appearance == .system && textSize == .standard && greeting == .launch && pace == .normal
            && orbMotion && haptics && startTab == .today && hiddenSections.isEmpty
            && speakReplies && voiceID.isEmpty && voiceSource == .iphone && cloudVoice == .warm && aiGreeting && aiCommands
    }
}

extension View {
    /// 觸覺回饋（設定裡關掉就不震）
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        sensoryFeedback(feedback, trigger: trigger) { _, _ in AppSettings.shared.haptics }
    }

    /// 觸覺回饋，只有 condition 成立時（設定裡關掉就不震）
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, condition: @escaping (T, T) -> Bool) -> some View {
        sensoryFeedback(feedback, trigger: trigger) { old, new in AppSettings.shared.haptics && condition(old, new) }
    }

    /// 設定裡的外觀與字的大小（主畫面、鎖定畫面的視窗都要套）
    func appSettingsAppearance() -> some View {
        modifier(AppearanceModifier())
    }
}

/// 同一串修飾（不用 if）：換設定時畫面的狀態（捲到哪、開到哪一頁）不會重來
private struct AppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(AppSettings.shared.appearance.scheme)
            .dynamicTypeSize(AppSettings.shared.textSize.range)
    }
}
