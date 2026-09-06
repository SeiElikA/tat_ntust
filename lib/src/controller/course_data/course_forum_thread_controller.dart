import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:get/get.dart';

/// 討論串頁（公告與一般討論區共用）的狀態；由頁面的 State 建立與 [dispose]。
class CourseForumThreadController {
  CourseForumThreadController({required this.discussionId});

  final int discussionId;

  final posts = Rxn<Result<List<MoodleForumPost>>>();

  /// 重新載入。**已經在畫面上的貼文不會被丟掉**：剛送出的那一則已經併進
  /// `posts` 了，這一趟失敗時退回 `Stale` 而不是 `Failed`，使用者才不會看到
  /// 自己的回覆消失、或整頁變成錯誤畫面——那則回覆確實送出去了。
  ///
  /// [keepVisible] 是送出後那一趟重抓用的：清成 null 會讓整串（含剛送出的
  /// 那一則）在一趟來回之間變成轉圈再長回來，同樣是「回覆消失」。進頁面的
  /// 第一次載入與使用者自己按的重試維持預設，那裡的轉圈就是回饋本身。
  Future<void> loadPosts({bool keepVisible = false}) async {
    final previous = posts.value?.dataOrNull;
    if (!keepVisible || previous == null) posts.value = null;
    final result =
        await MoodleRepository.instance.getDiscussionPosts(discussionId);
    posts.value = switch (result) {
      Failed<List<MoodleForumPost>>(:final reason) when previous != null =>
        Stale<List<MoodleForumPost>>(previous, reason),
      _ => result,
    };
  }

  Future<Result<MoodleForumPost>> reply({
    required int postId,
    required String subject,
    required String text,
  }) =>
      MoodleRepository.instance
          .postReply(postId: postId, subject: subject, text: text);

  /// 把剛送出的回覆併進畫面與快取。`run()` 只在 fetch 成功那一刻寫快取，而
  /// 寫入路徑沒有 `cache:`，少了這一步離線重開會看不到自己剛發的那一則。
  Future<void> appendPost(MoodleForumPost added) async {
    final merged =
        MoodleForumUtils.mergePost(posts.value?.dataOrNull ?? const [], added);
    posts.value = Ok<List<MoodleForumPost>>(merged);
    await MoodleRepository.instance.saveDiscussionPosts(discussionId, merged);
  }

  void dispose() => posts.close();
}
