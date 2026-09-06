import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_can_add_discussion.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:get/get.dart';

/// 一個討論區的狀態：主題清單與「能不能開新主題」；由頁面的 State 建立與
/// [dispose]，生命週期就是那一個頁面（同 `CourseAssignmentController`）。
class CourseForumController {
  CourseForumController({required this.forumId});

  /// forum instance id（`Modules.instance`），不是 cmid。
  final int forumId;

  final discussions = Rxn<Result<List<Discussions>>>();

  /// 沒有快取：過期的「你可以發文」比沒有答案更糟。
  final canAdd = Rxn<Result<MoodleCanAddDiscussion>>();

  Future<void> loadAll() =>
      Future.wait([loadDiscussions(), loadCanAddDiscussion()]);

  /// [keepVisible] 給送出新主題之後的重抓用：畫面上已經有清單時不要先清成
  /// null，否則會在使用者眼前閃一次整頁轉圈。
  Future<void> loadDiscussions({bool keepVisible = false}) async {
    if (!keepVisible || discussions.value?.dataOrNull == null) {
      discussions.value = null;
    }
    discussions.value =
        await MoodleRepository.instance.getForumDiscussions(forumId);
  }

  Future<void> loadCanAddDiscussion() async {
    canAdd.value = null;
    canAdd.value = await MoodleRepository.instance.canAddDiscussion(forumId);
  }

  Future<Result<int>> postDiscussion(
          {required String subject, required String text}) =>
      MoodleRepository.instance
          .postDiscussion(forumId: forumId, subject: subject, text: text);

  void dispose() {
    discussions.close();
    canAdd.close();
  }
}
