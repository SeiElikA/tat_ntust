import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/file_utils.dart';
import 'package:flutter_app/src/util/moodle_forum_edit_utils.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/editor/moodle_rich_editor.dart';
import 'package:flutter_app/ui/components/editor/moodle_rich_editor_toolbar.dart';
import 'package:flutter_app/ui/components/page/inline_error_view.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

/// 排版與內嵌圖片都留得住的貼文編輯頁。
///
/// **這一頁刻意沒有「去網頁編輯」。** 它存在的理由就是把那條死路換掉；留一顆
/// 網頁鈕等於承認 App 這一半沒做完。編輯器載不起來時走 [InlineErrorView]，
/// 重試也是重新載入這一頁的編輯器，不是丟給瀏覽器。
///
/// 送出、挑檔、取消一律由呼叫端注入，所以這一頁不碰 repository，也不 import
/// `route_utils` / `error_page` / `base_page`（見 docs/ARCHITECTURE.md）。
/// 成功時 `Get.back` 帶回 [ForumEditOutcome]，**失敗一律留在原地**。
class CourseForumRichEditPage extends StatefulWidget {
  const CourseForumRichEditPage({
    super.key,
    required this.postId,
    required this.isTopicPost,
    required this.initialSubject,
    required this.initialHtml,
    required this.existingAttachments,
    required this.onSend,
    required this.attachPolicy,
    required this.onPickFiles,
    required this.onCancelUpload,
    required this.onOpenAttachment,
  });

  final int postId;

  /// 只有主題的第一篇才給改標題——編輯第一篇會連帶更新
  /// `forum_discussions.name`。
  final bool isTopicPost;

  final String initialSubject;

  /// 已經換成「載得動」的網址的貼文 HTML：`@@PLUGINFILE@@` 展開過，內嵌圖片
  /// 的網址帶著憑證。這一頁不做那件事，也不知道它發生過。
  final String initialHtml;

  final List<MoodleForumFile> existingAttachments;

  final Future<Result<ForumEditOutcome>> Function(
    String subject,
    String html,
    List<MoodleForumFile> keep,
    List<File> added, {
    required void Function(ForumTransferProgress progress) onProgress,
  }) onSend;

  final ForumAttachPolicy attachPolicy;
  final Future<List<File>> Function(int remaining) onPickFiles;
  final VoidCallback onCancelUpload;
  final Future<void> Function(MoodleForumFile file) onOpenAttachment;

  /// 卡與卡之間的間距。
  static const double _gap = 8;

  /// 空間排得下的時候，附件再多也不可以把編輯面壓到這個高度以下。
  static const double _editorMinHeight = 220;

  /// 附件最多佔編輯區的三分之一。
  static const double _attachMaxFraction = 0.34;

  /// 「標題＋一列檔案」大約要這麼高。連這樣都排不下就只留標題那一列。
  static const double _attachListMinHeight = 96;

  /// 附件卡在 [room]（編輯面與附件共用的高度）裡拿得到的上限與形態。
  ///
  /// 刻意是純算式：WebView 在 flutter_test 底下畫不出來，而「編輯面會不會被
  /// 壓成一條縫」的理由全部在這幾行裡。**上限不設地板**——56 之類的地板會反過來
  /// 蓋掉 [_editorMinHeight] 保留下來的高度。
  @visibleForTesting
  static ({double cap, bool dense}) attachSlot(
    double room, {
    required bool keyboard,
  }) {
    final free = room - _gap;
    final reserve =
        math.min(free * _attachMaxFraction, free - _editorMinHeight);
    // 打字時附件只留「附件 2/3」那一列；空間不夠列清單時也一樣，收起來的高度
    // 還給編輯面，而不是讓兩邊都不能用。
    final dense = keyboard || reserve < _attachListMinHeight;
    return (cap: dense ? free / 2 : reserve, dense: dense);
  }

  @override
  State<CourseForumRichEditPage> createState() =>
      _CourseForumRichEditPageState();
}

class _CourseForumRichEditPageState extends State<CourseForumRichEditPage> {
  final _editor = MoodleRichEditorController();
  late final TextEditingController _subjectController;

  /// 使用者決定留下的既有附件。
  late final List<MoodleForumFile> _kept;
  final _files = <File>[];

  /// 游標處生效的格式，由橋接回報。
  Set<String> _active = const {};

  bool _sourceMode = false;
  bool _ready = false;
  bool _failed = false;

  /// 使用者真的動過內容（editor.js 的 `input` 訊號），不是只移動游標。
  bool _edited = false;

  bool _sending = false;
  bool _uploading = false;
  double? _progress;
  String? _transferFile;

  /// 重試時換一把 key，讓 WebView 整個重建而不是沿用壞掉的那一個。
  int _editorGeneration = 0;

  static const int _subjectCounterFrom = 200;

  static const double _gap = CourseForumRichEditPage._gap;

  bool get _busy => _sending || _uploading;

  bool get _showSubject => widget.isTopicPost;

  int get _total => _files.length + _kept.length;

  bool get _hasDraft =>
      _edited ||
      _files.isNotEmpty ||
      _subjectController.text != widget.initialSubject ||
      _kept.length != widget.existingAttachments.length;

  bool get _canSend =>
      _ready &&
      !_failed &&
      !_busy &&
      (!_showSubject || _subjectController.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _subjectController = TextEditingController(text: widget.initialSubject);
    _kept = [...widget.existingAttachments];
    _subjectController.addListener(_onSubjectChanged);
  }

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  void _onSubjectChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // 鍵盤高度只有 Scaffold 外面讀得到：`resizeToAvoidBottomInset` 為真時
    // body 那一層的 viewInsets 已經被扣成 0 了。
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      // 送出中一律擋住：那一則已經在路上了。
      canPop: !_hasDraft && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_busy) {
          TaskUiDelegate.instance.toast(R.current.forumSending);
          return;
        }
        unawaited(_confirmDiscard());
      },
      child: Scaffold(
        appBar: baseAppbar(
          title: R.current.forumEditRichTitle,
          onBack: () => Navigator.maybePop(context),
        ),
        body: Column(
          children: [
            _statusSlot(),
            Expanded(
              child: AbsorbPointer(absorbing: _busy, child: _body(compact)),
            ),
          ],
        ),
        bottomNavigationBar: _sendBar(),
      ),
    );
  }

  /// 與撰寫頁同一套：固定 2px 的槽，上傳有值、送出不定量。
  Widget _statusSlot() {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 2,
      child: Align(
        alignment: Alignment.topCenter,
        child: _uploading
            ? LinearProgressIndicator(value: _progress, minHeight: 2)
            : _sending
                ? const LinearProgressIndicator(minHeight: 2)
                : Container(height: 1, color: scheme.outlineVariant),
      ),
    );
  }

  Widget _body(bool compact) {
    if (_failed) {
      return InlineErrorView(
        message: R.current.forumEditorLoadFailed,
        onRetry: () async => setState(() {
          _failed = false;
          _ready = false;
          _editorGeneration++;
        }),
      );
    }
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showSubject) ...[
            SectionCard([_subjectField(text, compact)]),
            const SizedBox(height: _gap),
          ],
          MoodleRichEditorToolbar(
            active: _active,
            sourceMode: _sourceMode,
            enabled: _ready && !_busy,
            onCommand: _editor.exec,
            onToggleSource: _toggleSource,
          ),
          const SizedBox(height: _gap),
          // 編輯面與附件在這一層裡分高度。主旨卡與工具列已經在外面吃掉自己的
          // 那一份，所以量的是**這裡**剩下多少，不是整個 body 有多高——量錯基準
          // 的話 _editorMinHeight 留下來的其實是別人的高度。
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final slot = CourseForumRichEditPage.attachSlot(box.maxHeight,
                  keyboard: compact);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _editorSlot()),
                  // 連卡片自己的 padding 都容不下時整張讓開：擠進去只會是一條
                  // 撐破版面的縫。
                  if (_total > 0 && slot.cap >= SectionCard.padding.vertical)
                    Padding(
                      padding: const EdgeInsets.only(top: _gap),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: slot.cap),
                        child: _attachments(slot.dense),
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _subjectField(TextTheme text, bool compact) => TextField(
        controller: _subjectController,
        enabled: !_busy,
        // 伺服器的 subject 是 varchar(255)，超過是 dmlwriteexception，
        // 畫面上只會看到一句通用的送出失敗。
        maxLength: MoodleForumUtils.subjectMaxLength,
        buildCounter: _subjectCounter,
        textInputAction: TextInputAction.next,
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          // 鍵盤升起＝正在寫內文，浮動標籤那一行的高度讓給編輯面；欄位是空的
          // 時候 hintText 照樣說得清楚。
          labelText: compact ? null : R.current.forumSubject,
          hintText: R.current.forumSubjectHint,
        ),
      );

  /// 編輯面就是第三張卡：同樣的圓角、同樣的底色，內容捲到頂端時被圓角切掉，
  /// 而不是滑到工具列後面去。
  Widget _editorSlot() {
    final fill = SectionCard.fill(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(SectionCard.radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SectionCard.radius),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MoodleRichEditor(
              key: ValueKey('rich-editor-${widget.postId}-$_editorGeneration'),
              controller: _editor,
              initialHtml: widget.initialHtml,
              onStateChanged: (active) {
                if (mounted) setState(() => _active = active);
              },
              onChanged: () {
                if (mounted && !_edited) setState(() => _edited = true);
              },
              onReady: () {
                if (mounted) setState(() => _ready = true);
              },
              onLoadFailed: () {
                if (mounted) setState(() => _failed = true);
              },
            ),
            if (!_ready)
              ColoredBox(
                color: fill,
                child: Center(
                  // 字級開到最大、機身又小的時候，編輯面本身就矮過這一組字：
                  // 捲得動總比把版面撐破好。
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(R.current.forumEditorLoading,
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 標題跟著清單一起捲：卡片被壓得比內容矮時，捲動是唯一不會把 Column
  /// 撐破的收法。[dense] 時只留「附件 2/3」那一列。
  Widget _attachments(bool dense) => SectionCard([
        Flexible(
          child: ListView(
            shrinkWrap: true,
            primary: false,
            padding: EdgeInsets.zero,
            children: [
              SectionSubLabel('${R.current.forumAttachments} $_total/'
                  '${widget.attachPolicy.maxFiles}'),
              if (!dense) ...[
                for (final f in _kept)
                  MoodleFileTile(
                    filename: f.filename,
                    onTap: () => unawaited(widget.onOpenAttachment(f)),
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      tooltip: R.current.forumRemoveAttachment,
                      onPressed:
                          _busy ? null : () => setState(() => _kept.remove(f)),
                    ),
                  ),
                for (final f in _files)
                  MoodleFileTile(
                    filename: MoodleForumEditUtils.basename(f.path),
                    onTap: null,
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      tooltip: R.current.forumRemoveAttachment,
                      onPressed:
                          _busy ? null : () => setState(() => _files.remove(f)),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ]);

  /// 只有快撞到上限時才出現。
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

  Widget _sendBar() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reason = _blockReason;
    return SafeArea(
      top: false,
      child: Material(
        color: scheme.surfaceContainer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 1, color: scheme.outlineVariant),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Icon(LucideIcons.info,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(reason,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    // 上傳可以取消（討論區上什麼都還沒動）；送出不行。
                    if (_uploading)
                      TextButton(
                        onPressed: widget.onCancelUpload,
                        child: Text(R.current.cancel),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  if (widget.attachPolicy.enabled)
                    IconButton(
                      tooltip: R.current.forumAddAttachment,
                      icon: const Icon(LucideIcons.paperclip, size: 20),
                      onPressed:
                          (_busy || _total >= widget.attachPolicy.maxFiles)
                              ? null
                              : () => unawaited(_pick()),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(96, 48)),
                    onPressed: _canSend ? () => unawaited(_send()) : null,
                    icon: _sending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : const Icon(LucideIcons.send, size: 18),
                    label: Text(_sending
                        ? R.current.forumSending
                        : R.current.forumSaveEdit),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底列上唯一的「為什麼現在存不了」。優先序由上而下。
  String? get _blockReason {
    if (_sending) return R.current.forumSending;
    if (_uploading) {
      final name = _transferFile;
      return name == null
          ? R.current.forumSending
          : sprintf(R.current.assignUploadingFile, [name]);
    }
    if (_failed) return R.current.forumEditorLoadFailed;
    if (!_ready) return R.current.forumEditorLoading;
    if (_showSubject && _subjectController.text.trim().isEmpty) {
      return R.current.forumSubjectRequired;
    }
    return null;
  }

  void _toggleSource() {
    final next = !_sourceMode;
    _editor.setSourceMode(next);
    setState(() {
      _sourceMode = next;
      _active = const {};
    });
  }

  Future<void> _pick() async {
    final policy = widget.attachPolicy;
    final remaining = policy.maxFiles - _total;
    if (remaining <= 0) return;
    final picked = await widget.onPickFiles(remaining);
    if (picked.isEmpty || !mounted) return;
    for (final file in picked) {
      final name = MoodleForumEditUtils.basename(file.path);
      final bytes = await file.length();
      if (!mounted) return;
      if (MoodleForumEditUtils.exceedsSize(bytes, policy.maxBytes)) {
        TaskUiDelegate.instance.toast(sprintf(R.current.forumAttachmentTooLarge,
            [name, FileUtils.formatBytes(policy.maxBytes, 1)]));
        continue;
      }
      // 既有附件會被 prepare_draft_area_for_post 種進 draft 區，同名的新檔案
      // 會回 filenameexist，而那時 draft 區已經是半套的。
      if (MoodleForumEditUtils.duplicateFilename([
            for (final f in _kept) f.filename,
            for (final f in _files) MoodleForumEditUtils.basename(f.path),
            name,
          ]) !=
          null) {
        TaskUiDelegate.instance.toast(R.current.forumAttachmentDuplicateName);
        continue;
      }
      if (_total >= policy.maxFiles) {
        TaskUiDelegate.instance.toast(sprintf(
            R.current.forumAttachmentCountExceeded,
            [policy.maxFiles.toString()]));
        break;
      }
      setState(() => _files.add(file));
    }
  }

  void _onProgress(ForumTransferProgress progress) {
    if (!mounted) return;
    setState(() {
      _uploading = progress.phase == ForumTransferPhase.upload;
      _sending = progress.phase == ForumTransferPhase.posting;
      _progress = progress.overall;
      _transferFile = progress.filename;
    });
  }

  Future<void> _send() async {
    if (!_canSend) return;
    // 拿不到內容時**絕對不能**當成空字串送出去：伺服器對空 message 是
    // 「不改」然後回 status: true，使用者會看到「已更新」而其實什麼都沒發生。
    final html = await _editor.content();
    if (!mounted) return;
    if (html == null) {
      TaskUiDelegate.instance.toast(R.current.forumEditorLoadFailed);
      return;
    }
    setState(() {
      _sending = _files.isEmpty;
      _uploading = _files.isNotEmpty;
      _progress = null;
      _transferFile = null;
    });
    try {
      final result = await widget.onSend(
          _subjectController.text.trim(), html, _kept, _files,
          onProgress: _onProgress);
      switch (result) {
        case Ok(:final data):
          // 只 pop 自己：這一頁一旦不在最上面，`Get.back` 會關掉別人的頁面。
          if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
            Get.back(result: data);
          }
        // 失敗（含 Stale——寫入路徑本來就沒有快取可退）：留在原地，
        // 編輯器裡的內容一個字都不動。
        case Stale(:final reason):
        case Failed(:final reason):
          TaskUiDelegate.instance.toast(reason.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploading = false;
          _progress = null;
          _transferFile = null;
        });
      }
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
}
