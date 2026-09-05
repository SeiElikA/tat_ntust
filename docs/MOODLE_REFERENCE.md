# Moodle 串接參考

> 這份文件是**參考資料**，不是待辦清單。尚未處理的問題請看
> [NEW_FEATURES.md](NEW_FEATURES.md)；這裡放的是查證過的事實，
> 免得日後重新研究一次。
>
> 對象是 `lib/src/connector/moodle_webapi_connector.dart`（441 行）、
> `moodle_login_page.dart`，以及四個 Moodle 分頁的呼叫路徑。
> 站台是 `https://moodle2.ntust.edu.tw`，全部走
> `/webservice/rest/server.php` 加 `moodlewsrestformat=json`。

## 目前用到的 Web Service 函式

| 函式 | 用途 | 呼叫處 |
| --- | --- | --- |
| `core_webservice_get_site_info` | 檢查 token、取 userid、取個人資料 | 4 處 |
| `core_enrol_get_users_courses` | 課號對照、某學期的課號清單、目前學期，三者共用一次往返 | `getCourseUrl`、`getCourseIds`、`getCurrentSemester` |
| `core_course_get_contents` | 課程目錄；也被公告流程借用來找討論區 id | `getCourseDirectory` |
| `mod_forum_get_forum_discussions` | 課程公告 | `getCourseAnnouncement` |
| `gradereport_user_get_grade_items` | 課程成績（結構化，取代先前解析 HTML 表格的 `gradereport_user_get_grades_table`） | `getGradeItems` |
| `core_enrol_get_enrolled_users` | 課程成員 | `getMember` |
| `core_message_get_user_notification_preferences` | 通知設定頁 | `getSettings` |
| `core_user_update_user_preferences` | 切換通知設定 | `toggleSetting` |

## 與官方 Moodle App 的差異

比對對象：`moodlehq/moodleapp` v5.3.0 與 `moodle/moodle` MOODLE_502_STABLE。

### 官方明顯更安全或更省，但 TAT 還沒跟上

（原本列了八項，其中檔案網址改 tokenpluginfile、wsAvailable 出手前檢查、
成績改用 grade_items、以及省掉多餘的學期分類呼叫，都已完成。）

**1. `invalidtoken` 才是唯一可靠的「token 已死」訊號**

伺服器端的對照表：

| 情況 | errorcode |
| --- | --- |
| token 不存在 | `invalidtoken` |
| token 過期、session token 的 session 消失、IP 限制、服務未啟用、權限不足 | `accessexception` |
| 站台維護中 | `sitemaintenance` |
| 帳號被刪除／停用／未確認 | `wsaccessuserdeleted` 等 |

官方的判斷是 `errorcode === 'invalidtoken'`，加上一個比對
`'Invalid token - token expired'` 訊息的分支——但那段字串是 `debuginfo`，
只有在站台開到 `DEBUG_DEVELOPER` 且 `debugdisplay` 時才會併進 `message`。
一般正式站不會，所以**實務上只有 `invalidtoken` 可靠**。

反過來說，**不要把 `accessexception` 當成 token 死掉**：它絕大多數是權限或
服務設定問題，據此重新登入會變成登入迴圈。

實作位置是 `AuthSession.invalidate` 與 `run()` 的 `FailureReason`。

**2. 請求合併與去重**

官方把讀取請求排隊，透過 `tool_mobile_call_external_functions` 一次送出，
並且對相同 cacheId 的進行中請求回傳同一個 Promise 而不是再發一次。
TAT 的四個課程分頁各自獨立發請求，沒有任何去重。

**3. HTTP 429 與 Retry-After**

官方對 429 有重試佇列並遵守 `Retry-After` 標頭。TAT 沒有任何處理，
遇到被限流的站台就是直接失敗。

**4. wstoken 放在 POST body**

官方只把 `moodlewsrestformat=json` 放在查詢字串，`wstoken` 與所有參數都是
POST 欄位。TAT 用 `parameter.data` 加 `getJsonByPost`，行為相同，
這一項沒有問題，列出來是為了避免日後有人改成 GET。

### 順帶確認的事實

- **錯誤一律是 HTTP 200。** `webservice_rest_server` 從頭到尾沒有設定狀態碼。
  唯一的例外是站台完全關閉 web service 時回 403 加空 body。
- 錯誤 JSON 一定有 `exception` 與 `message`；`errorcode` 只在例外物件有這個
  欄位時才出現，所以**不保證存在**；`debuginfo` 在站台的 debug 等級為
  Normal 以上就會出現。
- `warnings[]` 的元素有 `warningcode`（必填，只能是英數字）與 `message`
  （必填，未翻譯的英文，給 log 用不是給使用者看）。
- TAT 目前用的五個函式**沒有任何一個被棄用**：
  `mod_forum_get_forum_discussions`、`core_enrol_get_enrolled_users`、
  `core_message_get_user_notification_preferences`、
  `core_user_update_user_preferences`、`gradereport_user_get_grades_table`
  在 MOODLE_502_STABLE 與 main 都還在，也都沒有 `_is_deprecated()` 標記。
- `tool_mobile_get_autologin_key`（用 privatetoken 換取免登入開啟網頁的
  鑰匙）要求 **User-Agent 含有 `MoodleMobile`**，否則直接回
  `apprequired`。另外要求 HTTPS、拒絕站台管理員、伺服器端有 6 分鐘的
  頻率限制，產生的鑰匙綁定呼叫者 IP 且只有 60 秒有效。
  TAT 目前沒有用到 privatetoken，若要用得先改 User-Agent。
