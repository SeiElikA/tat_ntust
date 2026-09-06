import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/html/moodle_html_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:sprintf/sprintf.dart';

/// 撰寫頁：回覆一篇貼文，或在一個討論區開新主題。
///
/// 送出的動作由呼叫端注入（[onSendReply] / [onSendDiscussion]），這一頁因此
/// 不碰 repository，也不需要 `route_utils`（見 docs/ARCHITECTURE.md「UI 慣例」）。
///
/// 成功時 `Get.back` 帶回結果（回覆是新貼文、新主題是 discussion id），
/// **失敗一律留在原地**：草稿不能因為送出失敗就消失，畫面也不可以看起來像
/// 已經送出去了。
class CourseForumComposePage extends StatefulWidget {
  /// 回覆一篇貼文。[parent] 只用來顯示「你正在回覆誰」。
  const CourseForumComposePage.reply({
    super.key,
    required MoodleForumPost this.parent,
    required this.subject,
    required Future<Result<MoodleForumPost>> Function(String text)
        this.onSendReply,
    required this.dirName,
    required this.openWebView,
    required this.webUrl,
    required this.webTitle,
  })  : onSendDiscussion = null,
        forumName = "";

  /// 在討論區開新主題。標題由使用者自己填。
  const CourseForumComposePage.newDiscussion({
    super.key,
    required this.forumName,
    required Future<Result<int>> Function(String subject, String text)
        this.onSendDiscussion,
    required this.dirName,
    required this.openWebView,
    required this.webUrl,
    required this.webTitle,
  })  : parent = null,
        subject = "",
        onSendReply = null;

  /// 回覆的目標貼文；新主題時是 null。
  final MoodleForumPost? parent;

  /// 回覆要送出去的標題，由伺服器算好（`replysubject`）。
  final String subject;

  final String forumName;

  final Future<Result<MoodleForumPost>> Function(String text)? onSendReply;
  final Future<Result<int>> Function(String subject, String text)?
      onSendDiscussion;

  /// 引用卡裡的圖片與連結要用的下載目錄名（課程名）。
  final String dirName;

  final WebViewOpener openWebView;

  /// 「在網頁開啟」的目標；附件、排版與編輯都導到那裡。
  final String webUrl;
  final String webTitle;

  bool get isReply => onSendReply != null;

  @override
  State<CourseForumComposePage> createState() => _CourseForumComposePageState();
}

class _CourseForumComposePageState extends State<CourseForumComposePage> {
  /// 草稿活在 State 裡：轉螢幕、鍵盤開合、放棄對話框、App 切到背景都留得住，
  /// process 被殺掉才會消失。落地需要一把新的 store key，而那把 key 要進
  /// SessionCleaner，漏了就是跨帳號外洩——為了兩句話的回覆不划算。
  final _messageController = TextEditingController();
  final _subjectController = TextEditingController();

  /// 送出中。擋住連點兩下送出兩則——這一支沒有冪等鍵。
  bool _sending = false;

  /// 標題計數器從這個長度開始出現，平常不掛一個 `0/255` 在那裡。
  static const int _subjectCounterFrom = 200;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onTextChanged);
    _subjectController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _hasDraft =>
      _messageController.text.trim().isNotEmpty ||
      _subjectController.text.trim().isNotEmpty;

  bool get _canSend {
    if (_sending) return false;
    if (_messageController.text.trim().isEmpty) return false;
    if (!widget.isReply && _subjectController.text.trim().isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 送出中一律擋住：那一則已經在路上了，這時離開會讓下面的 `Get.back`
      // pop 到別人的頁面，而且伺服器收下的那一則不會有人併回畫面。
      canPop: !_hasDraft && !_sending,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_sending) {
          TaskUiDelegate.instance.toast(R.current.forumSending);
          return;
        }
        unawaited(_confirmDiscard());
      },
      child: Scaffold(
        appBar: baseAppbar(
          title: widget.isReply
              ? R.current.forumReply
              : R.current.forumNewDiscussion,
          // maybePop 才會經過上面那個 PopScope；直接 pop 會繞過放棄草稿的確認。
          onBack: () => Navigator.maybePop(context),
          action: [
            TextButton.icon(
              onPressed: _canSend ? () => unawaited(_send()) : null,
              // 這一頁沒有進度遮罩（寫入路徑不帶 progressMessage），送出中只有
              // 這顆轉圈；少了它整頁看起來就是按不動而已。顏色要自己指定：
              // onPressed 是 null 時前景色是停用灰，轉圈會幾乎看不見。
              icon: _sending
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 16),
              label: Text(R.current.forumSend),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            if (widget.isReply)
              ..._quote(widget.parent!)
            else
              ..._subjectField(),
            SectionHeader(
              icon: LucideIcons.pencil,
              title: widget.isReply
                  ? R.current.forumReply
                  : R.current.forumNewDiscussion,
              first: !widget.isReply,
            ),
            SectionCard([_messageField()]),
            const SizedBox(height: 16),
            _footer(),
          ],
        ),
      ),
    );
  }

  /// 送出前先讓使用者看見「回覆給誰、回覆哪一篇」。
  List<Widget> _quote(MoodleForumPost parent) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final author = parent.author?.fullname ?? "";
    return [
      SectionHeader(
        icon: LucideIcons.reply,
        title: sprintf(R.current.forumReplyingTo,
            [author.isNotEmpty ? author : R.current.forumUnknownAuthor]),
        first: true,
        trailing: Text(
          _time(parent),
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      SectionCard([
        if (widget.subject.isNotEmpty) SectionSubLabel(widget.subject),
        // 引用只是脈絡，太長會把輸入框擠出畫面。
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: SingleChildScrollView(child: _quoteBody(parent)),
        ),
      ]),
    ];
  }

  Widget _quoteBody(MoodleForumPost parent) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (parent.message.trim().isEmpty) {
      return Text(R.current.nothingHere,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant));
    }
    return MoodleHtmlView(
      html: parent.message,
      title: widget.webTitle,
      dirName: widget.dirName,
      openWebView: widget.openWebView,
    );
  }

  List<Widget> _subjectField() => [
        SectionHeader(
          icon: LucideIcons.messageSquarePlus,
          title: widget.forumName.isNotEmpty
              ? widget.forumName
              : R.current.forumNewDiscussion,
          first: true,
        ),
        SectionCard([
          TextField(
            controller: _subjectController,
            enabled: !_sending,
            // 伺服器的 `name` / `subject` 都是 varchar(255)，超過會是
            // dmlwriteexception——畫面上只會看到一句通用的送出失敗，使用者
            // 永遠猜不到是標題太長。enforcement 用平台預設：中文輸入法組字
            // 中途截斷會把字吃掉，組完再截才對。
            maxLength: MoodleForumUtils.subjectMaxLength,
            buildCounter: _subjectCounter,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              labelText: R.current.forumSubject,
              hintText: R.current.forumSubjectHint,
              // 說明「送出」為什麼是灰的，不要讓人對著停用的鈕猜。
              helperText: _subjectController.text.trim().isEmpty
                  ? R.current.forumSubjectRequired
                  : null,
            ),
          ),
        ]),
      ];

  /// 只有快撞到上限時才出現：平常掛一個 `0/255` 只是雜訊。
  Widget? _subjectCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) =>
      currentLength < _subjectCounterFrom
          ? null
          : Text('$currentLength/$maxLength',
              style: Theme.of(context).textTheme.bodySmall);

  Widget _messageField() => TextField(
        controller: _messageController,
        enabled: !_sending,
        autofocus: true,
        maxLines: null,
        minLines: 6,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: R.current.forumMessageHint,
          helperText: _messageController.text.trim().isEmpty
              ? R.current.forumMessageRequired
              : null,
        ),
      );

  /// 附件、排版、私訊回覆、編輯與群組選擇全部從這裡導出去，而且把理由寫出來。
  Widget _footer() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          R.current.forumPlainTextOnly,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () =>
              unawaited(widget.openWebView(widget.webTitle, widget.webUrl)),
          icon: const Icon(LucideIcons.externalLink, size: 16),
          label: Text(R.current.forumOpenInWeb),
        ),
      ],
    );
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() => _sending = true);
    final message = _messageController.text.trim();
    final subject = _subjectController.text.trim();
    try {
      final Result<Object> result = widget.isReply
          ? await widget.onSendReply!(message)
          : await widget.onSendDiscussion!(subject, message);
      switch (result) {
        case Ok(:final data):
          // 只 pop 自己。`Get.back` 會 pop 最上面那一個，而不是「這一頁」，
          // 一旦這一頁已經不在最上面就會把別人的頁面關掉。
          if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
            Get.back(result: data);
          }
        // 送出失敗（含 Stale——寫入路徑本來就沒有快取可退）：留在原地、
        // 文字原封不動，只吐一句已經對應好的訊息。
        case Stale(:final reason):
        case Failed(:final reason):
          TaskUiDelegate.instance.toast(reason.message);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await Get.dialog<bool>(
      AlertDialog.adaptive(
        content: Text(R.current.forumDiscardDraft),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: Text(R.current.cancel),
          ),
          TextButton(
            onPressed: () => Get.back<bool>(result: true),
            child: Text(R.current.sure),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    Get.back();
  }

  String _time(MoodleForumPost p) {
    final unix = p.timecreated ?? p.timemodified ?? 0;
    return unix > 0
        ? DateFormat.yMd()
            .add_jm()
            .format(DateTime.fromMillisecondsSinceEpoch(unix * 1000))
        : "";
  }
}
