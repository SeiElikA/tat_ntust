import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:get/get.dart';

/// 作業詳情頁的狀態：作業本體與繳交狀態；由頁面的 State 建立與 [dispose]。
class CourseAssignmentController {
  CourseAssignmentController({
    required this.courseId,
    required this.assignId,
    MoodleAssignment? assignment,
    Result<MoodleAssignSubmissionStatus>? status,
  })  : assignment = Rxn(assignment == null ? null : Ok(assignment)),
        // Failed 的 seed 要重抓：清單是背景抓的，這次是使用者主動要看。
        status = Rxn((status?.hasData ?? false) ? status : null);

  final String courseId;
  final int assignId;

  final Rxn<Result<MoodleAssignment>> assignment;
  final Rxn<Result<MoodleAssignSubmissionStatus>> status;

  /// 有沒有一趟送出評分正在跑。`submitAssignForGrading` 沒有進度框，少了這顆
  /// 旗標按第二下就會再發一趟，而伺服器對第二趟一律回 couldnotsubmitforgrading
  /// ——把成功的那一次報成失敗。
  final RxBool submitting = false.obs;

  Future<void> loadAll() => Future.wait([
        if (assignment.value == null) loadAssignment(),
        if (status.value == null) loadStatus(),
      ]);

  Future<void> loadAssignment() async {
    assignment.value = null;
    assignment.value =
        await MoodleRepository.instance.getAssignment(courseId, assignId);
  }

  Future<void> loadStatus() async {
    status.value = null;
    status.value =
        await MoodleRepository.instance.getSubmissionStatus(assignId);
  }

  /// 繳交寫入之後把伺服器回的新狀態直接套上。不重抓：repository 已經抓過了。
  void applyStatus(MoodleAssignSubmissionStatus fresh) =>
      status.value = Ok(fresh);

  /// 把已經存好的草稿送出評分。回 null 代表已經有一趟在跑，這一次什麼都沒做；
  /// 否則 `error` 為 null 才是成功，`fresh` 是伺服器回的新狀態（已經套進
  /// [status]），呼叫端拿它往上帶。不開對話框也不 toast：controller -> ui
  /// 是上行邊。
  Future<({String? error, MoodleAssignSubmissionStatus? fresh})?>
      submitForGrading({required bool acceptStatement}) async {
    if (submitting.value) return null;
    final a = assignment.value?.dataOrNull;
    final s = status.value?.dataOrNull;
    if (a == null || s == null) {
      return (error: R.current.assignSubmitForGradingRejected, fresh: null);
    }
    submitting.value = true;
    try {
      final result = await MoodleRepository.instance.submitAssignForGrading(
        assignment: a,
        status: s,
        acceptStatement: acceptStatement,
      );
      final data = result.dataOrNull;
      final fresh = data?.status;
      if (fresh != null) applyStatus(fresh);
      return switch (result) {
        // 被拒絕時 repository 回的是帶著 error 的 Ok：Failed 帶不了重抓回來的
        // 狀態，而那個狀態才說得清楚伺服器上到底變成什麼樣子。
        Ok() || Stale() => (error: data?.error, fresh: fresh),
        Failed(:final reason) => (error: reason.message, fresh: fresh),
      };
    } finally {
      submitting.value = false;
    }
  }

  void dispose() {
    assignment.close();
    status.close();
    submitting.close();
  }
}
