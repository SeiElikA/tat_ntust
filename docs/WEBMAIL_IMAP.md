# 內建信箱：IMAP / SMTP 用戶端

> 開發計畫與實作指南，寫給接手開工的人。
>
> 調查日期 **2026-09-06**，探測對象 `mail.ntust.edu.tw` / `140.118.31.91`。
> 底下標「已驗證」的是真的連上去測過的，標「未驗證」的**一定要先做 Phase 0**，
> 不要憑這份文件的樂觀語氣直接開工。

---

## 0. 一句話

學校信箱是 Openfind **Mail2000 V8**，對外開著 IMAPS 993 與 SMTPS 465，
協定層完全可行。介面翻修 2.0.0 已經把舊的 WebMail WebView 整個移除，所以這
是一個**從零開始的新功能**，沒有舊路徑要並存、沒有欄位會衝突、也沒有退路要
維護。

剩下兩個代價：App 要**長期保管一組可重放的明文密碼**（Mail2000 只有
`AUTH=LOGIN`，沒有 OAuth，也發不出應用程式專用密碼）；伺服器的 IMAP 擴充少到
只能做**輪詢式的陽春信箱**——沒有推播、沒有增量同步、沒有伺服器端排序。

另外信箱密碼**與 SSO 密碼是兩組不同的密碼**，使用者一定會先填錯，輸入的
對話框必須先講清楚這件事。

---

## 1. 現況：什麼都沒有

**信箱功能在 2.0.0 已經被整個移除。** `943a2d7 介面翻修 2.0.0` 拿掉了：

| 移除的東西 | 原本的作用 |
| --- | --- |
| `sub_system_page.dart` 的 `buildMail()` | 開 WebView 到 `mail.ntust.edu.tw`，並用 `evaluateJavascript` 往 SSO 表單塞帳密 |
| `lib/ui/pages/password/webmail_password_dialog.dart` | 輸入 WebMail 密碼的對話框 |
| `UserDataJson.webMailPassword` | 存在 Keychain / Keystore 的 WebMail 密碼 |
| `CredentialsStore` / `Model` 的 webMail 存取器 | 上面那個欄位的門面 |

現在 `grep -ri webmail lib/` 是空的，資訊系統頁也沒有任何信箱入口。

**這對本計畫是好事，不是壞事。** 早期版本的計畫有一大段在處理「新舊並存」：
不能沿用 `webMailPassword`（那格裝的是 SSO 密碼）、WebView 要留著當退路、
Phase 3 才能下架、下架時還要寫版本閘門清舊值。這些全部消失了：

- 沒有欄位衝突，直接在只有兩個欄位的 `UserDataJson` 上加第三個。
- 沒有 fallback 要維護，Phase 1 做出來就是唯一路徑。
- 沒有「既有使用者手上有一組 WebMail 密碼」的狀態——那個欄位連解碼都已經
  不存在了，舊的 secure storage blob 裡就算還留著字串也會被直接忽略。

代價是**入口要重新做**：`lib/ui/pages/other/other_page.dart` 的「更多」頁是
現在唯一合理的落點，見 §4.1。

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

### 2.5 登入之後才看得到的（2026-09-10，真帳號實測）

**登入後的 CAPABILITY 跟登入前一模一樣**：
`IMAP4 IMAP4REV1 AUTH=LOGIN LITERAL+ ID NAMESPACE STARTTLS`。
沒有任何擴充是登入後才冒出來的，§5 的限制全數成立。

**資料夾清單**（`LIST "" "*"`，名稱已從 modified UTF-7 解回）：

| 資料夾 | 角色 | 來源 |
| --- | --- | --- |
| `INBOX` | 收件匣 | — |
| `寄件備份匣` | 寄件備份 | Mail2000 內建 |
| `草稿匣` | 草稿 | Mail2000 內建 |
| `回收筒` | 垃圾桶 | Mail2000 內建 |
| `廣告信匣` | 垃圾信 | Mail2000 內建 |
| `Sent Messages` / `Drafts` / `Deleted Messages` / `Junk` / `Archive` / `Notes` | 同上的英文版 | 郵件軟體（Apple Mail 之類）自己建的 |

**每一個資料夾的 flags 都是空的**——實測證實伺服器不回任何 `\Drafts`
`\Sent` `\Trash` 屬性，角色只能靠名字判斷。而且**同一個角色有兩套名字並存**：
中文那套是 Mail2000 的原生資料夾，英文那套是使用者接過的郵件軟體建立的。

實作上必須兩套都認，而且**不能假設英文那套存在**（沒接過其他郵件軟體的帳號
只會有中文那五個）。寫死一張對照表，找不到就退回「只顯示 INBOX」，不要猜。

---

## 3. Phase 0：門檻

**未結的兩題沒過就不要進 Phase 1。** 兩題都需要一組真的學生帳號，
所以只能由人來做，agent 不要自己找帳號密碼來試。

> 驗證時的鐵則：**不要**把真帳號密碼寫進 repo、測試 fixture、log 或 commit。
> 驗完就清掉。

### 門檻 A：IMAP 開不開、用哪一組密碼 — ✅ 已結（2026-09-06）

**結論：IMAP 對一般帳號是開的，而且 Mail2000 的密碼與 SSO 密碼是兩組不同的密碼。**
（由專案擁有者確認：一般郵件軟體登得進去，用的不是 SSO 那一組。）

兩個後果：

1. **`Model.getPassword()` 那組不能拿來登 IMAP。** 那是 SSO 密碼，`LOGIN`
   會被拒。要在憑證裡新增一個獨立的 `mailPassword`，見 §4.7。2.0.0 移除了
   `webMailPassword` 之後這件事變得單純——沒有既有欄位會撞名，也沒有舊值要處理。
2. **使用者第一次一定會填錯。** 對多數人來說「學校密碼」只有一組，他們會直接
   填 SSO 那組然後認定 App 壞了。→ 密碼對話框要先講清楚，見 §4.8。

### 門檻 B：Big5 — ✅ 已結（2026-09-10）

用真帳號抓了收件匣最舊的八封，主旨的 encoded-word charset 統計是
`{utf-8: 5, big5: 5, 不明: 7}`——**Big5 確實還在用**，而且不是只出現在遠古信件：
該信箱最早的信是 2023 年，Big5 是學校系統**現在仍會送出**的編碼。

**`enough_mail` 實測解得開**，見 `test/connector/enough_mail_big5_test.dart`
（fixture 是真實信件去識別化後的 `test/fixtures/mail/big5_subject.eml`）。三項都過：

- `MimeMessage.decodeSubject()` —— 主旨是**跨行折疊成兩段 encoded-word**，
  那正是天真解碼器會斷掉的地方，它處理得了。
- `MailCodec.decodeHeader()` 直接吃原始標頭值也一樣，代表只拿 ENVELOPE 不抓
  整封信的路徑也安全。
- `decodeTextPlainPart()` 解 Big5 內文，沒有 U+FFFD 替換字元。

所以**不需要**動用 `charset_converter` 那條退路。

另外多數信件的頂層 `Content-Type` 沒有 charset（multipart），charset 在各
part 上——解碼要走 `BODYSTRUCTURE` 逐 part 判斷，不要只看信件層的 header。

**Big5 不是遠古遺跡**：該信箱最早的信是 2023 年，Big5 是學校系統現在仍會送出
的編碼，不能當成邊角案例略過。

### 門檻 C：寄件者限制 — ✅ 沒有限制（2026-09-10）

實測 `AUTH LOGIN` 成功後：

| 探測 | 結果 |
| --- | --- |
| `MAIL FROM` 自己的位址 → `RCPT TO` 自己 | `250` / `250` |
| `MAIL FROM` **別人的位址** → `RCPT TO` 自己 | `250` / `250` |

**信封寄件者沒有被強制等於登入帳號**，代寄在 envelope 層不會被擋。這對實作
是好消息（不必特別處理 From 改寫），但也代表**不能靠伺服器幫你擋錯**——
`From:` 一定要由 App 自己填成登入帳號，不要讓使用者輸入。

（探測到 `RCPT TO` 就 `RSET`，沒有進入 `DATA`，沒有寄出任何信。）

**還沒驗**：每日寄件量／收件人數上限。這個不真的寄信就測不出來，留到 Phase 2
實際寄信時再觀察。

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
| `lib/ui/pages/mail/mail_password_dialog.dart` | 1 (ui) | 輸入並**當場驗證**信箱密碼；照 `check_password_dialog.dart` 的樣子用 `TatDialog`（見 §4.8） |

憑證要**新增一個獨立欄位** `mailPassword` 存在既有的 `CredentialsStore` 裡，
詳見 §4.7。

**入口**：2.0.0 的底部分頁只剩課表／行事曆／成績／更多四個，資訊系統頁
（`SubSystemPage`）已經改成吃 `serviceId` 的子頁，不再是分頁之一。信箱的入口
放在 `lib/ui/pages/other/other_page.dart`——那一頁已經有 `SectionHeader` +
`_group([_Row(...)])` 的現成樣式（設定區就是這樣排的），加一列 `_Row` 指向
信箱頁即可。**不要**加進 `_categoryGrid` 那六格：那是學校資訊系統的分類，
信箱不屬於它。

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

`AppAuthSession.ensure({})` 會立刻回 `null`（`app_auth_session.dart:92` 的
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
- **Phase 1 採用的是「完全不快取內文」**：每次點開重抓，簡單且沒有一致性問題。
  這也表示 §4.6 那條「登出要遞迴刪 `<support>/mail/`」在 Phase 1 還用不到——
  磁碟上根本沒有這個目錄。真的開了 `MailBodyStore` 才要補那一步。

### 4.6 登出要清什麼

`lib/src/auth/session_cleaner.dart` 的 `logoutAll()` 是「漏一項，換帳號後 B 就
看到 A 的資料」的地方。信箱要加：

- envelope 快取：**不用改**，`CacheStore.clearAll()` 會掃 `cache_` 前綴。
- 新增的 `mailPassword`：**不用改**，`CredentialsStore.clear()`（`:112`）是整個
  `UserDataJson` 換新的，欄位跟著一起沒。
- **內文與附件目錄：要新增一步**。照 `clearWidgetImage` 的樣子多注入一個
  `clearMailBodies`，遞迴刪掉 `<support>/mail/`。**這一步漏掉就是資料外洩。**

### 4.7 憑證：新增 `mailPassword`

門檻 A 已確認 Mail2000 密碼與 SSO 密碼是兩組，所以不能拿 `Model.getPassword()`
去登 IMAP。2.0.0 之後 `UserDataJson` 只剩 `account` 與 `password` 兩個欄位，
加第三個沒有任何衝突。

要改的四個地方：

| 檔案 | 改什麼 |
| --- | --- |
| `lib/src/model/userdata/user_data_json.dart` | 加 `String mailPassword`，建構子預設 `""` |
| `lib/src/model/userdata/user_data_json.g.dart` | `dart run build_runner build --delete-conflicting-outputs` 重新產生，不要手改 |
| `lib/src/store/credentials_store.dart` | 加 `String get mailPassword` 與 `setMailPassword`，鏡像現有的 `account`（`:60`、`:120`）與 `password`（`:62`、`:122`） |
| `lib/src/store/model.dart` | 加 `getMailPassword()` / `setMailPassword()` 門面，鏡像 `:83`、`:85` |

三件不用做的事：

- **不需要資料遷移。** 產生出來的解碼會是 `json['mailPassword'] as String? ?? ""`
  （對照現有的 `user_data_json.g.dart` 對 `account` / `password` 的寫法），舊的
  secure storage blob 沒有這個 key 也解得開，只是拿到空字串——正好就是「還沒
  設定」該有的狀態。
- **不要動 `hasCredentials`**（`credentials_store.dart:64`）。它是
  `account` + `password`，代表「登入 TAT」。沒設定信箱密碼的人仍然是已登入使用者。
- **不要把 `mailPassword` 加進 `UserDataJson.toString()`。** 那個 toString 會進
  log、錯誤回報與 Crashlytics，檔案裡已經寫明理由；`password` 在那裡也只印
  `<已設定>`。

登出不用另外處理：`CredentialsStore.clear()`（`:112`）是整個 `UserDataJson`
換新的，新欄位跟著一起沒。

### 4.8 密碼輸入：一個對話框就夠

**已決策**：不做「這組密碼要去哪裡查／改」的教學或外部連結，直接請使用者填。

範本是 `lib/ui/pages/password/check_password_dialog.dart`——2.0.0 之後對話框
統一走 `TatDialog`（`lib/ui/other/tat_dialog.dart`），不要自己刻 `AlertDialog`。
需要的零件那個檔案都示範過了：`TatDialog(title:, body:, kind:, content:,
primary:, secondary:)`，配 `PasswordField` 當輸入欄。

唯一不能省的是**一句話講清楚這不是校務系統密碼**，否則使用者會反覆輸入同一組
SSO 密碼並認定 App 壞了。這句話放 `TatDialog` 的 `body`。

兩種進入情況，共用同一個 `MailPasswordDialog`：

| 情況 | 判斷式 | `body` 要傳達 |
| --- | --- | --- |
| 還沒設定 | `mailPassword` 是空的 | 這裡要填的是**信箱密碼**，跟登入 TAT 的校務系統密碼不是同一組 |
| 密碼失效 | IMAP 認證失敗 | 同上，外加這次失敗的原因 |

（沒有第三種「既有使用者手上有舊的 WebMail 密碼」——2.0.0 已經把那個欄位
移除了，見 §1。）

實作要點：

- 已實作於 `lib/ui/pages/mail/mail_password_dialog.dart`。
- **輸入後立刻驗證**：拿去做一次 `ImapClient.login()`，成功才 `setMailPassword`
  並 `Model.instance.saveUserData()`。驗證期間用 `TatDialogAction.isLoading`
  把主要按鈕切成讀取中，不要讓使用者以為當掉了。
- 驗證失敗要分辨兩種：認證被拒（密碼錯，留在對話框）與連不上（網路問題，
  可重試）。兩者訊息不同，不要都寫「密碼錯誤」。
- 密碼輸入欄沿用 `lib/ui/pages/password/password_field.dart`。
- `TextEditingController` 與 `FocusNode` 都要 `dispose`
  （`check_password_dialog.dart:34` 已寫明理由：controller 會一路持有明文密碼）。
- 取消就退出信箱，不要做成無法離開的強制畫面。

---

## 5. 協定層的硬規則

伺服器只回 `IMAP4 IMAP4rev1 AUTH=LOGIN LITERAL+ ID NAMESPACE STARTTLS`。
**沒有的擴充決定了實作方式**，每一條都不是選擇題：

| 缺的擴充 | 必須怎麼寫 |
| --- | --- |
| `IDLE`（宣告上沒有，實際上收但不作用——見下方〈IDLE 是個陷阱〉） | 沒有推播。只能輪詢 |
| `MOVE` | 搬信 = `uidCopy` → `uidStore` 加 `\Deleted` → `expunge`。三步之間中斷會在來源留下副本，UI 要能容忍重複 |
| `SORT` / `THREAD` | 排序與對話串全部在客戶端做，代表要先抓回整批 envelope 才能排 |
| （`SEARCH` 有，但慢到不能用） | 見下方〈搜尋為什麼不走伺服器〉 |
| `UIDPLUS` | 寄出／存草稿後拿不到新 UID（沒有 `APPENDUID`），要再 `uidSearchMessages` 才對得回來 |
| `CONDSTORE` / `QRESYNC` | 沒有增量同步。新信靠 `UIDNEXT` 比對；已讀/刪除等 flag 變化只能整個資料夾重抓 flag |
| `SPECIAL-USE` | 認不出哪個是草稿／寄件備份／垃圾桶。實測所有資料夾的 flags 都是空的，只能靠名稱硬對，而且中英文兩套並存——對照表見 §2.5 |
| `ENABLE` / `UTF8=ACCEPT` | 非 ASCII 的資料夾名走 modified UTF-7；`enough_mail` 會處理，但不要自己拼字串 |
| 只有 `AUTH=LOGIN` | 沒有 OAuth、沒有 token、沒有應用程式專用密碼。App 必須存可重放的密碼——見 §6 |

`UIDVALIDITY` 一定要存下來並在每次 select 後比對；變了就把該資料夾的本機快取
整個丟掉重抓（UID 全部作廢）。這是唯一能防「顯示到別封信」的機制。

### IDLE 是個陷阱（2026-09-11 實測）

`CAPABILITY` 沒有宣告 `IDLE`，但**直接送它伺服器會收**，而且回的是合法的續行
`+ idling`，連線掛 13 分鐘也不會被踢。看到這裡很容易得出「其實可以做推播」的
結論——**是錯的**。

實測：一條連線 `SELECT Drafts` 之後進 IDLE，另一條連線 `APPEND` 一封信進同一個
資料夾，然後在 IDLE 那一頭等 **90 秒——一個位元組都沒有**。送 `DONE` 也只回
`OK IDLE terminated`。接著送一句 `NOOP`，`* 2 EXISTS` 立刻就來了。

也就是說：**更新是排著的，伺服器只是從來不主動吐**。它把 `IDLE` 當成一個合法
但沒有作用的指令解析掉。所以「掛一條連線等伺服器通知」在這台機器上不成立，
唯一的辦法是自己問。

一輪「有沒有新信」的檢查（connect + TLS + `LOGIN` + `SELECT` + 收工）實測
**0.30 秒**（三次中位數：0.12 / 0.07 / 0.03 / 0.05 / 0.01）。`SELECT` 就會回
`UIDNEXT`，所以絕大多數輪次連 `FETCH` 都不用發。

`MailWatchController` 就是照這個結論寫的：App 在前景時每分鐘問一次，進背景就
停。背景推播需要有人幫每個使用者掛連線並發 FCM，那是一台伺服器——而 `login_hint`
與 `privacySummaryLocalBody` 已經對使用者說過「不會上傳至任何伺服器」「TAT 沒有
伺服器」。

順帶一提，`APPEND` 回的是 `[APPENDUID 1694139369 215] APPEND completed`——
`UIDPLUS` 的行為也是有的，同樣沒有宣告。**這台伺服器的 `CAPABILITY` 不可信，
兩個方向都不可信**：沒宣告的可能有（IDLE、APPENDUID），宣告了的也未必好用
（`SEARCH` 見下）。要用哪一個擴充就自己測一次。

### 搜尋為什麼不走伺服器（2026-09-10 實測）

`SEARCH` 這台伺服器**有**，但在真實信箱（4366 封）上慢到不能用：

| 操作 | 耗時 | 命中 |
| --- | --- | --- |
| `SEARCH ALL` | 0.1s | 4366 |
| `FETCH` 最新 50 封 envelope | 1.1s | — |
| `FETCH` 最新 200 封 | 3.0s | — |
| `FETCH` 最新 **500** 封 | **7.0s** | — |
| `FETCH` 最新 1000 封 | 14.1s | — |
| `SEARCH HEADER FROM "Bulletin"` | 14.9s | 936 |
| `SEARCH HEADER SUBJECT "Bulletin"` | 16.0s | 936 |
| `SEARCH SUBJECT "Bulletin"` | **69.3s** | 936 |

兩件事要記住：

1. **`SUBJECT` 比 `HEADER SUBJECT` 慢四倍**，結果卻一模一樣（都是 936 封）。
   `enough_mail` 的 `SearchQueryType.subject` 產生的是前者。
2. **主旨與寄件者各查一次會被伺服器踢掉。** 實測回
   `mail.ntust.edu.tw auto logout; idle for too long`——連線在指令跑完前就被
   關掉，搜尋永遠不會回來。畫面上的症狀是轉圈轉到天荒地老。

所以搜尋改成**抓最新 500 封 envelope 回本機篩**（`MailConnector.search`）：
7 秒，比伺服器搜一次還快一倍，而且不會逾時。代價是搜尋範圍限於最近 500 封。
要擴大就是加大 `MailConfig.searchWindow`，成本是線性的（1000 封 14 秒）。

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

`connectToServer` 預設逾時 20 秒，行動網路上偏長，用 `timeout:` 調短
（`MailConfig.connectTimeout`）。

### `enough_mail` 與 `enough_convert` 的三個缺陷（真機上踩到的）

**quoted-printable + 非 Unicode charset 會解爛。** 這是「內文整個亂碼」的成因。
`quoted_printable_mail_codec.dart` 的 `decodeText` 把**連續的** `=XX` 湊成一組
才交給 charset codec，但 Big5 一個字是 lead(0xA1–0xF9) + trail(0x40–0x7E 或
0xA1–0xFE)，落在 0x40–0x7E 的 trail byte 是可列印 ASCII，QP **不會**編碼它。
於是解碼器只拿到孤立的 `=B7`，big5 解不了單一 byte 就吐替換字元，後面的 `s`
原樣留下——「新細明體」變成「?s細明體」。實測一封真的校內信有 **360 個**替換字元。
Shift-JIS 與 GBK 有同樣的結構，一樣會中。

`decodeContentBinary()` 救不了：`mail_codec.dart` 的 `_binaryDecodersByName`
沒有 quoted-printable 這一項，會 fallback 成把原始 QP 文字當 bytes 回傳。

繞道寫在 `MailConnector.decodeBestTextPart`：**只有**「quoted-printable + 非
Unicode charset」這個組合才自己解（`mimeData.render()` 拿原文 → 自己 QP → bytes
→ 用宣告的 charset 解），其餘一律走 `enough_mail`。base64 與 UTF-8 它本來就是
對的，不要為了這個缺陷重寫整條路徑。修完替換字元 360 → 16，CJK 444 → 734；
剩下的 16 個全在 `<style>` 的 `mso-level-text`，那是 Word 的 Symbol 字型單 byte
項目符號，本來就不是合法 Big5。

`test/connector/mail_big5_quoted_printable_test.dart` 有一條**反向哨兵**：斷言
上游輸出**仍然**有替換字元。哪天 enough_mail 修好了那條會變紅，那時就把繞道拿掉。

**`enough_convert` 的 Big5 解碼表少了 14 個碼位。** 這是「主旨裡有一個字變成
`?`」的成因。拿 Python 的 big5 codec 當權威來源掃過全部 13,710 個合法雙位元組
序列，只有這 14 個回 U+FFFD，其餘 13,696 個完全正確：

| bytes | 應為 | | bytes | 應為 | | bytes | 應為 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A1 50 | · | | A1 FE | ／ | | A2 58 | ° |
| A1 B1 | § | | A2 40 | ＼ | | A2 CC | 十 |
| A1 D1 | × | | A2 44 | ¥ | | A2 CE | 卅 |
| A1 D2 | ÷ | | A2 46 | ¢ | | A7 69 | **告** |
| A1 D3 | ± | | A2 47 | £ | | | |

前十三個是 Big5 標準與 ETen 擴充之間那批有爭議的符號，可以不管；**`A7 69` 是
「告」**，而校內公告的主旨幾乎都有「公告」兩個字，所以它天天發作。

同一張表也害到 header：`MailCodec.decodeHeader` 走的就是它。而且 header 的
**Q-encoding 對非 Unicode charset 是全毀的**——它把每個 `=XX` 先當成一個
latin1 字元再拼成字串，等於在 charset 解碼之前就把位元組轉成了字元，Big5 的
雙位元組序列整個對不回去（實測 `=?big5?Q?=A1i=B9q...?=` 解成「�i�q資學�|…」）。
這和上面那條內文 quoted-printable 的缺陷是同一類錯誤，只是發生在另一個檔案。

繞道寫在 `lib/src/util/mail_text_decoder.dart`：`big5()` 只補那 14 個碼位，
其餘原封不動交給 `Big5Codec`；`header()` 自己解 RFC 2047 的 encoded-word
（B 與 Q 都解，**相鄰的 encoded-word 先把位元組接起來再解**——一個 Big5 字
可能被折行切成兩半）。`MailConnector` 的主旨改走 `header()`，內文的非 Unicode
charset 一律走 `bytes()`，不再交給 `enough_mail`。

**不要拿 `Big5Codec` 的 encoder 產測試輸入。** 它不是解碼的忠實反函式：Big5
有一批字對應到兩個碼位（`／` 同時是 A1 FE 與 A2 41），編碼只會挑一個，不在表
裡的字直接變成 `?`；13,710 個碼位裡有 289 個轉一圈回不到原本的位元組。要位元組
就用權威來源。

`test/connector/mail_text_decoder_test.dart` 有一組**反向哨兵**：斷言上游那 14
個碼位**仍然**解不開、`decodeSubject()` **仍然**吐替換字元。哪天修好了那一組會
變紅，那時就把補丁拿掉。

**`decodeDate()` 回 local 而不是 UTC。**
`MimeMessage.decodeDate()` 回的是 **local flag 的 `DateTime`**，不是 UTC——
位移有正確吃進去（實測 `+0800` / `+0000` / `-0500` 的 epoch 差值正確），但拿它
跟 UTC 的 `DateTime` 直接 `==` 不會成立。`MailMessageJson` 存的是
`millisecondsSinceEpoch`，繞開了這個坑；比較與排序都用那個欄位，不要存字串。

---

## 6. 安全要求

這個功能會讓 App **每一次收信都拿明文密碼向外認證**，所以密碼必須長期維持在
可解密狀態。Mail2000 只有 `AUTH=LOGIN`，沒有 OAuth，也發不出應用程式專用密碼，
這組密碼一旦外洩就是整個校內信箱——比 `password`（SSO）以外多出來的那一份風險
全在這裡。

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
      （`check_password_dialog.dart:34` 已有先例與理由說明）。
- [x] **信件裡的遠端圖片預設不載入**（`mail_detail_page.dart` 的
      `customWidgetBuilder`）。信件是不受信任的內容，`<img>` 有相當比例是追蹤
      像素，載下去等於把「這封信被讀了、什麼時候、從哪個 IP」回報給寄件者。
      `cid:` 與 `data:` 這兩種內嵌來源不受影響。要做「顯示圖片」開關是 Phase 2
      之後的事，在那之前寧可少畫也不要默默外送已讀回條。
- [x] **純文字內文一律先跳脫再轉 HTML**（`MailConnector.plainTextToHtml`）。
      下游是 `HtmlWidget`，直接餵純文字的話換行會消失，內文裡的
      `<someone@example.com>` 還會被當標籤吃掉後面一整段。
- [x] **`cid:` 內嵌圖片換成 `data:` URI**（`MailConnector.inlineCidImages`）。
      那是信件自己夾帶的 part，顯示它不對外發任何請求，**沒有**追蹤問題；
      不換的話 `HtmlWidget` 認不得 `cid:`，Outlook 寄來的信會整片空白。
      單張 2 MB、整封 8 MB 的上限，免得一封夾十張圖的公告吃掉幾十 MB。
- [x] **`From:` 由 connector 填成登入帳號，不讓上層或使用者決定。**
      門檻 C 實測伺服器的信封寄件者沒有限制（填別人的位址一樣回 250），
      所以**不能靠伺服器幫忙擋錯**。
- [ ] `privacy-policy.md` 要改：App 的行為從「開一個網頁」變成
      「讀取、暫存並顯示使用者的信件內容」。這是上架審查會看的。

---

## 7. 分階段開發流程

每個 Phase 都是一個可以獨立合併的 PR。2.0.0 已經移除舊的 WebMail WebView，
所以沒有新舊並存的問題，也沒有退路可退——**Phase 1 做出來就是唯一的信箱路徑**，
品質門檻要比有 fallback 時更嚴。

### Phase 0 — 驗證 ✅ 已完成（2026-09-10）

三道門檻都用真帳號跑過了，沒有一道擋住開發：

- 門檻 A：IMAP 對帳號是開的，`AUTH=LOGIN` 用信箱密碼登入成功（§3）。
- 門檻 B：Big5 確實還在用（主旨 encoded-word 五筆），且 `enough_mail` 實測
  解得開，退路用不到（§3）。
- 門檻 C：信封寄件者沒有被限制，代寄不會被擋（§3）。每日寄件上限測不出來，
  留到 Phase 2。
- 資料夾清單已記錄在 §2.5，含「中英文兩套並存、flags 全空」這個實作陷阱。

Phase 0 的驗證腳本刻意**不留在 repo 裡**（它會讀 `.env` 的真帳號）。要重跑就照
§2.4 的公開探測加上一次 `IMAP4_SSL.login()`，驗完即刪。

### Phase 1 — 唯讀收件匣（約 1–2 週）

> **真機驗證（2026-09-10，Pixel 8 / Android 16）**：收件匣列表、未讀字重、
> 日期格式、中文與 emoji 都正常。過程中抓到兩個單元測試看不見的 bug，都已修好
> 並補上回歸測試：`initState` 裡同步開對話框造成的 `_debugLocked`（症狀是按下
> 確定後永遠轉圈），以及上面那條 quoted-printable + Big5 的解碼缺陷。
>
> **進度（2026-09-10）**：Phase 1 的骨幹已完成——`mail_config`、
> `mail_message_json`、`mail_connector`、`mail_repository`、`mail_controller`、
> 密碼對話框、收件匣列表頁、內文頁，以及「更多」頁的入口。
> 還沒做的是**寄信**（Phase 2）與**資料夾切換／搜尋**（Phase 3）。

- ~~加相依：`enough_mail: ^2.1.7`~~ 已完成（先不加 `enough_mail_html`）。
- **先做憑證欄位**（§4.7 的四個檔案）與**密碼對話框**（§4.8 的
  `mail_password_dialog.dart`，照 `check_password_dialog.dart` 用 `TatDialog` 寫）。
  這兩件事是這個 Phase 的前置，不是收尾——沒有它們誰都進不了信箱。
- 再做 `mail_config.dart`、`mail_message_json.dart`、`mail_connector.dart`、
  `mail_repository.dart`、`mail_controller.dart`、`lib/ui/pages/mail/mail_list_page.dart`、
  `mail_detail_page.dart`。
- 功能：密碼當場驗證、INBOX envelope 列表、下拉重新整理、讀取單封內文
  （`BODYSTRUCTURE` 選 `text/html`，沒有就退 `text/plain`）、標記已讀、刪除。
- 入口：在 `lib/ui/pages/other/other_page.dart` 加一列 `_Row`（§4.1），
  順手加對應的 l10n key（§8 的五個檔案）。
- 驗收：
  1. 沒設定過密碼的狀態進信箱，看到的是「這跟校務系統密碼不是同一組」的說明，
     而不是一句「密碼錯誤」。
  2. 輸入錯的密碼會當場被擋下來，而不是存進去之後才失敗。
  3. 斷網時顯示 `Stale` 的快取列表並有提示。

### Phase 2 — 寄信 ✅ 已完成（2026-09-10）

- `mail_compose_page.dart` + `MailConnector.send()`。
- 功能：新信、回覆、全部回覆、轉寄、附件。
- **50 MiB 的 `SIZE` 上限要在 UI 擋**，實作用 `MailConfig.maxAttachmentBytes`
  ＝ 35 MB 的**原始檔**大小，留約三成餘裕給 base64 膨脹與標頭。
- 沒有 `UIDPLUS`，寄件備份要自己 `APPEND` 到寄件夾再 `uidSearchMessages` 找回 UID。
- 驗收：寄給自己收得到；超過上限的附件在**選檔當下**就被擋掉，不是寄出才失敗。

### Phase 3 — 資料夾、搜尋、未讀數 ✅ 已完成（2026-09-10）

- `listMailboxes()` + 資料夾切換（名稱對映在 Phase 0 已經記錄）。
- 搜尋走伺服器端 `uidSearchMessages`（`SEARCH` 有，`SORT` 沒有，結果自己排）。
  **`SearchQueryType` 沒有「主旨或寄件者」**，所以是各查一次再取聯集；刻意不查
  內文，`TEXT` 在四千多封的信箱上慢到不能用。
- 未讀數：**只在信箱頁自己顯示，開頁時拉一次**。已決策**不做**主畫面
  tab 的 badge（§9），所以不要動 `lib/ui/screen/main_screen.dart`，
  啟動路徑上不增加任何網路往返。
- 沒有 WebView 要下架，也沒有舊欄位要清——2.0.0 已經先做掉了（§1）。

### 明確不做

- **背景推播新信通知。** 沒有 `IDLE`，加上 iOS 的 BGAppRefresh 排程權在系統
  手上，做出來的東西會延遲數小時甚至不觸發。唯一能做到真推播的架構是
  「自架伺服器代收」，那等於學生的帳號密碼要交到第三方伺服器上——**不要做**。
- **POP3。** 埠開著，但 IMAP 能做的它都做不到，沒有理由。
- **本機全文索引 / 完整離線信箱。** 沒有 `CONDSTORE`，同步成本不划算。

---

## 8. 每個 PR 都要過的專案規矩

```bash
flutter pub get --enforce-lockfile
dart analyze --fatal-infos        # 零 error / 零 warning / 零 info
flutter test                      # 現有 2125 個測試不能退步
python3 tool/deps.py --check      # 分層棘輪：上行邊必須維持 0
```

Flutter 版本鎖在 `.fvmrc`（3.38.5），fvm 與 Puro 都讀得到。**在 worktree 裡開發
要先從主 checkout 複製 `android/app/google-services.json` 與
`ios/Runner/GoogleService-Info.plist`**，那兩個檔案不進版控也不會跟著 worktree 過來。

> `.github/workflows/` 在 2.0.0 那個 commit 被刪掉了，所以上面四道現在**只會在
> 本機跑**，沒有任何自動閘門。`docs/ARCHITECTURE.md:19` 仍寫著「CI GitHub Actions
> 三個 job」，那句話已經對不上——動工的人自己要記得每個 PR 手動跑完這四道。

### 加 l10n 字串要動五個檔案

專案沒有把 `intl_utils` 放進 `dev_dependencies`，而 `lib/generated/` 是**進版控的**。
新增一個 key 要同時改：

1. `lib/l10n/intl_zh_TW.arb`
2. `lib/l10n/intl_en.arb`
3. `lib/generated/l10n.dart`
4. `lib/generated/intl/messages_zh_TW.dart`
5. `lib/generated/intl/messages_en.dart`

三道測試會抓你：

- `test/l10n/arb_translation_test.dart` — 兩份 arb 的 key 必須完全一致，
  而且 **`intl_en.arb` 不准出現任何中日韓字元**（不能拿中文充數）。
- `test/l10n/unused_keys_test.dart` — 每個 key 都必須在 `lib/` 或 `test/` 的
  非註解程式碼裡有讀取點，否則失敗。
- `test/l10n/no_captured_strings_test.dart` — **`R.current.xxx` 不可以寫在欄位
  初始化式或 `initState` 裡**。切語言走 `Get.updateLocale` → `forceAppUpdate()`，
  它重跑 `build()` 但不重建 State，捕捉起來的字串會凍在建立時的語言。信箱頁的
  標題、空狀態文字、對話框文案都要在 `build()` 裡才讀。

### 測試落點

照現有目錄擺：`test/connector/`、`test/repository/`、`test/store/`、
`test/controller/`、`test/ui/`。可用的既有工具：

- `test/helpers/fake_auth_session.dart` — `AuthSession.instance` 的測試替身
  （`requires: {}` 的路徑也要裝，否則 `UninstalledAuthSession` 會拋）。
- `test/helpers/reset_statics.dart` — 各層 `instance` 靜態欄位的重置。
- `test/helpers/test_l10n.dart` — 讓 `R.current` 在沒有 `BuildContext` 時可用。
- `test/helpers/recording_ui.dart` — 攔 `TaskUiDelegate` 的進度框與 toast。
- `test/helpers/finders.dart` — widget 測試的共用 finder。

`MailConnector` 的相依要能被替換掉（建構子注入或可覆寫的靜態工廠），
**測試絕對不可以真的連 `mail.ntust.edu.tw`**。IMAP 與 SMTP 的回應用逐字 fixture
放進 `test/fixtures/mail/`，擺法照現有的 `test/fixtures/` 子目錄慣例。

---

## 9. 已決策 / 待決策

### 已決策（2026-09-06，專案擁有者）

| # | 題目 | 決定 | 落在哪 |
| --- | --- | --- | --- |
| 1 | Mail2000 密碼與 SSO 密碼是否同一組 | **不同組**。接受要求使用者另外設定一組信箱密碼 | §3 門檻 A、§4.7 |
| 2 | 使用者怎麼知道要填哪一組密碼 | 用一個對話框請他填，文案要明講這跟 SSO 密碼不同 | §4.8 |
| 3 | 未讀數要不要上主畫面 tab badge | **不做**。未讀數只在信箱頁內顯示 | §7 Phase 3 |
| 4 | 要不要教使用者去哪裡查／改信箱密碼 | **不做**。直接用一個對話框請使用者填 | §4.8 |

> 決策 1、2 原本各自帶著「不能碰 `webMailPassword`」與「既有使用者會卡住」兩個
> 麻煩前提。2.0.0 移除舊 WebMail 之後那兩個前提都不存在了，決策本身不變，但
> 實作成本比拍板當下低很多。

### 還沒解決

1. **每日寄件量／收件人數上限**。不真的寄信測不出來，Phase 2 再觀察。

---

## 10. 順手記一筆

`pubspec.yaml` 的 `flutter_slidable: ^3.0.1` 註解寫「email使用可左右滑抽屜」，
但整個 `lib/` 沒有任何一處 import 它——是上游留下的死相依。
做信箱列表的滑動操作時剛好會用到它，屆時一併確認版本（最新是 4.0.3）；
若最後決定不用，應該把這個相依刪掉。
