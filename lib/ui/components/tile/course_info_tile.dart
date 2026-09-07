import 'package:flutter/material.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

class CourseInfoTile extends StatelessWidget {
  const CourseInfoTile(
      {super.key,
      required this.index,
      required this.title,
      required this.icon,
      this.isShowArrow = false,
      required this.onTap});

  final int index;
  final String title;
  final IconData icon;
  final bool isShowArrow;
  final Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap,
        child: Container(
          color: UIUtils.getListColor(index),
          height: 50,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Icon(
                  icon,
                  size: 24,
                  color: Get.theme.colorScheme.onSurface,
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Get.theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Visibility(
                  visible: isShowArrow,
                  child: const Icon(LucideIcons.chevronRight, size: 14)),
              const SizedBox(width: 8)
            ],
          ),
        ));
  }
}
