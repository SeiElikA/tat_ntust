import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/ntust_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:get/get.dart';

/// 一門課的兩個詳細內容分頁（課程、成員）共用的狀態。
///
/// 理由與 [CourseDataController] 相同：`PageView(children:)` 是懶載入的，
/// 成員清單要等使用者滑過去才開始抓。進入頁面時就一起發，滑過去多半已經好了。
///
/// 兩個請求打的是不同系統——課程資訊走 querycourse（免登入），成員走
/// Moodle，所以它們互不影響，其中一個失敗不會拖累另一個。
class CourseDetailController {
  CourseDetailController({required this.courseId, required this.semester});

  final String courseId;
  final SemesterJson semester;

  final info = Rxn<Result<CourseExtraInfoJson>>();
  final members = Rxn<Result<List<MoodleCoreEnrolGetUsers>>>();

  Future<void> loadAll() => Future.wait([loadInfo(), loadMembers()]);

  Future<void> loadInfo() async {
    info.value = null;
    info.value =
        await NtustRepository.instance.getCourseExtraInfo(courseId, semester);
  }

  Future<void> loadMembers() async {
    members.value = null;
    members.value = await MoodleRepository.instance.getMembers(courseId);
  }

  void dispose() {
    info.close();
    members.close();
  }
}
