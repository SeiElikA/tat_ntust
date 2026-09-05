import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_app/ui/components/tile/course_info_tile.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html_unescape/html_unescape.dart';

class CourseAnnouncementDetailPage extends StatefulWidget {
  final CourseInfoJson courseInfo;
  final Discussions discussions;

  const CourseAnnouncementDetailPage(
    this.courseInfo,
    this.discussions, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseAnnouncementDetailPageState();
}

class _CourseAnnouncementDetailPageState
    extends State<CourseAnnouncementDetailPage> {
  late String html;

  Future<Discussions?> initTask() async {
    return widget.discussions;
  }

  /// Future 只建一次。理由同 course_folder_page。
  late final Future<Discussions?> _task = initTask();

  Future<bool> onLinkTap(Discussions discussions, String url) async {
    if (Uri.parse(url).path.contains("pluginfile.php")) {
      String dirName = widget.courseInfo.main.course.name;
      // 下載自己有進度通知與生命週期，不擋住 onLinkTap 的回傳。
      unawaited(FileDownload.download(context, url, dirName));
    } else {
      unawaited(RouteUtils.toWebViewPage(discussions.name, url));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    Discussions discussions = widget.discussions;
    html = discussions.message;
    return Scaffold(
      appBar: baseAppbar(title: HtmlUnescape().convert(discussions.name)),
      body: Container(
        padding: const EdgeInsets.only(top: 10),
        child: FutureBuilder<Discussions?>(
          future: _task,
          builder:
              (BuildContext context, AsyncSnapshot<Discussions?> snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              if (snapshot.data == null) {
                return const ErrorPage();
              } else {
                return buildTree(snapshot.data!);
              }
            } else {
              return const Text("");
            }
          },
        ),
      ),
    );
  }

  Widget buildTree(Discussions discussions) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(right: 20, left: 20, top: 20),
          child: HtmlWidget(
            html,
            renderMode: RenderMode.column,
            textStyle: const TextStyle(height: 1.2),
            onTapUrl: (String s) => onLinkTap(discussions, s),
          ),
        ),
        Container(
          height: 20,
        ),
        ListView.builder(
          shrinkWrap: true,
          itemCount: discussions.attachments.length,
          itemBuilder: (BuildContext context, int index) {
            var ap = discussions.attachments[index];
            return CourseInfoTile(
                index: index,
                title: ap.filename,
                img: "img_doc",
                onTap: () {
                  String dirName = widget.courseInfo.main.course.name;
                  // 下載自己管生命週期與通知，不等它；這裡是同步回呼，
                  // unawaited_futures 抓不到，所以手動標示。
                  unawaited(FileDownload.download(
                      context,
                      MoodleWebApiConnector.fileUrlWithToken(ap.fileurl),
                      dirName,
                      name: ap.filename));
                });
          },
        )
      ],
    );
  }
}
