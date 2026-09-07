import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/moodle_assign_utils.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/status_pill.dart';
import 'package:intl/intl.dart';
import 'package:sprintf/sprintf.dart';

/// Unix 秒 → 畫面上的日期時間。作業詳情頁、繳交頁的表頭與清單共用同一種
/// 格式，放在這裡是因為頁面之間不互相 import（見 docs/ARCHITECTURE.md）。
String assignFormatUnix(int unix) => DateFormat.yMd()
    .add_jm()
    .format(DateTime.fromMillisecondsSinceEpoch(unix * 1000));

/// [DueHint] 對映成畫面文字。住在 UI 層是因為要 R.current；
/// 作業分頁與詳情頁共用。
String dueHintText(DueHint hint) => switch (hint.kind) {
      DueHintKind.noDueDate => R.current.assignNoDueDate,
      DueHintKind.dueInDays => sprintf(R.current.assignDueInDays, [hint.count]),
      DueHintKind.dueInHours =>
        sprintf(R.current.assignDueInHours, [hint.count]),
      DueHintKind.dueSoon => R.current.assignDueSoon,
      DueHintKind.overdueDays =>
        sprintf(R.current.assignOverdueDays, [hint.count]),
      DueHintKind.overdueHours =>
        sprintf(R.current.assignOverdueHours, [hint.count]),
      DueHintKind.overdueJustNow => R.current.assignOverdueJustNow,
    };

/// 作業的狀態籤，作業分頁與詳情頁共用；外觀走共用的 [StatusPill]，
/// 刻意不 import 任何頁面。
class AssignStatusChip extends StatelessWidget {
  const AssignStatusChip(this.status, {super.key, this.stale = false});

  final AssignDisplayStatus status;

  /// 資料來自快取（[Stale]）時多畫一個時鐘小圖示。
  final bool stale;

  /// null 還在抓畫轉圈；[Failed] 不知道狀態就什麼都不畫（背景抓的，不彈框）。
  static Widget fromResult(
    MoodleAssignment a,
    Result<MoodleAssignSubmissionStatus>? r, {
    required DateTime now,
  }) {
    if (r == null) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final data = r.dataOrNull;
    if (data == null) return const SizedBox.shrink();
    return AssignStatusChip(
      MoodleAssignUtils.resolveStatus(a, data, now: now),
      stale: r is Stale,
    );
  }

  static String labelOf(AssignDisplayStatus status) => switch (status) {
        AssignDisplayStatus.notSubmitted => R.current.assignStatusNotSubmitted,
        AssignDisplayStatus.draft => R.current.assignStatusDraft,
        AssignDisplayStatus.submitted => R.current.assignStatusSubmitted,
        AssignDisplayStatus.graded => R.current.assignStatusGraded,
        AssignDisplayStatus.overdue => R.current.assignStatusOverdue,
        AssignDisplayStatus.reopened => R.current.assignStatusReopened,
        AssignDisplayStatus.noSubmissionRequired =>
          R.current.assignStatusNoSubmissionRequired,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      AssignDisplayStatus.notSubmitted ||
      AssignDisplayStatus.noSubmissionRequired =>
        (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      // 重新開放跟草稿同一組顏色：兩者都是「還沒交出去，但已經動起來了」。
      AssignDisplayStatus.draft || AssignDisplayStatus.reopened => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
      AssignDisplayStatus.submitted => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      AssignDisplayStatus.graded => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
      AssignDisplayStatus.overdue => (
          scheme.errorContainer,
          scheme.onErrorContainer
        ),
    };
    return StatusPill(
      background: bg,
      foreground: fg,
      stale: stale,
      label: labelOf(status),
    );
  }
}
