# 新開發項目

> 還沒動工、但已經查證過可行性的功能。
>
> 這裡放的是**調查結果**，不是待辦清單——每一項都寫清楚查到什麼、還沒查到
> 什麼、以及動工前會撞到哪些既有的限制，這樣接手的人不用從頭查一遍。
>
> 已經在做或已經決定不做的事情不放這裡。

---

## 在 TAT 裡看 Moodle 通知

`可行` `工作量 中` `已調查`

**一句話**：做得到，但只能是「拉」不能是「推」——TAT 關掉的時候，沒有任何
機制能把 Moodle 的通知送進來。

### 為什麼會有這個題目

「其它 → 設定 → 同步臺科 Moodle 設定」那一頁，是 Moodle 自己的通知偏好矩陣
的鏡像：一個分頁對應一個 Moodle 的訊息輸出外掛（processor），分頁裡每一則
通知一個開關。頁面本身沒有任何 TAT 專屬的東西。

問題是其中一個分頁是假的：

| 分頁 | 有沒有作用 | 為什麼 |
| --- | --- | --- |
| **Email** | ✅ 有 | TAT 什麼都不用做，Moodle 的 cron 直接寄信 |
| **Mobile**（airnotifier） | ❌ **沒有** | TAT 從來沒有呼叫 `core_user_add_user_device` 註冊裝置。TAT 的推播走 Firebase，跟 Moodle 的 airnotifier 是兩套不通的系統 |
| **Popup**（站內通知） | ⚠️ 對 TAT 沒作用，但對使用者**有** | 它控制的是 moodle2 網站上那個鈴鐺。TAT 目前不讀那些通知，所以在 App 裡看不出差別 |

所以那個 Mobile 開關會把偏好寫回學校伺服器，然後永遠不會產生任何通知。

### 關鍵的一件事：要接的是 popup，不是 mobile

直覺會想「把 Mobile 那個開關接起來」——那是錯的方向。註冊 airnotifier 需要
一台 airnotifier 伺服器加上真的裝置 token，而且就算接起來，推播還是走
Moodle 的基礎建設，跟 TAT 現有的 Firebase 推播是兩條路。

**要做的是讀 `popup` 那一欄**：Moodle 把「站內通知」存在資料庫裡，有 Web API
可以讀。TAT 只要定期去拉就好，不需要任何推播基礎建設。

### 技術上查到了什麼

**token 不用動。** `MoodleWebApiConnector.buildLoginLaunch()` 要的是
`service=moodle_mobile_app`——官方 Moodle App 用的同一個標準服務，它的通知
分頁就是靠這個 token。TAT 現在已經用這顆 token 打了兩個 `core_message_*`
的 function（讀寫通知偏好），所以權限這一關是通的。

**要打的 function：**

| function | 用途 |
| --- | --- |
| `message_popup_get_popup_notifications` | 主要的：讀通知清單 |
| `message_popup_get_unread_popup_notification_count` | 未讀數，做紅點用 |
| `core_message_mark_notification_read` | 標記單則已讀 |
| `core_message_mark_all_notifications_as_read` | 全部已讀 |

`core_message_get_conversations` 是**聊天**不是通知，不要拿它。

**猜錯不會當掉。** `MoodleWebApiConnector.wsFunctionBlocked` 會先看 site_info
的 `functions[]` 再決定要不要送，不在清單上就回一個合成的 `accessexception`
並標記 `skippedBeforeRequest: true`。所以萬一學校沒開這些 function，畫面會是
「這個站台不支援」而不是閃退。

### 還沒查到的（動工前要確認）

**repo 裡沒有存過 site_info 的 fixture**，所以無法確認 moodle2.ntust.edu.tw
到底有沒有開放上面那四個 function。文件裡曾經記過「437 個 function」，但那是
一次性探測時記下的**數量**，清單本身沒有存下來。

**有一個零成本的檢查現在就能做**：打開「同步臺科 Moodle 設定」那一頁，
如果出現一個「站內通知 / Popup」的分頁，就代表伺服器有在寫 popup 通知表，
`message_popup_get_popup_notifications` 就會有東西回來。分頁清單直接來自
`core_message_get_user_notification_preferences` 的 `processors`。

### 動工時會撞到的限制

**`max SCC` 棘輪卡在 28/28。** 新頁面如果 import `BasePage` 或 `ErrorPage`，
或者被 `route_utils.dart` import，都會把最大強連通分量頂到 29，
`python3 tool/deps.py --check` 直接紅燈。要繞開——參考
`ResultView` 為什麼要把 `errorBuilder` 從呼叫端注入進來（見
`lib/ui/components/page/result_view.dart` 的註解），那正是為了同一件事。

**要抄的樣板是 `lib/ui/pages/course_data/screen/course_announcement_page.dart`**，
不是 `lib/ui/pages/announcement/announcement_page.dart`——後者是 Firebase
Remote Config 的 App 公告，跟 Moodle 無關。

### 規模

大約 3 個新檔案、4 個既有檔案要改：

- `MoodleWebApiConnector` 加四個 wsfunction（全部走既有的 `_callWs` 匯流點）
- 通知的 model
- `MoodleRepository` 加對應的方法（走 `run()`，不要傳 `progressMessage`——
  頁面自己用 `ResultView` 畫 loading）
- 一個列表頁 + 進入點

### 使用者拿得到什麼、拿不到什麼

拿得到：打開 App（或下拉重新整理）時看得到 Moodle 的通知、未讀數、點掉已讀。

**拿不到：App 關著的時候不會有任何提示。** 那需要 Moodle 端把推播送到
Firebase，而 Moodle 的推播管道是 airnotifier，跟 TAT 的 Firebase 是兩套。
要真的做到「推」，得先架 airnotifier 並呼叫 `core_user_add_user_device`——
那是另一個題目，規模大得多。

### 如果不做這個功能

那 Mobile 那個分頁應該藏起來，因為它現在會騙人。最小的改法是在
`lib/src/controller/setting/moodle_setting_controller.dart` 過濾
`res.preferences.processors`——**要在 controller 裡過濾，不能在頁面裡**，
否則 `TabController.length` 會跟分頁數量對不上。另外要加一個
`tab.isEmpty` 的保護，不然清單被濾空時會留下一條空的分頁列。

---
