import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/controller/course_data/course_assign_submit_controller.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/service/file_pick_service.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/file_utils.dart';
import 'package:flutter_app/src/util/language_utils.dart';
import 'package:flutter_app/src/util/moodle_assign_submit_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/html/moodle_html_view.dart';
import 'package:flutter_app/ui/components/page/section_empty_state.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

/// 交作業的編輯頁：檔案清單、線上文字、繳交聲明。
///
/// 沒有 `errorBuilder`：這一頁不做 `ResultView`，作業與狀態都是值傳進來的。
/// WebView 開啟器由呼叫端注入，見 docs/ARCHITECTURE.md「UI 慣例」。
class CourseAssignSubmitPage extends StatefulWidget {
  const CourseAssignSubmitPage({
    super.key,
    required this.assignment,
    required this.status,
    required this.courseName,
    required this.openWebView,
  });

  final MoodleAssignment assignment;
  final MoodleAssignSubmissionStatus status;
  final String courseName;
  final WebViewOpener openWebView;

  @override
  State<CourseAssignSubmitPage> createState() => _CourseAssignSubmitPageState();
}

class _CourseAssignSubmitPageState extends State<CourseAssignSubmitPage> {
  late final CourseAssignSubmitController _controller;
  late final TextEditingController _textController;

  MoodleAssignment get _assignment => widget.assignment;

  @override
  void initState() {
    super.initState();
    _controller = CourseAssignSubmitController(
      assignment: widget.assignment,
      status: widget.status,
    );
    _textController = TextEditingController(text: _controller.onlineText.value);
    _textController
        .addListener(() => _controller.onlineText.value = _textController.text);
  }

  @override
  void dispose() {
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  int get _maxFiles => MoodleAssignSubmitUtils.maxFiles(_assignment);

  int get _maxBytes => MoodleAssignSubmitUtils.maxBytes(_assignment);

  List<String> get _fileTypes => MoodleAssignSubmitUtils.fileTypes(_assignment);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final busy = _controller.isBusy;
      return PopScope(
        canPop: !busy && !_hasUnsavedChanges,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          unawaited(_handleBack());
        },
        child: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            // baseAppbar 的返回鍵走 Get.back()＝Navigator.pop，會繞過 PopScope，
            // 所以這一頁自己接管，否則寫入到一半也按得掉。
            child: baseAppbar(
              title: _assignment.name,
              onBack: () => unawaited(_handleBack()),
            ),
          ),
          // 進度列刻意留在 AbsorbPointer 外面：校園網路上傳一個大檔可能很久，
          // 使用者至少要按得到「取消」。
          body: Column(
            children: [
              if (busy) _progressBar(),
              Expanded(
                child: AbsorbPointer(absorbing: busy, child: _buildList()),
              ),
            ],
          ),
        ),
      );
    });
  }

  bool get _hasUnsavedChanges =>
      _controller.filesChanged || _controller.textChanged;

  Widget _progressBar() {
    final name = _controller.transferFile.value;
    return Column(
      children: [
        // progress 是 null 就畫不定量的：只改線上文字時沒有東西可以量，
        // 一條停在 0% 的實心條看起來就是當掉了。
        LinearProgressIndicator(value: _controller.progress.value),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name == null
                      ? R.current.assignSubmit
                      : sprintf(
                          _controller.transferPhase.value ==
                                  AssignTransferPhase.download
                              ? R.current.assignPreparingFile
                              : R.current.assignUploadingFile,
                          [name]),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _controller.cancel,
                child: Text(R.current.cancel),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        if (_controller.fileSubmissionEnabled) ...[
          SectionHeader(
            icon: LucideIcons.paperclip,
            title: R.current.assignAttachmentSection,
            first: true,
          ),
          _filesCard(),
        ],
        if (_controller.onlineTextEnabled) ...[
          SectionHeader(
            icon: LucideIcons.fileText,
            title: R.current.assignOnlineText,
            first: !_controller.fileSubmissionEnabled,
          ),
          _onlineTextCard(),
        ],
        if (_controller.statementRequired && !_assignment.tracksDrafts) ...[
          SectionHeader(
            icon: LucideIcons.shieldCheck,
            title: R.current.assignSubmissionStatement,
          ),
          _statementCard(),
        ],
        const SizedBox(height: 28),
        // 鈕是 disabled 卻不說原因等於讓人卡在那裡。
        if (_controller.onlineTextIsRich) _blockedHint(),
        Obx(() => FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed:
                  _controller.canSave ? () => unawaited(_onSave()) : null,
              child: Text(_assignment.tracksDrafts
                  ? R.current.assignSaveDraft
                  : R.current.assignSubmit),
            )),
      ],
    );
  }

  /// 線上文字是舊的富文字時整頁都不能存：只送 files_filemanager 不會保留它，
  /// 伺服器端的 onlinetext save() 沒有 isset 把關。
  Widget _blockedHint() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        R.current.assignSubmitBlockedByOnlineText,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _filesCard() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Obx(() {
      final files = _controller.files;
      final hints = <String>[
        sprintf(R.current.assignFileLimit, [_maxFiles.toString()]),
        if (_maxBytes > 0)
          sprintf(R.current.assignFileSizeLimit,
              [FileUtils.formatBytes(_maxBytes, 1)]),
        if (_fileTypes.isNotEmpty)
          sprintf(R.current.assignFileTypes, [_fileTypes.join(', ')]),
      ];
      return SectionCard([
        if (files.isEmpty)
          SectionEmptyState(
            icon: LucideIcons.paperclip,
            message: R.current.assignFilesEmpty,
          )
        else
          for (final f in files)
            MoodleFileTile(
              filename: f.filename,
              mimetype: f is OnlineDraftFile ? f.mimetype : '',
              trailing: IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                tooltip: R.current.assignRemoveFile,
                onPressed: () => _controller.files.remove(f),
              ),
              // 剛挑的本機檔案沒有網址可以開，就讓那一列不吃點擊——空的
              // callback 只會給一個什麼都不做的漣漪。
              onTap: f is OnlineDraftFile ? () => _openFile(f) : null,
            ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed:
              files.length >= _maxFiles ? null : () => unawaited(_pickFiles()),
          icon: const Icon(LucideIcons.paperclip, size: 18),
          label: Text(R.current.assignAddFiles),
        ),
        const SizedBox(height: 8),
        // 清空之後那顆儲存鈕會是 disabled，不說原因等於讓人卡在那裡。
        if (_controller.filesEmptied)
          Text(R.current.assignFilesEmptiedWebOnly,
              style: text.bodySmall?.copyWith(color: scheme.error)),
        for (final hint in hints)
          Text(hint,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ]);
    });
  }

  Widget _onlineTextCard() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (!_controller.onlineTextEditable) {
      // 覆蓋含內嵌檔案的線上文字會留下孤兒檔案、圖片連結失效，所以導網頁。
      return SectionCard([
        Text(R.current.assignOnlineTextNotEditable,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => unawaited(_openInWeb()),
          icon: const Icon(LucideIcons.externalLink, size: 18),
          label: Text(R.current.assignOpenInWeb),
        ),
      ]);
    }
    final wordLimit = _controller.wordLimit;
    return SectionCard([
      TextField(
        controller: _textController,
        maxLines: null,
        minLines: 6,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: R.current.assignOnlineTextHint,
        ),
      ),
      const SizedBox(height: 8),
      if (wordLimit <= 0)
        Text(R.current.assignOnlineTextHint,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
      else
        // 字數要即時算：超過上限時伺服器會拒掉整趟 save_submission，而那時
        // 檔案那半可能已經寫進去了，事後才知道太晚。
        Obx(() {
          final over = _controller.overWordLimit;
          return Text(
            '${sprintf(R.current.assignWordCount, [
                  _controller.wordCount.toString(),
                  wordLimit.toString()
                ])}${over ? ' · ${R.current.assignWordCountExceeded}' : ''}',
            style: text.bodySmall?.copyWith(
                color: over ? scheme.error : scheme.onSurfaceVariant),
          );
        }),
    ]);
  }

  /// 已經交上去的那一份可以點開來確認；本機剛挑的沒有網址。
  Future<void> _openFile(OnlineDraftFile file) => FileDownload.download(
        context,
        MoodleWebApiConnector.fileUrlWithToken(file.fileurl),
        widget.courseName,
        name: file.filename,
      );

  Widget _statementCard() {
    return SectionCard([
      MoodleHtmlView(
        html: _assignment.submissionstatement ?? '',
        title: _assignment.name,
        dirName: widget.courseName,
        openWebView: widget.openWebView,
      ),
      Obx(() => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _controller.accepted.value,
            onChanged: (v) => _controller.accepted.value = v ?? false,
            title: Text(R.current.assignAcceptStatement),
          )),
    ]);
  }

  /// 挑檔案。`FileType.custom` 只吃副檔名，所以只有整份清單都判讀得出來時才
  /// 交給挑選器過濾，否則挑回來自己擋。
  Future<void> _pickFiles() async {
    final remaining = _maxFiles - _controller.files.length;
    if (remaining <= 0) return;
    final types = _fileTypes;
    final extensions = types.isNotEmpty && _allExtensions(types)
        ? [for (final t in types) t.startsWith('.') ? t.substring(1) : t]
        : const <String>[];

    final List<File> picked;
    try {
      picked = await FilePickService.instance
          .pick(limit: remaining, extensions: extensions);
    } on FilePickFailure catch (e) {
      TaskUiDelegate.instance.toast(switch (e.reason) {
        FilePickFailureReason.denied => R.current.assignFilePickerDenied,
        FilePickFailureReason.unavailable =>
          R.current.assignFilePickerUnavailable,
      });
      return;
    }
    if (picked.isEmpty) return;

    for (final file in picked) {
      final name = _basename(file.path);
      if (MoodleAssignSubmitUtils.checkFileType(name, types) ==
          FileTypeCheck.rejected) {
        TaskUiDelegate.instance
            .toast(sprintf(R.current.assignFileTypeRejected, [name]));
        continue;
      }
      final bytes = await file.length();
      if (MoodleAssignSubmitUtils.exceedsSize(bytes, _maxBytes)) {
        TaskUiDelegate.instance.toast(sprintf(R.current.assignFileTooLarge,
            [name, FileUtils.formatBytes(_maxBytes, 1)]));
        continue;
      }
      final next = [
        ..._controller.files,
        LocalDraftFile(file, name, size: bytes)
      ];
      if (MoodleAssignSubmitUtils.duplicateFilename(next) != null) {
        TaskUiDelegate.instance.toast(R.current.assignFileDuplicateName);
        continue;
      }
      if (_controller.files.length >= _maxFiles) {
        TaskUiDelegate.instance.toast(
            sprintf(R.current.assignFileCountExceeded, [_maxFiles.toString()]));
        break;
      }
      _controller.files.add(LocalDraftFile(file, name, size: bytes));
    }
  }

  static bool _allExtensions(List<String> types) {
    for (final t in types) {
      if (MoodleAssignSubmitUtils.checkFileType('probe.$t', types) ==
          FileTypeCheck.unverifiable) {
        return false;
      }
      if (t.contains('/')) return false;
    }
    return true;
  }

  static String _basename(String path) {
    final index = path.lastIndexOf(RegExp(r'[/\\]'));
    return index < 0 ? path : path.substring(index + 1);
  }

  Future<void> _onSave() async {
    // 對話框會讓出好幾幀，回來時可能已經有一趟在跑了。
    if (_controller.isBusy) return;
    // 沒有草稿階段的作業「存檔」就是繳交，文案不可以騙人，所以先確認一次。
    if (!_assignment.tracksDrafts) {
      final already = widget.status.submissionFor(_assignment);
      final extra = (already != null && already.isSubmitted)
          ? '\n\n${R.current.assignSubmitAgainWarning}'
          : '';
      final confirmed = await _confirm(R.current.assignSubmit,
          '${R.current.assignSubmitDirectConfirm}$extra');
      if (confirmed != true) return;
    }

    // 這一頁只負責存檔：沒有草稿階段的作業 save_submission 就是繳交，有草稿
    // 階段的則由詳情頁那顆「送出評分」接手。
    final outcome = await _controller.save(submitForGrading: false);
    // 這一次連請求都沒發（已經有一趟在跑），不可以報成功。
    if (!outcome.acted) return;

    final result = _controller.lastResult;
    final error = outcome.error;
    if (error != null) {
      TaskUiDelegate.instance.toast(error);
      if (!mounted) return;
      // 有 result 就代表 save_submission 已經送出去了。它不是原子的：一個
      // 外掛成功、另一個失敗也只回一則 warning，所以要把重抓回來的狀態帶回
      // 上一頁，畫面不可以繼續拿寫入前的清單當基準。
      if (result != null) Get.back(result: result);
      return;
    }
    TaskUiDelegate.instance.toast(_assignment.tracksDrafts
        ? R.current.assignDraftSaved
        : R.current.assignSubmittedToast);
    if (!mounted) return;
    Get.back(result: result);
  }

  /// 返回鍵與系統手勢共用的出口。
  Future<void> _handleBack() async {
    // 寫入進行中不給走：CancelToken 到不了 save_submission，離開只會讓這一趟
    // 的結果沒有人接，上一頁停在寫入前的狀態。要停請按進度列那顆「取消」。
    if (_controller.isBusy) return;
    if (!_hasUnsavedChanges) {
      Get.back();
      return;
    }
    await _confirmDiscard();
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await Get.dialog<bool>(AlertDialog.adaptive(
      content: Text(R.current.assignDiscardChanges),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: Text(R.current.cancel),
        ),
        TextButton(
          onPressed: () => Get.back(result: true),
          child: Text(R.current.sure),
        ),
      ],
    ));
    // 問完才開始寫入的話，這裡放行等於中途離場。
    if (confirmed == true && !_controller.isBusy) Get.back();
  }

  Future<bool?> _confirm(String title, String content) => Get.dialog<bool>(
        AlertDialog.adaptive(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text(R.current.cancel),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: Text(R.current.sure),
            ),
          ],
        ),
      );

  Future<void> _openInWeb() async {
    final url = Connector.uriAddQuery(
      MoodleWebApiConnector.assignViewUrl(_assignment.cmid),
      {"lang": LanguageUtils.getLangIndex() == LangEnum.zh ? "zh_tw" : "en"},
    );
    await widget.openWebView(_assignment.name, url);
  }
}
