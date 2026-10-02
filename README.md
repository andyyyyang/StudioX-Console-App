# StudioX Console App

StudioX 後台的 iOS App（雛形）。一個 App 管你所有的網站（studiox.tw、黃毛丫頭、博信國際），
首頁就是 **Xena** —— 24 小時值班的店長：有事主動找你、昨晚做了什麼都記下來、要動手改東西一定先問你。

> 雛形階段：資料是示範資料（`DemoConsole`），還沒接上正式的 console。可以登入、看網站與訂單、回客服、
> 跟 Xena 聊天，按下確認卡片後示範資料真的會變（訂單狀態、客服對話、草稿、值班紀錄）。

## 開啟

需要 Xcode 27（macOS Tahoe 26.6 以上、Apple silicon），目標 iOS 27。

```bash
open StudioXConsole.xcodeproj
```

選 iPhone 模擬器 → Run。實機要在 Signing & Capabilities 選自己的 Team。
專案用 Xcode 的「同步資料夾」：在 `StudioXConsole/` 底下新增的檔案會自動加進專案，不用改 `project.pbxproj`。

**怎麼玩**：登入畫面按「透過 Apple 登入」（或任何 Email＋密碼）→ 首頁 Xena 跟你打招呼 →
「3 筆訂單可以備貨了」按「交給 Xena」→ 確認 → 回到「網站 → 黃毛丫頭」訂單就變了。
底部的 Xena 小條隨時點開對話，試試：「今天營收多少？」「林先生的訂單晚到了，怎麼處理？」「幫 YG2610020027 退款」。

## 畫面

| 分頁 | 內容 |
|---|---|
| **登入** | 和 console 網頁登入同一套品牌：大字 StudioX ＋玻璃標誌（三塊 Liquid Glass 積木會散開又組合，可以拖著轉）；下方玻璃面板裡 Xena 打招呼；透過 Apple（黑）／用 Email（玻璃） |
| **Xena** | 水滴＋招呼（一個字一個字打出來）、「需要你看一下」（她主動找你的事，能直接交給她處理）、「處理好了」、「我值班時做了這些」（值班紀錄時間軸）、可以問她的話 |
| **網站** | 網站選擇器（7 天訪客、走勢、漲跌）→ 單一網站儀表板：在線人數、訪客圖表、熱門頁面、訂單（有商店的網站）、最近的內容、開啟後台；連接 Claude／ChatGPT 的 MCP 網址 |
| **收件匣** | 三個網站的客服對話：等你／Xena 處理中／全部；對話裡看得到 Jev 的分類與判斷、接手、回覆、交還 Xena、結案 |
| **我** | 帳號、各網站職能、Xena 的設定（主動提醒、夜班安靜模式、每日摘要時間）、推播、登出 |
| **Xena 小條** | tab bar 上面常駐（`tabViewBottomAccessory`）：小水滴＋輪播她正在看著的事，點了打開對話 |

## Xena

- **水滴**（`Xena/XenaOrb.swift`）：和網頁版同一顆（atelier-cms 的 `copilot/orb3d.ts`、`orb-motion.ts`）——
  中間粉、青、琥珀、紫四團光在旋轉，左上一扇窗光，底下一圈會呼吸的光暈，外面是會折射後面畫面的 Liquid Glass。
  狀態（`XenaMood`）：值班中、在聽、查資料、回覆中、有事想說（光核偏暖）、夜班（00:00–06:00，暗一點慢一點）。
  能量平滑追目標、相位累加，切換狀態不會跳；回答完、事情做完會「彈」一下。減少動態時停住、減少透明度時不用玻璃。
- **對話**（`Xena/XenaSession.swift`）：事件格式和網頁版完全相同（`lib/copilot/engine.ts` 的 `CopilotEvent`）：
  `thread`、`text`（串流）、`tool` / `tool-done`（逐筆顯示查了什麼）、`confirm`（確認卡片）、`cards`（點了到那筆訂單／對話）、`ask`（問你選一個）。
- **寫入一律兩步驟**：要改東西時先出確認卡片，你按「確認執行」才做；退款這類不能復原的要打字確認（和 MCP 的規則一樣）。
  首頁筆記上的「交給 Xena」也一樣先出卡片。
- 示範的劇本在 `Services/DemoConsole.swift`（照關鍵字）：營收、備貨、延誤的訂單（會問你要怎麼處理）、報價回覆、等你回覆的對話、流量、起草新消息、改單一訂單狀態、退款。

## 程式結構

```
StudioXConsole/
  App/         進入點、RootView、分頁、AppModel（登入、資料、導覽）
  Brand/       品牌色（= AuthScreen.tsx 的 CSS 變數）、StudioX 標誌幾何（= lib/brand-mark.ts）、玻璃標誌、背景色光
  Login/       登入畫面
  Home/        Xena 首頁
  Xena/        水滴、對話（XenaSession）、對話畫面、確認卡片、底部小條
  Sites/       網站選擇器、網站儀表板、訂單
  Inbox/       客服收件匣、對話
  Account/     我
  Components/  膠囊按鈕、狀態標籤、走勢線、打字效果…
  Model/       資料型別；CopilotEvent.swift 對應網頁版 Xena 的事件
  Services/    ConsoleBackend（介面）、DemoConsole（示範資料）、LiveConsole（接正式環境的準備）
```

Swift 6、預設 `@MainActor`（Xcode 26 起新專案的設定）、`@Observable`、SwiftUI＋Liquid Glass、Swift Charts，沒有第三方套件。

## 接上正式環境

App 要能讀寫真的資料，console（atelier-cms，`CMS_MODULES` 含 `console`）要先補這幾件事：

1. **App 的登入**：console 的 OIDC 現在只給網站後台用（`/api/console/oidc/token` 一定要 client secret，回傳網址要是網站的）。
   要加一個給 App 的公開 client（沒有密鑰、只靠 PKCE、回傳網址 `studiox-console://oauth`），並發 App 用的 access token（含 refresh）。
   App 這邊已經寫好 PKCE 與授權碼交換（`Services/LiveConsole.swift` 的 `ConsoleSignIn`），用 `ASWebAuthenticationSession` 打開授權頁即可。
2. **Xena 用 Bearer token**：`lib/copilot/auth.ts` 現在只認瀏覽器的登入 cookie，而且 POST 要同網域的 `Origin`。
   加上「`Authorization: Bearer <App token>`」的路徑後，App 直接用同一個 `/api/copilot/chat`、`/api/copilot/confirm`
   （串流解析已經寫好：`XenaStreamClient`）。
3. **App 用的清單 API**：網站與流量摘要（`lib/console/sites-list.ts` ＋ `site-stats.ts` 已經有）、各網站的訂單、客服對話、Xena 的主動筆記與值班紀錄
   （console 經各網站的 relay 拿，和 MCP 閘道 `lib/console/mcp-gateway.ts` 一樣用一次性通行證）。
4. **推播**：網站後台現在是 Web Push（`lib/web-push.ts`）；App 要 APNs：裝置註冊 API、`alertStaff()` 多一條 APNs 管道，事件清單沿用 `staff-alert-events.ts`。
5. 接好之後新增 `LiveConsole: ConsoleBackend`，在 `AppModel(backend:)` 換掉 `DemoConsole()`。

## 之後可以做

- Face ID 解鎖（後台權限很大）
- 小工具（Widget）／即時動態：今天的訂單、等你回覆的數字、Xena 的一句話
- App Intents：「嘿 Siri，問 Xena 今天營收」
- 推播直接帶確認卡片（Notification actions 按確認／取消）
