# 新開發項目

> 還沒動工、但已經查證過可行性的功能。
>
> 這裡放的是**調查結果**，不是待辦清單——每一項都寫清楚查到什麼、還沒查到
> 什麼、以及動工前會撞到哪些既有的限制，這樣接手的人不用從頭查一遍。
>
> 已經在做或已經決定不做的事情不放這裡。

---

## App 關著的時候收得到 Moodle 通知

`不可行（缺伺服器）` `工作量 大` `已調查`

**一句話**：站內通知已經做完了（「公告與通知」頁，走 `message_popup_*`，見
docs/MOODLE_REFERENCE.md），但那是「拉」；要做到「推」，得先有一台 airnotifier。

「其它 → 設定 → 同步臺科 Moodle 設定」是 Moodle 通知偏好矩陣的鏡像，一個分頁
對應一個訊息輸出外掛（processor）：

| 分頁 | 有沒有作用 | 為什麼 |
| --- | --- | --- |
| **Email** | ✅ 有 | TAT 什麼都不用做，Moodle 的 cron 直接寄信 |
| **Popup**（站內通知） | ✅ 有 | 它控制的就是「公告與通知」頁讀的那張表：關掉之後新的通知不再進那張表。TAT 顯示的「你在 Moodle 關閉了站內通知」則是另一個開關——Moodle 網站上的「停用所有通知」（`emailstop`），這一頁改不到它 |
| **Mobile**（airnotifier） | ❌ **沒有** | TAT 從來沒有呼叫 `core_user_add_user_device` 註冊裝置。TAT 的推播走 Firebase，Moodle 的推播走 airnotifier，兩套不通 |

所以那個 Mobile 開關會把偏好寫回學校伺服器，然後永遠不會產生任何通知——它現在
是這一頁上唯一會騙人的分頁。

**要真的做到「推」**，得先架一台 airnotifier 並讓學校的 Moodle 指過去，再由 TAT
呼叫 `core_user_add_user_device` 註冊裝置 token。那是基礎建設的題目，不是 App
的題目。TAT 這一端能做的只有「開 App 或下拉時去拉」，而那已經做完了。

**如果決定不做**，那 Mobile 分頁應該藏起來。最小的改法是在
`lib/src/controller/setting/moodle_setting_controller.dart` 過濾
`res.preferences.processors`——**要在 controller 裡過濾，不能在頁面裡**，
否則 `TabController.length` 會跟分頁數量對不上。另外要加一個 `tab.isEmpty`
的保護，不然清單被濾空時會留下一條空的分頁列。

---

## 課表分享與匯入（QR）

`可行` `工作量 中` `已調查` → **完整開發計畫見 [docs/COURSE_TABLE_SHARE.md](COURSE_TABLE_SHARE.md)**

用 QR 交換「學期 + 課號清單」，收到的人還原成完整課表，疊在自己的課表上找共
同空堂。**零後端，而且收方不需要登入學校帳號**——還原走的是免憑證的
querycourse。

關鍵事實已經查證：課號是固定 9 碼全大寫英數，所以整包能待在 QR 的
alphanumeric 模式（10 門課只要 version 6）；`getCourseIdList()`
（`course_table_json.dart:188`）能吐出清單，
`getCourseMainInfoListByCourseId()`（`course_connector.dart:171`）能還原回來。

**不要做 base64 或 gzip**——會把 payload 踢進 byte 模式，比明碼更大。

分兩階段，分界點在「完全不碰平台設定」：階段一只做 App 內掃描（相機、相簿選
圖、貼上代碼），階段二才加 Universal Links / App Links 讓系統相機能直接開 App。
階段一的 QR 就已經是完整 URL 格式，所以階段二上線時流通中的 QR 會自動生效。

兩個已經知道會撞到的限制：`addCourseDetailByCourseInfo()` 一遇衝堂就
`return false`，疊圖不能重用它；`getCourseMainInfoListByCourseId()` 是一門課一
個 POST 且循序，10 門課要好幾秒，得併發加進度。

---
## repo 裡還沒有 site_info 的 fixture

`待補` `工作量 小` `已調查`

`MoodleWebApiConnector.wsFunctionBlocked` 與 `preferredUnreadCountFunction`
都是看 `core_webservice_get_site_info` 的 `functions[]` 決定要不要送請求，但
repo 裡從來沒有存過一份真的 `functions[]`，所以「moodle2.ntust.edu.tw 到底
開了哪些 function」全部只能靠 fail-open 的行為推測。文件裡曾經記過「437 個
function」，那是一次性探測時記下的**數量**，清單本身沒有存下來。

用真帳號打一次 site_info、把 `functions[]` 存成 `test/fixtures/` 的第一份
site_info fixture，之後所有 `wsFunctionBlocked` 的判斷才有依據。

---

## 內建信箱改成 App 內收發（IMAP / SMTP）

`可行（有前提）` `工作量 大` `已調查` → **完整開發計畫見 [docs/WEBMAIL_IMAP.md](WEBMAIL_IMAP.md)**

**一句話**：學校信箱是 Openfind Mail2000 V8，已實測對外開著 IMAPS 993 與
SMTPS 465（587 與 25 不通），協定層可行；但伺服器的 IMAP 擴充只有
`IMAP4rev1 AUTH=LOGIN LITERAL+ ID NAMESPACE STARTTLS`，沒有 `IDLE`、`MOVE`、
`SORT`、`UIDPLUS`、`CONDSTORE`、`SPECIAL-USE`，所以只做得出「輪詢式的陽春信箱」，
背景推播新信在沒有自架伺服器的前提下**做不到**。

現況是 `lib/ui/pages/subsystem/sub_system_page.dart:150` 的 WebView 加
`evaluateJavascript` 塞帳密，密碼從來沒有被驗證過，而且靠寫死的 Kendo UI
DOM 結構。

**已確認信箱密碼與 SSO 密碼是兩組不同的密碼**（2026-09-06）。App 現在存的
`webMailPassword` 是塞進 `login.ntust.edu.tw` 的 SSO 密碼，IMAP 不收，所以要
新增一個獨立的 `mailPassword` 欄位，而且**每一位既有使用者第一次開新信箱都會
卡住**——要用一個對話框請他重新填一次，而且文案必須明講這跟校務系統密碼不是同一組。

還沒驗證的是 Big5 舊信解碼與寄信端的限制（寄件者位址、每日上限）。
門檻、分層設計、憑證欄位怎麼加、密碼對話框規格與逐階段實作步驟都寫在
WEBMAIL_IMAP.md。
