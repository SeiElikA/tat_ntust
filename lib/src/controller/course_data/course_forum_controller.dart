import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_can_add_discussion.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/moodle_forum_edit_utils.dart';
import 'package:get/get.dart';

/// 一個討論區的狀態：主題清單、「能不能開新主題」與附件政策；由頁面的 State
/// 建立與 [dispose]，生命週期就是那一個頁面（同 `CourseAssignmentController`）。
class CourseForumController {
  CourseForumController({required this.forumId, required this.courseId});

  /// forum instance id（`Modules.instance`），不是 cmid。
  final int forumId;

  /// 附件政策要從 `get_forums_by_courses` 拿 forum record，那一支吃的是課號。
  final String courseId;

  final discussions = Rxn<Result<List<Discussions>>>();

  /// 沒有快取：過期的「你可以發文」比沒有答案更糟。
  final canAdd = Rxn<Result<MoodleCanAddDiscussion>>();

  /// 新主題的附件政策。同樣不快取，理由同 [canAdd]。null ＝還沒問到 ⇒ 不給。
  final attachPolicy = Rxn<ForumAttachPolicy>();

  ForumAttachPolicy get policy =>
      attachPolicy.value ?? const ForumAttachPolicy.off();

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
    await loadAttachPolicy();
  }

  /// `can_add_discussion.cancreateattachment` 已經把 capability、
  /// `maxattachments` 與 `maxbytes` 三件事都算完了，所以新主題這條路把它直接
  /// 交給 repository，只差 forum record 上的那兩個數字。**null ＝不知道 ⇒ 不給**。
  Future<void> loadAttachPolicy() async {
    final known = canAdd.value?.dataOrNull?.cancreateattachment;
    if (known != true) {
      attachPolicy.value = const ForumAttachPolicy.off();
      return;
    }
    final result = await MoodleRepository.instance.getForumAttachPolicy(
      courseId: courseId,
      forumId: forumId,
      knownCanCreateAttachment: true,
    );
    attachPolicy.value = result.dataOrNull ?? const ForumAttachPolicy.off();
  }

  Future<Result<ForumDiscussionOutcome>> postDiscussion({
    required String subject,
    required String text,
    List<File> attachments = const [],
    void Function(ForumTransferProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      MoodleRepository.instance.postDiscussion(
        forumId: forumId,
        subject: subject,
        text: text,
        attachments: attachments,
        policy: policy,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

  void dispose() {
    discussions.close();
    canAdd.close();
    attachPolicy.close();
  }
}
