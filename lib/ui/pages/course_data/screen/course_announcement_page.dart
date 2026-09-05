import 'package:flutter_app/src/controller/course_data/course_data_controller.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/other/svg_tint.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class CourseAnnouncementPage extends StatefulWidget {
  final CourseInfoJson courseInfo;

  /// 三個（或兩個）分頁共用的狀態。頁面在進入時就把所有請求發完，
  /// 所以每個分頁只負責畫自己那一份。
  final CourseDataController controller;

  const CourseAnnouncementPage(
    this.courseInfo, {
    required this.controller,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseAnnouncementPageState();
}

class _CourseAnnouncementPageState extends State<CourseAnnouncementPage>
    with AutomaticKeepAliveClientMixin {
  /// null 代表還在載入。
  ///
  /// 請求不能寫進 build()，否則每一次 rebuild（切主題、切語言、鍵盤彈出、上層
  /// setState）都會重跑整段流程。狀態住在 controller 而不是這個 State：三個分頁
  /// 的請求要在進入頁面時一起發出去，而 PageView 只 mount 當前那一個。
  Rxn<Result<MoodleModForumGetForumDiscussions>> get _state => widget.controller.announcements;

  // 沒有 initState 觸發請求：由頁面在進入時一次發完三個（或兩個），
  // 見 CourseDataController.loadAll / CourseDetailController.loadAll。

  Future<void> _load() => widget.controller.loadAnnouncements();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      padding: const EdgeInsets.only(top: 10),
      child: ResultView<MoodleModForumGetForumDiscussions>(
        state: _state,
        onRetry: _load,
        errorBuilder: (message) => ErrorPage(errorMsg: message),
        builder: (data) => buildTree(data.discussions),
      ),
    );
  }

  Widget buildTree(List<Discussions> discussions) {
    if (discussions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset("assets/image/img_open_folder.svg",
                colorFilter: svgTint(Get.theme.colorScheme.onSurface),
                height: 72),
            const SizedBox(height: 24),
            Text(R.current.announcementEmpty)
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: discussions.length,
      itemBuilder: (BuildContext context, int index) {
        var ap = discussions[index];
        final DateFormat formatter = DateFormat.yMd().add_jm();

        final String formatted = formatter
            .format(DateTime.fromMillisecondsSinceEpoch(ap.modified * 1000));

        return InkWell(
          child: Container(
            color: UIUtils.getListColor(index),
            padding: const EdgeInsets.only(top: 10, bottom: 10),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: SvgPicture.asset(
                    "assets/image/img_message.svg",
                    colorFilter: svgTint(Get.theme.colorScheme.onSurface),
                  ),
                ),
                Expanded(
                    child: Text(
                  ap.name,
                  style: TextStyle(
                      height: 1.2,
                      color: Get.theme.colorScheme.onSurface,
                      overflow: TextOverflow.fade),
                  maxLines: 2,
                )),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ap.userfullname,
                      textAlign: TextAlign.end,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatted,
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          onTap: () async {
            await RouteUtils.toAnnouncementDetailPage(widget.courseInfo, ap);
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
