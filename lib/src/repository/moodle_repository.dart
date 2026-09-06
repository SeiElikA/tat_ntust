import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_calendar_action_events.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_gradereport_get_grade_items.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_gradereport_overview_course_grades.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_message_popup_notifications.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_can_add_discussion.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_quiz_get_quizzes_by_courses.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_quiz_get_user_attempts.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_quiz_get_user_best_grade.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_user_picture.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/repository/retry.dart';
import 'package:flutter_app/src/repository/run.dart';
import 'package:flutter_app/src/store/cache_store.dart';
import 'package:flutter_app/src/util/file_utils.dart';
import 'package:flutter_app/src/util/moodle_assign_submit_utils.dart';
import 'package:flutter_app/src/util/moodle_assign_utils.dart';
import 'package:flutter_app/src/util/moodle_avatar_utils.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_app/src/util/moodle_quiz_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sprintf/sprintf.dart';

/// 課程頁各分頁、行事曆待辦與作業詳情的 Moodle 資料來源。取得分兩段：課號換
/// 內部 id、再拿資料；第一段失敗必須在 `fetch` 內丟 [TaskFailure]，否則
/// `run()` 不會去讀快取，離線使用者就看不到硬碟上的資料。
class MoodleRepository {
  MoodleRepository();

  static MoodleRepository instance = MoodleRepository();

  /// 課號到 Moodle 內部 id 的對照。分頁並行寫同一包 blob，覆寫由 `CacheStore`
  /// 內部的 per-name 佇列負責，這裡不該再自己加鎖。
  static CacheKey<String> _findIdKey(String courseId) => CacheKey<String>(
        "cache_moodle_support",
        courseId,
        decode: (json) => json as String,
      );

  /// 同一課號正在解析中的 Future，用來去重：課程頁並行發三個請求，第一次寫進
  /// 快取之前另外兩次早就出發了，快取擋不住。static 是為了跨過測試替換 instance。
  @visibleForTesting
  static final Map<String, Future<String>> findIdInFlight = {};

  Future<String> _findId(String courseId) {
    final running = findIdInFlight[courseId];
    if (running != null) return running;
    final future = _resolveFindId(courseId);
    findIdInFlight[courseId] = future;
    // whenComplete 而不是 then：失敗也要移除，否則一次失敗會永久釘住這個課號。
    return future.whenComplete(() => findIdInFlight.remove(courseId));
  }

  /// 測試用的縫：把「真的去問 Moodle」那一步隔開，去重那一層才驗得到。
  @visibleForTesting
  Future<String?> fetchCourseUrl(String courseId) =>
      MoodleWebApiConnector.getCourseUrl(courseId);

  @visibleForTesting
  Future<String> findIdForTesting(String courseId) => _findId(courseId);

  Future<String> _resolveFindId(String courseId) async {
    final key = _findIdKey(courseId);
    final cached = await CacheStore.instance.read<String>(key);
    if (cached != null) return cached;

    String? findId;
    try {
      findId = await fetchCourseUrl(courseId);
    } catch (_) {
      findId = null;
    }
    if (findId == null) {
      await CacheStore.instance.removeEntry<String>(key);
      throw const TaskFailure(UnsupportedCourse());
    }
    await CacheStore.instance.write<String>(key, findId);
    return findId;
  }

  /// 兩段式取得的共用外殼。刻意沒有 progressMessage：呼叫端全是 `ResultView`，
  /// 它自己就會畫 LoadingPage，再開進度框會變成同一件事兩個轉圈。
  Future<Result<T>> _withCourse<T>({
    required String courseId,
    required CacheKey<T> cache,
    required Future<T?> Function(String findId) fetch,
    required String errorMessage,
    required String debugLabel,
  }) =>
      run<T>(
        requires: const {SystemId.moodleWebApi},
        cache: cache,
        errorMessage: errorMessage,
        debugLabel: debugLabel,
        fetch: () async => fetch(await _findId(courseId)),
      );

  /// 這一門課的成績。
  Future<Result<MoodleUserGradesEntity>> getCourseScore(String courseId) =>
      _withCourse<MoodleUserGradesEntity>(
        courseId: courseId,
        cache: CacheKey<MoodleUserGradesEntity>(
          "cache_moodle_score",
          courseId,
          decode: decodeCachedScore,
        ),
        fetch: MoodleWebApiConnector.getScore,
        errorMessage: R.current.getMoodleScoreError,
        debugLabel: 'moodleScore',
      );

  /// 這一門課的檔案與單元。
  Future<Result<List<MoodleCoreCourseGetContents>>> getCourseDirectory(
          String courseId) =>
      _withCourse<List<MoodleCoreCourseGetContents>>(
        courseId: courseId,
        cache: CacheKey<List<MoodleCoreCourseGetContents>>(
          "cache_moodle_directory",
          courseId,
          decode: (json) => (json as List)
              .map((e) => MoodleCoreCourseGetContents.fromJson(e))
              .toList(),
        ),
        fetch: MoodleWebApiConnector.getCourseDirectory,
        errorMessage: R.current.getMoodleCourseDirectoryError,
        debugLabel: 'moodleDirectory',
      );

  /// 這一門課的公告。找不到公告區時回的是 forumFound=false 的空清單，不是失敗。
  Future<Result<MoodleModForumGetForumDiscussions>> getAnnouncements(
          String courseId) =>
      _withCourse<MoodleModForumGetForumDiscussions>(
        courseId: courseId,
        cache: CacheKey<MoodleModForumGetForumDiscussions>(
          "cache_moodle_message",
          courseId,
          decode: (json) => MoodleModForumGetForumDiscussions.fromJson(json),
        ),
        fetch: MoodleWebApiConnector.getCourseAnnouncement,
        errorMessage: R.current.getMoodleCourseAnnouncementError,
        debugLabel: 'moodleAnnouncement',
      );

  /// 這一門課的修課學生。
  Future<Result<List<MoodleCoreEnrolGetUsers>>> getMembers(String courseId) =>
      _withCourse<List<MoodleCoreEnrolGetUsers>>(
        courseId: courseId,
        cache: CacheKey<List<MoodleCoreEnrolGetUsers>>(
          "cache_moodle_member",
          courseId,
          decode: (json) => (json as List)
              .map((e) => MoodleCoreEnrolGetUsers.fromJson(e))
              .toList(),
        ),
        // 空清單算失敗，不是「這門課沒有學生」；run() 只把 null 當失敗。
        fetch: (findId) async {
          final value = await MoodleWebApiConnector.getMember(findId);
          return (value == null || value.isEmpty) ? null : value;
        },
        errorMessage: R.current.getMoodleMembersError,
        debugLabel: 'moodleMember',
      );

  /// 這門課的作業清單；空清單是合法結果。
  Future<Result<List<MoodleAssignment>>> getAssignments(String courseId) =>
      _withCourse<List<MoodleAssignment>>(
        courseId: courseId,
        cache: CacheKey<List<MoodleAssignment>>(
          "cache_moodle_assign",
          courseId,
          decode: (json) => (json as List)
              .map((e) => MoodleAssignment.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList(),
        ),
        fetch: MoodleWebApiConnector.getAssignments,
        errorMessage: R.current.getMoodleAssignmentsError,
        debugLabel: 'moodleAssignments',
      );

  /// 從清單裡挑單一作業；給「檔案」分頁點進來、手上只有 assign id 的情況。
  Future<Result<MoodleAssignment>> getAssignment(
      String courseId, int assignId) async {
    final list = await getAssignments(courseId);
    return switch (list) {
      Ok(:final data) => switch (MoodleAssignUtils.findById(data, assignId)) {
          final a? => Ok<MoodleAssignment>(a),
          null =>
            Failed<MoodleAssignment>(FetchFailed(R.current.assignmentNotFound)),
        },
      Stale(:final data, :final reason) => switch (
            MoodleAssignUtils.findById(data, assignId)) {
          final a? => Stale<MoodleAssignment>(a, reason),
          null => Failed<MoodleAssignment>(reason),
        },
      Failed(:final reason) => Failed<MoodleAssignment>(reason),
    };
  }

  /// 繳交狀態的快取鍵。寫入路徑要用同一把，才補得回這一趟的新狀態。
  static CacheKey<MoodleAssignSubmissionStatus> submissionStatusKey(
          int assignId) =>
      CacheKey<MoodleAssignSubmissionStatus>(
        "cache_moodle_assign_status",
        assignId.toString(),
        decode: decodeCachedSubmissionStatus,
      );

  /// 繳交狀態、成績與回饋。[assignId] 已是 Moodle 內部 id，不走 [_withCourse]。
  /// [background]：清單上 N 份並行抓時不彈框、不開登入頁；詳情頁傳 false。
  Future<Result<MoodleAssignSubmissionStatus>> getSubmissionStatus(
    int assignId, {
    bool background = false,
  }) =>
      run<MoodleAssignSubmissionStatus>(
        requires: const {SystemId.moodleWebApi},
        cache: submissionStatusKey(assignId),
        fetch: () => MoodleWebApiConnector.getSubmissionStatus(assignId),
        errorMessage: R.current.getMoodleAssignmentStatusError,
        debugLabel: 'moodleAssignStatus',
        retry: background ? RetryPolicy.none : RetryPolicy.askUser,
        background: background,
      );

  /// 這門課的測驗清單；空清單是合法結果。
  Future<Result<List<MoodleQuiz>>> getQuizzes(String courseId) =>
      _withCourse<List<MoodleQuiz>>(
        courseId: courseId,
        cache: CacheKey<List<MoodleQuiz>>(
          "cache_moodle_quiz",
          courseId,
          decode: (json) => (json as List)
              .map((e) =>
                  MoodleQuiz.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
        ),
        fetch: MoodleWebApiConnector.getQuizzes,
        errorMessage: R.current.getMoodleQuizzesError,
        debugLabel: 'moodleQuizzes',
      );

  /// 從清單裡挑單一測驗；頁面只有 quiz id（`Modules.instance`）。
  /// 與 [getAssignment] 同一套三態轉寫：Ok/Stale 找不到就是 Failed。
  Future<Result<MoodleQuiz>> getQuiz(String courseId, int quizId) async {
    final list = await getQuizzes(courseId);
    return switch (list) {
      Ok(:final data) => switch (MoodleQuizUtils.findById(data, quizId)) {
          final q? => Ok<MoodleQuiz>(q),
          null => Failed<MoodleQuiz>(FetchFailed(R.current.quizNotFound)),
        },
      Stale(:final data, :final reason) => switch (
            MoodleQuizUtils.findById(data, quizId)) {
          final q? => Stale<MoodleQuiz>(q, reason),
          null => Failed<MoodleQuiz>(reason),
        },
      Failed(:final reason) => Failed<MoodleQuiz>(reason),
    };
  }

  /// 作答紀錄。[quizId] 已是 Moodle 內部 id，不走 [_withCourse]。
  /// [background] 同 [getSubmissionStatus]：進頁面時三支並行，只讓測驗本體
  /// 那支彈框；這一支的重試鈕在區塊自己的 `InlineErrorView` 上。
  Future<Result<List<MoodleQuizAttempt>>> getQuizAttempts(
    int quizId, {
    bool background = false,
  }) =>
      run<List<MoodleQuizAttempt>>(
        requires: const {SystemId.moodleWebApi},
        cache: CacheKey<List<MoodleQuizAttempt>>(
          "cache_moodle_quiz_attempts",
          quizId.toString(),
          decode: (json) => (json as List)
              .map((e) => MoodleQuizAttempt.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList(),
        ),
        fetch: () => MoodleWebApiConnector.getQuizAttempts(quizId),
        errorMessage: R.current.getMoodleQuizAttemptsError,
        debugLabel: 'moodleQuizAttempts',
        retry: background ? RetryPolicy.none : RetryPolicy.askUser,
        background: background,
      );

  /// 最佳成績與及格分數。[background] 同 [getQuizAttempts]。
  Future<Result<MoodleQuizBestGrade>> getQuizBestGrade(
    int quizId, {
    bool background = false,
  }) =>
      run<MoodleQuizBestGrade>(
        requires: const {SystemId.moodleWebApi},
        cache: CacheKey<MoodleQuizBestGrade>(
          "cache_moodle_quiz_grade",
          quizId.toString(),
          decode: decodeCachedQuizBestGrade,
        ),
        fetch: () => MoodleWebApiConnector.getQuizBestGrade(quizId),
        errorMessage: R.current.getMoodleQuizBestGradeError,
        debugLabel: 'moodleQuizBestGrade',
        retry: background ? RetryPolicy.none : RetryPolicy.askUser,
        background: background,
      );

  /// 討論串的快取。讀與「樂觀併入之後寫回」共用同一把 key。
  static CacheKey<List<MoodleForumPost>> discussionPostsKey(int discussionId) =>
      CacheKey<List<MoodleForumPost>>(
        "cache_moodle_forum_posts",
        discussionId.toString(),
        decode: (json) => (json as List)
            .map((e) =>
                MoodleForumPost.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// 一則討論串（第一篇加回覆）。[discussionId] 是 `Discussions.discussion`，
  /// 不是 `Discussions.id`——後者是第一篇貼文的 id。
  Future<Result<List<MoodleForumPost>>> getDiscussionPosts(int discussionId) =>
      run<List<MoodleForumPost>>(
        requires: const {SystemId.moodleWebApi},
        cache: discussionPostsKey(discussionId),
        fetch: () => MoodleWebApiConnector.getDiscussionPosts(discussionId),
        errorMessage: R.current.getMoodleForumPostsError,
        debugLabel: 'moodleForumPosts',
      );

  /// 一個一般討論區的主題清單。[forumId] 是 forum instance id
  /// （`Modules.instance`），不是 cmid。
  Future<Result<List<Discussions>>> getForumDiscussions(int forumId) =>
      run<List<Discussions>>(
        requires: const {SystemId.moodleWebApi},
        cache: CacheKey<List<Discussions>>(
          "cache_moodle_forum_discussions",
          forumId.toString(),
          decode: (json) => (json as List)
              .map((e) => Discussions.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
        ),
        fetch: () => MoodleWebApiConnector.getForumDiscussions(forumId),
        errorMessage: R.current.getMoodleCourseAnnouncementError,
        debugLabel: 'moodleForumDiscussions',
      );

  /// 能不能在這個討論區開新主題。刻意不快取：過期的「你可以發文」比沒有答案
  /// 更糟——按下去才被伺服器拒絕。[background] 固定為真，這是進頁時的預載。
  Future<Result<MoodleCanAddDiscussion>> canAddDiscussion(int forumId) =>
      run<MoodleCanAddDiscussion>(
        requires: const {SystemId.moodleWebApi},
        background: true,
        retry: RetryPolicy.none,
        errorMessage: R.current.forumCannotPost,
        debugLabel: 'moodleCanAddDiscussion',
        fetch: () => MoodleWebApiConnector.canAddDiscussion(forumId),
      );

  @visibleForTesting
  Future<MoodleForumPost> writeReply({
    required int postId,
    required String subject,
    required String message,
  }) =>
      MoodleWebApiConnector.addDiscussionPost(
          postId: postId, subject: subject, message: message);

  @visibleForTesting
  Future<int> writeDiscussion({
    required int forumId,
    required String subject,
    required String htmlMessage,
  }) =>
      MoodleWebApiConnector.addDiscussion(
          forumId: forumId, subject: subject, htmlMessage: htmlMessage);

  /// 回覆一篇貼文。走 `run()` 是為了登入保證與離線分類，不是快取。
  ///
  /// `retry: none`：`run()` 的重試會整個重跑 `fetch`，而
  /// `mod_forum_add_discussion_post` 沒有冪等鍵——按一次重試就多發一則。
  /// 理由同 [changeProfilePicture]。
  ///
  /// `background: false`：使用者主動按的按鈕，token 死掉時要開得了登入頁。
  Future<Result<MoodleForumPost>> postReply({
    required int postId,
    required String subject,
    required String text,
  }) =>
      run<MoodleForumPost>(
        requires: const {SystemId.moodleWebApi},
        retry: RetryPolicy.none,
        errorMessage: R.current.forumSendError,
        debugLabel: 'moodleForumReply',
        fetch: () async {
          try {
            return await writeReply(
                postId: postId, subject: subject, message: text);
          } on MoodleApiException catch (e) {
            throw TaskFailure(FetchFailed(forumPostFailureMessage(e)));
          }
        },
      );

  /// 開一個新主題，回討論串 id。[text] 是使用者打的純文字，escape 在這裡做：
  /// `mod_forum_add_discussion` 沒有 `messageformat`，伺服器一律當 HTML 存。
  /// `retry` 與 `background` 的理由同 [postReply]。
  Future<Result<int>> postDiscussion({
    required int forumId,
    required String subject,
    required String text,
  }) =>
      run<int>(
        requires: const {SystemId.moodleWebApi},
        retry: RetryPolicy.none,
        errorMessage: R.current.forumSendError,
        debugLabel: 'moodleForumNewDiscussion',
        fetch: () async {
          try {
            return await writeDiscussion(
              forumId: forumId,
              subject: subject,
              htmlMessage: MoodleForumUtils.plainTextToHtml(text),
            );
          } on MoodleApiException catch (e) {
            throw TaskFailure(FetchFailed(forumPostFailureMessage(e)));
          }
        },
      );

  /// 樂觀併入剛送出的回覆之後把整串寫回同一筆快取。理由同
  /// [saveNotifications]：`run()` 只在 fetch 成功那一刻寫快取，寫入路徑沒有
  /// `cache:`，不補這一趟的話離線重開會看不到自己剛發的那一則。
  Future<void> saveDiscussionPosts(
          int discussionId, List<MoodleForumPost> posts) =>
      CacheStore.instance.write<List<MoodleForumPost>>(
          discussionPostsKey(discussionId), posts);

  /// 待辦快取只有一筆（'all'）；登出時 `cache_` 前綴整包清掉，不會跨帳號。
  static CacheKey<List<MoodleActionEvent>> upcomingEventsKey() =>
      CacheKey<List<MoodleActionEvent>>(
        "cache_moodle_action_events",
        "all",
        decode: (json) => (json as List)
            .map((e) =>
                MoodleActionEvent.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// 測試用的縫（同 [fetchCourseUrl]）。
  @visibleForTesting
  Future<List<MoodleActionEvent>?> fetchActionEvents() =>
      MoodleWebApiConnector.getActionEvents();

  /// 所有課程的待辦（逾期 14 天內到之後）。[background]：進頁時的預載，
  /// 不開進度框、不開登入頁、不彈重試框；按重新整理時傳 false。
  Future<Result<List<MoodleActionEvent>>> getUpcomingEvents(
          {bool background = false}) =>
      run<List<MoodleActionEvent>>(
        requires: const {SystemId.moodleWebApi},
        cache: upcomingEventsKey(),
        background: background,
        retry: background ? RetryPolicy.none : RetryPolicy.askUser,
        errorMessage: R.current.getUpcomingEventsError,
        debugLabel: 'moodleUpcomingEvents',
        fetch: fetchActionEvents,
      );

  /// 目前學期的 Moodle 總分，快取只有一筆（'current'）；登出時 `cache_` 前綴
  /// 整包清掉，不會跨帳號。
  static CacheKey<MoodleCourseGradeList> courseGradesKey() =>
      CacheKey<MoodleCourseGradeList>(
        "cache_moodle_course_grades",
        "current",
        decode: (json) =>
            MoodleCourseGradeList.fromJson(Map<String, dynamic>.from(json)),
      );

  /// 測試用的縫（同 [fetchCourseUrl]）。
  @visibleForTesting
  Future<MoodleCourseGradeList?> fetchCourseGrades() =>
      MoodleWebApiConnector.getCourseGrades();

  /// 每一門課的 Moodle 目前總分。空清單是合法結果（這學期沒有任何課開放成績）。
  /// [background]：進頁時的第一趟不開登入頁、不彈重試框；下拉重新整理傳 false。
  Future<Result<MoodleCourseGradeList>> getCourseGrades(
          {bool background = false}) =>
      run<MoodleCourseGradeList>(
        requires: const {SystemId.moodleWebApi},
        cache: courseGradesKey(),
        background: background,
        retry: background ? RetryPolicy.none : RetryPolicy.askUser,
        errorMessage: R.current.getMoodleCourseGradesError,
        debugLabel: 'moodleCourseGrades',
        fetch: fetchCourseGrades,
      );

  /// 站內通知的快取只有一筆（'all'）；登出時 `cache_` 前綴整包清掉。
  static CacheKey<MoodleNotificationList> notificationsKey() =>
      CacheKey<MoodleNotificationList>(
        "cache_moodle_notification",
        "all",
        decode: (json) =>
            MoodleNotificationList.fromJson(Map<String, dynamic>.from(json)),
      );

  /// 測試用的縫（同 [fetchCourseUrl]）。
  @visibleForTesting
  Future<MoodleNotificationList?> fetchNotifications() =>
      MoodleWebApiConnector.getNotifications();

  /// 站內通知。空清單是合法結果——清單空但 `unreadcount > 0` 代表使用者在
  /// Moodle 關掉了站內通知，見 MoodleNotificationUtils.looksDisabledByUser。
  Future<Result<MoodleNotificationList>> getNotifications(
          {bool background = false}) =>
      run<MoodleNotificationList>(
        requires: const {SystemId.moodleWebApi},
        cache: notificationsKey(),
        background: background,
        retry: background ? RetryPolicy.none : RetryPolicy.askUser,
        errorMessage: R.current.getMoodleNotificationsError,
        debugLabel: 'moodleNotifications',
        fetch: fetchNotifications,
      );

  /// 樂觀標記已讀之後把新狀態寫回同一筆快取。`run()` 只在 fetch 成功那一刻
  /// 寫快取，寫入路徑沒有 `cache:`，不補這一趟的話下一次讀快取（離線）會把
  /// 剛剛標掉的圓點與未讀數整批復活。
  Future<void> saveNotifications(MoodleNotificationList list) =>
      CacheStore.instance
          .write<MoodleNotificationList>(notificationsKey(), list);

  @visibleForTesting
  Future<int?> fetchUnreadNotificationCount() =>
      MoodleWebApiConnector.getUnreadNotificationCount();

  /// 紅點用的未讀數。刻意不快取：過期的數字比沒有數字更糟，失敗時由呼叫端
  /// 保留上一個值。
  Future<Result<int>> getUnreadNotificationCount() => run<int>(
        requires: const {SystemId.moodleWebApi},
        background: true,
        retry: RetryPolicy.none,
        errorMessage: R.current.getMoodleNotificationsError,
        debugLabel: 'moodleUnreadCount',
        fetch: fetchUnreadNotificationCount,
      );

  @visibleForTesting
  Future<bool> writeNotificationRead(int notificationId) =>
      MoodleWebApiConnector.markNotificationRead(notificationId);

  /// 寫入也走 `run()`：要的是它的登入保證與離線分類，不是快取。
  /// `fetch` 必須把 false 轉成 null——`run()` 只把 null 當失敗，回 false 會被
  /// 當成成功。
  Future<Result<bool>> markNotificationRead(int notificationId) => run<bool>(
        requires: const {SystemId.moodleWebApi},
        background: true,
        retry: RetryPolicy.none,
        errorMessage: R.current.notificationMarkReadError,
        debugLabel: 'moodleMarkNotificationRead',
        fetch: () async =>
            await writeNotificationRead(notificationId) ? true : null,
      );

  @visibleForTesting
  Future<bool> writeAllNotificationsRead() =>
      MoodleWebApiConnector.markAllNotificationsRead();

  Future<Result<bool>> markAllNotificationsRead() => run<bool>(
        requires: const {SystemId.moodleWebApi},
        background: true,
        retry: RetryPolicy.none,
        errorMessage: R.current.notificationMarkAllReadError,
        debugLabel: 'moodleMarkAllNotificationsRead',
        fetch: () async => await writeAllNotificationsRead() ? true : null,
      );

  @visibleForTesting
  Future<int?> writeDraftFile(
    File file, {
    required String filename,
    int? draftItemId,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) =>
      MoodleWebApiConnector.uploadDraftFile(
        file,
        filename: filename,
        draftItemId: draftItemId,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

  @visibleForTesting
  Future<MoodleUpdatePictureResult?> writeProfilePicture({
    required int draftItemId,
    bool delete = false,
  }) =>
      MoodleWebApiConnector.updateProfilePicture(
          draftItemId: draftItemId, delete: delete);

  /// 換頭貼（[file] 為 null 就是移除）。走 `run()` 是為了它的登入保證與離線
  /// 分類，不是快取——寫入路徑沒有快取可讀。
  ///
  /// `retry: none`：這一趟帶著一個已經上傳到 draft 區的檔案，`run()` 的重試會
  /// 從頭再跑一次 fetch，等於再上傳一次；而且失敗原因多半是站台設定
  /// （userimagesdisabled / noprofileedit），重試不會變好。錯誤訊息由呼叫端
  /// 用 toast 呈現。
  ///
  /// `background: false`：token 死掉時仍然要開得了 Moodle 登入頁——那是使用者
  /// 主動按下的動作，不是背景預載。
  Future<Result<MoodleAvatarChange>> changeProfilePicture({
    File? file,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) =>
      run<MoodleAvatarChange>(
        requires: const {SystemId.moodleWebApi},
        retry: RetryPolicy.none,
        errorMessage: R.current.avatarUpdateError,
        debugLabel: 'moodleChangeAvatar',
        fetch: () => _changeProfilePicture(
          file: file,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
      );

  Future<MoodleAvatarChange?> _changeProfilePicture({
    required File? file,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final site = MoodleWebApiConnector.siteInfo;
    if (file != null) {
      // uploadfiles 是外部服務設定裡的同一顆開關，upload.php 自己也會擋；
      // 先看一眼可以省下一趟注定失敗的上傳。
      if (site != null && site.uploadfiles != 1) {
        throw TaskFailure(FetchFailed(R.current.avatarUploadDisabled));
      }
      final maxBytes = site?.usermaxuploadfilesize ?? 0;
      if (MoodleAvatarUtils.exceedsLimit(await file.length(), maxBytes)) {
        throw TaskFailure(FetchFailed(sprintf(
            R.current.avatarTooLarge, [FileUtils.formatBytes(maxBytes, 1)])));
      }
    }

    final MoodleUpdatePictureResult? result;
    try {
      final draftId = file == null
          ? 0
          : await writeDraftFile(
              file,
              filename: avatarUploadFilename(file.path),
              onProgress: onProgress,
              cancelToken: cancelToken,
            );
      if (draftId == null) return null;
      result =
          await writeProfilePicture(draftItemId: draftId, delete: file == null);
    } on MoodleApiException catch (e) {
      throw TaskFailure(FetchFailed(avatarFailureMessage(e)));
    }
    if (result == null) return null;

    if (!result.success) {
      // success 只代表 user.picture 有沒有變。刪一張本來就不存在的頭貼也會回
      // false，那不是錯誤；上傳路徑的 false 才是 process_new_icon 解不開這張圖。
      if (file == null) return const MoodleAvatarChange.noChange();
      throw TaskFailure(FetchFailed(R.current.avatarInvalidImage));
    }
    return MoodleAvatarChange(url: result.profileimageurl);
  }

  /// 寫入之後把重抓到的狀態補寫回同一筆快取。`run()` 只在 fetch 成功那一刻寫
  /// 快取，而寫入路徑沒有 `cache:`，不補這一趟的話離線時會看到繳交前的狀態。
  Future<void> saveSubmissionStatus(
          int assignId, MoodleAssignSubmissionStatus status) =>
      CacheStore.instance.write<MoodleAssignSubmissionStatus>(
          submissionStatusKey(assignId), status);

  @visibleForTesting
  Future<bool> writeSubmission({
    required int assignId,
    String? onlineText,
    int? draftItemId,
  }) =>
      MoodleWebApiConnector.saveSubmission(
        assignId: assignId,
        onlineText: onlineText,
        draftItemId: draftItemId,
      );

  @visibleForTesting
  Future<bool> writeSubmitForGrading({
    required int assignId,
    required bool acceptStatement,
  }) =>
      MoodleWebApiConnector.submitForGrading(
          assignId: assignId, acceptStatement: acceptStatement);

  @visibleForTesting
  Future<bool> downloadOnlineFile(String fileUrl, String savePath,
          {CancelToken? cancelToken,
          void Function(int received, int total)? onProgress}) =>
      MoodleWebApiConnector.downloadFileTo(fileUrl, savePath,
          cancelToken: cancelToken, onProgress: onProgress);

  @visibleForTesting
  Future<MoodleAssignSubmissionStatus?> refetchSubmissionStatus(int assignId) =>
      MoodleWebApiConnector.getSubmissionStatus(assignId);

  /// 重傳舊檔案時的暫存目錄。抽成縫是因為 `getTemporaryDirectory()` 走平台通道，
  /// 測試碰不到。
  @visibleForTesting
  Future<Directory> createSubmitTempDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(
        '${base.path}/assign_submit_${DateTime.now().microsecondsSinceEpoch}');
    await dir.create(recursive: true);
    return dir;
  }

  /// 交作業。走 `run()` 是為了它的登入保證與離線分類，不是快取。
  ///
  /// `retry: none`：這一趟中途可能已經把檔案送進 draft 區、甚至已經存了一次
  /// 繳交，`run()` 的重試會從頭再跑一次 fetch，等於重傳＋重存。
  ///
  /// `background: false`：token 死掉時仍然要開得了 Moodle 登入頁——這是使用者
  /// 主動按下的動作。
  Future<Result<MoodleAssignSubmitResult>> saveAssignSubmission({
    required MoodleAssignment assignment,
    required MoodleAssignSubmissionStatus status,
    required AssignSubmissionDraft draft,
    void Function(AssignTransferProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      run<MoodleAssignSubmitResult>(
        requires: const {SystemId.moodleWebApi},
        retry: RetryPolicy.none,
        errorMessage: R.current.assignSubmitError,
        debugLabel: 'moodleSaveAssignSubmission',
        fetch: () => _saveAssignSubmission(
          assignment: assignment,
          status: status,
          draft: draft,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
      );

  /// 把已經存好的草稿送出評分。不動繳交內容，所以不走 `save_submission`。
  ///
  /// [acceptStatement] 只在使用者真的勾了同意時才是 true。
  Future<Result<MoodleAssignSubmitResult>> submitAssignForGrading({
    required MoodleAssignment assignment,
    required MoodleAssignSubmissionStatus status,
    required bool acceptStatement,
  }) =>
      run<MoodleAssignSubmitResult>(
        requires: const {SystemId.moodleWebApi},
        retry: RetryPolicy.none,
        errorMessage: R.current.assignSubmitForGradingRejected,
        debugLabel: 'moodleSubmitAssignForGrading',
        fetch: () async {
          // 縱深防禦：`cansubmit` 是伺服器唯一算得準的閘門。
          if (!status.canSubmit) {
            throw TaskFailure(
                FetchFailed(R.current.assignSubmitForGradingRejected));
          }
          try {
            await writeSubmitForGrading(
              assignId: assignment.id,
              acceptStatement: acceptStatement,
            );
          } on MoodleApiException catch (e) {
            // 拒絕也要重抓：`couldnotsubmitforgrading` 不說原因，而伺服器可能
            // 早就是 SUBMITTED（另一個裝置送過了）。Failed 帶不了資料，所以
            // 走 Ok 加 error，由呼叫端 toast。
            return MoodleAssignSubmitResult(
              status: await _refreshStatus(assignment.id),
              submitted: false,
              error: assignSubmitFailureMessage(e),
            );
          }
          return MoodleAssignSubmitResult(
            status: await _refreshStatus(assignment.id),
            submitted: true,
          );
        },
      );

  Future<MoodleAssignSubmitResult?> _saveAssignSubmission({
    required MoodleAssignment assignment,
    required MoodleAssignSubmissionStatus status,
    required AssignSubmissionDraft draft,
    void Function(AssignTransferProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // 縱深防禦：UI 已經擋過一次，但按鈕畫出來到按下去之間可能已經過了截止時間。
    if (MoodleAssignSubmitUtils.blockOf(assignment, status) != null) {
      throw TaskFailure(FetchFailed(R.current.assignSubmitRejected));
    }
    if (draft.isEmpty) {
      throw TaskFailure(FetchFailed(R.current.assignNothingToSubmit));
    }

    int? draftItemId;
    Directory? tempDir;
    // save_submission 不是原子的：assign::save_submission 逐一呼叫每個
    // enabled 外掛的 save()，一個成功一個失敗也只回一則 couldnotsavesubmission。
    // 所以只要送出去了，之後的失敗都必須帶著重抓回來的狀態。
    var sentSubmission = false;
    try {
      final files = draft.files;
      if (files != null) {
        _checkDraftFiles(assignment, files);
        // 逐一算大小：超限的檔案伺服器不會抱怨，只會靜靜不見。
        for (final f in files) {
          if (f is LocalDraftFile) {
            final bytes = await f.file.length();
            if (MoodleAssignSubmitUtils.exceedsSize(
                bytes, MoodleAssignSubmitUtils.maxBytes(assignment))) {
              throw TaskFailure(
                  FetchFailed(sprintf(R.current.assignFileTooLarge, [
                f.filename,
                FileUtils.formatBytes(
                    MoodleAssignSubmitUtils.maxBytes(assignment), 1)
              ])));
            }
          }
        }
        draftItemId = await _buildDraftArea(
          files,
          onProgress: onProgress,
          cancelToken: cancelToken,
          openTempDir: () async => tempDir ??= await createSubmitTempDir(),
        );
      }

      sentSubmission = true;
      await writeSubmission(
        assignId: assignment.id,
        onlineText: draft.onlineText,
        draftItemId: draftItemId,
      );
    } on MoodleApiException catch (e) {
      final message = assignSubmitFailureMessage(e);
      // 還沒送出 save_submission：伺服器上什麼都沒動，直接失敗。
      if (!sentSubmission) throw TaskFailure(FetchFailed(message));
      return MoodleAssignSubmitResult(
        status: await _refreshStatus(assignment.id),
        submitted: false,
        error: message,
      );
    } finally {
      await _removeTempDir(tempDir);
    }

    // 存檔已經成功了：這之後不論成敗都要重抓狀態，畫面不可以停在繳交前。
    //
    // `submissiondrafts == 0` 的作業 save_submission 已經把 status 設成
    // SUBMITTED 了，再送一次 submit_for_grading 必定回 couldnotsubmitforgrading
    // （`$submission->status == SUBMITTED` 那條 return false），會把成功的繳交
    // 報成失敗——所以那種作業一律不送第二趟。
    var submitFailed = false;
    if (draft.submitForGrading && assignment.tracksDrafts) {
      try {
        await writeSubmitForGrading(
          assignId: assignment.id,
          acceptStatement: draft.acceptStatement,
        );
      } on MoodleApiException {
        submitFailed = true;
      }
    }

    final fresh = await _refreshStatus(assignment.id);
    // 第 4 步成功、第 5 步失敗不可以報成功，但訊息要說清楚「已存檔、未送出評分」，
    // 而且重抓到的狀態照樣要帶上去——內容真的存進去了，畫面停在存檔前才是說謊。
    return MoodleAssignSubmitResult(
      status: fresh,
      submitted:
          !submitFailed && (draft.submitForGrading || !assignment.tracksDrafts),
      error: submitFailed ? R.current.assignSavedNotSubmitted : null,
    );
  }

  /// 送出前一定要在本地擋掉的三件事：重名（upload.php 會回 filenameexist）、
  /// 超過檔案數（伺服器靜靜丟掉多的）、站台關掉上傳。
  void _checkDraftFiles(
      MoodleAssignment assignment, List<AssignDraftFile> files) {
    // 空清單會把繳交區的檔案全部刪光（file_save_draft_area_files 的同步語意），
    // 呼叫端的約定是「files 非 null 就必定非空」，這裡再擋一次。
    if (files.isEmpty) {
      throw TaskFailure(FetchFailed(R.current.assignFilesEmptiedWebOnly));
    }
    final duplicate = MoodleAssignSubmitUtils.duplicateFilename(files);
    if (duplicate != null) {
      throw TaskFailure(FetchFailed(R.current.assignFileDuplicateName));
    }
    final max = MoodleAssignSubmitUtils.maxFiles(assignment);
    if (files.length > max) {
      throw TaskFailure(FetchFailed(
          sprintf(R.current.assignFileCountExceeded, [max.toString()])));
    }
    final site = MoodleWebApiConnector.siteInfo;
    if (site != null && site.uploadfiles != 1) {
      throw TaskFailure(FetchFailed(R.current.assignUploadDisabled));
    }
  }

  /// 把整份清單送進同一個 draft 區，回那個 itemid。
  ///
  /// 第一個檔案不送 itemid（拿一個新的），其餘每一個都送回同一個；一個一個傳，
  /// 不並行，避免伺服器端的競態。任何一個失敗就整批放棄——半套的 draft 送進
  /// `save_submission` 就是「只交到一半」。
  Future<int> _buildDraftArea(
    List<AssignDraftFile> files, {
    required Future<Directory> Function() openTempDir,
    void Function(AssignTransferProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    int? itemId;
    for (var i = 0; i < files.length; i++) {
      final entry = files[i];
      void report(AssignTransferPhase phase, double ratio) =>
          onProgress?.call(AssignTransferProgress(
            done: i,
            total: files.length,
            ratio: ratio,
            phase: phase,
            filename: entry.filename,
          ));

      final File local;
      // 舊檔案要先下載再重傳，兩段各佔這個檔案的一半，進度條才不會倒退。
      final double uploadBase;
      if (entry is LocalDraftFile) {
        uploadBase = 0;
        report(AssignTransferPhase.upload, 0);
        local = entry.file;
      } else {
        uploadBase = 0.5;
        final online = entry as OnlineDraftFile;
        report(AssignTransferPhase.download, 0);
        final dir = await openTempDir();
        final path = '${dir.path}/${i}_${_safeName(online.filename)}';
        final ok = await downloadOnlineFile(
          online.fileurl,
          path,
          cancelToken: cancelToken,
          onProgress: (received, total) => report(AssignTransferPhase.download,
              total <= 0 ? 0 : received / total * 0.5),
        );
        if (!ok) {
          throw TaskFailure(FetchFailed(R.current.assignSubmitError));
        }
        local = File(path);
        // 收到什麼就傳什麼是這條路上唯一會毀掉使用者沒動過的東西的地方：
        // `files_filemanager` 是同步，把一頁錯誤 HTML 當成 report.pdf 傳上去，
        // 伺服器就會刪掉真的那一份。長度對不上寧可整批放棄。
        final bytes = await local.length();
        if (bytes <= 0 || (online.filesize > 0 && bytes != online.filesize)) {
          throw TaskFailure(FetchFailed(R.current.assignSubmitError));
        }
      }
      final uploaded = await writeDraftFile(
        local,
        filename: entry.filename,
        draftItemId: itemId,
        onProgress: (sent, total) => report(AssignTransferPhase.upload,
            uploadBase + (total <= 0 ? 0 : sent / total * (1 - uploadBase))),
        cancelToken: cancelToken,
      );
      if (uploaded == null) {
        throw TaskFailure(FetchFailed(R.current.assignSubmitError));
      }
      itemId ??= uploaded;
    }
    onProgress?.call(AssignTransferProgress(
      done: files.length,
      total: files.length,
      ratio: 0,
      phase: AssignTransferPhase.upload,
    ));
    // files 非 null 時約定必定非空，所以這裡一定有值。
    return itemId!;
  }

  /// 檔名是伺服器給的（`clean_param(PARAM_FILE)`），仍然不信任它會不會帶分隔符。
  static String _safeName(String filename) =>
      filename.replaceAll(RegExp(r'[/\\]'), '_');

  Future<void> _removeTempDir(Directory? dir) async {
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // 暫存檔清不掉不影響這次繳交，系統自己也會清。
    }
  }

  /// 寫入之後一定要重抓：使用者看到的必須是伺服器的真相，不是我們的樂觀狀態。
  ///
  /// 重抓不到時把那一筆快取**刪掉**：留著的是寫入前的狀態，離線再開會理直氣壯
  /// 地畫成「未繳交」。寧可退成錯誤畫面，也不要拿舊快照冒充現況。
  Future<MoodleAssignSubmissionStatus?> _refreshStatus(int assignId) async {
    try {
      final fresh = await refetchSubmissionStatus(assignId);
      if (fresh != null) {
        await saveSubmissionStatus(assignId, fresh);
        return fresh;
      }
    } catch (_) {
      // 寫入本身已經成功了，重抓失敗不該把它翻成失敗。
    }
    await CacheStore.instance.removeEntry(submissionStatusKey(assignId));
    return null;
  }
}

/// 一次繳交的結果。沒有 `.g.dart`：不落地也不上傳。
class MoodleAssignSubmitResult {
  const MoodleAssignSubmitResult({
    required this.status,
    required this.submitted,
    this.error,
  });

  /// 寫入之後重新抓的繳交狀態；抓不到是 null（寫入本身已經成功了）。
  final MoodleAssignSubmissionStatus? status;

  /// true = 已送出評分，或這份作業沒有草稿階段（存檔就是繳交）。
  final bool submitted;

  /// 非 null＝這一趟沒有完全成功，要 toast 這句話。**仍然是 `Ok`**：
  /// [Failed] 帶不了資料，而 `save_submission` 不是原子的，被拒絕之後
  /// [status] 才是唯一說得清楚伺服器上到底變成什麼樣子的東西。
  final String? error;
}

/// 交作業的 errorcode 換成使用者看得懂的一句話。認不得的一律回
/// [R.current.assignSubmitError]——把英文原文丟到畫面上不叫「處理錯誤」。
/// `couldnotsavesubmission` 一碼多因（逾期／內容為空／外掛回錯），所以那一句
/// 只能是涵蓋性的，真正的原因由重抓回來的狀態卡自己說。
String assignSubmitFailureMessage(MoodleApiException e) =>
    switch (e.errorcode) {
      'couldnotsavesubmission' => R.current.assignSubmitRejected,
      'couldnotsubmitforgrading' => R.current.assignSubmitForGradingRejected,
      'submissionslocked' => R.current.assignSubmitLocked,
      'nopermissions' ||
      'required_capability_exception' ||
      'accessexception' =>
        R.current.assignSubmitNoPermission,
      'filenameexist' => R.current.assignFileDuplicateName,
      'fileoversized' ||
      'userquotalimit' ||
      'upload_error_ini_size' ||
      'upload_error_form_size' =>
        R.current.assignFileTooLargeUnknown,
      'virusfounduser' => R.current.assignFileVirusFound,
      _ => R.current.assignSubmitError,
    };

/// 換頭貼的結果。沒有 `.g.dart`：不落地也不上傳，沒有東西序列化它。
class MoodleAvatarChange {
  const MoodleAvatarChange({required this.url});

  /// 伺服器算出來的新頭貼網址。伺服器說「沒有變」時是空字串。
  final String url;

  /// 刪除一張本來就不存在的頭貼：不是錯誤，但也沒有新網址。
  const MoodleAvatarChange.noChange() : url = '';
}

/// 送進 draft 區的檔名。副檔名照著挑到的檔案走，其餘一律正規化：
/// Android 的 resizer 會把重新編碼過的 JPEG 存成 `scaled_foo.webp`，
/// 那對 `getimagesize()` 無害，但 draft 區裡看起來很怪，而檔名是我們決定的。
String avatarUploadFilename(String path) => path.toLowerCase().endsWith('.png')
    ? 'profile_picture.png'
    : 'profile_picture.jpg';

/// Moodle 的 errorcode 換成使用者看得懂的一句話。認不得的一律回
/// [R.current.avatarUpdateError]——把英文原文丟到畫面上不叫「處理錯誤」。
String avatarFailureMessage(MoodleApiException e) => switch (e.errorcode) {
      'accessexception' => R.current.avatarNotSupported,
      'userimagesdisabled' => R.current.avatarDisabledOnSite,
      'noprofileedit' => R.current.avatarProfileLocked,
      'nopermissions' => R.current.avatarNoPermission,
      'fileoversized' ||
      'userquotalimit' ||
      'upload_error_ini_size' ||
      'upload_error_form_size' =>
        R.current.avatarTooLargeUnknown,
      _ => R.current.avatarUpdateError,
    };

/// 發文失敗的 errorcode 換成使用者看得懂的一句話。認不得的一律回
/// [R.current.forumSendError]——伺服器的英文原文不會出現在畫面上。
String forumPostFailureMessage(MoodleApiException e) => switch (e.errorcode) {
      'nopostforum' => R.current.forumErrorNoPermission,
      'cannotcreatediscussion' => R.current.forumErrorCannotCreateDiscussion,
      'invalidparentpostid' ||
      'notpartofdiscussion' =>
        R.current.forumErrorPostGone,
      'forumblockingtoomanyposts' => R.current.forumErrorTooManyPosts,
      'accessexception' => R.current.forumCannotPost,
      _ => R.current.forumSendError,
    };

/// 舊快取的遷移點，不要簡化成 `fromJson`：每個欄位都有 defaultValue，舊格式的
/// blob 丟進去不會拋，只會得到一頁空白而且永遠命中快取。明確要求 `gradeitems`
/// 存在，缺席就拋，`CacheStore.read` 會移除那一筆並照常走網路重抓。
MoodleUserGradesEntity decodeCachedScore(dynamic json) {
  if (json is! Map<String, dynamic> || !json.containsKey('gradeitems')) {
    throw const FormatException(
        'cache_moodle_score 是 gradereport_user_get_grades_table 年代的舊格式');
  }
  return MoodleUserGradesEntity.fromJson(json);
}

/// 走 connector 的 `submissionStatusOf` 而不是 `fromJson`：`gradefordisplay`
/// 的 HTML 清洗只寫在那一處。
MoodleAssignSubmissionStatus decodeCachedSubmissionStatus(dynamic json) {
  final status = MoodleWebApiConnector.submissionStatusOf(json);
  if (status == null) {
    throw const FormatException('cache_moodle_assign_status 的形狀不對');
  }
  return status;
}

/// 走 connector 的 `quizBestGradeOf` 而不是 `fromJson`：每個欄位都有
/// defaultValue，別的舊 blob 丟進去不會拋，只會得到一頁「尚未有成績」而且
/// 永遠命中快取。缺 `hasgrade` 就拋，`CacheStore.read` 會移除那一筆。
MoodleQuizBestGrade decodeCachedQuizBestGrade(dynamic json) {
  final grade = MoodleWebApiConnector.quizBestGradeOf(json);
  if (grade == null) {
    throw const FormatException('cache_moodle_quiz_grade 的形狀不對');
  }
  return grade;
}
