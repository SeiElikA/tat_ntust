import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// 頭貼可以做的三件事。
enum AvatarAction { gallery, camera, remove }

/// 頭貼的動作選單。回 null 代表使用者取消（點外面、按返回、按取消都算）。
///
/// [canRemove] 為 false 時不顯示「移除」：使用者用的是主題預設圖，
/// core_user::update_picture 會因為 picture 沒有變而回 success:false，
/// 看起來像失敗，但他其實什麼都沒做錯。
Future<AvatarAction?> showAvatarActionSheet(
  BuildContext context, {
  required bool canRemove,
}) {
  return showModalBottomSheet<AvatarAction>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _AvatarActionSheet(canRemove: canRemove),
  );
}

class _AvatarActionSheet extends StatelessWidget {
  const _AvatarActionSheet({required this.canRemove});

  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      // 可捲：modal sheet 的高度上限是螢幕的 9/16，字級放大或小螢幕上
      // 四列加標題就會超出去。
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionSubLabel(R.current.avatarChange),
            ),
            ListTile(
              leading: const Icon(LucideIcons.images),
              title: Text(R.current.avatarFromGallery),
              onTap: () => Navigator.pop(context, AvatarAction.gallery),
            ),
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: Text(R.current.avatarTakePhoto),
              onTap: () => Navigator.pop(context, AvatarAction.camera),
            ),
            if (canRemove) ...[
              const SectionDivider(),
              ListTile(
                leading: Icon(LucideIcons.trash2, color: scheme.error),
                title: Text(R.current.avatarRemove,
                    style: TextStyle(color: scheme.error)),
                onTap: () => Navigator.pop(context, AvatarAction.remove),
              ),
            ],
            const SectionDivider(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(R.current.cancel),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
