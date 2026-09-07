import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/util/rich_editor_bridge_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:sprintf/sprintf.dart';

/// 所見即所得編輯器的工具列。**完全沒有 WebView**，所以它是這整個功能裡
/// 唯一可以用 widget test 蓋滿的一塊。
///
/// 這一排照官方 Moodle App 的 `rich-text-editor`：粗體 / 斜體 / 底線 /
/// 刪除線 / 內文 / h3 / h4 / h5 / 項目符號 / 編號 / 清除格式，再加一顆原始碼
/// 切換。**沒有插入圖片**——官方 App 也沒有，`mod_forum` 那條路只能保留貼文
/// 原有的圖片，加不了新的。
class MoodleRichEditorToolbar extends StatelessWidget {
  const MoodleRichEditorToolbar({
    super.key,
    required this.active,
    required this.onCommand,
    required this.sourceMode,
    required this.onToggleSource,
    this.enabled = true,
  });

  /// 目前游標處生效的格式，值是 [RichEditorBridgeUtils.tokenOf] 的字面值。
  final Set<String> active;

  final ValueChanged<EditorCommand> onCommand;

  /// 原始碼模式：格式鈕全部停用（在原始碼上套粗體沒有意義）。
  final bool sourceMode;
  final VoidCallback onToggleSource;

  /// 編輯器還沒準備好、或正在送出時整排停用。
  final bool enabled;

  static IconData _iconOf(EditorCommand c) => switch (c) {
        EditorCommand.bold => LucideIcons.bold,
        EditorCommand.italic => LucideIcons.italic,
        EditorCommand.underline => LucideIcons.underline,
        EditorCommand.strikeThrough => LucideIcons.strikethrough,
        EditorCommand.paragraph => LucideIcons.pilcrow,
        EditorCommand.heading3 => LucideIcons.heading3,
        EditorCommand.heading4 => LucideIcons.heading4,
        EditorCommand.heading5 => LucideIcons.heading5,
        EditorCommand.unorderedList => LucideIcons.list,
        EditorCommand.orderedList => LucideIcons.listOrdered,
        EditorCommand.removeFormat => LucideIcons.removeFormatting,
      };

  static String labelOf(EditorCommand c) => switch (c) {
        EditorCommand.bold => R.current.forumEditorBold,
        EditorCommand.italic => R.current.forumEditorItalic,
        EditorCommand.underline => R.current.forumEditorUnderline,
        EditorCommand.strikeThrough => R.current.forumEditorStrikethrough,
        EditorCommand.paragraph => R.current.forumEditorParagraph,
        EditorCommand.heading3 => sprintf(R.current.forumEditorHeading, ['3']),
        EditorCommand.heading4 => sprintf(R.current.forumEditorHeading, ['4']),
        EditorCommand.heading5 => sprintf(R.current.forumEditorHeading, ['5']),
        EditorCommand.unorderedList => R.current.forumEditorBulletList,
        EditorCommand.orderedList => R.current.forumEditorNumberedList,
        EditorCommand.removeFormat => R.current.forumEditorClearFormat,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard([
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final command in EditorCommand.values)
              _button(
                icon: _iconOf(command),
                tooltip: labelOf(command),
                selected: active.contains(RichEditorBridgeUtils.tokenOf(
                  command,
                )),
                onPressed:
                    (enabled && !sourceMode) ? () => onCommand(command) : null,
                scheme: scheme,
              ),
            const VerticalDivider(width: 9, indent: 8, endIndent: 8),
            _button(
              icon: LucideIcons.codeXml,
              tooltip: R.current.forumEditorSource,
              selected: sourceMode,
              onPressed: enabled ? onToggleSource : null,
              scheme: scheme,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _button({
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback? onPressed,
    required ColorScheme scheme,
  }) =>
      IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        isSelected: selected,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.secondaryContainer : null,
          foregroundColor: selected ? scheme.onSecondaryContainer : null,
        ),
      );
}
