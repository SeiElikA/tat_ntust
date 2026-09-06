import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/controller/course_data/course_announcement_controller.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/html/moodle_html_view.dart';
import 'package:flutter_app/ui/components/page/inline_error_view.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:intl/intl.dart';

/// 一則公告的討論串：第一篇加上全部回覆。WebView 開啟器由呼叫端注入，
/// 見 docs/ARCHITECTURE.md「UI 慣例」；貼文本文走 [MoodleHtmlView]。
class CourseAnnouncementDetailPage extends StatefulWidget {
  const CourseAnnouncementDetailPage(
    this.courseInfo,
    this.discussion, {
    required this.openWebView,
    super.key,
  });

  final CourseInfoJson courseInfo;
  final Discussions discussion;
  final WebViewOpener openWebView;

  @override
  State<StatefulWidget> createState() => _CourseAnnouncementDetailPageState();
}

class _CourseAnnouncementDetailPageState
    extends State<CourseAnnouncementDetailPage> {
  late final CourseAnnouncementController _controller;

  @override
  void initState() {
    super.initState();
    // discussion 才是討論串 id；id 是第一篇貼文的 id（見 docs/MOODLE_REFERENCE.md）。
    _controller = CourseAnnouncementController(
        discussionId: widget.discussion.discussion);
    unawaited(_controller.loadPosts());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 標題的 HTML 實體已由 connector 還原。
      appBar: baseAppbar(title: widget.discussion.name),
      body: ResultView<List<MoodleForumPost>>(
        state: _controller.posts,
        onRetry: _controller.loadPosts,
        errorBuilder: _fallback,
        builder: (posts) => _thread(MoodleForumUtils.buildThread(posts)),
      ),
    );
  }

  /// 抓不到回覆時至少把公告本文畫出來：清單那一列本身就是第一篇貼文。
  Widget _fallback(String message) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          ..._postBlock(
              ThreadPost(MoodleForumUtils.rootPostOf(widget.discussion), 0),
              first: true),
          const SizedBox(height: 12),
          InlineErrorView(message: message, onRetry: _controller.loadPosts),
        ],
      );

  Widget _thread(List<ThreadPost> items) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        itemCount: items.length,
        itemBuilder: (context, index) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _postBlock(items[index], first: index == 0),
        ),
      );

  List<Widget> _postBlock(ThreadPost t, {required bool first}) {
    final p = t.post;
    final scheme = Theme.of(context).colorScheme;
    final author = p.author?.fullname ?? "";
    return [
      Padding(
        padding: EdgeInsets.only(left: t.depth.clamp(0, 3) * 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon:
                  t.depth == 0 ? Icons.campaign_outlined : Icons.reply_outlined,
              title: author.isNotEmpty ? author : R.current.forumUnknownAuthor,
              first: first,
              trailing: Text(
                _time(p),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            SectionCard([
              // 只有第一篇印標題：回覆的 subject 是伺服器語系的「回覆: …」，
              // 重複又難看。
              if (t.depth == 0 && p.subject.isNotEmpty)
                SectionSubLabel(p.subject),
              _body(p),
              if (p.attachments.isNotEmpty) ...[
                const SectionDivider(),
                SectionSubLabel(R.current.forumAttachments),
                for (final f in p.attachments)
                  MoodleFileTile(
                    filename: f.filename,
                    onTap: () => unawaited(FileDownload.download(
                      context,
                      MoodleWebApiConnector.fileUrlWithToken(f.url),
                      widget.courseInfo.main.course.name,
                      name: f.filename,
                    )),
                  ),
              ],
            ]),
          ],
        ),
      ),
    ];
  }

  Widget _body(MoodleForumPost p) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (p.isdeleted) {
      return Text(R.current.forumPostDeleted,
          style: text.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant));
    }
    if (p.message.trim().isEmpty) {
      return Text(R.current.nothingHere,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant));
    }
    return MoodleHtmlView(
      html: p.message,
      title: widget.discussion.name,
      dirName: widget.courseInfo.main.course.name,
      openWebView: widget.openWebView,
    );
  }

  /// isdeleted 的貼文 timecreated 是 null（post_exporter 這時不載內容）。
  String _time(MoodleForumPost p) {
    final unix = p.timecreated ?? p.timemodified ?? 0;
    return unix > 0
        ? DateFormat.yMd()
            .add_jm()
            .format(DateTime.fromMillisecondsSinceEpoch(unix * 1000))
        : "";
  }
}
