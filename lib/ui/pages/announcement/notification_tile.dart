import 'package:flutter/material.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_message_popup_notifications.dart';
import 'package:flutter_app/src/util/moodle_notification_utils.dart';
import 'package:flutter_app/ui/components/html/moodle_html_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';

/// 站內通知的一列。有 contexturl 的點了會開網頁（右側 open_in_new），沒有的
/// 就地展開內文（右側 chevron）——兩種行為在點下去之前就分得出來。
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.now,
    required this.openable,
    required this.expanded,
    required this.onTap,
    required this.openWebView,
  });

  final MoodleNotification notification;

  /// 「現在」，由呼叫端一次算好，整份清單的時間欄才是同一個時間點。
  final DateTime now;

  /// 有可以開啟的自家網址（`MoodleNotificationUtils.openUrlOf`）。
  final bool openable;

  final bool expanded;
  final VoidCallback onTap;
  final WebViewOpener openWebView;

  /// 伺服器的 `iconurl` 刻意不用：那是站台主題圖，每一列要多一次網路請求，
  /// 深色模式也不會反相。
  static IconData iconFor(String? component) {
    final name = component ?? '';
    return switch (name) {
      'mod_assign' => LucideIcons.clipboardList,
      'mod_forum' => LucideIcons.messagesSquare,
      'mod_quiz' => LucideIcons.fileQuestion,
      'mod_feedback' || 'mod_choice' || 'mod_survey' => LucideIcons.vote,
      'mod_lesson' || 'mod_scorm' => LucideIcons.bookOpen,
      _ => name.startsWith('mod_') ? LucideIcons.puzzle : LucideIcons.bell,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final unread = !notification.read;
    final summary = MoodleNotificationUtils.plainSummaryOf(notification);
    final body =
        expanded ? MoodleNotificationUtils.bodyHtmlOf(notification) : '';

    return InkWell(
      onTap: onTap,
      child: Container(
        // 未讀有三個訊號：底色、粗體標題與圓點，不只靠顏色。
        color: unread ? scheme.primary.withValues(alpha: 0.05) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconChip(component: notification.component, unread: unread),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notification.subject,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                                height: 1.3,
                                fontWeight:
                                    unread ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 8),
                            Semantics(
                              label: R.current.notificationUnread,
                              child: Container(
                                key: ValueKey('unread-${notification.id}'),
                                margin: const EdgeInsets.only(top: 5),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // 展開時內文就在下面，而摘要多半是同一句話：
                      // fullmessagehtml 缺席時 bodyHtmlOf 退回的正是
                      // plainSummaryOf 挑到的那個欄位。
                      if (summary.isNotEmpty && body.isEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 6),
                      _MetaLine(
                        source: _sourceLabel(),
                        time: MoodleNotificationUtils.formatCreatedTime(
                            notification.createdTime, now),
                        style: text.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  openable
                      ? LucideIcons.externalLink
                      : (expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown),
                  size: openable ? 14 : 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 12),
              MoodleHtmlView(
                html: body,
                title: notification.subject,
                dirName: 'notification',
                openWebView: openWebView,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 來源，也就是 Moodle 的活動名稱。core 的系統通知沒有 contexturlname。
  String _sourceLabel() {
    final source = notification.contexturlname?.trim();
    return (source == null || source.isEmpty)
        ? R.current.notificationUnknownSource
        : source;
  }
}

/// 「來源 · 時間」。兩段分開排版而不是一個 `Text`：活動名稱是老師打的、
/// 長度沒有上限，包在同一串裡被 ellipsis 吃掉的一定是後面的時間——而時間是
/// 這一列唯一的新舊訊號。
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.source, required this.time, this.style});

  final String source;
  final String time;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$source · $time',
      child: Row(
        children: [
          Flexible(
            child: Text(
              source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Text(' · $time', maxLines: 1, style: style),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.component, required this.unread});

  final String? component;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color:
            unread ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(
        NotificationTile.iconFor(component),
        size: 20,
        color: unread ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
    );
  }
}
