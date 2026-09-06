import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:sprintf/sprintf.dart';

/// 討論串清單的一列。公告分頁與一般討論區頁共用，兩邊長得一樣才對——
/// 它們是同一種東西（forum discussion），只是討論區的 type 不同。
class ForumDiscussionCard extends StatelessWidget {
  const ForumDiscussionCard({
    super.key,
    required this.discussion,
    required this.formatter,
    required this.onTap,
  });

  final Discussions discussion;
  final DateFormat formatter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // 用建立時間：modified 是第一篇貼文被編輯過的時間，詳情頁那邊印的是建立時間。
    final formatted = formatter
        .format(DateTime.fromMillisecondsSinceEpoch(discussion.created * 1000));
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (discussion.pinned) ...[
                    Icon(LucideIcons.pin,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      discussion.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                          height: 1.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${discussion.userfullname} · $formatted",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (discussion.numreplies > 0) ...[
                    const SizedBox(width: 8),
                    Icon(LucideIcons.messageSquare,
                        size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      sprintf(R.current.forumReplies, [discussion.numreplies]),
                      style: text.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
