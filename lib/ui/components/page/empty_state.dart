import 'package:flutter/material.dart';

/// 整頁的空狀態：一個大圖示加一行說明。嵌在頁面中段、周圍畫面還在的區塊
/// 有自己更小的一份（`SectionEmptyState`），不要共用這個。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 72,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(height: 24),
          Text(message),
        ],
      ),
    );
  }
}
