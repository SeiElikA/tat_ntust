import 'package:flutter_app/src/model/moodle_webapi/moodle_core_calendar_action_events.dart';
import 'package:flutter_app/src/util/moodle_course_name_utils.dart';

/// 待辦清單的分組。順序就是畫面順序。
enum DeadlineBucket { overdue, today, thisWeek, later }

class DeadlineGroup {
  const DeadlineGroup(this.bucket, this.events);

  final DeadlineBucket bucket;
  final List<MoodleActionEvent> events;
}

/// 待辦清單的純函式：分組與時間格式。沒有任何 UI 與網路。
class UpcomingEventUtils {
  UpcomingEventUtils._();

  /// 課名前綴的實作在 [MoodleCourseNameUtils]：課程總分那一頁也要用同一套規則。
  static String stripCoursePrefix(String name) =>
      MoodleCourseNameUtils.stripCoursePrefix(name);

  /// 顯示用課名：shortname 優先、空的退 fullname；站台事件沒有 course 回 null。
  static String? courseLabelOf(MoodleActionEvent event) {
    final course = event.course;
    if (course == null) return null;
    for (final raw in [course.shortname, course.fullname]) {
      final label = stripCoursePrefix(raw);
      if (label.isNotEmpty) return label;
    }
    return null;
  }

  /// 依 timesort 相對於 [now] 分組（本週到這個星期日 24:00）。不看 overdue
  /// 旗標：那是伺服器匯出當下算的，Stale 快取顯示時早就過時。
  static List<DeadlineGroup> groupByDeadline(
      List<MoodleActionEvent> events, DateTime now) {
    final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);
    // weekday：Mon=1 .. Sun=7，所以 8 - weekday 就是到下週一還有幾天。
    final startOfNextWeek =
        DateTime(now.year, now.month, now.day + (8 - now.weekday));

    final buckets = {
      for (final bucket in DeadlineBucket.values) bucket: <MoodleActionEvent>[],
    };
    final sorted = [...events]
      ..sort((a, b) => a.timesort.compareTo(b.timesort));
    for (final event in sorted) {
      final due = event.dueTime;
      final bucket = due.isBefore(now)
          ? DeadlineBucket.overdue
          : due.isBefore(startOfTomorrow)
              ? DeadlineBucket.today
              : due.isBefore(startOfNextWeek)
                  ? DeadlineBucket.thisWeek
                  : DeadlineBucket.later;
      buckets[bucket]!.add(event);
    }
    return [
      for (final bucket in DeadlineBucket.values)
        if (buckets[bucket]!.isNotEmpty)
          DeadlineGroup(bucket, buckets[bucket]!),
    ];
  }

  /// 本地時間 `MM/dd HH:mm`，跨年才補年份。刻意不跟語系走：這格是 tile 右側的
  /// 固定欄，標題要留寬，純數字兩個語系都讀得懂。
  static String formatDueTime(DateTime due, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final day =
        '${two(due.month)}/${two(due.day)} ${two(due.hour)}:${two(due.minute)}';
    return due.year == now.year ? day : '${due.year}/$day';
  }
}
