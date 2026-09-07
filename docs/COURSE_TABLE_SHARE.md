# 課表分享與匯入（QR）

`可行` `工作量 中` `已調查`

用 QR 交換「學期 + 課號清單」，收到的人靠免憑證的 querycourse 還原成完整課
表，疊在自己的課表上找共同空堂。**零後端、收方不需要登入學校帳號。**

分兩階段：階段一只做 App 內掃描，階段二才加系統相機的深連結。分界點刻意選
在「完全不碰平台設定」這條線上——階段一動不到 `AndroidManifest.xml`、動不到
iOS entitlements、不需要簽章金鑰指紋，所以它的風險完全在 Dart 這一側。

---

## 為什麼可行

每一項都查證過，不是推測：

| 事實 | 位置 |
| --- | --- |
| 課號是固定 9 碼全大寫英數（`CS2028701`、`3T5127701`、`AD2001301`） | `test/fixtures/querycourse/courses_1151_sample.json` |
| 課表能吐出去重後的課號清單 | `CourseTableJson.getCourseIdList()`，`lib/src/model/course_table/course_table_json.dart:188` |
| 課號清單能還原成完整課表（課名、時間、教室、老師），**且免憑證** | `CourseConnector.getCourseMainInfoListByCourseId()`，`lib/src/connector/course_connector.dart:171` |
| 學期字串就是 `"${year}${semester}"` 四碼（`1141`、`114H`） | 同上，`course_connector.dart:195` |
| 「匯入課程」加進來的課也有真課號，能正常還原 | `CustomCoursePage` 是從 querycourse 搜尋後挑一門，不是手打的自訂課程 |

最後一項很重要：目前**沒有**真正手動輸入的自訂課程，所以不存在「無法編碼的
課」。哪天加了那種功能，才需要擴充格式（見下方的版本碼）。

---

## 載體格式

QR 的 alphanumeric 模式字集是 `0-9 A-Z` 加上 `空格 $ % * + - . / :`，一個字元
吃 5.5 bits；byte 模式吃 8 bits。**課號全是大寫英數，所以整包能待在
alphanumeric 模式。**

```
HTTPS://NTUST-TAT.WEB.APP/S/TAT11141CS20287013T5127701AD2001301...
└─────── 前綴，28 字元 ──────┘└magic┘└學期┘└──── 課號，固定 9 碼 ────┘
```

- 前綴全大寫是**刻意的**。URL 的 scheme 與 host 依 RFC 3986 大小寫不敏感，
  所以這是一個合法、點得開的網址；而小寫字母不在 alphanumeric 字集裡，寫成
  小寫會把整包踢進 byte 模式。
- `TAT1` 是 magic + 版本。之後改格式用 `TAT2`，解析端保留對 `TAT1` 的支援。
- 學期 4 碼，直接沿用 connector 已經在用的拼法。
- 課號固定 9 碼，**不需要分隔符**。
- 路徑 `/S/` 是大寫。AASA 那邊要設 `"caseSensitive": false`（階段二的事）。

**不要做 base64、不要做 gzip。** 兩者都會強制進 byte 模式，base64 還額外膨脹
33%，結果比明碼更大。

### 大小

| 內容 | 字元數 | 模式 | QR |
| --- | --- | --- | --- |
| 10 門課，全大寫 | 126 | alphanumeric | **version 6，41×41** |
| 10 門課，一般小寫網址 | 126 | byte | version 8，49×49 |
| 20 門課，全大寫 | 216 | alphanumeric | version 8，49×49 |

version 6 是稀疏、隔著桌子也掃得到的尺寸。

### 不放名字

分享者的名字**不進 QR**，三個理由：

1. 中文字在 UTF-8 是 3 bytes，一放進去整包掉進 byte 模式，QR 大一圈。
2. 名字外洩是隱私問題，而 QR 沒有撤銷機制。
3. 由匯入者自己命名（掃完跳「這是誰的課表？」）本來就比較好用——你在通訊錄
   裡也是自己決定備註名稱。

### 不需要 checksum

QR 標準本身有 Reed-Solomon 糾錯。magic 字串加上「長度必須是 `28 + 8 + 9k`」
的嚴格驗證就足以擋掉別的 App 的 QR。

---

## 階段一：App 內掃描

### 範圍

**要做的：**

1. `lib/src/util/course_table_share_codec.dart`——編碼與解碼，純函式
2. 分享頁：全螢幕 QR（提高螢幕亮度），底下一行「請用 TAT 掃描」
3. 匯入頁：相機掃描、**從相簿選圖**、**貼上代碼**三條路徑
4. `lib/src/store/shared_table_store.dart`——已匯入課表的儲存
5. 已匯入清單的管理（改名、刪除）
6. 疊圖與共同空堂

**明確不做的（留給階段二）：**

- `AndroidManifest.xml` 的 intent-filter
- iOS 的 Associated Domains 與 entitlements
- `assetlinks.json`、`apple-app-site-association`
- `app_links` 套件
- 任何跟簽章金鑰指紋有關的事

### 三條匯入路徑，缺一不可

| 路徑 | 場景 | 實作 |
| --- | --- | --- |
| 相機掃描 | 面對面 | `mobile_scanner` |
| **相簿選圖** | **QR 截圖丟到 LINE 群** | `mobile_scanner` 的 `analyzeImage()` + 既有的 `image_picker` |
| **貼上代碼** | 沒裝 App 的人先拿到字串 | 純文字輸入框 |

相簿選圖不是附加功能。學生會把 QR 截圖丟進 LINE，而收到的人**沒辦法用自己的
手機掃自己的螢幕**——少了這條路徑，這個功能在群組裡是廢的。

### 落地頁（可選，可以延到階段二）

階段一如果有人用系統相機掃 TAT 的 QR，會開瀏覽器連到 `ntust-tat.web.app`，
而那裡什麼都沒有，看起來像壞掉。

補救成本很低：Firebase Hosting（你已經有 `ntust-tat` 專案，見
`lib/firebase_options.dart:57`）部署一頁靜態 HTML，寫「有人分享課表給你，請用
TAT App 掃描」加下載連結加可複製的短碼。這**不是** App Links，只是一個靜態
檔案，不碰任何平台設定。

想把階段一壓到最小的話這項可以砍，代價就是那個 404。

### 套件

| 用途 | 套件 | 版本 | 授權 |
| --- | --- | --- | --- |
| 產生 QR | `qr_flutter` | 4.1.0 | BSD-3 |
| 掃描 QR | `mobile_scanner` | 7.4.0 | BSD-3 |

加之前先跑 `flutter pub add --dry-run`。pubspec 裡已經有好幾個「卡在某版因為
Dart SDK」的註解（本專案的 Flutter 3.38.5 帶的是 Dart 3.10.4），`mobile_scanner`
7.x 有可能拉高 `minSdkVersion` 或 iOS deployment target。

另外 `mobile_scanner` 在 Android 走 ML Kit，會讓 APK 明顯變大；可以改用 Play
Services 的 unbundled 版本緩解。

### 要先驗證的假設

**qr.dart 會不會自動選 alphanumeric 模式。** `QrCode.fromData` 有自動模式偵
測，很有把握它會，但這直接決定 QR 大小。寫一個測試斷言「126 字元的 payload
產出的 version ≤ 6」把它釘住——如果斷言掛了，代表得手動指定模式。

### 效能：還原是每門課一個請求

`getCourseMainInfoListByCourseId` 是 `for (var courseId in courseIds)` 迴圈，
**一門課一個 POST，而且循序**（`course_connector.dart:177`）。10 門課就是 10 次
來回，實測會是好幾秒。

做法：併發上限 3～4 條（別對學校主機一次開 10 條）+ 進度顯示（`3/10 正在還
原…`）。這個函式目前只被「匯入課程」以單門課呼叫，改成併發要留意既有呼叫點。

### 儲存：開新的，不要動既有的

`CourseTableStore`（`lib/src/store/course_table_store.dart`）以
`(studentId, semester)` 為主鍵，而且它的 `tables` 直接餵給收藏課表 UI
（`course_controller.dart:82` 的 `favorites`）。把別人的課表塞進去會污染那份
清單。

開 `lib/src/store/shared_table_store.dart`，key `shared_course_table_list`，
每筆存：

```
{ label: "阿明", payload: "HTTPS://...", table: <快取的 CourseTableJson>, importedAt: ... }
```

`payload` 是真相來源（很小，隨時能重新還原成最新資料），`table` 只是避免每次
開啟都重打網路的快取。這樣完全不碰既有的儲存格式。

### 疊圖

**不能重用 `CourseTableJson.addCourseDetailByCourseInfo()`**
（`course_table_json.dart:162`）——它一遇到衝堂就 `return false` 拒絕加入，那是
「加課」語意，不是「疊圖」語意。

疊圖要新寫一層純函式，對每個 `(day, section)` 算出四態：只有我有課 / 只有對
方有課 / 都有課 / **都沒課（共同空堂）**。三人以上疊加時，「都沒課」才是有價
值的答案。

渲染的接點很乾淨：`course_table_page.dart:210-211` 走的是
`courseTableControl.getCourseInfo(day, section)` 與
`getCourseInfoColor(day, section)`。在 `CourseTableControl`
（`lib/src/util/course_table_control.dart:37`）加一個 overlay 欄位與模式，讓這兩
個 getter 依模式回不同結果，頁面幾乎不用改。

### 建議的實作順序

1. **codec + 測試**（零相依、零 UI、零網路）。做完就能確定載體設計是對的。
2. 儲存層
3. 分享頁（產生 QR）
4. 匯入頁（三條路徑）
5. 疊圖

第 1 步完全隔離，可以先合。

### 測試

codec 的測試要涵蓋：正常課表、空課表、非 TAT 的 QR、被截斷的字串、小寫、長度
不是 `9k`、暑期學期 `114H`、裸 payload（貼上代碼那條路徑）、以及上面那個
QR version 上限的斷言。

---

## 階段二：系統相機直接開 App

目標：用系統相機掃 QR 就直接開 TAT 並匯入，不強制走 App 內掃描。

因為階段一的 QR 已經是完整 URL，**階段二上線時所有流通中的 QR 自動生效**，
不需要任何人重新分享。

### 為什麼一定是 Universal Links / App Links

自訂 scheme（`tat://`）行不通——iOS 相機與 Android 的掃描器基本上只對
`https://` 提供「點一下開啟」，自訂 scheme 不會跳出可點的提示。

Firebase Dynamic Links **已經在 2025 年 8 月關閉**，不要去找它。這裡用的是
Firebase **Hosting**，完全不同的產品，還活著而且免費。

### 要放上 Firebase Hosting 的東西

`public/.well-known/apple-app-site-association`：

```json
{ "applinks": { "details": [{
  "appIDs": ["<TEAM_ID>.club.ntust.tat"],
  "components": [{ "/": "/S/*", "caseSensitive": false }]
}]}}
```

`public/.well-known/assetlinks.json`：

```json
[{ "relation": ["delegate_permission/common.handle_all_urls"],
   "target": { "namespace": "android_app",
     "package_name": "club.ntust.tat",
     "sha256_cert_fingerprints": ["<SHA256>"] }}]
```

Firebase Hosting 對 `/.well-known/apple-app-site-association` 有內建處理，會自動
用 `application/json` 送出——那正是 Universal Links 最容易踩雷的地方。

### 兩端設定

**Android**——`AndroidManifest.xml` 目前只有 `MAIN` 與 `FLUTTER_NOTIFICATION_CLICK`
兩個 intent-filter，要加第三個：

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="ntust-tat.web.app"
          android:pathPrefix="/S" />
</intent-filter>
```

**iOS**——專案現在完全沒有 entitlements 檔（`ios/Runner/` 底下沒有），要在
Xcode 開 Associated Domains capability 產生 `Runner.entitlements`，填
`applinks:ntust-tat.web.app`，並到開發者後台把 App ID 的 Associated Domains
打開。

順手把 `ios/Runner.xcodeproj/project.pbxproj` 裡混用的
`IPHONEOS_DEPLOYMENT_TARGET`（同時有 14.0 與 15.0）統一。

**程式端**——`app_links` 7.2.1（Apache-2.0）。

### 跟 GetX 整合的兩個地雷

- **冷啟動有 race。** `lib/main.dart:159` 那段初始路由邏輯會決定進 `home` 還是
  `login`；deep link 必須等 store 載入、GetX router 就緒之後才能導航，否則會被
  初始路由蓋掉。把 payload 暫存成 pending，在 `onReady` 之後才消化。
- **不要把匯入擋在登入後面。** 還原課表只靠免憑證的 querycourse，所以沒登入
  的全新安裝也能直接完成匯入。這對轉換率是關鍵。

`MainActivity` 是 `launchMode="singleTop"`，熱啟動走 `onNewIntent`，`app_links`
的 stream 會接到。但 manifest 上還有 `android:clearTaskOnLaunch="true"`，它跟深
連結的返回堆疊互動要實機測。

### 最大的坑：Play App Signing

`assetlinks.json` 裡的 SHA-256 必須是 **Google Play 重簽之後的那把金鑰**
（Play Console → 應用程式完整性），**不是上傳金鑰**。這是 Android App Links 最
常見的死因，而且失敗是靜默的——連結就是不開 App，沒有任何錯誤訊息。

建議 `sha256_cert_fingerprints` 陣列同時放 debug、upload、Play 三把，本機測試
才不用一直改。驗證：

```
adb shell pm verify-app-links --re-verify club.ntust.tat
```

iOS 那邊 AASA 會走 Apple CDN 快取，改完不會立刻生效，測試要重裝。

---

## 已知限制

- **Deferred deep link 做不到。** 沒裝 App 的人點連結 → 落地頁 → 安裝 → 打開，
  payload 已經遺失，iOS 與 Android 都不會傳遞。自己做需要伺服器加指紋比對，不
  值得。替代方案是落地頁顯示可複製的短碼，配合 App 裡的「貼上代碼匯入」。
- **落地頁畫不出課表。** querycourse 幾乎確定沒送 CORS 標頭，瀏覽器的 fetch 會
  被擋。落地頁只能顯示「有人分享課表給你」加下載連結加短碼。
- **同課號會回多筆。** 同一課號開在不同教室會有多筆（`courses_1151_sample.json`
  裡 `AD2001301` 就出現兩次，`parseSearchResult` 的註解也寫了）。還原時要決定合
  併規則還是全部顯示。
- **舊學期可能還原不了。** querycourse 的歷史資料未必完整，分享上學期課表可能
  查不到，要有明確的錯誤訊息而不是空白課表。
- **QR 沒有撤銷機制。** 課表等於一週行蹤表，分享頁要有明確提示。這是純 QR 的
  固有代價。
- **系統相機會顯示一串大寫網址。** 全大寫是為了 QR 密度刻意選的，稍微醜，但也
  讓人一眼看出是 TAT。改小寫只是 QR 大兩個 version。
