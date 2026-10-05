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
`StudioXConsole.entitlements`（專案根目錄）開了 Push Notifications 與 Time Sensitive Notifications：
自動簽章會幫 App ID 打開這兩項，第一次用新的 Team 跑實機時 Xcode 會問要不要註冊，按好。

### 建置與上架

- **每次推上 GitHub 都會編一次**（`.github/workflows/ios.yml`）：GitHub 的 Mac（macos-26）用共用的 scheme 編模擬器版、不簽章
  （有 Xcode 27 用 27；GitHub 還沒裝的時候用最新的 Xcode 26，只有 iOS 27 才有的 API 以 Xcode 27 為準）；編不過時 Actions 的摘要列出每個錯誤與警告（檔案、行號）。只在 App 的檔案有改時跑，
  同一個分支連推只編最新的一次。私有 repo 的 Mac 分鐘數是一般的 10 倍，注意 GitHub 方案的額度。
- **推上來就出一版 TestFlight**（`.github/workflows/testflight.yml`）：GitHub 的 Mac 用 App Store Connect API 金鑰自己處理簽章，
  不用打開 Xcode、不用接 iPhone、不用匯出憑證：
  1. 便宜的 Linux 先檢查：Secrets 設好了沒、App ID `tw.studiox.console` 註冊了沒（沒有就註冊）、App Store Connect 上有沒有這個 App
  2. Mac：打開 App ID 的推播能力，建一張**這一次專用**的 Apple Distribution 憑證（私鑰只在那台 Mac 的暫時鑰匙圈）與 App Store 描述檔，
     封存、上傳；結束就撤銷憑證、刪掉描述檔（已經上傳的版本不受影響，憑證也不會越積越多）
  3. Linux：等 Apple 處理好，把最近的提交寫成「測試內容」，交給內部測試群組（沒有就建一個「StudioX 團隊」），
     把帳號持有人和 Secrets 的 `TESTFLIGHT_TESTERS` 加進群組，寄 TestFlight 邀請給群組裡還沒裝的人
  - 邀請別人：Secrets 加 `TESTFLIGHT_TESTERS`，逗號隔開，每一筆 `email` 或 `姓名 <email>`（例如 `王小明 <ming@example.com>`），
    再到 Actions → TestFlight 邀請 → Run workflow。內部測試員一定要是 App Store Connect 團隊的成員（Apple 的規定），
    還不是的人會先收到 Apple 的團隊邀請（Developer、只看得到這個 App、不能動憑證）；接受後再跑一次，就會收到 TestFlight 邀請
  - 推到 `main` 或 `claude/ios-app-prototype-4492mf`（App 的檔案有改）就跑，也可以在 Actions → TestFlight → Run workflow 手動跑
  - 版號用 UTC 時間（`2610021405`＝26/10/02 14:05），版本改 `MARKETING_VERSION`
  - GitHub 還沒裝 Xcode 27 的時候用最新的 Xcode 建置，最低系統先設成那個 SDK 的版本（摘要會寫用了哪一版）
  - Secrets 還沒設定時整個流程跳過，不會失敗；Mac 的部分大約 10 分鐘（私有 repo 的 Mac 分鐘數是一般的 10 倍）

  **第一次設定（只有這幾步要在網頁上做）**：
  1. App Store Connect → 使用者與存取權 → 整合 → App Store Connect API → 團隊金鑰「＋」：名稱 `GitHub TestFlight`、存取權 **Admin**
     （要能建憑證與描述檔）→ 下載 `.p8`（只能下載一次），記下金鑰 ID 與上面的 Issuer ID
  2. GitHub 這個 repo → Settings → Secrets and variables → Actions → New repository secret，新增四個：
     | 名稱 | 內容 |
     |---|---|
     | `ASC_KEY_ID` | 金鑰 ID（10 個字） |
     | `ASC_ISSUER_ID` | Issuer ID（一串有 `-` 的 UUID） |
     | `ASC_PRIVATE_KEY` | 用文字編輯器打開 `.p8`，整段貼上（含 `-----BEGIN PRIVATE KEY-----` 那兩行） |
     | `APPLE_TEAM_ID` | developer.apple.com → Account → Membership 的 Team ID（10 個字） |
  3. Actions → TestFlight → Run workflow 跑一次：它會註冊 App ID，然後停下來說「App Store Connect 上還沒有這個 App」
  4. App Store Connect → App →「＋」新增 App：平台 iOS、名稱 StudioX、主要語言 繁體中文、套件 ID 選 `tw.studiox.console`、SKU `studiox-console`
     （Apple 不讓 API 建 App，這一步只能在網頁上做）
  5. TestFlight → 內部測試「＋」建一個群組，把自己和同事加進去
  6. 回 Actions 重跑。之後每次推上來，十幾分鐘後 iPhone 上的 TestFlight 就有新版

  **只要重寄邀請**（不建置）：Actions → TestFlight 邀請 → Run workflow（`.github/workflows/testflight-invite.yml`）。
  邀請信寄到 App Store Connect 帳號的 Apple ID 信箱；也可以直接打開 iPhone 的 TestFlight（同一個 Apple ID 登入）。

  金鑰被拒時，Actions 的摘要會列出 Apple 回的錯誤，和每個 Secret 的格式檢查（只檢查格式、不會印出內容）。
  團隊金鑰與個人金鑰（Individual key）都可以，流程會自己判斷。

  `.p8` 只放在 GitHub 的 Secrets；不要貼在對話、程式或 issue 裡。要換金鑰就在 App Store Connect 撤銷舊的、更新三個 Secrets。
- **也可以用 Xcode Cloud**（Apple 的建置服務）：專案已經有共用的 scheme 與 `ci_scripts/`（測試內容），在 Xcode 的 Integrate → Create Workflow 設定即可。
  兩個都開會各出一版，選一個用就好。
- 上架需要的都準備好了：`ITSAppUsesNonExemptEncryption = NO`（TestFlight 不會卡在出口合規）、隱私清單 `PrivacyInfo.xcprivacy`、
  沒有透明度的 App 圖示。TestFlight 和 App Store 的版本用正式環境的推播（App 自己判斷），console 的 APNs 金鑰兩種都能送。

### App Store 上架（`.github/workflows/appstore.yml`、`ci/appstore.py`）

提交訊息帶標籤就會跑（推到 main 或這個分支）：

| 標籤 | 做什麼 |
|---|---|
| `[appstore-shots]` | 在 Mac 上用示範模式截 App Store 尺寸的截圖（6.9 吋 iPhone、13 吋 iPad），存到 `docs/appstore/raw/`；`[appstore-shots-ipad]` 只重拍 iPad |
| `[appstore]` | 上傳這一版的上架資料：文字（`ci/appstore/metadata.json`）、分類、年齡分級、價格（免費）、上架地區（全部，中國大陸要 ICP 備案先不上）、宣傳圖、最新的 build、審核說明。不送審 |
| `[appstore-submit]` | 同上，然後送審 |

- 宣傳圖：`python3 ci/appstore/compose.py --fonts <Noto Sans CJK TC 的資料夾>` 把 `docs/appstore/raw/` 合成到 `docs/appstore/iphone69/`、`ipad13/`
  （文字、版型、放大的地方在檔案開頭的 SLIDES）。示範資料是虛構的店家（晨麥手作、木白設計），不放真實客戶
- 審核用示範模式：歡迎頁「先看看示範（不用登入）」；刪除帳號在設定最下面（App Store 5.1.1(v)，console 的 `DELETE /api/app/account`）
- API 做不到、要在 App Store Connect 網頁上做的：App 隱私權問卷、審核聯絡人（`[appstore]` 的摘要會提醒還缺什麼）

## 功能

| 分頁 | 內容 |
|---|---|
| **Xena** | 日期、一行一行升起的招呼（照真的資料說：昨天各網站的訂單與收款、現在誰在等你）、Xena 的水滴；各網站即時數字的跑馬燈；Needs you（客人在等回覆、已付款等出貨、營運異常、轉給專人的對話、新的專案詢問，點了直接去處理）；昨天的營運；各網站最近 7 天的訪客；常問的幾句 |
| **網站** | 每個網站：概況（在線、訪客、瀏覽、平均停留、可以按住看每天數字的走勢圖、昨天的營運）＋**這個網站可以管理的所有內容**（照網站的欄位定義分組：內容、商店、行銷、顧客、自動化、網站設定） |
| **營運報表** | 昨天／7／30／90 天：收款、付款的訂單、新訂單、平均客單、新訂單現在的狀態、等出貨、等付款、客人等回覆、通知逾時、偵測到的異常；會員總數、這個月新加入、累積消費、各等級人數、消費最多的五位 |
| **行銷** | 簡訊活動（看收得到幾位、今天的額度、靜音時段，發送要打「發送」；寄完的成功、失敗與原因）、LINE 優惠推播（照網站 LINE 卡片樣式的預覽、商品照片當大圖、優惠碼、對象：所有好友／綁定的會員／N 天沒買的／買過某個商品，先看人數；傳送中的進度、傳過的紀錄）、待發通知（倒數中的立即送出或取消並復原）、整合（寄測試信、送測試簡訊） |
| **流量** | 今天／7／30／90 天／一年：訪客、瀏覽、造訪、跳出、停留；每天或每小時的走勢；購物漏斗（進站→看商品→加購物車→結帳→下單，含各商品）；一週 7×24 的時段熱度；熱門頁面、入口頁、來源網站、流量來源、國家、裝置、瀏覽器、作業系統、utm；哪些內容頁帶來生意 |
| **Google 搜尋** | Search Console：點擊、曝光、點閱率、平均排名（和上一期比）、每天走勢、搜尋關鍵字、頁面、國家 |
| **內容與商店** | 商品（格狀卡片、圖片上傳與換主圖、價格、庫存、上架、營養標示）、分類、組合、折價券（票券預覽）、商店橫幅（照網站的樣子即時預覽）、公告、FAQ、里程碑、會員等級、簡訊行銷、攤位菜單（價目表、暫停供應）、作品、服務、文章（Markdown 編輯＋預覽、封面、SEO、英文翻譯）、合作方式、首頁／關於／聯絡文案、頁面 SEO（Google 搜尋結果預覽＋字數提醒）、品牌資訊、網站設定、匯款帳號、運費、通知、AI 客服設定、自動化流程與執行 |
| **會員** | 消費、等級、邀請、RFM 分群、最近的訂單、折價券；直接發一次性的折價券、照現在的規則重算等級（一位或全部）、看這位的客服紀錄 |
| **訂單** | 搜尋（單號、收件人、電話、Email）；等出貨／待付款／已出貨／已完成／已取消／全部，捲到底載入更早的；一次選好幾張標記出貨或完成；出貨後補上、改物流單號；訂單內容：品項、金額、收件、付款（匯款單標出「客人說的、還沒對帳」，看過帳單可以確認收款）、物流單號與貨態、託運單、7-11 取貨單號、電子發票（載具、統編、捐贈）、退款；標記已出貨、已完成、取消、退款；分享追蹤頁、出貨單 |
| **收件匣** | 「現在」：客服信（等最久的在前）、Xena 轉給專人的網站對話、新的專案詢問、信箱（不是客服對話的信：轉成客服對話或收起來）；客服信可以看這位客人的訂單、直接回信（Xena 擬回覆、潤飾）、結案。「全部紀錄」：所有網站過去的官網與 LINE 對話、客服信、專案詢問，結束了的也在；照日子分段、搜尋客人與內容、只看某個管道，捲到底載入更早的；專案詢問可以標已回覆、封存 |
| **搜尋** | 分頁列右邊的放大鏡：一次搜所有網站——訂單編號、收件人、電話、會員、折價碼、商品（商店網站的 search），以及每個網站的文章、作品、服務、FAQ（內容集合的 list）；結果照網站分組，點了直接打開；客服的對話與信在「在客服紀錄找」一鍵搜收件匣的全部紀錄 |
| **我** | 首頁右上角的頭像（iPad 在側欄）：帳號、各網站的職能、通知、安全（Face ID）、Xena、console、登出（只撤銷這台裝置、不再收到通知） |
| **Xena 對話** | tab bar 上面常駐的小條點開；和網頁版同一個 Xena、同一份對話紀錄；查了什麼逐筆顯示，要改東西出確認卡片 |

### 通知

網站要通知後台人員的事（客人在等回覆、Xena 轉真人、新訂單、物流異常、等你決定的自動化…）也送到 App：

- **誰收什麼由網站決定**，和網站後台的手機推播（Web Push）同一套：職能、自己在網站的通知設定、勿擾時段、訊息預覽。
  網站把該收到的人交給 console，console 經 Apple 的推播（APNs）送到他登記過的 iPhone、iPad。不用先在瀏覽器開通知
- **第一次**：首頁出現「打開通知」的卡片，說明會通知什麼，按了才跳系統的詢問。允許後 App 向 Apple 拿 device token，
  登記到 console（`/api/app/devices`；Xcode 直接裝的是測試環境、TestFlight 與 App Store 是正式環境，App 自己看簽章判斷）
- **我 → 通知**：這台裝置的狀態、送一則測試通知、每個網站開或關；有個人通知設定的網站（黃毛丫頭）可以直接改哪些事要通知、
  勿擾時段（緊急的照樣通知）、訊息預覽——和網站後台「通知設定 → 手機推播」是同一份
- **點通知直接打開那件事**：客服信、訂單、Xena 的網站對話、等你決定的自動化執行、新的專案詢問（收件匣的那一段）；
  通知依網站分組，同一件事的新通知取代舊的，轉真人、等你決定這類緊急的在專注模式也會出現。App 開著時照樣跳出來，首頁與收件匣跟著更新
- App 圖示上的數字＝收件匣在等的（客人在等回覆＋轉給專人＋新的詢問）
- 登出時從 console 移除這台裝置；撤銷 App 的授權、被移出網站的人也不會再收到

伺服器要設定 Apple 的推播金鑰（console 的 `APNS_KEY`、`APNS_KEY_ID`、`APNS_TEAM_ID`，見 atelier-cms 的 README）；
沒設定時「我 → 通知」會說「伺服器還沒設定推播」。

### Face ID

- **鎖住 App**（預設開）：打開 App、離開超過設定的時間（立刻／1、5、15 分鐘／1 小時，預設 1 分鐘）回來要先解鎖；
  沒有 Face ID／Touch ID 的裝置用裝置密碼。鎖定畫面放在自己的視窗，連打開中的 Xena、確認卡片、編輯畫面都蓋得住
- **切換 App 時蓋住畫面**：多工畫面、拉下通知中心時看不到訂單與客人資料
- **退款、刪除前再驗證一次**（預設開）：要打字確認或標成危險的動作，在 App 的確認卡片與 Xena 的確認卡片按下去之前都要再驗證
- 這三個在「我 → 安全」調整（存在這台裝置）；關掉保護也要先驗證，借手機的人不能自己關

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
權限照各網站的職能。App 是人在操作的後台，網站的「AI 連接器」設定（關閉、只能查詢、方案不含外部 AI）只管 Claude／ChatGPT 這類 AI，不影響 App。

## 伺服器（atelier-cms，console）

| 端點 | 用途 |
|---|---|
| `/api/oauth/authorize`、`/api/oauth/token`、`/api/oauth/revoke` | 登入：第一方的公開 client `studiox-app`（PKCE、回傳網址 `studiox-console://oauth`）。用系統的登入視窗打開 console 的登入頁（Apple、Email、邀請都一樣），登入後直接回 App，不經過 AI 連接器的同意畫面。每台裝置各自一組 token（access 1 小時、refresh 30 天輪替），和 AI 連接器互不影響 |
| `GET /api/app/me` | 登入的人、可以管理的網站（圖示、7 天流量、後台網址、能用的工具） |
| `GET /api/app/schema?site=` | 網站的資料與欄位定義（網站的 relay 方法 `site/schema`） |
| `GET /api/app/record?site=&entity=&id=` | 一筆資料現在的欄位值（網站的 `site/record`） |
| `POST /api/mcp` | 各網站的資料與動作：`list`／`get`（order、support_thread、assistant_conversation、inquiry）、`traffic_report`、`ops_report`、`update_order`、`bulk_update_orders`、`refund_order`、`reply_support`、`update` |
| `/api/copilot/*` | Xena：對話（SSE）、確認卡片、對話紀錄 |
| `/api/app/devices`、`/api/app/devices/test` | 通知：登記這台裝置、關掉哪些網站、登出時移除、送測試通知 |
| `GET/PUT /api/app/notifications?site=` | 自己在某個網站的通知設定（網站的 `site/push-prefs`） |

token 存在 Keychain（這台裝置、解鎖後才讀得到）。console 的「AI → 連接外部 AI」看得到「StudioX App」，撤銷＝所有裝置登出。

## 程式結構

```
StudioXConsole/
  App/         進入點、分頁與側欄、選單列的快捷鍵、AppModel（登入狀態、網站清單、欄位定義、導覽、通知打開的頁面）、
               AppDelegate（通知的 token 與點擊）、鎖定畫面
  Search/      所有網站一起搜
  Brand/       顏色、字（Inter Tight＋Instrument Serif，Fonts/）、動態、平面標誌
  Components/  按鈕、標籤、卡片、細線清單、區塊標題、數字、欄位、空狀態、確認（兩步驟寫入）、招牌元件
  Welcome/     歡迎頁（3D 玻璃 Logo 的 WKWebView ＋ 登入面板）與打包好的 welcome.html / welcome.js
  Home/        Xena 首頁、Briefing（各網站的待辦與報表，同時拿）
  Sites/       網站、網站的工作區（iPad）、概況、流量、Google 搜尋
  CMS/         照網站欄位定義畫的清單與編輯畫面、欄位、預覽、圖片、會員、攤位菜單、FAQ、信箱
  Orders/      訂單、訂單內容
  Inbox/       收件匣、客服信、Xena 的網站對話
  Account/     設定（首頁右上角的齒輪／iPad 側欄）：外觀、字的大小、Xena 怎麼說話、首頁放哪些、通知、安全
  Xena/        3D 水珠（XenaOrb.metal：studiox.tw Xena 介紹頁的 orb3d.ts 搬到 Metal）、對話（XenaSession）、對話畫面
  Voice/       用說的跟 Xena 聊：XenaSpeech（耳朵：iOS 26 SpeechAnalyzer，不支援就 SFSpeechRecognizer；嘴巴：AVSpeechSynthesizer 中文（台灣）聲音）、
               XenaConversation（一來一往、停一下就當說完、她回一句說一句、點水珠打斷）、XenaVoiceView（整個畫面）、
               XenaLocal（Apple Intelligence／Foundation Models，語音先經過它再跟雲端 Xena 配合：你說的每一句先聽懂——切頁、念卡片、再說一次、確認／取消、選選項、閒聊、結束在手機上馬上做；其他的整理好交給 Xena，她針對內容馬上先回一句（串流，一寫好就說）；查資料時說在查什麼、等太久說一聲；回答太長濃縮成重點＋卡片；首頁開場白。寫出來的數字都核對過才用）
  Model/       資料（照網站工具回的 JSON）、欄位定義（Schema）、Xena 的事件
  Services/    Auth（OAuth＋PKCE＋Keychain）、ConsoleAPI（token 自動換新、MCP、欄位定義、上傳、通知、Xena 的 SSE）、SiteData（各工具）、
               PushCenter（通知）、AppLock（Face ID）、AppSettings（設定頁可以微調的偏好）
Web/
  welcome/     歡迎頁的打包（esbuild；logo3d.ts 複製自 studio_website）
  assets/      從後台原始碼產生的圖：icons.cjs（Heroicons）
ci/asc.py      App Store Connect API（TestFlight 流程：App ID、這一次專用的憑證與描述檔、測試內容、內部測試）
ci/appstore.py App Store 上架（上架資料、價格、地區、截圖、build、審核說明、送審）；ci/appstore/ 宣傳圖合成與上架文字
ci_scripts/    Xcode Cloud 用的（測試內容）
.github/workflows/
  ios.yml        每次推上來編一次（模擬器、不簽章）
  testflight.yml 推上來就出一版 TestFlight
  ui-screenshots.yml  示範模式的 UI 截圖（[screenshots]、[appstore-shots]）
  appstore.yml   App Store 上架、送審（[appstore]、[appstore-submit]）
```

Swift 6、預設 `@MainActor`、`@Observable`、SwiftUI＋Liquid Glass、Swift Charts，沒有第三方套件。

## 還沒做

- 小工具（今天的訂單、等你回覆的數字）、App Intents（「問 Xena 今天營收」）
- 通知上直接回覆、標記出貨（通知的動作按鈕）
