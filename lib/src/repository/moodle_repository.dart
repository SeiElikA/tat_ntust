import 'package:flutter/foundation.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_gradereport_get_grade_items.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/repository/run.dart';
import 'package:flutter_app/src/store/cache_store.dart';

/// 課程頁四個分頁的資料來源。
///
/// 每一次取得都是兩段：先把課號換成 Moodle 的內部 id，再用那個 id 拿資料。
/// **第一段失敗必須在 `fetch` 內丟 [TaskFailure]**，這樣 `run()` 的失敗路徑
/// 才會去讀 [CacheKey] 而回得出 [Stale]；否則離線使用者看不到已經存在硬碟上
/// 的成績。
class MoodleRepository {
  MoodleRepository();

  static MoodleRepository instance = MoodleRepository();

  /// 課號到 Moodle 內部 id 的對照。
  ///
  /// 四個分頁共用同一個 name，只靠 courseId 分筆，而課程頁的分頁是並行載入
  /// 的。整包 blob 的無鎖覆寫由 `CacheStore` 內部的 per-name 佇列負責，這裡
  /// 不需要也不應該自己再加鎖。
  static CacheKey<String> _findIdKey(String courseId) => CacheKey<String>(
        "cache_moodle_support",
        courseId,
        decode: (json) => json as String,
      );

  /// 第一段（課號 → Moodle 內部 id）正在解析中的課程 id。
  ///
  /// read-through：命中就完全不打網路。`getCourseUrl` 內含兩次 POST，三個
  /// 分頁並行時差別是六次網路往返。找不到對應時丟 [UnsupportedCourse]
  /// （不可重試），並清掉對照表那一筆，下次重試才會重新解析。
  ///
  /// 課程頁一次發出三個請求（檔案、公告、成績），少了這張表三個會同時 miss
  /// 快取、同時打 `core_course_get_courses_by_field`——第一次寫進快取之前另外
  /// 兩次早就出發了，快取擋不住。
  ///
  /// 用 static 而不是實例欄位，理由與 `AppAuthSession.inFlight` 相同：
  /// `MoodleRepository.instance` 在測試裡會被換掉，去重要跨得過那次替換。
  /// 同一個課號正在解析中的 Future，用來去重。
  @visibleForTesting
  static final Map<String, Future<String>> findIdInFlight = {};

  Future<String> _findId(String courseId) {
    final running = findIdInFlight[courseId];
    if (running != null) return running;
    final future = _resolveFindId(courseId);
    findIdInFlight[courseId] = future;
    // whenComplete 而不是 then：失敗也要移除，否則一次失敗會把這個課號的
    // 結果永久釘成那個例外。
    return future.whenComplete(() => findIdInFlight.remove(courseId));
  }

  /// 測試用的縫：把「真的去問 Moodle」那一步隔開。沒有它，去重那一層只能
  /// 靠測試複製一份邏輯來驗——那種測試會過，但驗的是副本不是正式程式碼。
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

  /// 兩段式取得的共用外殼。
  ///
  /// **沒有 progressMessage，這是刻意的。** 呼叫端全是 `ResultView`，它在
  /// `state.value == null` 時就會畫自己的 LoadingPage；再傳 progressMessage
  /// 會多蓋一層全螢幕阻擋式進度框，同一件事兩個轉圈，還擋住底下的骨架。
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

  /// 這一門課的公告。
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
        // 空清單算失敗，不是「這門課沒有學生」。run() 只把 null 當失敗，
        // 所以要映成 null，才會去讀快取。
        fetch: (findId) async {
          final value = await MoodleWebApiConnector.getMember(findId);
          return (value == null || value.isEmpty) ? null : value;
        },
        errorMessage: R.current.getMoodleMembersError,
        debugLabel: 'moodleMember',
      );
}

/// `cache_moodle_score` 這一筆的解碼器。
///
/// **這是舊快取的遷移點，不要簡化成 `MoodleUserGradesEntity.fromJson`。**
///
/// 硬碟上可能還留著 `gradereport_user_get_grades_table` 年代的舊 blob，而
/// [MoodleUserGradesEntity] 每個欄位都有 defaultValue，把那包舊 blob 丟進
/// `fromJson` **不會拋**——只有 `gradeitems` 缺席退回空清單，成績頁因此一片
/// 空白；又因為快取命中，重開 App 也還是空白，直到有人手動登出。
///
/// 所以這裡明確要求 `gradeitems` 這個 key 存在，缺席就拋。`CacheStore.read`
/// 會把 decode 失敗的那一筆從整包 blob 移除、回傳 null，於是照常走網路重抓
/// 新格式。舊資料只會被讀壞一次。
MoodleUserGradesEntity decodeCachedScore(dynamic json) {
  if (json is! Map<String, dynamic> || !json.containsKey('gradeitems')) {
    throw const FormatException(
        'cache_moodle_score 是 gradereport_user_get_grades_table 年代的舊格式');
  }
  return MoodleUserGradesEntity.fromJson(json);
}
