import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_calendar_action_events.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/src/util/upcoming_event_utils.dart';
import 'package:flutter_app/ui/components/page/inline_error_view.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/other/svg_tint.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

/// 行事曆頁底部的「待辦」區塊：所有課程的截止事項，分成逾期／今天／本週／之後。
/// 不可 import error_page / route_utils，見 docs/ARCHITECTURE.md「UI 慣例」。
class UpcomingEventsSection extends StatelessWidget {
  const UpcomingEventsSection({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onOpen,
    this.clock = DateTime.now,
  });

  /// null 代表載入中。
  final Rx<Result<List<MoodleActionEvent>>?> state;

  final Future<void> Function() onRetry;

  final Future<void> Function(MoodleActionEvent event) onOpen;

  /// 「現在」。測試注入固定的時間，分組才可預期。
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            R.current.upcomingEvents,
            style:
                TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
        ),
        ResultView<List<MoodleActionEvent>>(
          shrinkWrap: true,
          state: state,
          onRetry: onRetry,
          errorBuilder: (message) =>
              InlineErrorView(message: message, onRetry: onRetry),
          builder: (events) => _buildGroups(context, events),
        ),
      ],
    );
  }

  Widget _buildGroups(BuildContext context, List<MoodleActionEvent> events) {
    // 分組在 build 時依注入的時鐘重算，Stale 的舊快取也會落在正確的組。
    final groups = UpcomingEventUtils.groupByDeadline(events, clock());
    if (groups.isEmpty) return const _Empty();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final group in groups) _buildGroup(context, group)],
    );
  }

  Widget _buildGroup(BuildContext context, DeadlineGroup group) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = group.bucket == DeadlineBucket.overdue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 12, bottom: 6),
          child: Text(
            _labelOf(group.bucket),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: overdue ? scheme.error : scheme.onSurfaceVariant,
                ),
          ),
        ),
        for (var i = 0; i < group.events.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          _buildTile(
            context,
            group.events[i],
            index: i,
            length: group.events.length,
            overdue: overdue,
          ),
        ],
      ],
    );
  }

  String _labelOf(DeadlineBucket bucket) => switch (bucket) {
        DeadlineBucket.overdue => R.current.deadlineOverdue,
        DeadlineBucket.today => R.current.deadlineToday,
        DeadlineBucket.thisWeek => R.current.deadlineThisWeek,
        DeadlineBucket.later => R.current.deadlineLater,
      };

  Widget _buildTile(
    BuildContext context,
    MoodleActionEvent event, {
    required int index,
    required int length,
    required bool overdue,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bodySmall = Theme.of(context).textTheme.bodySmall;
    final subtitle = _subtitleOf(event);
    return InkWell(
      onTap: () => onOpen(event),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: UIUtils.getBorderRadius(index, length),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          children: [
            Icon(_iconFor(event.modulename),
                size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurface, fontSize: 15),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              UpcomingEventUtils.formatDueTime(event.dueTime, clock()),
              key: ValueKey('due-${event.id}'),
              style: bodySmall?.copyWith(
                color: overdue ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: overdue ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「課名 · 該做的事」。站台事件沒有課名；action.name 只在現在做得到時顯示。
  static String? _subtitleOf(MoodleActionEvent event) {
    final action = event.action;
    final parts = [
      UpcomingEventUtils.courseLabelOf(event),
      if (action != null && action.actionable) action.name,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static IconData _iconFor(String? modulename) => switch (modulename) {
        'assign' => Icons.assignment_outlined,
        'quiz' => Icons.quiz_outlined,
        'forum' => Icons.forum_outlined,
        'lesson' || 'scorm' => Icons.menu_book_outlined,
        'choice' || 'feedback' || 'survey' => Icons.poll_outlined,
        _ => Icons.event_note_outlined,
      };
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/image/img_calendar.svg',
              colorFilter: svgTint(scheme.onSurface),
              height: 56,
            ),
            const SizedBox(height: 16),
            Text(
              R.current.upcomingEventsEmpty,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
