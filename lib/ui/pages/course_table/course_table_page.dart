import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/ui/pages/course_table/modal/semester_dialog.dart';
import 'package:flutter_app/ui/pages/course_table/modal/favorite_dialog.dart';
import 'package:flutter_app/ui/pages/course_table/modal/course_detail_dialog.dart';
import 'package:flutter_app/ui/pages/course_table/custom_course_page.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'dart:async';
import 'package:flutter_app/src/config/course_config.dart';
import 'package:flutter_app/src/controller/announcement/notification_badge_controller.dart';
import 'package:flutter_app/src/controller/course_table/course_controller.dart';
import 'package:flutter_app/src/enum/course_table_ui_state.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/ui/components/page/base_page.dart';
import 'package:flutter_app/ui/components/widget_size_render_object.dart';
import 'package:flutter_app/ui/pages/course_table/component/course_menu.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:get/get.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:sprintf/sprintf.dart';

class CourseTablePage extends GetView<CourseController> {
  const CourseTablePage({super.key});

  @override
  Widget build(BuildContext context) {
    controller.refreshSemester();

    return Obx(() {
      return BasePage(
          title: R.current.titleCourse,
          resizeToAvoidBottomInset: false,
          isLoading: controller.isLoading.value == CourseTableUIState.loading,
          isError: controller.isLoading.value == CourseTableUIState.fail,
          action: actionList(),
          child: contentView());
    });
  }

  List<Widget> actionList() {
    return [
      // 內層 Obx 只讀未讀數，未讀數變動時不會連整張課表一起重建。
      Obx(() {
        final unread = NotificationBadgeController.instance.unread.value;
        final icon = Icon(LucideIcons.megaphone, color: Get.iconColor);
        return IconButton(
          // 純圖示按鈕在螢幕閱讀器下只會唸「按鈕」，要靠 tooltip 補語意。
          tooltip: unread > 0
              ? sprintf(R.current.notificationUnreadTooltip, [unread])
              : R.current.announcementCenter,
          icon: unread > 0 ? Badge.count(count: unread, child: icon) : icon,
          iconSize: 24,
          splashRadius: 18,
          onPressed: () {
            unawaited(RouteUtils.toAnnouncementCenter());
          },
          enableFeedback: true,
        );
      }),
      Visibility(
        visible: AuthSession.instance.isSignedIn,
        child: IconButton(
          tooltip: R.current.refresh,
          icon: const Icon(LucideIcons.refreshCw),
          splashRadius: 18,
          iconSize: 24,
          onPressed: () {
            controller.getCourseTable(
              semesterSetting: controller.semesterSetting.value,
              refresh: true,
            );
          },
          enableFeedback: true,
        ),
      ),
      Visibility(
        visible: AuthSession.instance.isSignedIn,
        child: CourseMenu(
          studentId: controller.studentId.value,
          onSelected: _onMenuSelected,
        ),
      )
    ];
  }

  Widget contentView() {
    return WidgetSizeOffsetWrapper(
      onSizeChange: (Size size) {
        controller.courseHeight.value = (size.height -
                CourseConfig.studentIdHeight -
                CourseConfig.dayHeight) /
            CourseConfig.showCourseTableNum; //計算每堂課高度
      },
      child: Column(
        children: <Widget>[
          SizedBox(
            height: CourseConfig.studentIdHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(controller.studentId.value),
                  ),
                ),
                TextButton(
                  onPressed: _showSemesterList,
                  child: Row(
                    children: [
                      Text(
                        controller.semesterString.value,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Get.theme.colorScheme.onSurface),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(5),
                      ),
                      Icon(LucideIcons.chevronDown,
                          size: 24, color: Get.iconColor)
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: controller.isLoading.value != CourseTableUIState.success
                ? const SizedBox()
                : _buildListView(),
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    return SingleChildScrollView(
      child: Screenshot(
        controller: controller.screenshotController,
        child: Column(
          children: List.generate(
            controller.courseTableControl.getSectionIntList.length + 1,
            (index) {
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 375),
                child: ScaleAnimation(
                  child: FadeInAnimation(
                    child: (index == 0)
                        ? _buildDay()
                        : _buildCourseTable(index - 1),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDay() {
    List<Widget> widgetList = [];
    widgetList.add(Container(
      width: CourseConfig.sectionWidth,
    ));
    for (int i in controller.courseTableControl.getDayIntList) {
      widgetList.add(
        Expanded(
          child: Text(
            controller.courseTableControl.getDayString(i),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Container(
      color: Get.theme.scaffoldBackgroundColor
          .withAlpha(CourseConfig.courseTableWithAlpha),
      height: CourseConfig.dayHeight,
      child: Row(
        children: widgetList,
      ),
    );
  }

  Widget _buildCourseTable(int index) {
    var courseTableControl = controller.courseTableControl;
    int section = courseTableControl.getSectionIntList[index];

    List<Widget> widgetList = [];
    widgetList.add(
      Container(
        width: CourseConfig.sectionWidth,
        alignment: Alignment.center,
        child: Text(
          courseTableControl.getSectionString(section),
          textAlign: TextAlign.center,
        ),
      ),
    );

    for (int day in courseTableControl.getDayIntList) {
      CourseInfoJson? courseInfo =
          courseTableControl.getCourseInfo(day, section);
      Color color = courseTableControl.getCourseInfoColor(day, section);
      courseInfo = courseInfo ?? CourseInfoJson();
      widgetList.add(
        Expanded(
          child: courseInfo.isEmpty
              ? const SizedBox()
              : Container(
                  padding: const EdgeInsets.all(1),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(0),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        backgroundColor: color,
                        elevation: 0),
                    child: AutoSizeText(
                      courseInfo.main.course.name,
                      style: TextStyle(
                          color: UIUtils.getOnColor(color),
                          fontSize: 14,
                          height: 1.2),
                      minFontSize: 10,
                      maxLines: 3,
                      textAlign: TextAlign.center,
                    ),
                    onPressed: () {
                      _showCourseDetailDialog(section, courseInfo!);
                    },
                  ),
                ),
        ),
      );
    }

    return Container(
      color: UIUtils.getListColor(index),
      height: controller.courseHeight.value,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgetList,
      ),
    );
  }

  /// **哪一個 widget 出現是這一頁的事。**
  ///
  /// controller 只做資料操作、把結果回傳給這裡；controller 自己呼叫 `Get.dialog`
  /// 或 `RouteUtils` 會讓 `lib/src/controller` 反向 import `lib/ui`。

  Future<void> _showSemesterList() async {
    final semesterList = await controller.loadSemesterList();
    unawaited(Get.dialog(SemesterDialog(
      semesterList: semesterList,
      onSelected: (value) => controller.getCourseTable(semesterSetting: value),
    )));
  }

  void _showCourseDetailDialog(int section, CourseInfoJson courseInfo) {
    Get.dialog(CourseDetailDialog(
      courseInfo: courseInfo,
      time: controller.courseTableControl.getTimeString(section),
      onDetailTap: () => _openCourseDetail(courseInfo),
      onMoodleTap: () => _openCourseData(courseInfo),
      onRemoveTap: () => controller.removeCourse(courseInfo),
    ));
  }

  /// 課號為空的自訂課程沒有詳情可以看。
  bool _hasCourseId(CourseInfoJson courseInfo) {
    final course = courseInfo.main.course;
    if (course.id.isEmpty) {
      MyToast.show(course.name + R.current.noSupport);
      return false;
    }
    return true;
  }

  void _openCourseData(CourseInfoJson courseInfo) {
    // 先關掉詳情對話框再導頁。
    Get.back();
    if (!_hasCourseId(courseInfo)) return;
    RouteUtils.toCourseDataPage(courseInfo);
  }

  void _openCourseDetail(CourseInfoJson courseInfo) {
    if (!_hasCourseId(courseInfo)) return;
    RouteUtils.toCourseDetailPage(controller.currentSemester, courseInfo);
  }

  Future<void> _onMenuSelected(int value) async {
    switch (value) {
      case 0:
        MyToast.show("${R.current.credit}: ${controller.totalCredit}");
      case 1:
        await _showFavorites();
      case 2:
        await _addCustomCourse();
      case 3:
        await controller.setWidget();
    }
  }

  Future<void> _showFavorites() async {
    final value = controller.favorites;
    if (value.isEmpty) {
      MyToast.show(R.current.noAnyFavorite);
      return;
    }
    unawaited(Get.dialog(FavoriteDialog(
      value: value,
      onPressed: (index) async {
        await controller.applyFavorite(value[index]);
        Get.back();
      },
      onDelete: (index) => controller.deleteFavorite(value[index]),
    )));
  }

  Future<void> _addCustomCourse() async {
    final info =
        await Get.to(() => const CustomCoursePage()) as CourseMainInfoJson?;
    if (info == null) return;
    await controller.addCustomCourse(info);
  }
}
