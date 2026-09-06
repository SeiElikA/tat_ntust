# Moodle 串接參考

> 這份文件是**參考資料**，不是待辦清單。尚未處理的問題請看
> [NEW_FEATURES.md](NEW_FEATURES.md)；這裡放的是查證過的事實，
> 免得日後重新研究一次。
>
> 對象是 `lib/src/connector/moodle_webapi_connector.dart`、
> `moodle_login_page.dart`，以及五個 Moodle 分頁的呼叫路徑。
> 站台是 `https://moodle2.ntust.edu.tw`，全部走
> `/webservice/rest/server.php` 加 `moodlewsrestformat=json`。

## 目前用到的 Web Service 函式

| 函式 | 用途 | 呼叫處 |
| --- | --- | --- |
| `core_webservice_get_site_info` | 檢查 token、取 userid、取個人資料 | 4 處 |
| `core_enrol_get_users_courses` | 課號對照、某學期的課號清單、目前學期，三者共用一次往返 | `getCourseUrl`、`getCourseIds`、`getCurrentSemester` |
| `core_course_get_contents` | 課程目錄；也被公告流程借用來找討論區 id | `getCourseDirectory` |
| `mod_forum_get_forums_by_courses` | 用 `type == 'news'` 結構性地找公告區（回的是陣列不是物件；站台沒開這支就退回名稱比對） | `getCourseAnnouncement` |
| `mod_forum_get_forum_discussions` | 課程公告清單 | `getCourseAnnouncement` |
| `mod_forum_get_discussion_posts` | 公告討論串的第一篇與全部回覆（`sortby=created&sortdirection=ASC`；`includeinlineattachments=1` 必帶——post_exporter 不跑 format_text，`message` 裡的 `@@PLUGINFILE@@` 要靠 `messageinlinefiles` 自己換，`moodlewssettingfileurl` 對它無效；附件走 stored_file_exporter，網址欄位是 `url` 不是 `fileurl`，也沒有 mimetype；`isdeleted` 的貼文照樣回，內容被換成站台語系的字串、`timecreated` 是 null） | `getDiscussionPosts` |
| `gradereport_user_get_grade_items` | 課程成績（結構化，取代先前解析 HTML 表格的 `gradereport_user_get_grades_table`） | `getGradeItems` |
| `core_enrol_get_enrolled_users` | 課程成員 | `getMember` |
| `core_message_get_user_notification_preferences` | 通知設定頁 | `getSettings` |
| `core_user_update_user_preferences` | 切換通知設定 | `toggleSetting` |
| `tool_mobile_get_autologin_key` | 用 privatetoken 換 autologin.php 的一次性鑰匙，讓 WebView 免登入 | `autologinUrl` |
| `core_calendar_get_action_events_by_timesort` | 行事曆頁的待辦：所有課程的截止事項（只回 action event；`timesortfrom` 往前 14 天，`limitnum` 上限 50，不送 `timesortto`；回滿一頁就帶 `aftereventid`＝上一頁的 `lastid` 翻頁，最多 4 頁，與官方 App 同一套判斷；`name` / `activityname` / `course.fullname` / `course.shortname` 都是 format_string 過的，App 還原實體） | `getActionEvents` |
| `mod_assign_get_assignments` | 課程頁「作業」分頁的作業清單（只送 `courseids[0]`；duedate 等已含使用者與群組的 override；`name` 是 format_string 過的——`&` 會是 `&amp;`——App 在 `assignmentsOf` 還原；模型只宣告畫面在讀的欄位，`configs`、`gradingduedate`、`introfiles` 等不落地） | `getAssignments` |
| `mod_assign_get_submission_status` | 單一作業對自己的繳交狀態、成績與回饋（帶 `userid`；`lastattempt.submission` 缺席 = 還沒繳交；團隊作業**兩筆都回**，學生頁看的是 `teamsubmission`，非團隊作業才看 `submission`，見 `submissionFor`；`feedback` 缺席 = 學生看不到任何成績或回饋；`feedback.gradefordisplay` 是 PARAM_RAW 的 HTML 片段，數值成績在預設 Real 顯示型態下是 `85.00&nbsp;/&nbsp;100.00`，App 在 `submissionStatusOf` 還原；`feedback.grade` 在只有評語時也在，分數是 `-1.00000`；外掛以 `type` 分辨，不看本地化的 `name`） | `getSubmissionStatus` |

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

### 會咬人的地方

- `mod_forum_get_forum_discussions` 每一列的 `id` 是**第一篇貼文**的 id，
  `discussion` 才是討論串 id。拿 `id` 去問 `mod_forum_get_discussion_posts`
  會問到別人的討論串或直接拋錯。
- 同一支的 `attachment` 欄位是 PARAM_RAW（`"1"` 或空字串），不是 bool。
- 同一支的 `created` / `modified` 也都是**第一篇貼文**的：老師事後編輯過公告
  只會動 `modified`，討論串本身的 `timemodified` 不動。清單與詳情頁都印
  `created`，否則同一則公告兩個畫面會顯示不同時間。
- 同一支的 `name` 與 `subject` 都經過 `format_string`，兩個都要還原實體；只還原
  `name` 的話，抓不到回覆時的退路畫面會出現字面上的 `&amp;`。
- pluginfile 網址的每一段是 PHP `rawurlencode`（只留 `A-Za-z0-9-_.~`），比
  Dart 的 `Uri.encodeComponent` 多轉了 `!*'()`。用檔名去反推 `@@PLUGINFILE@@`
  的前綴時兩種都要試，否則 `Lecture (1).png` 這種附件會對不上。

### 順帶確認的事實

- `core_course_get_contents` 的 `contents` 是 `VALUE_DEFAULT, array()`，所以
  這個 key 一定在。可見的 folder 模組拿到 `[]` 就代表資料夾真的沒有檔案，
  伺服器沒有另一個「內容被藏起來」的訊號，所以 TAT 刪掉了那個從來沒被寫成
  true 的 `folderIsNone`，改成直接進資料夾頁畫空狀態。
- `contents[].filepath` 是 PARAM_PATH：根目錄是 `/`，子目錄頭尾都有斜線
  （`/講義/第一週/`）。`url` 模組（`url_export_contents`）直接塞 `null`，
  模型收成空字串，`MoodleFolderUtils` 一律當成根目錄。
- 資料夾模組的每一筆都是 `type: 'file'`——子資料夾只存在於 `filepath` 裡；
  伺服器順序是 `sortorder DESC, id ASC`，不是字母序，TAT 自己照名稱重排。
- `fileurl` 由 `file_encode_url` 產生，本身就含 `filepath`，所以子資料夾裡的
  檔案下載不需要再拼路徑。
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
  鑰匙）要求 **User-Agent 含有 `MoodleMobile`**（`is_moodle_app()` 是不分
  大小寫的子字串比對），否則直接回 `apprequired`。TAT 只在這一個請求上用
  `ConnectorParameter.userAgent` 附上記號，`presetUserAgent` 不動。
  另外要求 HTTPS、拒絕站台管理員；伺服器端對同一位使用者有 6 分鐘的頻率
  限制（`autologinmintimebetweenreq`，預設 360 秒，**與官方 App 共用**），
  `MoodleWebApiConnector.autologinMinInterval` 在本機照抄這個數字，省掉
  注定 lockout 的請求。產生的鑰匙綁定呼叫者 IP、只能用一次、60 秒內有效。
  `autologin.php` 的轉址參數是 `urltogo`（PARAM_LOCALURL）：不是
  `https://<wwwroot>/…` 開頭、帶 userinfo 或非 ASCII 都會被清成空字串並
  **靜靜地**轉到首頁，所以 `autologinTarget` 只放行自家 https 網址。
  成功時 `autologin.php` 以 303 轉到 `urltogo`，WebView 停在 `autologin.php`
  本身就代表鑰匙被拒（`expiredkey` 60 秒、`ipmismatch` 綁定呼叫者 IP、
  `invalidkey` 已用過），`InAppWebViewPage` 這時退回去開原網址
  （`fallbackUrl`）。鑰匙建立的 MoodleSession 只存在平台 WebView 的 cookie
  store——WS 呼叫是 `NO_MOODLE_COOKIES`，Dio jar 從來沒有它——所以
  `InAppWebViewPage` 開 Moodle 網址時**不清** cookie store，6 分鐘內的第二頁
  才能沿用第一頁的 session；登出由 `SessionCleaner` 清整個 store。
  privatetoken 只能放 POST body，出現在 query string 會被當成
  `invalidprivatetoken`。
