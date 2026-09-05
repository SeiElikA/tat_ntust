import 'package:flutter_app/src/controller/course_detail/course_detail_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

class CourseInfoPage extends StatefulWidget {
  final String courseId;
  final SemesterJson semester;

  /// 三個（或兩個）分頁共用的狀態。頁面在進入時就把所有請求發完，
  /// 所以每個分頁只負責畫自己那一份。
  final CourseDetailController controller;

  const CourseInfoPage(
    this.courseId,
    this.semester, {
    required this.controller,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseInfoPageState();
}

class _CourseInfoPageState extends State<CourseInfoPage>
    with AutomaticKeepAliveClientMixin {
  /// null 代表還在載入。請求不能寫進 build()。狀態住在 controller 而不是這個
  /// State：三個分頁的請求要在進入頁面時一起發出去，而 PageView 只 mount 當前
  /// 那一個。
  Rxn<Result<CourseExtraInfoJson>> get _state => widget.controller.info;

  // 沒有 initState 觸發請求：由頁面在進入時一次發完三個（或兩個），
  // 見 CourseDataController.loadAll / CourseDetailController.loadAll。

  Future<void> _load() => widget.controller.loadInfo();

  /// 把課程資料攤平成畫面上的卡片清單。
  ///
  /// 卡片必須每次 build 重新產生：_buildCourseInfo 把 Get.theme 的顏色寫死在
  /// TextStyle 裡，只做一次就再也不會跟著主題或語言變。
  ///
  /// 回傳的元素可以是 null：_buildCourseInfo 對空欄位回 null，getAnimationList
  /// 會把它畫成 SizedBox。
  List<Widget?> _buildListItem(CourseExtraInfoJson courseExtraInfo) {
    final List<Widget?> listItem = [];
    listItem
        .add(_buildCourseInfo(R.current.semester, courseExtraInfo.semester));
    listItem
        .add(_buildCourseInfo(R.current.courseId, courseExtraInfo.courseNo));
    listItem.add(
        _buildCourseInfo(R.current.courseName, courseExtraInfo.courseName));
    listItem.add(
        _buildCourseInfo(R.current.instructor, courseExtraInfo.courseTeacher));
    listItem.add(_buildCourseInfo(
        "${R.current.courseTimes}/${R.current.practicalTimes}",
        sprintf("%s/%s",
            [courseExtraInfo.courseTimes, courseExtraInfo.practicalTimes])));
    listItem.add(_buildCourseInfo(
        R.current.requireOption,
        sprintf("%s/%s",
            [courseExtraInfo.requireOption, courseExtraInfo.allYear])));

    listItem.add(_buildCourseInfo(
        R.current.choosePeople,
        sprintf("%s ( %s / %s )", [
          courseExtraInfo.allStudent,
          courseExtraInfo.chooseStudent,
          courseExtraInfo.threeStudent
        ])));
    try {
      listItem.add(_buildCourseInfo(
          R.current.chooseUpBoundary,
          sprintf(R.current.choosePeopleString, [
            courseExtraInfo.restrict1,
            courseExtraInfo.restrict2,
            int.parse(courseExtraInfo.nTNURestrict) +
                int.parse(courseExtraInfo.nTURestrict)
          ])));
    } catch (e) {
      Log.d(e.toString());
    }

    listItem.add(
        _buildCourseInfo(R.current.classRoomNo, courseExtraInfo.classRoomNo));
    listItem.add(
        _buildCourseInfo(R.current.coreAbility, courseExtraInfo.coreAbility));
    listItem
        .add(_buildCourseInfo(R.current.courseURL, courseExtraInfo.courseURL));
    listItem.add(_buildCourseInfo(
        R.current.courseObject, courseExtraInfo.courseObject.trimLeft()));
    listItem.add(_buildCourseInfo(
        R.current.courseContent, courseExtraInfo.courseContent.trimLeft()));
    listItem.add(_buildCourseInfo(
        R.current.courseTextbook, courseExtraInfo.courseTextbook));
    listItem.add(_buildCourseInfo(
        R.current.courseRefbook, courseExtraInfo.courseRefbook));
    listItem.add(
        _buildCourseInfo(R.current.courseNote, courseExtraInfo.courseNote));
    listItem.add(_buildCourseInfo(
        R.current.courseGrading, courseExtraInfo.courseGrading));
    listItem.add(
        _buildCourseInfo(R.current.courseRemark, courseExtraInfo.courseRemark));
    return listItem;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      padding: const EdgeInsets.only(top: 10),
      child: ResultView<CourseExtraInfoJson>(
        state: _state,
        onRetry: _load,
        errorBuilder: (message) => ErrorPage(errorMsg: message),
        builder: (info) => getAnimationList(_buildListItem(info)),
      ),
    );
  }

  Widget getAnimationList(List<Widget?> listItem) {
    return AnimationLimiter(
      child: ListView.builder(
        itemCount: listItem.length,
        padding: const EdgeInsets.only(bottom: 6),
        itemBuilder: (BuildContext context, int index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: listItem[index] ?? const SizedBox(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget? _buildCourseInfo(String text, String info) {
    if (info.isEmpty) {
      return null;
    }
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: info));
        unawaited(Fluttertoast.showToast(msg: R.current.copy));
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                    fontSize: 14,
                    color: Get.theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                info,
                style: TextStyle(
                  height: 1.2,
                  color: Get.theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
