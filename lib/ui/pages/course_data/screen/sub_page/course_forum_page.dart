import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/controller/course_data/course_forum_controller.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_can_add_discussion.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/language_utils.dart';
import 'package:flutter_app/src/util/moodle_forum_edit_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/empty_state.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_compose_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/forum_attach_picker.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/forum_bottom_bar.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_thread_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/forum_discussion_card.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// 一個討論區的主題清單。錯誤畫面與 WebView 開啟器由呼叫端注入，
/// 見 docs/ARCHITECTURE.md「UI 慣例」。
class CourseForumPage extends StatefulWidget {
  const CourseForumPage(
    this.courseInfo, {
    required this.forumId,
    required this.forumName,
    required this.forumUrl,
    required this.errorBuilder,
    required this.openWebView,
    super.key,
  });

  final CourseInfoJson courseInfo;

  /// forum instance id（`Modules.instance`），三支 ws function 要的都是它。
  final int forumId;

  final String forumName;

  /// 課程目錄那一列自己帶的網址，用來「在網頁開啟」。
  final String forumUrl;

  final Widget Function(String message) errorBuilder;
  final WebViewOpener openWebView;

  @override
  State<StatefulWidget> createState() => _CourseForumPageState();
}

class _CourseForumPageState extends State<CourseForumPage> {
  late final CourseForumController _controller;

  /// 撰寫頁的上傳可以取消，token 由這一頁持有（那一頁不碰 dio）。
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _controller = CourseForumController(
      forumId: widget.forumId,
      courseId: widget.courseInfo.main.course.id,
    );
    unawaited(_controller.loadAll());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: baseAppbar(
        title: widget.forumName,
        action: [
          IconButton(
            tooltip: R.current.forumOpenInWeb,
            icon: const Icon(LucideIcons.externalLink, size: 18),
            onPressed: () =>
                unawaited(widget.openWebView(widget.forumName, _forumUrl())),
          ),
        ],
      ),
      body: ResultView<List<Discussions>>(
        state: _controller.discussions,
        onRetry: _controller.loadAll,
        errorBuilder: widget.errorBuilder,
        builder: _list,
      ),
      // 不能發文的說明釘在底部，不是清單的最後一項：五十則主題不必捲到底
      // 才知道自己不能發文。
      bottomNavigationBar: _postingFooter(),
      floatingActionButton: Obx(() => _canAddDiscussion
          ? FloatingActionButton(
              onPressed: () => unawaited(_compose()),
              tooltip: R.current.forumNewDiscussion,
              child: const Icon(LucideIcons.messageSquarePlus),
            )
          : const SizedBox.shrink()),
    );
  }

  /// 課程目錄那一列帶的網址加上語系。不呼叫 `autologinUrl`：注入的
  /// [CourseForumPage.openWebView] 自己會換。
  String _forumUrl() => Connector.uriAddQuery(
        widget.forumUrl,
        {"lang": LanguageUtils.getLangIndex() == LangEnum.zh ? "zh_tw" : "en"},
      );

  /// 樂觀但不說謊：伺服器說可以才給鈕，還在問（null）時不給。它不含發文
  /// 節流，所以真的被拒時由送出那一步的訊息負責說明（forumErrorTooManyPosts）。
  bool get _canAddDiscussion =>
      _controller.canAdd.value?.dataOrNull?.status == true &&
      MoodleWebApiConnector.canCreateDiscussion;

  /// 站台沒開 `mod_forum_add_discussion`。**這一種才真的是「App 內不行」**：
  /// 網頁版那顆「新增討論主題」還在，所以那條列給得起一個真的出口。
  bool get _postingUnsupportedByApp =>
      !MoodleWebApiConnector.canCreateDiscussion;

  /// 伺服器自己回了 `status == false`。網頁版問的是同一個
  /// `forum_user_can_post_discussion`，所以那裡一樣不給——這一種**不可以**
  /// 掛「在網頁開啟」，也不可以說成是 App 的限制。
  bool get _postingRefusedByServer {
    // 先讀 observable 再判斷：短路掉這一行的話外層的 Obx 就沒有東西可以追蹤，
    // GetX 會直接丟「improper use of a GetX」。
    final answer = _controller.canAdd.value;
    return answer is Ok<MoodleCanAddDiscussion> && !answer.data.status;
  }

  /// 這一問失敗了。沒有快取所以只會是 [Failed]，而它一輩子只發過一次——
  /// 不補一個重試，使用者只能離開頁面再進來。
  bool get _postingUnknown =>
      _controller.canAdd.value is Failed<MoodleCanAddDiscussion>;

  /// 包 [Obx] 才會跟著 `canAdd` 更新：清單與這一問是平行發的，清單先回來時
  /// 答案通常還沒到。
  Widget _postingFooter() => Obx(() {
        final refusedByServer = _postingRefusedByServer;
        if (_postingUnsupportedByApp) {
          return ForumNoticeBar(
            message: R.current.forumCannotPost,
            onOpenWeb: _openInWeb,
          );
        }
        if (refusedByServer) {
          return ForumNoticeBar(message: R.current.forumCannotPostHere);
        }
        // 問不到不等於不行，所以不說「不開放發文」，但也不能什麼都不說：
        // 少了 FAB 又沒有半句話，看起來就是 App 壞了。
        if (_postingUnknown) {
          return ForumNoticeBar(
            message: R.current.forumCannotCheckPosting,
            onOpenWeb: _openInWeb,
            onRetry: () => unawaited(_controller.loadCanAddDiscussion()),
          );
        }
        return const SizedBox.shrink();
      });

  void _openInWeb() =>
      unawaited(widget.openWebView(widget.forumName, _forumUrl()));

  Widget _list(List<Discussions> discussions) {
    if (discussions.isEmpty) {
      return EmptyState(
          icon: LucideIcons.messagesSquare, message: R.current.forumEmpty);
    }
    final formatter = DateFormat.yMd().add_jm();
    return Obx(() => ListView.separated(
          // 有 FAB 時留出它的高度，沒有就不留一塊空白。
          padding: _canAddDiscussion
              ? const EdgeInsets.fromLTRB(12, 12, 12, 88)
              : const EdgeInsets.fromLTRB(12, 12, 12, 12),
          itemCount: discussions.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final d = discussions[index];
            return ForumDiscussionCard(
              discussion: d,
              formatter: formatter,
              onTap: () => unawaited(_openThread(d)),
            );
          },
        ));
  }

  /// 主文被刪掉、或第一篇被編輯過時清單那一列就過期了（標題、迴紋針、
  /// 回覆數），討論串頁會回頭喊一聲，這裡負責重抓。
  void _refreshDiscussions() {
    if (!mounted) return;
    unawaited(_controller.loadDiscussions(keepVisible: true));
  }

  Future<void> _openThread(Discussions d) async {
    await Get.to<void>(() => CourseForumThreadPage(
          widget.courseInfo,
          // discussion 才是討論串 id；id 是第一篇貼文的 id。
          discussionId: d.discussion,
          title: d.name,
          forumId: widget.forumId,
          fallbackDiscussion: d,
          onDiscussionChanged: _refreshDiscussions,
          openWebView: widget.openWebView,
        ));
  }

  Future<void> _compose() async {
    final outcome = await Get.to<ForumDiscussionOutcome>(
      () => CourseForumComposePage.newDiscussion(
        forumName: widget.forumName,
        // 每一次送出都是一把新的 token。`??=` 會把使用者取消過的那一把一直
        // 遞回去，而 dio 對已取消的 token 是在送出之前就直接丟——重試永遠
        // 不可能成功，人就困在一頁按不動的撰寫器上。
        onSendDiscussion: (subject, text, files, {required onProgress}) async {
          final token = CancelToken();
          _cancelToken = token;
          try {
            return await _controller.postDiscussion(
              subject: subject,
              text: text,
              attachments: files,
              onProgress: onProgress,
              cancelToken: token,
            );
          } finally {
            _cancelToken = null;
          }
        },
        attachPolicy: _controller.policy,
        onPickFiles: _pickFiles,
        onCancelUpload: () => _cancelToken?.cancel(),
        openWebView: widget.openWebView,
        webUrl: _forumUrl(),
        webTitle: widget.forumName,
      ),
    );
    if (outcome == null || !mounted) return;
    TaskUiDelegate.instance.toast(R.current.forumSendDone);
    final warning = outcome.warning;
    if (warning != null) TaskUiDelegate.instance.toast(warning);
    // 清單還沒有這一則（伺服器只回了 id，沒有回主題本體），所以直接進討論串，
    // 順手重抓清單；`fallbackDiscussion` 是 null——手上沒有那一列。
    unawaited(_controller.loadDiscussions(keepVisible: true));
    await Get.to<void>(() => CourseForumThreadPage(
          widget.courseInfo,
          discussionId: outcome.discussionId,
          // 剛打的標題，不是討論區名字：後者只是使用者上一頁看到的那一行。
          title:
              outcome.subject.isNotEmpty ? outcome.subject : widget.forumName,
          forumId: widget.forumId,
          onDiscussionChanged: _refreshDiscussions,
          openWebView: widget.openWebView,
        ));
  }

  Future<List<File>> _pickFiles(int remaining) =>
      pickForumAttachments(context, remaining: remaining);
}
