import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/html/moodle_html_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:intl/intl.dart';

/// 討論串裡的一則貼文。
///
/// 從討論串頁抽出來是為了 `ListView.builder`：底部那條回覆列每打一個字就
/// setState 一次，貼文如果還住在頁面的 method 裡就會整串跟著重建。
class ForumPostBlock extends StatelessWidget {
  const ForumPostBlock({
    super.key,
    required this.item,
    required this.first,
    required this.aimed,
    required this.canReply,
    required this.hasOwnerActions,
    required this.onReply,
    required this.onActions,
    required this.onOpenFile,
    required this.openWebView,
    required this.dirName,
    required this.title,
  });

  final ThreadPost item;
  final bool first;

  /// 使用者正在回覆這一篇：加一圈 1px 的 primary 外框當定位。
  final bool aimed;

  final bool canReply;

  /// 編輯或刪除至少有一個可用時才畫 `⋯`。
  final bool hasOwnerActions;

  final VoidCallback onReply;
  final VoidCallback onActions;
  final void Function(MoodleForumFile file) onOpenFile;

  final WebViewOpener openWebView;
  final String dirName;
  final String title;

  static final ButtonStyle _denseAction = TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final p = item.post;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final author = p.author?.fullname ?? "";
    return Padding(
      padding: EdgeInsets.only(left: item.depth.clamp(0, 3) * 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            // 深度 0 是主文（公告分頁共用這一頁）；回覆用 user 而不是 reply：
            // 縮排已經在說「這是一則回覆」，同一個字形不該同時表達「這是回覆」
            // 與「回覆這則」。
            icon: item.depth == 0 ? LucideIcons.megaphone : LucideIcons.user,
            title: author.isNotEmpty ? author : R.current.forumUnknownAuthor,
            first: first,
            trailing: Text(
              _timeLabel(p),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          DecoratedBox(
            decoration: aimed
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.primary, width: 1),
                  )
                : const BoxDecoration(),
            child: SectionCard([
              // 只有第一篇印標題：回覆的 subject 是伺服器語系的「回覆: …」，
              // 重複又難看。
              if (item.depth == 0 && p.subject.isNotEmpty)
                SectionSubLabel(p.subject),
              _body(context, p),
              if (p.attachments.isNotEmpty) ...[
                const SectionDivider(),
                SectionSubLabel(R.current.forumAttachments),
                for (final f in p.attachments)
                  MoodleFileTile(
                    filename: f.filename,
                    onTap: () => onOpenFile(f),
                  ),
              ],
              if (canReply || hasOwnerActions) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (canReply)
                      TextButton.icon(
                        style: _denseAction,
                        onPressed: onReply,
                        icon: const Icon(LucideIcons.reply, size: 16),
                        label: Text(R.current.forumReply),
                      ),
                    const Spacer(),
                    if (hasOwnerActions)
                      IconButton(
                        tooltip: R.current.forumPostActions,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(LucideIcons.ellipsisVertical,
                            size: 18, color: scheme.onSurfaceVariant),
                        onPressed: onActions,
                      ),
                  ],
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, MoodleForumPost p) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (p.isdeleted) {
      return Text(R.current.forumPostDeleted,
          style: text.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant));
    }
    if (p.message.trim().isEmpty) {
      return Text(R.current.nothingHere,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant));
    }
    return MoodleHtmlView(
      html: p.message,
      title: title,
      dirName: dirName,
      openWebView: openWebView,
    );
  }

  /// 建立時間，被改過就接一句「已編輯」——少了這個記號，討論串會默默改寫歷史。
  /// `isdeleted` 的貼文 timecreated 是 null（post_exporter 這時不載內容）。
  static String _timeLabel(MoodleForumPost p) {
    final unix = p.timecreated ?? p.timemodified ?? 0;
    if (unix <= 0) return "";
    final formatted = DateFormat.yMd()
        .add_jm()
        .format(DateTime.fromMillisecondsSinceEpoch(unix * 1000));
    final created = p.timecreated;
    final modified = p.timemodified;
    final edited = created != null && modified != null && modified > created;
    return edited ? '$formatted · ${R.current.forumEdited}' : formatted;
  }
}
