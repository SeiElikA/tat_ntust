import 'package:flutter/material.dart';

/// 群組標題，刻意放在卡片外：內容載入中或失敗時標題仍在。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.first = false,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, first ? 4 : 20, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 內容卡：surfaceContainer、圓角 12、padding 14/12。
class SectionCard extends StatelessWidget {
  const SectionCard(this.children, {super.key});

  static const double radius = 12;
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  /// 卡片底色的唯一出處。編輯面與工具列的漸層都要跟它一致，各自寫一份在
  /// 動態取色的機器上一定會對不起來。
  static Color fill(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainer;

  static BoxDecoration _decoration(BuildContext context) => BoxDecoration(
        color: fill(context),
        borderRadius: BorderRadius.circular(radius),
      );

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: _decoration(context),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// 列數不定時的內容卡：外觀同 [SectionCard]，但內容留在 sliver 裡逐列建構，
/// 上百個檔案的資料夾才不會在進頁時一次建完。
class SectionCardSliver extends StatelessWidget {
  const SectionCardSliver({super.key, required this.sliver});

  final Widget sliver;

  @override
  Widget build(BuildContext context) => DecoratedSliver(
        decoration: SectionCard._decoration(context),
        sliver: SliverPadding(padding: SectionCard.padding, sliver: sliver),
      );
}

/// 「標籤：值」的一列。標籤小而淡（固定 104 寬），值才是主角。
class SectionField extends StatelessWidget {
  const SectionField(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label,
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: text.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                    height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// 卡片內的子標題。
class SectionSubLabel extends StatelessWidget {
  const SectionSubLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// 卡片內的分隔線。
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 24,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}
