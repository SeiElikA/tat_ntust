import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_gradereport_get_grade_items.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:get/get.dart';

/// 一門課的三個 Moodle 分頁（檔案、公告、成績）共用的狀態。
///
/// `PageView(children:)` 是懶載入的（cacheExtent 0），分頁各自在 initState
/// 發請求的話，每滑到一個分頁就得從頭等一次。狀態抽出來由頁面持有，三個
/// 請求才能在進入頁面時一起發出去。
///
/// 不是 GetxController：生命週期就是那一個頁面，交給 State 建立與 [dispose]
/// 最單純，也不必處理 GetX 的註冊與 fenix 語意。
class CourseDataController {
  CourseDataController(this.courseId);

  final String courseId;

  /// null 代表還在載入，與 `ResultView` 的約定一致。
  final directory = Rxn<Result<List<MoodleCoreCourseGetContents>>>();
  final announcements = Rxn<Result<MoodleModForumGetForumDiscussions>>();
  final score = Rxn<Result<MoodleUserGradesEntity>>();

  /// 三個一起抓。
  ///
  /// 三個請求都會先解析同一個課程的 Moodle 內部 id，所以
  /// `MoodleRepository` 那邊必須有 in-flight 去重，否則等於把
  /// `core_course_get_courses_by_field` 打三次。見 `MoodleRepository._findId`。
  Future<void> loadAll() => Future.wait([
        loadDirectory(),
        loadAnnouncements(),
        loadScore(),
      ]);

  Future<void> loadDirectory() async {
    directory.value = null;
    directory.value =
        await MoodleRepository.instance.getCourseDirectory(courseId);
  }

  Future<void> loadAnnouncements() async {
    announcements.value = null;
    announcements.value =
        await MoodleRepository.instance.getAnnouncements(courseId);
  }

  Future<void> loadScore() async {
    score.value = null;
    score.value = await MoodleRepository.instance.getCourseScore(courseId);
  }

  void dispose() {
    directory.close();
    announcements.close();
    score.close();
  }
}
