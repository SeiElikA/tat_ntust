import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/controller/course_data/course_forum_thread_controller.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/language_utils.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/html/moodle_html_view.dart';
import 'package:flutter_app/ui/components/page/inline_error_view.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_compose_page.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// 一則討論串：第一篇加上全部回覆。公告分頁與一般討論區都推這一頁——它們是
/// 同一種東西，只是討論區的 type 不同。WebView 開啟器由呼叫端注入，
/// 見 docs/ARCHITECTURE.md「UI 慣例」；貼文本文走 [MoodleHtmlView]。
class CourseForumThreadPage extends StatefulWidget {
  const CourseForumThreadPage(
    this.courseInfo, {
    required this.discussionId,
    required this.title,
    this.fallbackDiscussion,
    required this.openWebView,
    super.key,
  });

  final CourseInfoJson courseInfo;

  /// `Discussions.discussion`，不是 `Discussions.id`——後者是第一篇貼文的 id
  /// （見 docs/MOODLE_REFERENCE.md）。
  final int discussionId;

  /// AppBar 標題。HTML 實體已由 connector 還原。
  final String title;

  /// 抓不到回覆時的退路貼文來源：清單那一列本身就是第一篇貼文。從剛建立的
  /// 主題直接進來時手上沒有那一列，是 null。
  final Discussions? fallbackDiscussion;

  final WebViewOpener openWebView;

  @override
  State<StatefulWidget> createState() => _CourseForumThreadPageState();
}

class _CourseForumThreadPageState extends State<CourseForumThreadPage> {
  late final CourseForumThreadController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        CourseForumThreadController(discussionId: widget.discussionId);
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
      appBar: baseAppbar(title: widget.title),
      body: ResultView<List<MoodleForumPost>>(
        state: _controller.posts,
        onRetry: _controller.loadPosts,
        errorBuilder: _fallback,
        builder: _thread,
      ),
    );
  }

  /// 抓不到回覆時至少把第一篇畫出來：清單那一列本身就是第一篇貼文。從剛建立
  /// 的主題進來時手上沒有那一列，就只畫錯誤與重試。
  Widget _fallback(String message) {
    final discussion = widget.fallbackDiscussion;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        if (discussion != null) ...[
          ..._postBlock(ThreadPost(MoodleForumUtils.rootPostOf(discussion), 0),
              first: true),
          const SizedBox(height: 12),
        ],
        InlineErrorView(message: message, onRetry: _controller.loadPosts),
      ],
    );
  }

  Widget _thread(List<MoodleForumPost> posts) {
    final items = MoodleForumUtils.buildThread(posts);
    // 沒有任何一篇可以回覆時用一行說明加網頁入口收尾，而不是給一顆按下去才
    // 失敗的鈕。討論串被鎖、cutoff 過了、公告區的學生身分都會走到這裡。
    final locked = !posts.any(_canReply);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      itemCount: items.length + (locked ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == items.length) return _lockedFooter();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _postBlock(items[index], first: index == 0),
        );
      },
    );
  }

  Widget _lockedFooter() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            R.current.forumThreadLocked,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          TextButton.icon(
            onPressed: () => unawaited(_openInWeb()),
            icon: const Icon(LucideIcons.externalLink, size: 16),
            label: Text(R.current.forumOpenInWeb),
          ),
        ],
      ),
    );
  }

  Future<void> _openInWeb() =>
      widget.openWebView(widget.title, _discussionUrl());

  /// 網頁版討論串。這裡不呼叫 `autologinUrl`：注入的 [CourseForumThreadPage
  /// .openWebView] 自己會換，再換一次等於在六分鐘的伺服器節流內多燒一把鑰匙。
  String _discussionUrl() => Connector.uriAddQuery(
        "${MoodleWebApiConnector.host}/mod/forum/discuss.php"
        "?d=${widget.discussionId}",
        {"lang": LanguageUtils.getLangIndex() == LangEnum.zh ? "zh_tw" : "en"},
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
              icon: t.depth == 0 ? LucideIcons.megaphone : LucideIcons.reply,
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
              // 回覆鈕逐篇而不是一條底部列：回覆的對象因此永遠不會弄錯，
              // 而最常見的「回第一篇」剛好落在最上面。
              if (_canReply(p))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_compose(p)),
                    icon: const Icon(LucideIcons.reply, size: 16),
                    label: Text(R.current.forumReply),
                  ),
                ),
            ]),
          ],
        ),
      ),
    ];
  }

  /// 伺服器算的 `capabilities.reply` 是唯一判準（**不是** `urls.reply`：
  /// `selfenrol` 會讓那個網址在不能回覆時也非 null）；站台沒開放這支
  /// function 時整排都不畫。
  bool _canReply(MoodleForumPost p) =>
      MoodleForumUtils.canReply(p) && MoodleWebApiConnector.canPostToForum;

  /// 伺服器組好的「回覆: …」，語系跟著站台；沒有就退回討論串標題。
  String _replySubject(MoodleForumPost parent) =>
      parent.replysubject.isNotEmpty ? parent.replysubject : widget.title;

  Future<void> _compose(MoodleForumPost parent) async {
    final added = await Get.to<MoodleForumPost>(
      () => CourseForumComposePage.reply(
        parent: parent,
        subject: _replySubject(parent),
        onSendReply: (text) => _controller.reply(
          postId: parent.id,
          subject: _replySubject(parent),
          text: text,
        ),
        dirName: widget.courseInfo.main.course.name,
        openWebView: widget.openWebView,
        webUrl: _discussionUrl(),
        webTitle: widget.title,
      ),
    );
    if (added == null || !mounted) return;
    await _controller.appendPost(added);
    TaskUiDelegate.instance.toast(R.current.forumSendDone);
    // 重抓是為了拿伺服器排好的順序與新的 capabilities；失敗時 controller 會
    // 退回 Stale，剛送出的那一則留在畫面上——寫入確實成功了，不可以變成錯誤頁。
    // `keepVisible`：這一趟途中畫面維持原狀，不要先閃成一頁轉圈。
    await _controller.loadPosts(keepVisible: true);
    if (_controller.posts.value is Stale<List<MoodleForumPost>>) {
      TaskUiDelegate.instance.toast(R.current.forumSendDoneRefreshFailed);
    }
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
      title: widget.title,
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
