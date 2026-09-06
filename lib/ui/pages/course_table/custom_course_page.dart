import 'package:flutter/material.dart';
import 'package:flutter_app/ui/components/custom_snackbar.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/controller/course_table/course_controller.dart';
import 'package:flutter_app/ui/components/card/course_search_card.dart';
import 'package:flutter_app/ui/components/input/search_bar.dart';
import 'package:flutter_app/ui/components/page/base_page.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

class CustomCoursePage extends GetView<CourseController> {
  const CustomCoursePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return BasePage(title: R.current.importCourse, child: contentView());
    });
  }

  Widget contentView() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
        child: CourseSearchBar(
          onSubmit: _onSubmit,
        ),
      ),
      Expanded(
          child: controller.courseInfoList.isEmpty ? hintView() : listView())
    ]);
  }

  Widget listView() {
    return Scrollbar(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: controller.courseInfoList.length,
        itemBuilder: (context, index) {
          var info = controller.courseInfoList[index];
          return CourseSearchCard(
            info: info,
            onTap: (info) {
              Get.back(result: info);
            },
          );
        },
        separatorBuilder: (BuildContext context, int index) {
          return const SizedBox(height: 12);
        },
      ),
    );
  }

  Widget hintView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.search,
              size: 76, color: Get.theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              "${R.current.courseSearchHint}\n\n${R.current.importCourseWarning}",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, color: Get.theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  /// 查無結果的提示屬於這一頁：controller 自己呼叫 `CustomSnackBar` 會讓
  /// lib/src/controller 反向 import lib/ui。
  Future<void> _onSubmit(String value) async {
    await controller.onCustomCourseSearchSubmit(value);
    if (controller.courseInfoList.isEmpty) {
      CustomSnackBar.showCustomErrorSnackBar(
          title: R.current.error, message: R.current.courseSearchNotFound);
    }
  }
}
