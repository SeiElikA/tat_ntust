import 'dart:async';

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
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/empty_state.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_compose_page.dart';
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

  @override
  void initState() {
    super.initState();
    _controller = CourseForumController(forumId: widget.forumId);
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

  /// 只有拿到明確的「不行」才說不行：伺服器答了 status == false，或站台根本
  /// 沒開放這支 function。還在問時什麼都不說，問失敗交給 [_postingUnknown]
  /// ——問不到不等於不行，那句話會是假的。
  bool get _postingRefused {
    // 先讀 observable 再判斷：短路掉這一行的話外層的 Obx 就沒有東西可以追蹤，
    // GetX 會直接丟「improper use of a GetX」。
    final answer = _controller.canAdd.value;
    if (!MoodleWebApiConnector.canCreateDiscussion) return true;
    return answer is Ok<MoodleCanAddDiscussion> && !answer.data.status;
  }

  /// 這一問失敗了。沒有快取所以只會是 [Failed]，而它一輩子只發過一次——
  /// 不補一個重試，使用者只能離開頁面再進來。
  bool get _postingUnknown =>
      _controller.canAdd.value is Failed<MoodleCanAddDiscussion>;

  /// 包 [Obx] 才會跟著 `canAdd` 更新：清單與這一問是平行發的，清單先回來時
  /// 答案通常還沒到。
  Widget _postingFooter() => Obx(() {
        if (_postingRefused) return _footer(R.current.forumCannotPost);
        // 問不到不等於不行，所以不說「不開放發文」，但也不能什麼都不說：
        // 少了 FAB 又沒有半句話，看起來就是 App 壞了。
        if (_postingUnknown) {
          return _footer(R.current.forumCannotCheckPosting,
              onRetry: () => unawaited(_controller.loadCanAddDiscussion()));
        }
        return const SizedBox.shrink();
      });

  Widget _list(List<Discussions> discussions) {
    if (discussions.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: EmptyState(
                icon: LucideIcons.messagesSquare,
                message: R.current.forumEmpty),
          ),
          _postingFooter(),
        ],
      );
    }
    final formatter = DateFormat.yMd().add_jm();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      itemCount: discussions.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == discussions.length) return _postingFooter();
        final d = discussions[index];
        return ForumDiscussionCard(
          discussion: d,
          formatter: formatter,
          onTap: () => unawaited(Get.to(() => CourseForumThreadPage(
                widget.courseInfo,
                // discussion 才是討論串 id；id 是第一篇貼文的 id。
                discussionId: d.discussion,
                title: d.name,
                fallbackDiscussion: d,
                openWebView: widget.openWebView,
              ))),
        );
      },
    );
  }

  /// 沒有發文入口時說一句為什麼，並把網頁入口留著——沉默會讓人以為是
  /// App 壞了。[onRetry] 只有「問不到」那一種狀態才給。
  Widget _footer(String message, {VoidCallback? onRetry}) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Wrap(
            children: [
              TextButton.icon(
                onPressed: () => unawaited(
                    widget.openWebView(widget.forumName, _forumUrl())),
                icon: const Icon(LucideIcons.externalLink, size: 16),
                label: Text(R.current.forumOpenInWeb),
              ),
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: Text(R.current.refresh),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _compose() async {
    final discussionId = await Get.to<int>(
      () => CourseForumComposePage.newDiscussion(
        forumName: widget.forumName,
        onSendDiscussion: (subject, text) =>
            _controller.postDiscussion(subject: subject, text: text),
        dirName: widget.courseInfo.main.course.name,
        openWebView: widget.openWebView,
        webUrl: _forumUrl(),
        webTitle: widget.forumName,
      ),
    );
    if (discussionId == null || !mounted) return;
    TaskUiDelegate.instance.toast(R.current.forumSendDone);
    // 清單還沒有這一則（伺服器只回了 id，沒有回主題本體），所以直接進討論串，
    // 順手重抓清單；`fallbackDiscussion` 是 null——手上沒有那一列。
    unawaited(_controller.loadDiscussions(keepVisible: true));
    await Get.to(() => CourseForumThreadPage(
          widget.courseInfo,
          discussionId: discussionId,
          title: widget.forumName,
          openWebView: widget.openWebView,
        ));
  }
}
