import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/moodle_assign_utils.dart';
import 'package:sprintf/sprintf.dart';

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

/// 作業的狀態籤，作業分頁與詳情頁共用；刻意不 import 任何頁面。
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
      AssignDisplayStatus.draft => (
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stale) ...[
            Icon(Icons.history, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(labelOf(status), style: TextStyle(fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}
