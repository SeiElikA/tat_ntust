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
| `gradereport_overview_get_course_grades` | 「Moodle 目前成績」頁：這個帳號全部課程的目前總分（只送 `userid`；`grades[]` 一定在，可能是空陣列，`warnings` 伺服器端永遠是空的，所以不傳 `treatWarningsAsError`）。**`grade` 是伺服器格式化好的字串**：總分被藏起來或還沒有成績時是字面上的 `"-"`（`grade_format_gradevalue` 對 null 回 `'-'`，兩者從客戶端分不出來），課程總分是無評分／文字型態時是空字串，量尺與等第會過 `format_string`（實體要還原），小數點分隔符跟的是**伺服器上的 Moodle 帳號語言**——一律不解析成數字。`rawgrade` 與 `rank` 刻意不建模：前者是 PARAM_RAW 直傳的 DB 值（字串／float／null 都可能，沒有小數位設定、量尺與等第對照），後者要站台開了 `report_overview_showrank` 才有。**被跳過的課沒有任何 warning**：課程設定關掉「顯示成績」、學生在該課沒有 gradebookrole、課程被隱藏、缺 `moodle/grade:view` 四種情況都是 `continue`，那門課單純不在 `grades[]` 裡。**伺服器端會先把所有課重算一次成績**（`regrade_all_courses_if_needed` 在 WS 路徑上呼叫的是無條件的 `grade_regrade_final_grades`），掛著 `'type' => 'read'` 卻是重呼叫，只在使用者真的開那一頁時發，不預載 | `getCourseGrades` |
| `core_enrol_get_enrolled_users` | 課程成員 | `getMember` |
| `core_message_get_user_notification_preferences` | 通知設定頁 | `getSettings` |
| `core_user_update_user_preferences` | 切換通知設定 | `toggleSetting` |
| `tool_mobile_get_autologin_key` | 用 privatetoken 換 autologin.php 的一次性鑰匙，讓 WebView 免登入 | `autologinUrl` |
| `core_calendar_get_action_events_by_timesort` | 行事曆頁的待辦：所有課程的截止事項（只回 action event；`timesortfrom` 往前 14 天，`limitnum` 上限 50，不送 `timesortto`；回滿一頁就帶 `aftereventid`＝上一頁的 `lastid` 翻頁，最多 4 頁，與官方 App 同一套判斷；`name` / `activityname` / `course.fullname` / `course.shortname` 都是 format_string 過的，App 還原實體） | `getActionEvents` |
| `mod_assign_get_assignments` | 課程頁「作業」分頁的作業清單（只送 `courseids[0]`；duedate 等已含使用者與群組的 override；`name` 是 format_string 過的——`&` 會是 `&amp;`——App 在 `assignmentsOf` 還原；模型只宣告畫面在讀的欄位，`gradingduedate`、`introfiles` 等不落地；`submissiondrafts`、`requiresubmissionstatement`、`submissionstatement`、`timelimit`、`blindmarking` 與 `configs` 是繳交入口的判準所以有落地——`configs[]` **只收錄 enabled 且 visible 的外掛**，「有沒有 `subtype == assignsubmission` 且 `plugin == file` 的任何一列」就是「檔案繳交有沒有開」；`submissionstatement` 只有 `requiresubmissionstatement` 為真時才在，而且是**站台層級**的 admin 設定，可能是空字串） | `getAssignments` |
| `mod_assign_get_submission_status` | 單一作業對自己的繳交狀態、成績與回饋（帶 `userid`；`lastattempt.submission` 缺席 = 還沒繳交；團隊作業**兩筆都回**，學生頁看的是 `teamsubmission`，非團隊作業才看 `submission`，見 `submissionFor`；`feedback` 缺席 = 學生看不到任何成績或回饋；`feedback.gradefordisplay` 是 PARAM_RAW 的 HTML 片段，數值成績在預設 Real 顯示型態下是 `85.00&nbsp;/&nbsp;100.00`，App 在 `submissionStatusOf` 還原；`feedback.grade` 在只有評語時也在，分數是 `-1.00000`；外掛以 `type` 分辨，不看本地化的 `name`；`lastattempt.canedit` / `cansubmit` 是「能不能交」的唯一依據——`submissions_open()` 已經把 cutoffdate、allowsubmissionsfromdate、延長期限、鎖定與是否選課全部算完，App 不可以自己再用日期推一次，而且 `cansubmit` 在沒開草稿的作業上**永遠是 false**） | `getSubmissionStatus` |
| `mod_assign_save_submission` | 存一次繳交（type=write；`plugindata` 是扁平鍵 `plugindata[onlinetext_editor][text]` / `[format]` / `[itemid]` 與 `plugindata[files_filemanager]`，同 `toggleSetting` 的 `preferences[0][type]`；**回的是裸的 warnings 陣列不是物件**，見下方〈交作業那條路〉；`submissiondrafts == 0` 時這一支就是繳交，沒有第二步） | `saveSubmission` |
| `mod_assign_submit_for_grading` | 把已存好的草稿送出評分（type=write；`acceptsubmissionstatement` 只在使用者真的勾了才送 1——那會在伺服器留下 `statement_accepted` 稽核事件；回傳形狀同上，唯一的 warningcode 是 `couldnotsubmitforgrading`，**不會說原因**） | `submitForGrading` |
| `mod_quiz_get_quizzes_by_courses` | 課程頁測驗詳情的測驗本體（只送 `courseids[0]`；`timeopen` / `timeclose` / `timelimit` / `attempts` 已含使用者與群組的 override（`quiz_update_effective_access`），App 不再算；**測驗是最上層的平坦陣列，沒有 `courses[]` 那一層**——所以「空清單」的判讀改看 warnings，見下方「會咬人的地方」；`name` 是 format_string 過的，App 在 `quizzesOf` 還原；模型只宣告畫面在讀的欄位） | `getQuizzes` |
| `mod_quiz_get_user_attempts` | 自己在這個測驗的作答紀錄（`status=all`、`includepreviews=0`，不送 `userid`；伺服器排序是 `attempt ASC`，App 自己倒過來）。**Moodle 5.0 起改名為 `mod_quiz_get_user_quiz_attempts`**，判準與官方 App 相同：site_info 的 `functions[]` 有新名就用新的（`preferredQuizAttemptsFunction`） | `getQuizAttempts` |
| `mod_quiz_get_user_best_grade` | 這個測驗的最佳成績與及格分數（只送 `quizid`，不送 `userid`；`hasgrade == false` 是正常回應——沒作答、老師關掉分數顯示、評分為 null 三者伺服器不區分；`gradetopass` 缺席代表站台沒設，不是 0） | `getQuizBestGrade` |
| `message_popup_get_popup_notifications` | 公告與通知頁的站內通知清單（`useridto` 送真的 id、`newestfirst=1`、`limit=50`——伺服器的預設 0 是「不限筆數」；`newestfirst` 拿到的是最新 N 則、**不分已讀未讀**，而外層的 `unreadcount` 算的是收件匣全部，所以「回滿一頁而且手上的未讀數還少於 `unreadcount`」時要用 `offset` 往下翻，最多 4 頁，同 `getActionEvents` 的態度；回應外層自帶 `unreadcount`，紅點不必再打一趟；`subject` / `contexturlname` 是 PARAM_TEXT，實體還在，App 在 `notificationsOf` 還原） | `getNotifications` |
| `message_popup_get_unread_popup_notification_count` | 課表頁紅點的未讀數（回**裸 JSON 數字**） | `getUnreadNotificationCount` |
| `core_message_get_unread_notification_count` | 同上的退路（@since 4.0，算的是全部 notifications，不只 popup，所以可能高估） | `getUnreadNotificationCount` |
| `core_message_mark_notification_read` | 點開一則通知時標記已讀（參數叫 `notificationid`；`warnings` 在伺服器端永遠是空的） | `markNotificationRead` |
| `core_user_update_picture` | 「其他」頁換／移除 Moodle 頭貼（@since 3.2；只送 `draftitemid` 與 `delete`，**不送 `userid`**——這一支真的把 0 當成自己；`draftitemid` 沒有 `VALUE_DEFAULT`，移除時也要送，送 0；`warnings` 伺服器端寫死是空陣列，唯一的訊號是 `success`；`profileimageurl` 是 `VALUE_OPTIONAL`，只有 `success` 為 true 才在） | `updateProfilePicture` |
| `webservice/upload.php`（不是 wsfunction） | 把檔案送進自己的 draft 檔案區，換一個 `itemid` 給上一列用（只送 `token` 與一個檔案欄位；`filepath` 不送，預設就是 `/`；**沒有 `filearea` 參數**，那是寫死的 `draft`。第一趟不送 `itemid`，伺服器會 `file_get_unused_draft_itemid()` 開一個新的；**要把多個檔案放進同一個 draft 區，第二個以後必須把第一趟拿到的 `itemid` 送回來**，而同一區裡檔名重複會回 `filenameexist`，所以呼叫端要先擋重名） | `uploadDraftFile` |
| `core_message_mark_all_notifications_as_read` | 「全部標為已讀」（回**裸 bool**；標的是 `{notifications}` 全部，不只 popup——所以確認框刻意不寫數字，畫面上的未讀數只算 popup，寫上去會少報這次寫入的範圍） | `markAllNotificationsRead` |

## 與官方 Moodle App 的差異

比對對象：`moodlehq/moodleapp` v5.3.0 與 `moodle/moodle` MOODLE_502_STABLE。

**站內通知：官方 App 早就不用 `message_popup_*`**，它的清單是
`core_message_get_messages(type='notifications')`，未讀數優先打
`core_message_get_unread_notification_count`。TAT 反過來以 popup 為主是刻意的：
畫面上顯示的是 popup 清單，紅點若用「全部 notifications 的未讀數」就會出現
「紅點 3、點進去只有 1 則未讀」。判準本身與官方相同——都是 site_info 的
`functions[]`（TAT 的 `wsFunctionBlocked` / `preferredUnreadCountFunction`）。
書面上的 Plan B 是 `core_message_get_messages`（同在 MOODLE_OFFICIAL_MOBILE_SERVICE、
欄位是 popup 的超集），但不實作兩條路。

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

- **測驗的三支各有一個容易踩的地方。**
  - `mod_quiz_get_user_attempts` 在 Moodle 5.0 被標記 deprecated（6.0 移除），
    改用 `mod_quiz_get_user_quiz_attempts`；兩支的參數與回傳形狀一模一樣，
    唯一的差別是 `state`：新的會多回 `notstarted` 與 `submitted`，舊的為了
    相容把它們改寫成 `inprogress` 與 `finished`。NTUST 現在跑 4.5.12，新那支
    **不存在**，所以判準是 site_info 的 `functions[]`（`preferredQuizAttemptsFunction`），
    載入前 fail-open 到舊名。`MoodleQuizUtils.attemptStateOf` 七個值都接得住，
    站台升級時才不會整排變成「未知狀態」。
  - **`quizzes: []` 加上非空的 `warnings` 是「沒選這門課」，不是「這門課沒有
    測驗」。** `util::validate_courses` 把沒權限的課從 courses 移除並塞一筆
    warning；`quizzesOf` 據此回 null，空清單加空 warnings 才是成功。
  - **`status` 一定要送 `all`。** 伺服器預設是 `finished`（= `FINISHED` 或
    `ABANDONED`），會把作答中與逾期未送出的那幾次整個藏起來。而「已用幾次」
    照 `mod/quiz/view.php` 只數 `finished` 與 `abandoned`——作答中的那一次還
    沒消耗次數。
  - `get_quizzes_by_courses` 把 `mod/quiz:view` 同時當成 intro 與 groups 的
    capability（多數活動的第二個參數是 `moodle/course:manageactivities`），
    所以學生也拿得到 `section` / `visible`；`overduehandling` 與 `graceperiod`
    則在第二層 capability 裡，測驗關閉時剛好消失，因此不建模。
  - **`userid` 可以不送**：`get_user_attempts` 與 `get_user_best_grade` 的
    PHP 都有 `if (empty($params['userid'])) $userid = $USER->id;`，與上面那
    三支通知函式相反。送別人的 id 會撞上 `mod/quiz:viewreports`。
- **換頭貼那條路有五個地方跟其他 function 都不一樣。**
  - **`webservice/upload.php` 回的是 `text/plain`。** `core_renderer_ajax::header()`
    在 `$_FILES` 非空時寫死 `Content-type: text/plain`（給 YUI 的 iframe 上傳用），
    而 Dio 只對 `application/json` 系的 mime 做 jsonDecode，所以 `response.data`
    **一定是 String**。把這條路改去共用 `_callWs`、或把 body 直接 `as List`，
    第一次真的上傳就會炸 TypeError——`decodeUploadBody` 存在就是為了這件事。
  - **它的例外包用 `error` 當鍵，不是 `message`。** 形狀是
    `{error, errorcode, stacktrace, debuginfo, reproductionlink}`，
    所以共用的 `moodleErrorOf` 讀得到 errorcode 卻讀不到訊息，得有自己的
    `draftFileOf`。而且它一律回 HTTP 200：單一檔案的失敗（`fileoversized`）
    是陣列裡的一個元素，整包的失敗（`userquotalimit`、`accessexception`）
    才是那個物件。
  - **`process_new_icon` 只吃 GIF / JPEG / PNG，而且是用 `getimagesize()` 嗅
    內容不是看副檔名。** HEIC 與 WebP 一律被拒，沒有任何錯誤訊息，只有
    `success: false`。所以挑圖那一步一定要指定 `maxWidth` / `maxHeight`
    （Android 的 resizer 只有被要求縮放時才重新編碼成 JPEG/PNG，否則原封不動
    轉送），那兩個參數是正確性需求不是最佳化。
  - **`success: false` 的意思是「`user.picture` 沒有變」，不是「失敗」。**
    上傳路徑的 false 是 Moodle 解不開這張圖；刪除路徑的 false 是本來就沒有
    頭貼——後者不該報錯給使用者看，所以「移除」那一列只在
    `MoodleAvatarUtils.hasCustomPicture` 為真時出現。
  - **`usercanmanageownfiles` 是錯的閘門。** 它報的是
    `moodle/user:manageownfiles`（私人檔案區），而 `core_user_update_picture`
    要的是 `moodle/user:editownprofile`，site_info 根本沒報那一項。能事先看的
    只有 `uploadfiles == 1` 與 `functions[]` 裡有沒有這支；權限的答案要等
    回應的 `nopermissions`，SSO 綁定的個人資料則是 `noprofileedit`。
- **交作業那條路有七個坑，每一個都會把失敗變成看起來像成功。**
  - **兩支寫入函式回的是裸陣列，`treatWarningsAsError` 對它們無效。**
    `save_submission_returns()` 回的是 `new external_warnings()`，而
    `external_warnings extends external_multiple_structure`——成功是 `[]`，
    失敗是 `[{item, itemid, warningcode, message}]`。共用的 `moodleErrorOf`
    第一行就是 `if (data is! Map) return null`，照抄 `toggleSetting` 的寫法會
    100% 把失敗當成功，所以另有一個吃 List 的 `writeWarningOf`。warning 的
    `message` 是寫死的英文，`item` 帶著使用者 id 而且跟著**伺服器帳號語言**，
    兩個都不可以直接顯示；`couldnotsavesubmission` 又一碼多因（逾期／內容為空／
    外掛回錯），所以只能對映成一句涵蓋性的中文，真正的原因由重抓回來的狀態卡說。
    **而「不是 List」本身就是失敗**：`external_warnings` 只可能是 `[]` 或
    `[{...}]`，回 String / null / Map 代表這一趟根本沒到 Moodle（captive portal
    的 HTML、代理的錯誤頁，還有被 `validateStatus: status <= 500` 放行的 500）。
    讀取路徑 fail-open 是因為它有快取可以退，寫入路徑不行——`writeShapeErrorOf`
    就是為了這件事，回 `badresponse`。
  - **`files_filemanager` 是同步不是附加。** `assignsubmission_file::save()` 走
    `file_save_draft_area_files()`，它會把繳交區裡「不在這個 draft 區」的舊檔案
    `delete()` 掉。所以：清單沒變就**完全不送**這個鍵（不送＝保留現有檔案，這也是
    「只改線上文字」的正確作法）；要送就必須是「繳交區最後應該長的樣子」的完整
    清單，要保留的舊檔案得先下載再重傳（官方 App 的 `fileuploader.ts` 就是這樣
    做的，而且一次傳一個避免伺服器端競態）。**下載回來的那一份一定要驗長度**：
    共用的 `validateStatus` 放行到 500，一頁錯誤 HTML 會被原封寫成 `report.pdf`
    再傳上去，而同步語意會刪掉真的那一份——這是整條路上唯一會毀掉使用者沒動過
    的東西的地方。`external_files` 的 `filesize` 是 VALUE_OPTIONAL，缺席時退成
    「非空即可」。
  - **超過 `maxfilesubmissions` / `maxsubmissionsizebytes` 的檔案伺服器不會抱怨，
    只會不見。** `file_save_draft_area_files` 對它們是 `continue`，
    `save_submission` 照樣回 `[]`——不本地擋就會出現「App 說繳交成功、Moodle 上
    只有兩個檔案」。同理 `filetypeslist` **伺服器端根本不驗**（`accepted_types`
    只餵給網頁表單的 filepicker），只有客戶端擋得住；但 Moodle 的群組名
    （`document`、`archive`、`web_image`）要整張 file types 表才解得開，遇到就
    整份降級成「無法判讀」，只顯示原始字串不擋——寧可讓老師看到一個格式不對的
    檔案，也不要讓學生交不出來。
  - **`submissiondrafts == 0` 時「存檔」就是「繳交」，而 `requiresubmissionstatement`
    在 `save_submission` 路徑上沒有伺服器端把關。** 前者 `save_submission` 直接
    把 status 設成 SUBMITTED 並寄出繳交回條（而且 `cansubmit` 在這種作業上永遠是
    false，因為 `show_submit_button` 最後一行就是 `return submissiondrafts`），
    所以按鈕文案跟著它走、還要多一道確認框；後者只有 `submit_for_grading` 會擋，
    而且是 `return false` 沒有 notice，只能由 App 自己要求勾選，**而且只有真的
    勾了才送 `acceptsubmissionstatement=1`**——替使用者代勾等於偽造那筆
    `statement_accepted` 稽核事件。
  - **`onlinetext_editor` 沒有 `files_filemanager` 那個對稱：不送不是保留，是
    覆蓋。** `file_postupdate_standard_filemanager` 開頭就是
    `if (empty($data->{$field.'_filemanager'})) return $data;`，所以省略檔案那
    個鍵真的等於「不動」；但 `file_postupdate_standard_editor` 是無條件的
    `$editor = $data->{$field.'_editor'}; $data->$field = $editor['text'];`，而
    `assign::save_submission` 對**每一個 enabled 且 visible 的外掛**都呼叫
    `save()`，`assign_submission_onlinetext::save()` 又沒有 isset 把關（只有它的
    `submission_is_empty()` 有）。結果是：作業同時開了檔案與線上文字、學生只改
    檔案時，只送 `files_filemanager` 會把現有的線上文字寫成 null。**外掛開著就
    一定要送這個鍵**，沒動過也要把伺服器原本那一份原樣送回去（不能用
    `htmlToPlain` → `plainToHtml` 重組，那會弄丟粗體之類的標記）。
  - **`check_word_count` 是唯一會擋下整趟 `save_submission` 的內容限制，而它不
    說自己是誰。** `assign_submission_onlinetext::save()` 超過 `wordlimit` 就
    `return false`，externallib 把它變成同一句 `couldnotsavesubmission`——使用者
    會看到「可能已經超過期限」。而且 `assign::save_submission` 的外掛迴圈是
    `$pluginerror = true` 之後**繼續跑**，檔案那半照樣已經同步進去了。所以字數
    必須本地先算，分隔符照 `count_words` 的 `~[\p{Z}\p{Cc}—–]+~u`。
  - **`save_submission` 不是原子的，所以被拒絕之後一定要重抓狀態。** 一個外掛
    成功、另一個失敗，回的還是一則 `couldnotsavesubmission`。寫入路徑的失敗因此
    不能走 `Failed`（它帶不了資料），要回帶著 `error` 的 `Ok` 加上重抓回來的
    狀態；重抓不到就把 `cache_moodle_assign_status/<id>` **刪掉**，留著的是寫入
    前的快照，離線再開會理直氣壯地畫成「未繳交」。
  - 附帶：`onlinetext_editor.itemid` 送 0 是安全的（`file_postupdate_standard_editor`
    的 `empty($editor['itemid'])` 分支會整段跳過 draft 同步），代價是原本內文若有
    內嵌圖片，用純文字覆蓋會留下孤兒檔案且圖片連結失效——所以現有的 onlinetext
    一旦含 `<img>` / `@@PLUGINFILE@@`，**整份作業都不給在 App 內存**（不是只有
    文字框不給編：只送檔案那半會踩到上面那一條），導網頁。而且
    `getSubmissionStatus` 帶了 `moodlewssettingfileurl`，拿到的 HTML 裡
    `@@PLUGINFILE@@` 已經被換成絕對網址，也不能原樣送回去。
- **通知相關的三支不能送 `useridto: 0`。**
  `message_popup_get_unread_popup_notification_count`、
  `core_message_get_unread_notification_count` 與
  `core_message_mark_all_notifications_as_read` 都是「先比對
  `$useridto != $USER->id` 再檢查權限」，沒有「0 代入目前使用者」那一步，
  送 0 直接回 `accessdenied`——文件上的 `0 for any user` 會把人騙進去。
  只有 `message_popup_get_popup_notifications` 真的把 0 當成自己。
- **`timecreatedpretty` 是伺服器端語系算好的**（`get_string('ago', ...)`，跟著
  Moodle 帳號語言，不是 App 的語言切換），而且是抓取當下算的，離線快取拿出來
  時早就過時。一律用 `timecreated` 自己格式化。
- **`iconurl` 與 `customdata.notificationiconurl` 都不可以過
  `fileUrlWithToken()`。** 前者是 `/theme/image.php/...` 的主題圖（公開、免
  憑證），後者是 `/tokenpluginfile.php/<user key>/...`（自帶一次性憑證，而且
  `_pluginFileSegment` 的正則不會 match 它）；兩者都會掉進 `fileUrlWithToken`
  的 `?token=<wsToken>` 退路，等於把長效 token 貼到不需要憑證的網址上。TAT
  兩個都不抓：icon 用本地 Material icon，寄件者頭像不顯示。
- **站內通知清單空不等於「沒有新通知」。** `$USER->emailstop` 為真時伺服器直接
  回空陣列，但外層的 `unreadcount` 照算——「清單空 + unreadcount > 0」是
  「使用者自己在 Moodle 關掉了站內通知」，畫面要分得出來
  （`MoodleNotificationUtils.looksDisabledByUser`）。這個未讀數在 App 內沒有
  非破壞性的辦法清掉（`emailstop` 只有 Moodle 網站改得動，設定頁的開關是
  per-provider 的 processor，不是它），所以課表頁的紅點在這個狀態要歸零並停掉
  輪詢（`NotificationBadgeController.setDisabled`），否則會變成一顆永遠亮著、
  點進去什麼都沒有的紅點。
- **已讀的通知伺服器預設 7 天後刪除**（`messagingdeletereadnotificationsdelay`
  604800，另有 `messagingdeleteallnotificationsdelay` 約 30 天），清理排程每
  小時跑一次。所以通知清單是收件匣不是封存，「全部標為已讀」要先確認；對已被
  刪掉的 id 標記已讀會回 `dml_missing_record_exception`，只能 toast，不可以
  讓整頁變成錯誤畫面。

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
