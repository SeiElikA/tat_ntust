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

## repo 裡還沒有 site_info 的 fixture

`待補` `工作量 小` `已調查`

`MoodleWebApiConnector.wsFunctionBlocked` 與 `preferredUnreadCountFunction`
都是看 `core_webservice_get_site_info` 的 `functions[]` 決定要不要送請求，但
repo 裡從來沒有存過一份真的 `functions[]`，所以「moodle2.ntust.edu.tw 到底
開了哪些 function」全部只能靠 fail-open 的行為推測。文件裡曾經記過「437 個
function」，那是一次性探測時記下的**數量**，清單本身沒有存下來。

用真帳號打一次 site_info、把 `functions[]` 存成 `test/fixtures/` 的第一份
site_info fixture，之後所有 `wsFunctionBlocked` 的判斷才有依據。
