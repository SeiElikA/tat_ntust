import 'package:flutter/material.dart';
import 'package:flutter_app/ui/other/svg_tint.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 整頁的空狀態：一張淡色插圖加一行說明。嵌在頁面中段、周圍畫面還在的區塊
/// 有自己更小的一份（`SectionEmptyState`），不要共用這個。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.asset, required this.message});

  /// `assets/image/` 底下的 SVG 路徑。
  final String asset;

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            asset,
            colorFilter: svgTint(Theme.of(context).colorScheme.onSurface),
            height: 72,
          ),
          const SizedBox(height: 24),
          Text(message),
        ],
      ),
    );
  }
}
