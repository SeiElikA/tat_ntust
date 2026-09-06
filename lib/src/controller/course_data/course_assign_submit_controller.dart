import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart'
    show AssignStartOutcome;
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/moodle_assign_attempt_utils.dart';
import 'package:flutter_app/src/util/moodle_assign_submit_utils.dart';
import 'package:get/get.dart';

/// 繳交編輯頁的狀態。普通類別而不是 GetxController：生命週期就是那一個頁面，
/// 同 CourseAssignmentController。
class CourseAssignSubmitController {
  CourseAssignSubmitController({
    required this.assignment,
    required this.status,
  }) {
    final sub = status.submissionFor(assignment);
    _serverFiles = sub?.files ?? const [];
    _serverOnlineText = sub?.onlineText ?? '';
    _serverDrafts = [
      for (final f in _serverFiles)
        OnlineDraftFile(f.filename, f.fileurl,
            mimetype: f.mimetype, filesize: f.filesize),
    ];
    files.assignAll(_serverDrafts);
    onlineText.value = MoodleAssignSubmitUtils.htmlToPlain(_serverOnlineText);
  }

  final MoodleAssignment assignment;

  /// 進頁時的那一份。只有它決定草稿的初值——重抓回來的那一份不可以拿去
  /// 重新 seed，使用者可能已經在打字了。
  final MoodleAssignSubmissionStatus status;

  /// 「開始作答」寫入之後重抓回來的那一份。`start_submission` 只會寫
  /// `timestarted`，繳交內容不動，所以只換這一個參考、不重 seed。
  final Rxn<MoodleAssignSubmissionStatus> refreshed =
      Rxn<MoodleAssignSubmissionStatus>();

  /// 現在該拿來算倒數與狀態的那一份。
  MoodleAssignSubmissionStatus get currentStatus => refreshed.value ?? status;

  late final List<MoodleAssignFile> _serverFiles;
  late final String _serverOnlineText;
  late final List<OnlineDraftFile> _serverDrafts;

  /// 伺服器上已經交了的檔案，給畫面比對用。
  List<MoodleAssignFile> get serverFiles => _serverFiles;

  /// 伺服器上那幾份的草稿列，照伺服器的順序，**被標記移除的也還在裡面**。
  /// 畫面要照這一份畫，不是照 [files]：`files_filemanager` 是同步不是附加，
  /// 從清單裡消失就等於儲存時會被 Moodle 刪掉，那件事不可以只用一下無聲的
  /// 消失來表示。
  List<OnlineDraftFile> get serverDrafts => _serverDrafts;

  /// 這一次儲存會從 Moodle 上刪掉幾個已經交出去的檔案。
  int get pendingServerRemovals =>
      filesChanged ? _serverDrafts.where((f) => !files.contains(f)).length : 0;

  /// 把伺服器上的那一份標記成「儲存後移除」。那一列不會消失，只是換一個樣子，
  /// 而且刪除要等到真的按下儲存才發生。
  void removeServerFile(OnlineDraftFile file) => files.remove(file);

  /// 取消移除。一定要插回原來的位置：[MoodleAssignSubmitUtils.fileListChanged]
  /// 是逐格比對的，接在最後面會讓「什麼都沒動」被算成有變更，白白重傳整份清單。
  void restoreServerFile(OnlineDraftFile file) {
    if (files.contains(file)) return;
    final target = _serverDrafts.indexOf(file);
    if (target < 0) return;
    var at = 0;
    for (var i = 0; i < target; i++) {
      if (files.contains(_serverDrafts[i])) at++;
    }
    files.insert(at, file);
  }

  /// 初值＝伺服器上的那一份。
  final RxList<AssignDraftFile> files = <AssignDraftFile>[].obs;

  /// 初值＝現有線上文字還原成的純文字。
  final RxString onlineText = ''.obs;

  final RxBool accepted = false.obs;

  /// 有沒有一趟寫入正在跑。跟 [progress] 分開：只改線上文字時沒有任何檔案
  /// 可以量，那時候要畫不定量的進度條，而不是一條停在 0% 的實心條。
  final RxBool busy = false.obs;

  /// 有沒有一趟「開始作答」正在跑。跟 [busy] 分開：它不是傳輸，動作列畫的
  /// 還是同一顆鈕，只是不能再按第二下——第二下會拿到 opensubmissionexists。
  final RxBool starting = false.obs;

  /// 「開始作答」那一趟寫入回報的事實。**沒有任何狀態欄位講得出這兩件事**：
  /// 站台關掉 `enabletimelimit` 時 `timelimit` 照樣是原值，重抓失敗時
  /// `timestarted` 照樣是 0，兩者看起來都跟「還沒開始」一模一樣，而動作列在
  /// 那個狀態下只畫得出「開始作答」——沒有這一顆，儲存鈕永遠出不來。
  final Rxn<AssignStartFact> startFact = Rxn<AssignStartFact>();

  /// 0..1；量不出來時是 null。
  final Rxn<double> progress = Rxn<double>();

  /// 正在處理的那個檔名；沒有在傳檔案時是 null。
  final RxnString transferFile = RxnString();

  /// [transferFile] 現在在哪一段。
  final Rx<AssignTransferPhase> transferPhase = AssignTransferPhase.upload.obs;

  bool get isBusy => busy.value;

  CancelToken? _cancelToken;

  /// 這一趟之後的結果，頁面用它把新狀態帶回上一頁。被伺服器拒絕時也會有值：
  /// `save_submission` 不是原子的，那時候的狀態才是唯一的真相。
  MoodleAssignSubmitResult? lastResult;

  bool get fileSubmissionEnabled => MoodleAssignSubmitUtils.pluginEnabled(
      assignment, MoodleAssignSubmitUtils.pluginFile);

  bool get onlineTextEnabled => MoodleAssignSubmitUtils.pluginEnabled(
      assignment, MoodleAssignSubmitUtils.pluginOnlineText);

  /// 現有的線上文字含有圖片或排版時不給在 App 內編輯，覆蓋會弄壞內嵌檔案。
  bool get onlineTextEditable => onlineTextEnabled && !onlineTextIsRich;

  /// 這份作業開了線上文字，而現有內容不是純文字。
  ///
  /// 這時候**整頁都不能存**，不是只有文字框不給編：`assign_submission_onlinetext`
  /// 的 `save()` 沒有 isset 把關，只送 `files_filemanager` 不會保留現有文字，
  /// 反而會被空值覆蓋；而現有內容含內嵌檔案時也不能原封送回去
  /// （`getSubmissionStatus` 帶了 `moodlewssettingfileurl`，`@@PLUGINFILE@@`
  /// 已經被換成絕對網址）。所以只剩導網頁一條路。
  bool get onlineTextIsRich =>
      onlineTextEnabled &&
      !MoodleAssignSubmitUtils.onlineTextIsPlain(_serverOnlineText);

  bool get filesChanged =>
      fileSubmissionEnabled &&
      MoodleAssignSubmitUtils.fileListChanged(files, _serverFiles);

  /// 伺服器上原本有檔案卻被清空。`files_filemanager` 是同步不是附加，送一個
  /// 空的 draft 區等於把繳交檔案全部刪掉；v1 不做這件事，要刪請到網頁。
  bool get filesEmptied =>
      fileSubmissionEnabled && _serverFiles.isNotEmpty && files.isEmpty;

  bool get textChanged =>
      onlineTextEditable &&
      onlineText.value !=
          MoodleAssignSubmitUtils.htmlToPlain(_serverOnlineText);

  /// `wordlimitenabled` 為假時是 0。
  int get wordLimit => MoodleAssignSubmitUtils.wordLimit(assignment);

  int get wordCount => MoodleAssignSubmitUtils.countWords(onlineText.value);

  /// 伺服器的 `check_word_count` 失敗只回一句 `couldnotsavesubmission`，連
  /// 「是字數超過」都說不出來，而那時候檔案那半可能已經寫進去了。
  bool get overWordLimit =>
      onlineTextEditable && wordLimit > 0 && wordCount > wordLimit;

  /// 沒開草稿又要求同意聲明時，伺服器不會擋，只能由 App 自己要求勾選。
  bool get statementRequired =>
      assignment.requiresStatement &&
      (assignment.submissionstatement ?? '').trim().isNotEmpty;

  bool get _statementOk =>
      !(statementRequired && !assignment.tracksDrafts) || accepted.value;

  /// 儲存鈕為什麼不能按；null = 可以存。**作答時限到期不在裡面**：伺服器
  /// 照收只標記遲交，本地擋下來就是把寫好的東西鎖死在畫面上。
  AssignSaveBlock? get saveBlock => MoodleAssignSubmitUtils.saveBlockOf(
        onlineTextIsRich: onlineTextIsRich,
        filesEmptied: filesEmptied,
        overWordLimit: overWordLimit,
        statementOk: _statementOk,
        dirty: filesChanged || textChanged,
      );

  /// [isBusy] 刻意不是 [AssignSaveBlock] 的一員：忙碌時動作列畫的是傳輸列
  /// 而不是這顆鈕，那個理由字串永遠不會被畫出來。
  bool get canSave => !isBusy && saveBlock == null;

  /// 開始一次有時限的作答。回 null 代表已經有一趟在跑；否則 error 為 null
  /// 才是成功。不開對話框也不 toast：controller -> ui 是上行邊。
  Future<({String? error})?> startTimedAttempt() async {
    if (starting.value) return null;
    starting.value = true;
    try {
      final result = await MoodleRepository.instance
          .startAssignAttempt(assignment: assignment);
      final data = result.dataOrNull;
      final fresh = data?.status;
      if (fresh != null) refreshed.value = fresh;
      final outcome = data?.outcome;
      if (outcome != null) startFact.value = _factOf(outcome);
      return switch (result) {
        Ok() || Stale() => (error: null),
        Failed(:final reason) => (error: reason.message),
      };
    } finally {
      starting.value = false;
    }
  }

  static AssignStartFact? _factOf(AssignStartOutcome outcome) =>
      switch (outcome) {
        AssignStartOutcome.noTimeLimit => AssignStartFact.noTimeLimit,
        AssignStartOutcome.started ||
        AssignStartOutcome.alreadyRunning =>
          AssignStartFact.started,
        // notOpen 走的是 Failed，這裡拿不到它。
        AssignStartOutcome.notOpen => null,
      };

  /// 送出一次繳交。不開對話框、不 toast：controller → ui 是上行邊，確認框與
  /// 提示由頁面負責。
  Future<AssignSaveOutcome> save({required bool submitForGrading}) async {
    // 回「成功」是不行的：畫面會 toast「作業已繳交」再帶著空的 lastResult
    // 收工。canSave 與 AbsorbPointer 都是下一幀才生效，擋不住同一幀的第二下。
    if (isBusy) return const AssignSaveOutcome(acted: false);
    final token = CancelToken();
    _cancelToken = token;
    busy.value = true;
    progress.value = null;
    try {
      final result = await MoodleRepository.instance.saveAssignSubmission(
        assignment: assignment,
        status: currentStatus,
        draft: AssignSubmissionDraft(
          // 線上文字外掛只要開著就一定要送：伺服器端的 save() 沒有 isset
          // 把關，不送等於用空值覆蓋掉學生現有的文字。沒動過就把伺服器自己
          // 那一份原樣送回去——重組會弄丟粗體之類的標記。
          onlineText: onlineTextEnabled
              ? (textChanged
                  ? MoodleAssignSubmitUtils.plainToHtml(onlineText.value)
                  : _serverOnlineText)
              : null,
          files: filesChanged ? List<AssignDraftFile>.of(files) : null,
          submitForGrading: submitForGrading,
          acceptStatement: accepted.value,
        ),
        onProgress: (p) {
          progress.value = p.overall;
          transferFile.value = p.filename;
          transferPhase.value = p.phase;
        },
        cancelToken: token,
      );
      switch (result) {
        case Ok(:final data):
        case Stale(:final data):
          lastResult = data;
          return AssignSaveOutcome(acted: true, error: data.error);
        case Failed(:final reason):
          // 使用者自己按的取消不是「繳交失敗」。
          return AssignSaveOutcome(
            acted: true,
            error: token.isCancelled
                ? R.current.assignSubmitCancelled
                : reason.message,
          );
      }
    } finally {
      busy.value = false;
      progress.value = null;
      transferFile.value = null;
      _cancelToken = null;
    }
  }

  /// 取消進行中的傳輸。只擋得住下載與上傳那幾趟——`save_submission` 一旦送出
  /// 就沒有回頭路，中止連線只會讓我們不知道伺服器到底存了沒有。
  void cancel() {
    _cancelToken?.cancel('cancelled by user');
  }

  void dispose() {
    cancel();
    files.close();
    onlineText.close();
    transferFile.close();
    transferPhase.close();
    accepted.close();
    refreshed.close();
    starting.close();
    startFact.close();
    busy.close();
    progress.close();
  }
}

/// [CourseAssignSubmitController.save] 的結果。「忙碌」與「成功」必須分得開：
/// 兩者共用一個 null 就會把「什麼都沒做」報成「已繳交」。
class AssignSaveOutcome {
  const AssignSaveOutcome({required this.acted, this.error});

  /// false = 已經有一趟在跑，這一次連請求都沒發。
  final bool acted;

  /// null = 完全成功；否則是要 toast 的那一句。
  final String? error;
}
