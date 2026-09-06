# 內建信箱：從 WebView 改成 IMAP / SMTP 用戶端

> 開發計畫與實作指南，寫給接手開工的人。
>
> 調查日期 **2026-09-06**，探測對象 `mail.ntust.edu.tw` / `140.118.31.91`。
> 底下標「已驗證」的是真的連上去測過的，標「未驗證」的**一定要先做 Phase 0**，
> 不要憑這份文件的樂觀語氣直接開工。

---

## 0. 一句話

學校信箱是 Openfind **Mail2000 V8**，對外開著 IMAPS 993 與 SMTPS 465，
協定層完全可行。三個代價：App 從「WebView 借用一次密碼」變成「長期保管一組
可重放的明文密碼」；伺服器的 IMAP 擴充少到只能做**輪詢式的陽春信箱**（沒有
推播、沒有增量同步、沒有伺服器端排序）；而信箱密碼**與 SSO 密碼是兩組不同的
密碼**，所以每一位既有使用者都得再設定一次，輸入的對話框必須講清楚這件事。

---

## 1. 現況：要被取代的東西

| 位置 | 內容 |
| --- | --- |
| `lib/ui/pages/subsystem/sub_system_page.dart:150` | `buildMail()`，開 WebView 到 `https://mail.ntust.edu.tw` |
| 同檔 `:165-182` | `loadDone` 回呼裡 `evaluateJavascript`，在 `login.ntust.edu.tw` 塞 username / password |
| `lib/ui/pages/password/webmail_password_dialog.dart` | 輸入 WebMail 密碼的對話框 |
| `lib/src/store/credentials_store.dart:64` | `webMailPassword`，存在 Keychain / Keystore |

四個問題：

1. **密碼從來沒被驗證過**。`webmail_password_dialog.dart:70` 只檢查非空就
   `setWebMailPassword` 存下去，打錯要等到 WebView 登入失敗才知道。
2. **靠寫死的前端 DOM**。那段 `loginForm.kendoBindingTarget.target.obsCtrl.obsData`
   是 Kendo UI 的內部結構，學校改版就會靜默失效（不會報錯，只是不填）。
3. **只有網頁的能力**。沒有通知、沒有離線、沒有原生搜尋、沒有和 App 其他頁面整合。
4. **WebView 內的密碼注入本身就不理想**：密碼進了 WebView 的 JS 環境。

改成 IMAP 之後 (1) 直接消失（登入當下就驗），(2) 完全消失，(3) 變成可以做，
(4) 換成另一組不同的風險——見 §6。

---

## 2. 已驗證的事實

### 2.1 對外開放的埠

| Port | 狀態 | Banner / 備註 |
| --- | --- | --- |
| 993 IMAPS | **OPEN** | TLS 1.2，憑證 `CN=*.ntust.edu.tw`，SAN 含 `ntust.edu.tw`，有效至 2027-02-18 |
| 465 SMTPS | **OPEN** | `220 mail.ntust.edu.tw ESMTP Service(Mail2000 ESMTP Server V8.00) ready` |
| 143 IMAP | OPEN | 有 `STARTTLS`，但沒有理由用它 |
| 110 / 995 POP3(S) | OPEN | `+OK MPOP3D V8.0` |
| 587 submission | **timeout** | 對外不通 |
| 25 SMTP | **timeout** | 對外不通 |

→ **收信一律 993、寄信一律 465，兩邊都是 implicit TLS**（`isSecure: true`）。
587 + STARTTLS 是多數教學文的預設路徑，在這台機器上是死路，不要浪費時間。

### 2.2 IMAP CAPABILITY（993，登入前）

```
* OK [CAPABILITY IMAP4 IMAP4rev1 AUTH=LOGIN LITERAL+ ID NAMESPACE STARTTLS]
```

### 2.3 SMTP EHLO 回應（465）

```
250-mail.ntust.edu.tw
250-PIPELINING
250-8BITMIME
250-AUTH=LOGIN
250-AUTH LOGIN
250 SIZE 52428800
```

→ 附件總大小上限 **52428800 bytes = 50 MiB**（是編碼後的 MIME 大小，
base64 會膨脹約 4/3，UI 要用約 **37 MB** 的原始檔上限去擋才安全）。

### 2.4 自己重跑這份探測

不需要帳號密碼，任何時候都可以重驗（例如懷疑學校改設定了）：

```bash
python3 - <<'PY'
import socket, ssl
ctx = ssl.create_default_context(); host = "mail.ntust.edu.tw"
def tls(port, cmds):
    s = ctx.wrap_socket(socket.create_connection((host, port), timeout=6), server_hostname=host)
    print(f"--- {port} {s.version()}"); s.settimeout(5); print(s.recv(300))
    for c in cmds:
        s.sendall(c); import time; time.sleep(0.4); print(s.recv(600))
    s.close()
tls(993, [b'a1 CAPABILITY\r\n'])
tls(465, [b'EHLO tat.app\r\n'])
PY
```

---

## 3. Phase 0：門檻

**未結的兩題沒過就不要進 Phase 1。** 兩題都需要一組真的學生帳號，
所以只能由人來做，agent 不要自己找帳號密碼來試。

> 驗證時的鐵則：**不要**把真帳號密碼寫進 repo、測試 fixture、log 或 commit。
> 驗完就清掉。

### 門檻 A：IMAP 開不開、用哪一組密碼 — ✅ 已結（2026-09-06）

**結論：IMAP 對一般帳號是開的，而且 Mail2000 的密碼與 SSO 密碼是兩組不同的密碼。**
（由專案擁有者確認：一般郵件軟體登得進去，用的不是 SSO 那一組。）

這個答案是整個計畫裡影響最大的一件事，兩個直接後果：

1. **不能沿用 `webMailPassword` 這個欄位。** 它現在裝的是被塞進
   `login.ntust.edu.tw` 的 SSO 密碼，拿去做 IMAP `LOGIN` 一定失敗；而且
   Phase 1–2 期間 WebView 入口還要留著，那條路徑仍然需要這組 SSO 密碼。
   → 要新增一個獨立欄位，見 §4.7。
2. **既有使用者第一次開新信箱一定會卡住。** 他們手上沒有 Mail2000 密碼的概念，
   只會覺得「我明明設過 WebMail 密碼了」。→ 密碼對話框的文案必須點破這件事，見 §4.8。

### 門檻 B：Big5 解得開嗎

台灣校內信箱的舊信常是 `charset=big5`。`enough_mail` 靠
`enough_convert` 解碼，該套件的支援清單裡有 Big5，但**沒有實測過這台伺服器**。

驗法：撈一封 2015 年以前的中文信，確認主旨與內文都不是亂碼。
真的解不開時退路是專案已有的 `charset_converter: ^2.3.0`（原生轉碼）。

### 門檻 C：寄信的限制

`AUTH LOGIN` 通過之後還有兩件事沒驗：

- 寄件者位址是否必須等於登入帳號（多數學校強制，會拒絕代寄）。
- 有沒有每日寄件量／收件人數上限。

驗法：用同一個郵件軟體寄一封給自己，再寄一封 From 改成別的位址，看哪個被拒。

---

## 4. 設計

### 4.1 分層落點

完全落在現有分層裡，**不會產生上行邊**，`python3 tool/deps.py --check` 過得了。

| 新檔案 | rank | 職責 |
| --- | --- | --- |
| `lib/src/model/mail/mail_message_json.dart` | 8 (model) | envelope 的持久化形狀，`json_serializable` |
| `lib/src/model/mail/mail_folder_json.dart` | 8 (model) | 資料夾 |
| `lib/src/config/mail_config.dart` | 7 (config) | host / port / 逾時等常數 |
| `lib/src/store/mail_body_store.dart` | 6 (store) | 內文與附件落磁碟（見 §4.5） |
| `lib/src/connector/mail_connector.dart` | 4 (connector) | **唯一**碰 `ImapClient` / `SmtpClient` 的地方 |
| `lib/src/repository/mail_repository.dart` | 2.5 (repository) | 對外只回 `Result<T>`，套 `run()` |
| `lib/src/controller/mail_controller.dart` | 2 (controller) | 頁面狀態，只回資料不開對話框 |
| `lib/ui/pages/mail/` | 1 (ui) | 列表頁、內文頁、撰寫頁 |
| `lib/ui/pages/mail/mail_password_dialog.dart` | 1 (ui) | 輸入並**當場驗證**信箱密碼；鏡像現有的 `webmail_password_dialog.dart`（見 §4.7、§4.8） |

憑證要**新增一個獨立欄位**存在既有的 `CredentialsStore` 裡，
**不可以**沿用 `webMailPassword`——那一格裝的是 SSO 密碼。詳見 §4.7。

> **要一併更新 `docs/ARCHITECTURE.md`**：那份文件現在寫「connector 是唯一的
> HTTP 出口：單一 Dio 加持久化 cookie jar」。IMAP/SMTP 是 raw `SecureSocket`，
> 不走 Dio、不吃 cookie jar、不經過 `RedactingLogInterceptor`、Alice 也攔不到。
> 這是 App 的**第二種對外連線**，文件不改那句話就變成假的。

### 4.2 不要新增 `SystemId`

`lib/src/auth/auth_session.dart` 的註解寫得很清楚：`SystemId` 只有兩個成員，
「多一個成員就多一顆會被漏清的旗標」。信箱不該加進去，理由是它的認證模型不同——
IMAP 是**每條連線各自 LOGIN**，沒有需要跨請求維護的 session 狀態，
`ensure/invalidate` 那一套對它沒有意義。

### 4.3 `run()` 照用，`requires` 傳空集合

`AppAuthSession.ensure({})` 會立刻回 `null`（`app_auth_session.dart:85` 的
迴圈跑零次），所以：

```dart
Future<Result<List<MailMessageJson>>> getInbox({bool forceUpdate = false}) =>
    run<List<MailMessageJson>>(
      requires: const {},              // 信箱不依賴 SSO / Moodle
      cache: _inboxCacheKey,
      progressMessage: R.current.loading,
      debugLabel: 'mail.inbox',
      fetch: () => MailConnector.fetchInbox(),
    );
```

這樣就免費拿到：連線探測、進度框、快取回退（`Stale`）、重試迴圈。

### 4.4 錯誤對映

`fetch` 裡丟 `TaskFailure(reason)` 指定原因（見 `lib/src/repository/result.dart`）：

| 情況 | 丟什麼 | UI 行為 |
| --- | --- | --- |
| `mailPassword` 是空的 | `TaskFailure(NotSignedIn())` | 不可重試，畫「設定信箱密碼」按鈕，開 `MailPasswordDialog`（§4.8） |
| IMAP `NO`／認證失敗 | `TaskFailure(FetchFailed(訊息))` | 可重試；**另外**由 controller 開 `MailPasswordDialog` |
| 連線逾時 / socket 斷 | 讓例外逸出 | `run()` 自己依連線狀態分類成 `Offline` 或 `FetchFailed` |
| 資料夾不存在 | `TaskFailure(FetchFailed(...))` | 一般錯誤 |

> **不要**對認證失敗丟 `LoginFailed(detail)`。`run.dart` 的 `_confirmRetry`
> 看到 `LoginFailed` 且 `detail != null` 會把 `offerLoginScreen` 打開，
> 那顆按鈕通往**App 的 SSO 登入頁**，而信箱要的根本是另一組密碼（§4.7）——
> 使用者會被送去改一組跟這個錯誤無關的密碼。

### 4.5 快取：envelope 走 `CacheKey`，內文走磁碟

`CacheKey<T>` 底下是 SharedPreferences 的 JSON blob（`lib/src/store/cache_store.dart`），
**不適合塞信件內文與附件**。切法：

- **envelope 清單**（uid / 主旨 / 寄件者 / 日期 / 已讀旗標 / 有無附件）→ `CacheKey`，
  只留 INBOX 最新 **50 封**。key 名稱**必須以 `cache_` 開頭**（`cache_store.dart:24`
  有 assert），例如 `cache_mail_inbox`——前綴是登出時掃描清除的依據。
- **內文與附件** → `MailBodyStore`，寫在
  `getApplicationSupportDirectory()/mail/<uid>/`，做法照抄
  `calendar_repository.dart` 的檔案處理（先寫暫存檔、驗過內容才 rename）。
- Phase 1 可以先**完全不快取內文**，每次點開重抓，簡單且不會有一致性問題。

### 4.6 登出要清什麼

`lib/src/auth/session_cleaner.dart` 的 `logoutAll()` 是「漏一項，換帳號後 B 就
看到 A 的資料」的地方。信箱要加：

- envelope 快取：**不用改**，`CacheStore.clearAll()` 會掃 `cache_` 前綴。
- `webMailPassword` 與新增的 `mailPassword`：**不用改**，`CredentialsStore.clear()`
  是整個 `UserDataJson` 換新的，兩個欄位一起沒。
- **內文與附件目錄：要新增一步**。照 `clearWidgetImage` 的樣子多注入一個
  `clearMailBodies`，遞迴刪掉 `<support>/mail/`。**這一步漏掉就是資料外洩。**

### 4.7 憑證：新增獨立欄位，不要碰 `webMailPassword`

門檻 A 已確認 Mail2000 密碼與 SSO 密碼是兩組。`webMailPassword` 現在的唯一用途
是餵給 `sub_system_page.dart` 那段 WebView 的 SSO 表單，而那條路徑在 Phase 3
之前都要留著當退路——**覆寫它等於把退路也弄壞**。

要改的四個地方：

| 檔案 | 改什麼 |
| --- | --- |
| `lib/src/model/userdata/user_data_json.dart` | 加 `String mailPassword`，建構子預設 `""` |
| `lib/src/model/userdata/user_data_json.g.dart` | `dart run build_runner build --delete-conflicting-outputs` 重新產生 |
| `lib/src/store/credentials_store.dart` | 加 `String get mailPassword` 與 `setMailPassword`，鏡像現有的 `webMailPassword`（`:64`、`:126`） |
| `lib/src/store/model.dart` | 加 `getMailPassword()` / `setMailPassword()` 門面，鏡像 `:84`、`:86` |

三件不用做的事：

- **不需要資料遷移。** 產生出來的解碼是 `json['mailPassword'] as String? ?? ""`
  （對照現有的 `user_data_json.g.dart:12`），舊的 secure storage blob 沒有這個 key
  也解得開，只是拿到空字串——正好就是「還沒設定」該有的狀態。
- **不要動 `hasCredentials`。** 它是 `account` + `password`，代表「登入 TAT」。
  沒設定信箱密碼的人仍然是已登入使用者。
- **不要把 `mailPassword` 加進 `UserDataJson.toString()`。** 那個 toString 會進
  log、錯誤回報與 Crashlytics（檔案裡已經寫明理由），現有的 `webMailPassword`
  也沒有出現在裡面。

Phase 3 拿掉 WebView 入口時，`webMailPassword` 才可以連同欄位一起刪；清除舊值
寫在 `lib/src/version/app_version.dart` 的 `updateVersionCallback`，照現有
`if (version < Version.parse("1.2.6"))` 的樣子加一段版本閘門。

### 4.8 密碼輸入：一個對話框就夠

**已決策**：不做「這組密碼要去哪裡查／改」的教學或外部連結，直接請使用者填。
只需要一個對話框，做法完全鏡像現有的
`lib/ui/pages/password/webmail_password_dialog.dart`——那個檔案就是同一個模式的
現成範本（`Get.dialog(..., barrierDismissible: false)`，見
`sub_system_page.dart:156`）。

唯一不能省的是**一句話講清楚這不是校務系統密碼**，否則既有使用者會反覆輸入
同一組 SSO 密碼並認定 App 壞了。

三種進入情況，共用同一個 `MailPasswordDialog`，只換那句說明文字：

| 情況 | 判斷式 | 說明文字要傳達 |
| --- | --- | --- |
| 全新使用者 | `mailPassword` 空、`webMailPassword` 也空 | 這裡要填的是**信箱密碼** |
| **既有使用者** | `mailPassword` 空、`webMailPassword` **非空** | 「你之前設定的是校務系統密碼，收發信要另一組**信箱密碼**」 |
| 密碼失效 | IMAP 認證失敗 | 同上，外加這次失敗的原因 |

實作要點：

- **輸入後立刻驗證**：拿去做一次 `ImapClient.login()`，成功才 `setMailPassword`
  並存檔。這是新架構相對舊做法最明顯的改善——舊的
  `webmail_password_dialog.dart:70` 是不驗證就存。
- 驗證失敗要分辨兩種：認證被拒（密碼錯，留在對話框）與連不上（網路問題，
  可重試）。兩者訊息不同，不要都寫「密碼錯誤」。
- 密碼輸入欄沿用 `lib/ui/pages/password/password_field.dart`。
- `TextEditingController` 與 `FocusNode` 都要 `dispose`
  （`webmail_password_dialog.dart:24` 已寫明理由：controller 會一路持有明文密碼）。
- 取消就退出信箱，不要做成無法離開的強制畫面。

---

## 5. 協定層的硬規則

伺服器只回 `IMAP4 IMAP4rev1 AUTH=LOGIN LITERAL+ ID NAMESPACE STARTTLS`。
**沒有的擴充決定了實作方式**，每一條都不是選擇題：

| 缺的擴充 | 必須怎麼寫 |
| --- | --- |
| `IDLE` | 沒有推播。只能輪詢：進頁面抓一次 + 下拉重新整理。不要嘗試長連線等新信 |
| `MOVE` | 搬信 = `uidCopy` → `uidStore` 加 `\Deleted` → `expunge`。三步之間中斷會在來源留下副本，UI 要能容忍重複 |
| `SORT` / `THREAD` | 排序與對話串全部在客戶端做，代表要先抓回整批 envelope 才能排 |
| `UIDPLUS` | 寄出／存草稿後拿不到新 UID（沒有 `APPENDUID`），要再 `uidSearchMessages` 才對得回來 |
| `CONDSTORE` / `QRESYNC` | 沒有增量同步。新信靠 `UIDNEXT` 比對；已讀/刪除等 flag 變化只能整個資料夾重抓 flag |
| `SPECIAL-USE` | 認不出哪個是草稿／寄件備份／垃圾桶，只能用 `listMailboxes()` 回來的**名稱**硬對。Mail2000 的資料夾名可能是中文，要在 Phase 0 一併記錄實際字串 |
| `ENABLE` / `UTF8=ACCEPT` | 非 ASCII 的資料夾名走 modified UTF-7；`enough_mail` 會處理，但不要自己拼字串 |
| 只有 `AUTH=LOGIN` | 沒有 OAuth、沒有 token、沒有應用程式專用密碼。App 必須存可重放的密碼——見 §6 |

`UIDVALIDITY` 一定要存下來並在每次 select 後比對；變了就把該資料夾的本機快取
整個丟掉重抓（UID 全部作廢）。這是唯一能防「顯示到別封信」的機制。

### `enough_mail` 已確認的 API

`enough_mail: ^2.1.7`（2025-08-19；上一版 2.1.6 是 2023-12，**維護很稀，
踩到 bug 大概率要自己 fork 修**）。相依不會撞專案：它宣告 `intl: any`，
不影響 `pubspec.yaml` 裡 `intl: ^0.18.0` 的 `dependency_overrides`。

```dart
// 收信
final imap = ImapClient();                       // isLogEnabled 預設 false
await imap.connectToServer('mail.ntust.edu.tw', 993, isSecure: true);
await imap.login(account, password);             // AUTH=LOGIN
final box = await imap.selectInbox();
final fetch = await imap.fetchMessages(sequence, 'ENVELOPE FLAGS');

// 寄信
final smtp = SmtpClient('ntust.edu.tw');
await smtp.connectToServer('mail.ntust.edu.tw', 465, isSecure: true);
await smtp.ehlo();
await smtp.authenticate(account, password, AuthMechanism.login);
await smtp.sendMessage(mimeMessage);
```

`connectToServer` 預設逾時 20 秒，行動網路上偏長，用 `timeout:` 調短。

---

## 6. 安全要求

改動之後 App 的威脅模型變了：現在密碼只在 WebView 換一次 cookie；改完之後
**每一次收信都要拿明文密碼向外認證**，密碼必須長期維持在可解密狀態。
而 Mail2000 發不出應用程式專用密碼，這組密碼一旦外洩就是整個校內信箱。

開工前把這幾條當驗收條件：

- [ ] `isLogEnabled` 在 `ImapClient` / `SmtpClient` 一律**保持預設 `false`**。
      打開它會把整段 IMAP 對話（含 `LOGIN <帳號> <密碼>`）印到 stdout。
      `smtp_client.dart` 內部有 `if (isLogEnabled)` 分支，release 版絕不能開。
- [ ] 密碼只在呼叫 `login()` / `authenticate()` 的那一刻從 `CredentialsStore`
      讀出來，**不要**存成 connector 的欄位長期握著。
- [ ] 任何 `Log.d` / `Log.e` 都不得帶到密碼或整封信件內容。
- [ ] 新增的 `mailPassword` **不可以**出現在 `UserDataJson.toString()`——
      那個 toString 會進 log、錯誤回報與 Crashlytics（§4.7）。
- [ ] `onBadCertificate` **不要**設定（保持 null＝憑證錯就斷線）。
      憑證是有效的正式憑證，任何「先放行方便測試」的程式碼都不准進 commit。
- [ ] 密碼輸入 UI 沿用 `lib/ui/pages/password/password_field.dart`，
      `TextEditingController` 與 `FocusNode` 都要 `dispose`
      （`webmail_password_dialog.dart:24` 已有先例與理由說明）。
- [ ] `privacy-policy.md` 要改：App 的行為從「開一個網頁」變成
      「讀取、暫存並顯示使用者的信件內容」。這是上架審查會看的。

---

## 7. 分階段開發流程

每個 Phase 都是一個可以獨立合併的 PR。**WebView 入口在 Phase 3 之前一律保留**，
新舊並存，出問題可以立刻退回。

### Phase 0 — 驗證（半天，人工）

- 門檻 A **已結**（2026-09-06）：IMAP 是開的，密碼與 SSO 不同組。
- 還沒做的是門檻 B（Big5）與門檻 C（寄信限制），外加**記錄 `listMailboxes()`
  實際回來的資料夾名稱字串**——沒有 `SPECIAL-USE`，Phase 3 只能靠這份名單硬對。
- 產出：把答案寫回這份文件的 §3。
- **B 沒過**代表舊信會是亂碼，要先換 `charset_converter` 的解法再進 Phase 1；
  **C 沒過**只影響 Phase 2，不擋 Phase 1。

### Phase 1 — 唯讀收件匣（約 1–2 週）

- 加相依：`enough_mail: ^2.1.7`（先不加 `enough_mail_html`）。
- **先做憑證欄位**（§4.7 的四個檔案）與**密碼對話框**（§4.8 的
  `mail_password_dialog.dart`，照現有的 `webmail_password_dialog.dart` 改）。
  這兩件事是這個 Phase 的前置，不是收尾——沒有它們，任何既有使用者都進不了信箱。
- 再做 `mail_config.dart`、`mail_message_json.dart`、`mail_connector.dart`、
  `mail_repository.dart`、`mail_controller.dart`、`lib/ui/pages/mail/mail_list_page.dart`、
  `mail_detail_page.dart`。
- 功能：密碼當場驗證、INBOX envelope 列表、下拉重新整理、讀取單封內文
  （`BODYSTRUCTURE` 選 `text/html`，沒有就退 `text/plain`）、標記已讀、刪除。
- 入口：`sub_system_page.dart` 的 `buildMail()` 改成進新頁面，
  舊的 WebView 路徑降級成該頁面裡的一個「用網頁版開啟」選項
  （**那條路徑仍然讀 `webMailPassword`，不要改它**）。
- 驗收：
  1. 拿一個「已經設過 WebMail 密碼」的裝置狀態進信箱，看到的是「這是另一組
     信箱密碼」的說明，而不是一句「密碼錯誤」。
  2. 輸入錯的密碼會當場被擋下來，而不是存進去之後才失敗。
  3. 斷網時顯示 `Stale` 的快取列表並有提示。

### Phase 2 — 寄信（約 1 週）

- `mail_compose_page.dart` + `MailConnector.send()`。
- 功能：新信、回覆、全部回覆、轉寄、附件。
- **50 MiB 的 `SIZE` 上限要在 UI 擋**，用約 37 MB 的原始檔上限（base64 膨脹）。
- 沒有 `UIDPLUS`，寄件備份要自己 `APPEND` 到寄件夾再 `uidSearchMessages` 找回 UID。
- 驗收：寄給自己收得到；超過上限的附件在**選檔當下**就被擋掉，不是寄出才失敗。

### Phase 3 — 資料夾、搜尋、未讀數（約 1 週）

- `listMailboxes()` + 資料夾切換（名稱對映在 Phase 0 已經記錄）。
- 搜尋走伺服器端 `uidSearchMessages`（`SEARCH` 有，`SORT` 沒有，結果自己排）。
- 未讀數：**只在信箱頁自己顯示，開頁時拉一次**。已決策**不做**主畫面
  tab 的 badge（§9），所以不要動 `lib/ui/screen/main_screen.dart`，
  啟動路徑上不增加任何網路往返。
- 這個 Phase 之後才考慮拿掉 WebView 入口；真的拿掉時一併刪 `webMailPassword`
  欄位並在 `app_version.dart` 加版本閘門清舊值（§4.7）。

### 明確不做

- **背景推播新信通知。** 沒有 `IDLE`，加上 iOS 的 BGAppRefresh 排程權在系統
  手上，做出來的東西會延遲數小時甚至不觸發。唯一能做到真推播的架構是
  「自架伺服器代收」，那等於學生的帳號密碼要交到第三方伺服器上——**不要做**。
- **POP3。** 埠開著，但 IMAP 能做的它都做不到，沒有理由。
- **本機全文索引 / 完整離線信箱。** 沒有 `CONDSTORE`，同步成本不划算。

---

## 8. 每個 PR 都要過的專案規矩

```bash
flutter pub get
dart analyze --fatal-infos        # 零 error / 零 warning / 零 info
flutter test                      # 現有 885 個測試不能退步
python3 tool/deps.py --check      # 分層棘輪：上行邊必須維持 0
```

### 加 l10n 字串要動五個檔案

專案沒有把 `intl_utils` 放進 `dev_dependencies`，而 `lib/generated/` 是**進版控的**。
新增一個 key 要同時改：

1. `lib/l10n/intl_zh_TW.arb`
2. `lib/l10n/intl_en.arb`
3. `lib/generated/l10n.dart`
4. `lib/generated/intl/messages_zh_TW.dart`
5. `lib/generated/intl/messages_en.dart`

兩道測試會抓你：

- `test/l10n/arb_translation_test.dart` — 兩份 arb 的 key 必須完全一致，
  而且 **`intl_en.arb` 不准出現任何中日韓字元**（不能拿中文充數）。
- `test/l10n/unused_keys_test.dart` — 每個 key 都必須在 `lib/` 或 `test/` 的
  非註解程式碼裡有讀取點，否則失敗。

### 測試落點

照現有目錄擺：`test/connector/`、`test/repository/`、`test/store/`、
`test/controller/`、`test/ui/`。可用的既有工具：

- `test/helpers/fake_auth_session.dart` — `AuthSession.instance` 的測試替身
  （`requires: {}` 的路徑也要裝，否則 `UninstalledAuthSession` 會拋）。
- `test/helpers/reset_statics.dart` — 各層 `instance` 靜態欄位的重置。
- `test/helpers/recording_ui.dart` — 攔 `TaskUiDelegate` 的進度框與 toast。
- `test/helpers/test_l10n.dart` — 讓 `R.current` 在沒有 `BuildContext` 時可用。

`MailConnector` 的相依要能被替換掉（建構子注入或可覆寫的靜態工廠），
**測試絕對不可以真的連 `mail.ntust.edu.tw`**。IMAP 回應用逐字 fixture 放在
`test/fixtures/`，照 `test/helpers/moodle_*_fixtures.dart` 的做法。

---

## 9. 已決策 / 待決策

### 已決策（2026-09-06，專案擁有者）

| # | 題目 | 決定 | 落在哪 |
| --- | --- | --- | --- |
| 1 | Mail2000 密碼與 SSO 密碼是否同一組 | **不同組**。接受要求使用者另外設定一組信箱密碼 | §3 門檻 A、§4.7 |
| 2 | 既有使用者的 `webMailPassword` 怎麼辦 | 用一個對話框請他重填，文案要明講這跟 SSO 密碼不同 | §4.8 |
| 3 | 未讀數要不要上主畫面 tab badge | **不做**。未讀數只在信箱頁內顯示 | §7 Phase 3 |
| 4 | 要不要教使用者去哪裡查／改信箱密碼 | **不做**。直接用一個對話框請使用者填 | §4.8 |

### 還沒解決

1. **門檻 B、C 尚未驗證**（§3）。
2. **`listMailboxes()` 的實際資料夾名稱還沒記錄**，Phase 3 需要。

---

## 10. 順手記一筆

`pubspec.yaml` 的 `flutter_slidable: ^3.0.1` 註解寫「email使用可左右滑抽屜」，
但整個 `lib/` 沒有任何一處 import 它——是上游留下的死相依。
做信箱列表的滑動操作時剛好會用到它，屆時一併確認版本（最新是 4.0.3）；
若最後決定不用，應該把這個相依刪掉。
