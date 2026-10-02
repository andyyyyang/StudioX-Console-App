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

**console 與各網站要先部署 `claude/ios-app-prototype-4492mf`**：atelier-cms（console、studiox.tw、博信）與 yellowgirl-website（黃毛丫頭）。
App 的登入 client、API 與欄位定義在那裡（見下面「伺服器」）；網站還沒更新的話，內容的編輯畫面會說明「網站還沒更新到支援 App 編輯的版本」。

## 品牌與設計

App 的版面照 **studiox.tw**（studio_website 的 `src/styles/global.css`），狀態色、圖表色、系統控制項照後台（atelier-cms 的 `src/app/admin/_ui/theme.ts`）：

| App | 來源 |
|---|---|
| `Brand/Theme.swift` | 網站的 `:root`：暖紙色的底 `#f2f0eb`／`#0d0d0c`、墨色的字、`--line` 細線、品牌橘 `#ff5a1f`／`#ff6a33` 只點在重點；反白的帶（跑馬燈、頁尾）；狀態與圖表 5 色照 `theme.ts` |
| `Brand/Typography.swift` | Inter Tight（標題、數字、介面；中文跟著系統的蘋方）＋ Instrument Serif（標題裡的強調詞，品牌橘、正體不斜）。字級照 `--fs-*`：手機用 767px 以下那組、iPad 大一號；標題字重 500、字距 −0.035～−0.05em；字型檔在 `Brand/Fonts`（OFL），從網站用的同一份變體字型產生 |
| `Brand/Motion.swift` | 所有動態共用 `--ease`（cubic-bezier(0.22, 1, 0.36, 1)）與 0.3／0.6／1.1 秒；進場從下方 28pt 淡入、同一批晚 80ms；標題一行一行從遮罩下升起；「減少動態效果」時全部關掉 |
| `Components/` | `.btn`（墨色實心、方角 5、按下時品牌橘從下往上填滿、→ 轉 −45°）、篩選標籤、`.panel`、細線清單、`SectionHead`（英文大字＋襯線強調詞＋中文說明）、`Stats`（細線隔開的大數字，數字滾動跑上去）、只有底線的輸入框 |
| `Components/Signature.swift` | 網站的招牌元件：跑馬燈（反白、✳ 隔開）、點陣底紋、柔光、裁切記號、超大字標 `studiox.`、載入動畫（兩塊標誌轉 180° 卡上去、000→100、橘色的條）、閱讀進度 |
| 圖示 | 後台側欄同一套 Heroicons（24 outline），`Web/assets/icons.cjs` 從 `@heroicons/react` 直接輸出成向量圖；網站本身的 →、↗、✳、— 當字用 |
| App 圖示 | studiox.tw 的 apple-touch-icon（黑底、紙色標誌、品牌橘摺角） |
| Xena 的水滴與對話 | 後台的 `copilot/styles.ts`：五層圖的水滴（`Web/assets/xena-orb.mjs` 從 `ORB_BALL_CSS` 畫出來，照網頁的節奏動）；對話照 `CHAT_CSS`（自己的訊息是主色泡泡、確認卡片 16 圓角＋膠囊按鈕） |

### iPad

- 側欄（`TabView` 的 `.sidebarAdaptable`）：Xena、訂單、收件匣、我，**每個網站直接列在側欄**（`TabSection`）；
  手機與分割畫面變窄時自動收成底部分頁，網站收進「網站」分頁（`AppModel.setRegular` 把頁面搬過去）
- 網站是一個工作區（`NavigationSplitView`）：左邊是這個網站可以管理的東西，右邊是內容；訂單、收件匣是左邊清單、右邊內容
- 版面在寬的畫面放大字級、改多欄（數字 4 欄、商品 4 欄、報表兩欄），內容置中不貼滿
- 鍵盤：⌘1–⌘5 切換、⌘K 找 Xena、⌘R 重新整理、⌘N 新增、⌘S 儲存、⌘↩ 確認執行；指標停在列與按鈕上會亮起來

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
| **Xena** | 日期、一行一行升起的招呼（照真的資料說：昨天各網站的訂單與收款、現在誰在等你）、Xena 的水滴；各網站即時數字的跑馬燈；Needs you（客人在等回覆、已付款等出貨、營運異常、轉給專人的對話、新的專案詢問，點了直接去處理）；昨天的營運；各網站最近 7 天的訪客；常問的幾句 |
| **網站** | 每個網站：概況（在線、訪客、瀏覽、平均停留、可以按住看每天數字的走勢圖、昨天的營運）＋**這個網站可以管理的所有內容**（照網站的欄位定義分組：內容、商店、顧客、自動化、網站設定） |
| **流量** | 今天／7／30／90 天／一年：訪客、瀏覽、造訪、跳出、停留；每天或每小時的走勢；購物漏斗（進站→看商品→加購物車→結帳→下單，含各商品）；一週 7×24 的時段熱度；熱門頁面、入口頁、來源網站、流量來源、國家、裝置、瀏覽器、作業系統、utm；哪些內容頁帶來生意 |
| **Google 搜尋** | Search Console：點擊、曝光、點閱率、平均排名（和上一期比）、每天走勢、搜尋關鍵字、頁面、國家 |
| **內容與商店** | 商品（格狀卡片、圖片上傳與換主圖、價格、庫存、上架、營養標示）、分類、組合、折價券（票券預覽）、商店橫幅（照網站的樣子即時預覽）、公告、FAQ、里程碑、會員等級、簡訊行銷、攤位菜單（價目表、暫停供應）、作品、服務、文章（Markdown 編輯＋預覽、封面、SEO、英文翻譯）、合作方式、首頁／關於／聯絡文案、頁面 SEO（Google 搜尋結果預覽＋字數提醒）、品牌資訊、網站設定、匯款帳號、運費、通知、AI 客服設定、自動化流程與執行 |
| **會員** | 消費、等級、邀請、RFM 分群、最近的訂單、折價券；直接發一次性的折價券 |
| **訂單** | 等出貨／待付款／已出貨／已完成／全部；一次選好幾張標記出貨；訂單內容：品項、金額、收件、付款（匯款單標出「客人說的、還沒對帳」，看過帳單可以確認收款）、物流單號與貨態、託運單、7-11 取貨單號、電子發票（載具、統編、捐贈）、退款；標記已出貨、已完成、取消、退款；分享追蹤頁、出貨單 |
| **收件匣** | 客服信（等最久的在前）、Xena 轉給專人的網站對話、新的專案詢問、信箱（不是客服對話的信：轉成客服對話或收起來）；客服信可以看這位客人的訂單、直接回信、結案 |
| **我** | 帳號、各網站的職能、Xena、console、登出（只撤銷這台裝置） |
| **Xena 對話** | tab bar 上面常駐的小條點開；和網頁版同一個 Xena、同一份對話紀錄；查了什麼逐筆顯示，要改東西出確認卡片 |

### 內容的編輯畫面（和 CMS 同步）

清單與編輯畫面**不是 App 裡寫死的**：照網站自己的欄位定義（`GET /api/app/schema` → 網站的 `site/schema`，
和 list／get／update 查的是同一張實體登錄表）畫出來——每個欄位的型別、必填、選項、字數上限，內容集合的整棵欄位樹與翻譯，
以及這個人現在能不能新增、修改、刪除、換圖。網站加了欄位或改了選項，App 不用改版就跟著變。

- 打開一筆時從 `GET /api/app/record` 拿「現在的值」（和網站算「舊 → 新」用的是同一份），改了才出現「儲存 N 項變更」，只送改過的欄位
- 每種欄位都有對應的輸入：文字、長文、Markdown（編輯／預覽）、數字與金額（元）、開關、選項、日期、顏色、清單、
  一組欄位（object）、多筆（list，可以上下移）、SEO（附 Google 搜尋結果預覽）、翻譯（附原文）；其他結構可以直接改 JSON（格式不對不會送出）
- 預覽照網站上的樣子：商店橫幅、折價券、Google 搜尋結果、商品卡、文章卡
- 圖片：從相簿選（可以一次好幾張），縮到長邊 2400、JPEG，用網站的一次性上傳連結送過去（和手機上點連結上傳同一條路：存恢復點、通知、稽核）；移除、換主圖要確認

**寫入一律兩步驟**：所有會改資料的動作（出貨、退款、回信、結案…），第一次送出只拿到網站寫的標題與內容，
按「確認執行」才用同一組參數加確認碼真的送出；退款要打字確認，超過門檻還要店主的驗證碼。
權限照各網站的職能與網站的 AI 連接器設定（關閉、只能查詢）。

## 伺服器（atelier-cms，console）

| 端點 | 用途 |
|---|---|
| `/api/oauth/authorize`、`/api/oauth/token`、`/api/oauth/revoke` | 登入：第一方的公開 client `studiox-app`（PKCE、回傳網址 `studiox-console://oauth`）。用系統的登入視窗打開 console 的登入頁（Apple、Email、邀請都一樣），登入後直接回 App，不經過 AI 連接器的同意畫面。每台裝置各自一組 token（access 1 小時、refresh 30 天輪替），和 AI 連接器互不影響 |
| `GET /api/app/me` | 登入的人、可以管理的網站（圖示、7 天流量、後台網址、能用的工具） |
| `GET /api/app/schema?site=` | 網站的資料與欄位定義（網站的 relay 方法 `site/schema`） |
| `GET /api/app/record?site=&entity=&id=` | 一筆資料現在的欄位值（網站的 `site/record`） |
| `POST /api/mcp` | 各網站的資料與動作：`list`／`get`（order、support_thread、assistant_conversation、inquiry）、`traffic_report`、`ops_report`、`update_order`、`bulk_update_orders`、`refund_order`、`reply_support`、`update` |
| `/api/copilot/*` | Xena：對話（SSE）、確認卡片、對話紀錄 |

token 存在 Keychain（這台裝置、解鎖後才讀得到）。console 的「AI → 連接外部 AI」看得到「StudioX App」，撤銷＝所有裝置登出。

## 程式結構

```
StudioXConsole/
  App/         進入點、分頁與側欄、選單列的快捷鍵、AppModel（登入狀態、網站清單、欄位定義、導覽）
  Brand/       顏色、字（Inter Tight＋Instrument Serif，Fonts/）、動態、平面標誌
  Components/  按鈕、標籤、卡片、細線清單、區塊標題、數字、欄位、空狀態、確認（兩步驟寫入）、招牌元件
  Welcome/     歡迎頁（3D 玻璃 Logo 的 WKWebView ＋ 登入面板）與打包好的 welcome.html / welcome.js
  Home/        Xena 首頁、Briefing（各網站的待辦與報表，同時拿）
  Sites/       網站、網站的工作區（iPad）、概況、流量、Google 搜尋
  CMS/         照網站欄位定義畫的清單與編輯畫面、欄位、預覽、圖片、會員、攤位菜單、FAQ、信箱
  Orders/      訂單、訂單內容
  Inbox/       收件匣、客服信、Xena 的網站對話
  Account/     我
  Xena/        水滴、對話（XenaSession）、對話畫面
  Model/       資料（照網站工具回的 JSON）、欄位定義（Schema）、Xena 的事件
  Services/    Auth（OAuth＋PKCE＋Keychain）、ConsoleAPI（token 自動換新、MCP、欄位定義、上傳、Xena 的 SSE）、SiteData（各工具）
Web/
  welcome/     歡迎頁的打包（esbuild；logo3d.ts 複製自 studio_website）
  assets/      從後台原始碼產生的圖：icons.cjs（Heroicons）、xena-orb.mjs（Xena 的水滴）
```

Swift 6、預設 `@MainActor`、`@Observable`、SwiftUI＋Liquid Glass、Swift Charts，沒有第三方套件。

## 還沒做

- 推播（APNs）：網站後台現在是 Web Push（`lib/web-push.ts`）；要加 App 的裝置註冊與 APNs 管道（需要 Apple Developer 的推播金鑰）
- Face ID 解鎖、小工具（今天的訂單、等你回覆的數字）、App Intents（「問 Xena 今天營收」）
