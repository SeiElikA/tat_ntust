import 'package:flutter/foundation.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_calendar_action_events.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_gradereport_get_grade_items.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_message_popup_notifications.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/repository/retry.dart';
import 'package:flutter_app/src/repository/run.dart';
import 'package:flutter_app/src/store/cache_store.dart';
import 'package:flutter_app/src/util/moodle_assign_utils.dart';

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

  /// 繳交狀態、成績與回饋。[assignId] 已是 Moodle 內部 id，不走 [_withCourse]。
  /// [background]：清單上 N 份並行抓時不彈框、不開登入頁；詳情頁傳 false。
  Future<Result<MoodleAssignSubmissionStatus>> getSubmissionStatus(
    int assignId, {
    bool background = false,
  }) =>
      run<MoodleAssignSubmissionStatus>(
        requires: const {SystemId.moodleWebApi},
        cache: CacheKey<MoodleAssignSubmissionStatus>(
          "cache_moodle_assign_status",
          assignId.toString(),
          decode: decodeCachedSubmissionStatus,
        ),
        fetch: () => MoodleWebApiConnector.getSubmissionStatus(assignId),
        errorMessage: R.current.getMoodleAssignmentStatusError,
        debugLabel: 'moodleAssignStatus',
        retry: background ? RetryPolicy.none : RetryPolicy.askUser,
        background: background,
      );

  /// 一則公告的討論串（第一篇加回覆）。[discussionId] 是 `Discussions.discussion`，
  /// 不是 `Discussions.id`——後者是第一篇貼文的 id。
  Future<Result<List<MoodleForumPost>>> getDiscussionPosts(int discussionId) =>
      run<List<MoodleForumPost>>(
        requires: const {SystemId.moodleWebApi},
        cache: CacheKey<List<MoodleForumPost>>(
          "cache_moodle_forum_posts",
          discussionId.toString(),
          decode: (json) => (json as List)
              .map((e) =>
                  MoodleForumPost.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
        ),
        fetch: () => MoodleWebApiConnector.getDiscussionPosts(discussionId),
        errorMessage: R.current.getMoodleForumPostsError,
        debugLabel: 'moodleForumPosts',
      );

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
}

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
