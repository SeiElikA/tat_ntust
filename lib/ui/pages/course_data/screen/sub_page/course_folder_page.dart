import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/ui/components/file_type_icon.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';

class CourseFolderPage extends StatefulWidget {
  final CourseInfoJson courseInfo;
  final Modules modules;

  const CourseFolderPage(
    this.courseInfo,
    this.modules, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseFolderPageState();
}

class _CourseFolderPageState extends State<CourseFolderPage> {
  Future<Modules?> initTask() async {
    return widget.modules;
  }

  /// Future 只建一次。這一頁的 initTask 不打網路（只回傳 widget 欄位），但寫在
  /// build() 裡每次重建都會產生新的 Future，FutureBuilder 因此重跑一輪 waiting，
  /// 畫面會閃一下。
  late final Future<Modules?> _task = initTask();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.modules.name),
      ),
      body: Container(
        padding: const EdgeInsets.only(top: 10),
        child: FutureBuilder<Modules?>(
          future: _task,
          builder: (BuildContext context, AsyncSnapshot<Modules?> snapshot) {
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

  Widget buildTree(Modules modules) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: modules.contents.length,
      itemBuilder: (BuildContext context, int index) {
        var ap = modules.contents[index];
        return InkWell(
          child: Container(
            color: UIUtils.getListColor(index),
            height: 50,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: FileTypeIcon(
                    filename: ap.filename,
                    mimetype: ap.mimetype,
                  ),
                ),
                Expanded(
                  child: Text(
                    ap.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          onTap: () async {
            String dirName = widget.courseInfo.main.course.name;
            // 下載自帶進度通知與錯誤提示，生命週期比這個頁面長，
            // 等它結束只會卡住點擊處理，所以刻意不等。
            unawaited(FileDownload.download(context,
                MoodleWebApiConnector.fileUrlWithToken(ap.fileurl), dirName,
                name: ap.filename));
          },
        );
      },
    );
  }
}
