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
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_announcement_detail_page.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:sprintf/sprintf.dart';
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
      itemBuilder: (context, index) => _AnnouncementCard(
        discussion: data.discussions[index],
        formatter: formatter,
        onTap: () => unawaited(Get.to(() => CourseAnnouncementDetailPage(
              widget.courseInfo,
              data.discussions[index],
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

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.discussion,
    required this.formatter,
    required this.onTap,
  });

  final Discussions discussion;
  final DateFormat formatter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // 用建立時間：modified 是第一篇貼文被編輯過的時間，詳情頁那邊印的是建立時間。
    final formatted = formatter
        .format(DateTime.fromMillisecondsSinceEpoch(discussion.created * 1000));
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (discussion.pinned) ...[
                    Icon(LucideIcons.pin,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      discussion.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                          height: 1.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${discussion.userfullname} · $formatted",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (discussion.numreplies > 0) ...[
                    const SizedBox(width: 8),
                    Icon(LucideIcons.messageSquare,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      sprintf(R.current.forumReplies, [discussion.numreplies]),
                      style: text.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
