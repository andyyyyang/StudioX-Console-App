# StudioX Console App

StudioX 後台的 iOS App：一個 App 管你在 StudioX Console 上所有的網站（studiox.tw、黃毛丫頭、博信國際…），
首頁是 **Xena** —— 24 小時值班的店長。資料全部是正式的：登入用 StudioX 帳號，
讀寫走 console 既有的 API（和 AI 連接器同一個閘道、和網頁版同一個 Xena）。

## 開啟

Xcode 27（macOS Tahoe 26.6 以上、Apple silicon），目標 iOS 27。

```bash
open StudioXConsole.xcodeproj
```

Signing & Capabilities 選自己的 Team 就能跑模擬器或實機。專案用 Xcode 的「同步資料夾」：
`StudioXConsole/` 底下新增的檔案自動加進專案，不用改 `project.pbxproj`。

**console 要先部署 atelier-cms 的 `claude/ios-app-prototype-4492mf`**（App 的登入 client 與 API，見下面「伺服器」）。

## 品牌

樣式一律照 StudioX 後台的設計系統，色碼與規則一對一照抄，不另外發明：

| App | 來源（atelier-cms） |
|---|---|
| `Brand/Theme.swift` 的顏色 | `src/app/admin/_ui/theme.ts`（後台配色標準：主色橘只用在主要動作與選取、其他中性灰、亮暗各自選色、狀態色只表示狀態、圖表 5 色固定順序） |
| 版面 | `mobile-css.ts`：手機只有兩層——暖灰底（`--page-bg`）和實心卡片（`--adm-surface`、圓角 14、細框、沒有陰影） |
| 按鈕、狀態標籤、欄位 | `button-style.ts`（主要／次要／透明／危險，高度 28／32／40，手機主要動作 44）、`StatusBadge.tsx`、`styles.ts` |
| 圖示 | 後台側欄同一套 Heroicons（24 outline），`Web/assets/icons.cjs` 從 `@heroicons/react` 直接輸出成向量圖 |
| 字 | 後台用系統字（SF／蘋方）；歡迎頁的大字是 Inter Tight（和 console 登入頁、studiox.tw 一樣） |
| App 圖示 | studiox.tw 的 apple-touch-icon（黑底、紙色標誌、品牌橘摺角） |
| Xena 的水滴 | `copilot/styles.ts` 的 `ORB_BALL_CSS`：五層圖（光暈、水珠、光核、流光、柔光）由 `Web/assets/xena-orb.mjs` 從那份 CSS 直接畫出來，App 照網頁的節奏動（靜靜呼吸 3.8 秒、回答時 1.1 秒、光核 2.2 秒轉一圈…）；小圖示是側欄的 `OrbIcon` |
| Xena 的對話 | `copilot/styles.ts` 的 `CHAT_CSS`：自己的訊息是主色泡泡（18/18/6/18 圓角）、Xena 是一般文字、工具呼叫一行淡淡的小字、確認卡片 16 圓角＋膠囊按鈕 |

### 歡迎頁（3D 玻璃標誌）

和 console 的網頁登入同一個上半部：大字 StudioX ＋ studiox.tw 首頁那個 3D 玻璃 Logo ——
三塊積木各自轉著散開漂浮、又組合起來，攝影棚柔光箱的反光、邊緣的彩虹色散，可以用手指抓著玩。
用的就是首頁那份 `logo3d.ts`（three.js），打包在 App 裡（`Web/welcome` → `StudioXConsole/Welcome/`，不連網路），
在 `WKWebView` 裡跑；不能畫 3D 或「減少動態」時改顯示平面標誌（和網頁一樣）。
下方是透明的玻璃面板（Liquid Glass），Xena 打招呼、「用 StudioX 帳號登入」。

改了 `logo3d.ts`（studio_website 的 `src/scripts/logo3d.ts`，兩邊要一起改）之後重新打包：

```bash
cd Web/welcome && npm install && npm run build
```

## 功能

| 分頁 | 內容 |
|---|---|
| **Xena** | 水滴＋招呼（照真的資料說：昨天各網站的訂單與收款、現在誰在等你）；「需要你看一下」：客人在等回覆、已付款等出貨、營運異常、Xena 轉給專人的對話、新的專案詢問，點了直接去處理；昨天的營運報表；各網站最近 7 天的訪客 |
| **網站** | 網站選擇器（和 console 的 /sites 同一份：圖示、7 天訪客、走勢）→ 網站儀表板：在線、訪客、瀏覽、平均停留、走勢圖、熱門頁面、來源網站、流量來源；有商店的再加昨天的營運；開啟後台（console 單一登入）；連接 Claude／ChatGPT 的網址 |
| **訂單** | 有商店的網站才有。等出貨／待付款／已出貨／全部；一次選好幾張標記出貨；訂單內容：品項、金額、收件、付款（匯款單會標出「客人說的、還沒對帳」）、物流；標記已出貨（可填物流單號）、已完成、取消、退款；分享追蹤頁、出貨單 |
| **收件匣** | 客服信（客人已發言、我們還沒回，等最久的在前）、Xena 轉給專人的網站對話、新的專案詢問；客服信可以看這位客人的訂單、直接回信、結案 |
| **我** | 帳號、各網站的職能、console、登出（只撤銷這台裝置） |
| **Xena 對話** | tab bar 上面常駐的小條（後台右下角的水滴）點開；和網頁版同一個 Xena、同一份對話紀錄（網頁上聊到一半的在 App 接著聊）；查了什麼逐筆顯示，要改東西出確認卡片 |

**寫入一律兩步驟**：所有會改資料的動作（出貨、退款、回信、結案…），第一次送出只拿到網站寫的標題與內容，
按「確認執行」才用同一組參數加確認碼真的送出；退款要打字確認，超過門檻還要店主的驗證碼。
權限照各網站的職能與網站的 AI 連接器設定（關閉、只能查詢）。

## 伺服器（atelier-cms，console）

| 端點 | 用途 |
|---|---|
| `/api/oauth/authorize`、`/api/oauth/token`、`/api/oauth/revoke` | 登入：第一方的公開 client `studiox-app`（PKCE、回傳網址 `studiox-console://oauth`）。用系統的登入視窗打開 console 的登入頁（Apple、Email、邀請都一樣），登入後直接回 App，不經過 AI 連接器的同意畫面。每台裝置各自一組 token（access 1 小時、refresh 30 天輪替），和 AI 連接器互不影響 |
| `GET /api/app/me` | 登入的人、可以管理的網站（圖示、7 天流量、後台網址、能用的工具） |
| `POST /api/mcp` | 各網站的資料與動作：`list`／`get`（order、support_thread、assistant_conversation、inquiry）、`traffic_report`、`ops_report`、`update_order`、`bulk_update_orders`、`refund_order`、`reply_support`、`update` |
| `/api/copilot/*` | Xena：對話（SSE）、確認卡片、對話紀錄 |

token 存在 Keychain（這台裝置、解鎖後才讀得到）。console 的「AI → 連接外部 AI」看得到「StudioX App」，撤銷＝所有裝置登出。

## 程式結構

```
StudioXConsole/
  App/         進入點、分頁、AppModel（登入狀態、網站清單、導覽）
  Brand/       Theme（= theme.ts）、平面標誌
  Components/  按鈕、狀態標籤、卡片、欄位、空狀態、確認（兩步驟寫入）、提示
  Welcome/     歡迎頁（3D 玻璃 Logo 的 WKWebView ＋ 登入面板）與打包好的 welcome.html / welcome.js
  Home/        Xena 首頁、Briefing（各網站的待辦與報表，同時拿）
  Sites/       網站選擇器、網站儀表板
  Orders/      訂單、訂單內容
  Inbox/       收件匣、客服信、Xena 的網站對話
  Account/     我
  Xena/        水滴、對話（XenaSession）、對話畫面
  Model/       資料（照網站工具回的 JSON）、Xena 的事件
  Services/    Auth（OAuth＋PKCE＋Keychain）、ConsoleAPI（token 自動換新、MCP、Xena 的 SSE）、SiteData（各工具）
Web/
  welcome/     歡迎頁的打包（esbuild；logo3d.ts 複製自 studio_website）
  assets/      從後台原始碼產生的圖：icons.cjs（Heroicons）、xena-orb.mjs（Xena 的水滴）
```

Swift 6、預設 `@MainActor`、`@Observable`、SwiftUI＋Liquid Glass、Swift Charts，沒有第三方套件。

## 還沒做

- 推播（APNs）：網站後台現在是 Web Push（`lib/web-push.ts`）；要加 App 的裝置註冊與 APNs 管道（需要 Apple Developer 的推播金鑰）
- Face ID 解鎖、小工具（今天的訂單、等你回覆的數字）、App Intents（「問 Xena 今天營收」）
