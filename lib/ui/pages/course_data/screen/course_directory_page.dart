import 'package:flutter_app/src/controller/course_data/course_data_controller.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/ui/components/tile/course_info_tile.dart';
import 'package:flutter_app/src/util/my_toast.dart';

class CourseDirectoryPage extends StatefulWidget {
  final CourseInfoJson courseInfo;

  /// 三個（或兩個）分頁共用的狀態。頁面在進入時就把所有請求發完，
  /// 所以每個分頁只負責畫自己那一份。
  final CourseDataController controller;

  const CourseDirectoryPage(
    this.courseInfo, {
    required this.controller,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseDirectoryPageState();
}

class _CourseDirectoryPageState extends State<CourseDirectoryPage>
    with AutomaticKeepAliveClientMixin {
  /// null 代表還在載入。請求不能寫進 build()，否則每一次 rebuild（切主題、
  /// 切語言、鍵盤彈出、上層 setState）都會重跑整段流程。
  Rxn<Result<List<MoodleCoreCourseGetContents>>> get _state => widget.controller.directory;

  // 沒有 initState 觸發請求：由頁面在進入時一次發完三個（或兩個），
  // 見 CourseDataController.loadAll / CourseDetailController.loadAll。

  Future<void> _load() => widget.controller.loadDirectory();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      padding: const EdgeInsets.only(top: 10),
      child: ResultView<List<MoodleCoreCourseGetContents>>(
        state: _state,
        onRetry: _load,
        errorBuilder: (message) => ErrorPage(errorMsg: message),
        builder: buildTree,
      ),
    );
  }

  Widget buildTree(List<MoodleCoreCourseGetContents> directoryList) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: directoryList.length,
      itemBuilder: (BuildContext context, int index) {
        var ap = directoryList[index];
        return CourseInfoTile(
            index: index,
            title: ap.name,
            img: "img_file",
            isShowArrow: ap.modules.isNotEmpty,
            onTap: () {
              if (ap.modules.isEmpty) {
                MyToast.show(R.current.nothingHere);
                return;
              }
              RouteUtils.toCourseInfoPage(widget.courseInfo, ap);
            });
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
