import SwiftUI

/// 第一次用到雲端 AI 之前的說明與同意（App Review Guideline 5.1.2(i)：個人資料交給第三方 AI 之前，
/// 要清楚說明會交給誰、交什麼，並取得使用者明確的同意）。
///
/// 會用到雲端 AI 的：跟 Xena 對話（打字、用說的、交給 Xena 的事）、Xena 擬回覆／潤飾、Xena 分析客人的回覆建議、
/// 上傳文件給 Xena、雲端自然語音。這些都要先同意；不同意照樣能用 App 的其他功能，
/// Apple Intelligence 在 iPhone 上做的（聽懂指令、首頁開場白、手機上想的回覆建議）不受影響。
/// 同意存在 AppSettings.cloudAIConsent，隨時可以在設定關掉；ConsoleAPI 送出前也會再檢查一次。
struct CloudAIConsentSheet: View {
    /// 已經同意過、從設定打開來看說明：只有「關閉」
    var reviewing = false
    let answer: (Bool) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 12) {
                        XenaOrb(mood: .listening, size: 44)
                        Headline("Xena 會用 *雲端 AI*", role: .h2)
                        Text("Xena 是 StudioX 的 AI 店長。為了回答你、替你擬回覆，她需要把相關的內容交給 AI 服務處理。開始之前，先讓你知道會交出去什麼、交給誰。")
                            .textRole(.body)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    block("會交出去的內容") {
                        bullet("你跟 Xena 說的話：打字、用說的（由 Apple 的語音辨識轉成文字，錄音不會交給 AI 供應商）、你附給她的文件")
                        bullet("她為了回答去讀的網站資料：訂單、商品、文章、流量，和客人的客服對話（可能有客人的名字、聯絡方式、訂單內容）")
                        bullet("請 Xena 擬回覆、分析客人時：那段客服對話和這位客人的訂單")
                        bullet("開了雲端自然語音時：Xena 要念出來的那句話")
                    }

                    block("交給誰") {
                        bullet("經 StudioX Console 送到 AI 模型供應商：OpenAI、Anthropic、Google（依功能由 StudioX 選用其中一家）")
                        bullet("透過它們的商用 API，只用來產生這一次的回答；依它們的條款，不會被拿去訓練模型")
                        bullet("StudioX 不販售你的資料，也不用來投放廣告")
                    }

                    block("不會交出去的") {
                        bullet("Apple Intelligence 在 iPhone 上做的事：聽懂「打開訂單」這類指令、首頁的開場白、手機上想的回覆建議")
                        bullet("你沒有交給 Xena 的頁面：看訂單、回客人、改商品，照樣只在你的網站和 StudioX 之間")
                    }

                    Text("不同意也可以用 App 的其他功能，只是 Xena 對話、Xena 擬回覆和分析、雲端語音不能用。之後可以隨時在「設定 → AI 與隱私」改變心意。")
                        .textRole(.small)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("隱私權政策 ↗") { openURL(URL(string: "https://studiox.tw/privacy")!) }
                        .buttonStyle(.brand(.quiet, size: .sm))
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if reviewing {
                        Button("關閉") { answer(true) }
                            .buttonStyle(.brand(.primary, size: .lg, fullWidth: true))
                    } else {
                        Button("同意，使用 Xena") { answer(true) }
                            .buttonStyle(.brand(.accent, size: .lg, fullWidth: true))
                        Button("先不要") { answer(false) }
                            .buttonStyle(.brand(.ghost, size: .md, fullWidth: true))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Theme.sheet)
                .overlay(alignment: .top) { Rule() }
            }
            .brandPage()
            .navigationBarTitleDisplayMode(.inline)
        }
        // 要按按鈕回答（往下滑掉當作「先不要」，見 AppModel.answerCloudAI）
        .interactiveDismissDisabled(!reviewing)
        .presentationDragIndicator(reviewing ? .visible : .hidden)
    }

    private func block(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title)
            VStack(alignment: .leading, spacing: 8) { content() }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("・").foregroundStyle(Theme.muted)
            Text(text)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textRole(.small)
    }
}
