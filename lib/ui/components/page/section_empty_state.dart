import 'package:flutter/material.dart';
import 'package:flutter_app/ui/other/svg_tint.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 頁面中段的空狀態：插圖比 `EmptyState` 小一號、文字用 `onSurfaceVariant`。
/// 周圍還有標題與另一個區塊時要用這個——整頁級的那張圖疊兩份會像兩個空畫面。
class SectionEmptyState extends StatelessWidget {
  const SectionEmptyState({
    super.key,
    required this.asset,
    required this.message,
  });

  /// `assets/image/` 底下的 SVG 路徑。
  final String asset;

  final String message;

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
              asset,
              colorFilter: svgTint(scheme.onSurface),
              height: 56,
            ),
            const SizedBox(height: 16),
            Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
