import 'package:flutter/material.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// 段標題右邊那顆狀態籤的外觀。作業與測驗共用同一份，兩邊才不會各自漂走；
/// 顏色與文字由呼叫端決定。刻意不 import 任何頁面。
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.background,
    required this.foreground,
    required this.label,
    this.stale = false,
  });

  final Color background;
  final Color foreground;
  final String label;

  /// 資料來自快取（`Stale`）時多畫一個時鐘小圖示。
  final bool stale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stale) ...[
            Icon(LucideIcons.history, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 12, color: foreground)),
        ],
      ),
    );
  }
}
