import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:get/get.dart';

/// 公告討論串頁的狀態；由頁面的 State 建立與 [dispose]。
class CourseAnnouncementController {
  CourseAnnouncementController({required this.discussionId});

  final int discussionId;

  final posts = Rxn<Result<List<MoodleForumPost>>>();

  Future<void> loadPosts() async {
    posts.value = null;
    posts.value =
        await MoodleRepository.instance.getDiscussionPosts(discussionId);
  }

  void dispose() => posts.close();
}
