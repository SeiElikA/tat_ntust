import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/controller/course_data/course_data_controller.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/components/page/empty_state.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_thread_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/forum_discussion_card.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// 課程頁的「公告」分頁。錯誤畫面與 WebView 開啟器由呼叫端注入，
/// 見 docs/ARCHITECTURE.md「UI 慣例」。
class CourseAnnouncementPage extends StatefulWidget {
  const CourseAnnouncementPage(
    this.courseInfo, {
    required this.controller,
    required this.errorBuilder,
    required this.openWebView,
    super.key,
  });

  final CourseInfoJson courseInfo;

  /// 四個分頁共用的狀態；請求在進入頁面時已一次發完。
  final CourseDataController controller;

  final Widget Function(String message) errorBuilder;
  final WebViewOpener openWebView;

  @override
  State<StatefulWidget> createState() => _CourseAnnouncementPageState();
}

class _CourseAnnouncementPageState extends State<CourseAnnouncementPage>
    with AutomaticKeepAliveClientMixin {
  Rxn<Result<MoodleModForumGetForumDiscussions>> get _state =>
      widget.controller.announcements;

  // 沒有 initState 觸發請求，見 CourseDataController.loadAll。

  Future<void> _load() => widget.controller.loadAnnouncements();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ResultView<MoodleModForumGetForumDiscussions>(
      state: _state,
      onRetry: _load,
      errorBuilder: widget.errorBuilder,
      builder: buildTree,
    );
  }

  Widget buildTree(MoodleModForumGetForumDiscussions data) {
    if (!data.forumFound) {
      return _empty(R.current.announcementNoForum);
    }
    if (data.discussions.isEmpty) {
      return _empty(R.current.announcementEmpty);
    }

    final formatter = DateFormat.yMd().add_jm();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: data.discussions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => ForumDiscussionCard(
        discussion: data.discussions[index],
        formatter: formatter,
        onTap: () => unawaited(Get.to(() => CourseForumThreadPage(
              widget.courseInfo,
              // discussion 才是討論串 id；id 是第一篇貼文的 id。
              discussionId: data.discussions[index].discussion,
              title: data.discussions[index].name,
              fallbackDiscussion: data.discussions[index],
              openWebView: widget.openWebView,
            ))),
      ),
    );
  }

  Widget _empty(String message) =>
      EmptyState(icon: LucideIcons.messageSquare, message: message);

  @override
  bool get wantKeepAlive => true;
}
