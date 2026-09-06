import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
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
    files.assignAll([
      for (final f in _serverFiles)
        OnlineDraftFile(f.filename, f.fileurl,
            mimetype: f.mimetype, filesize: f.filesize),
    ]);
    onlineText.value = MoodleAssignSubmitUtils.htmlToPlain(_serverOnlineText);
  }

  final MoodleAssignment assignment;
  final MoodleAssignSubmissionStatus status;

  late final List<MoodleAssignFile> _serverFiles;
  late final String _serverOnlineText;

  /// 伺服器上已經交了的檔案，給畫面比對用。
  List<MoodleAssignFile> get serverFiles => _serverFiles;

  /// 初值＝伺服器上的那一份。
  final RxList<AssignDraftFile> files = <AssignDraftFile>[].obs;

  /// 初值＝現有線上文字還原成的純文字。
  final RxString onlineText = ''.obs;

  final RxBool accepted = false.obs;

  /// 有沒有一趟寫入正在跑。跟 [progress] 分開：只改線上文字時沒有任何檔案
  /// 可以量，那時候要畫不定量的進度條，而不是一條停在 0% 的實心條。
  final RxBool busy = false.obs;

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

  /// 沒有任何變更就不給按：那一趟必定被伺服器判成 submissionempty。
  bool get canSave =>
      !isBusy &&
      (filesChanged || textChanged) &&
      _statementOk &&
      !filesEmptied &&
      !onlineTextIsRich &&
      !overWordLimit;

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
        status: status,
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
