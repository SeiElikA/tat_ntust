import 'package:flutter/material.dart';
import 'package:flutter_app/ui/components/file_type_icon.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// Moodle 檔案的一列：類型 icon、檔名、下載提示。下載本身留給呼叫端，
/// 它才知道要存到哪個課程資料夾。
///
/// 資料夾頁的子資料夾列也走這裡，只是換掉 [leading] 與 [trailing]。
class MoodleFileTile extends StatelessWidget {
  const MoodleFileTile({
    super.key,
    required this.filename,
    this.mimetype = "",
    this.subtitle,
    this.leading,
    this.trailing,
    required this.onTap,
  });

  final String filename;

  /// 論壇附件沒有這個欄位，[FileTypeIcon] 會退回看副檔名。
  final String mimetype;

  /// null 時整列維持單行。
  final String? subtitle;

  /// 預設是依 [filename] / [mimetype] 決定的檔案類型 icon。
  final Widget? leading;

  /// 預設是下載提示。
  final Widget? trailing;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 28,
      horizontalTitleGap: 12,
      minVerticalPadding: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: leading ?? FileTypeIcon(filename: filename, mimetype: mimetype),
      title: Text(filename,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              text.bodyMedium?.copyWith(color: scheme.onSurface, height: 1.3)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      trailing: trailing ??
          Icon(LucideIcons.download, size: 18, color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
