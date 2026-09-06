import 'dart:async';

import 'package:expansion_tile_card/expansion_tile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/util/language_utils.dart';
import 'package:flutter_app/src/util/open_utils.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/file_type_icon.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_assignment_detail_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_html_page.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

class CourseInfoPage extends StatefulWidget {
  final CourseInfoJson courseInfo;
  final MoodleCoreCourseGetContents contents;

  const CourseInfoPage(
    this.courseInfo,
    this.contents, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseInfoPageState();
}

class _CourseInfoPageState extends State<CourseInfoPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: baseAppbar(
          title: widget.contents.name,
        ),
        body: buildTree());
  }

  /// resource 模組跟官方 App 一樣畫檔案類型 icon，其他模組依 modname 挑圖。
  Widget buildIcon(Modules ap) {
    if (ap.modname == "resource") {
      final file = ap.contents.isEmpty ? null : ap.contents.first;
      return FileTypeIcon(
        filename: file?.filename ?? "",
        mimetype: file?.mimetype ?? "",
        modicon: ap.modicon,
      );
    }
    return Icon(getIcon(ap.modname), size: 24, color: Get.iconColor);
  }

  IconData getIcon(String type) {
    switch (type) {
      case "forum":
        return LucideIcons.messageSquare;
      case "assign":
        return LucideIcons.clipboardList;
      case "folder":
        return LucideIcons.folder;
      case "label":
        return LucideIcons.tag;
      case "url":
        return LucideIcons.link;
      default:
        return LucideIcons.copy;
    }
  }

  void openWebView(Modules ap, {openWithExternalWebView = false}) async {
    unawaited(RouteUtils.toWebViewPage(
        ap.name,
        Connector.uriAddQuery(
          ap.url,
          (LanguageUtils.getLangIndex() == LangEnum.zh)
              ? {"lang": "zh_tw"}
              : {"lang": "en"},
        ),
        openWithExternalWebView: openWithExternalWebView));
  }

  void handleTap(Modules ap) async {
    switch (ap.modname) {
      case "forum":
        openWebView(ap);
        break;
      case "assign":
        // Modules.instance 就是 assign id；ErrorPage 與 RouteUtils 由這裡注入。
        unawaited(Get.to(() => CourseAssignmentDetailPage(
              widget.courseInfo,
              assignId: ap.instance,
              errorBuilder: (message) => ErrorPage(errorMsg: message),
              openWebView: RouteUtils.toWebViewPage,
            )));
        break;
      case "folder":
        // 空資料夾也進得去：資料夾頁自己畫空狀態，比一句 toast 清楚。
        unawaited(RouteUtils.toCourseFolderPage(widget.courseInfo, ap));
        break;
      case "label":
        break;
      case "url":
        if (ap.contents.isEmpty) {
          MyToast.show(R.current.nothingHere);
          return;
        }
        unawaited(OpenUtils.launchURL(ap.contents.first.fileurl));
        break;
      case "page":
        unawaited(Get.to(() => CourseHtmlPage(ap: ap)));
        break;
      case "resource":
      default:
        // contents 可能是空的（模組沒有檔案或看不到），先前這裡直接取 first，
        // 例外被 fire-and-forget 吃掉，使用者只看到點了沒反應。
        final file = ap.contents.isEmpty ? null : ap.contents.first;
        if (file == null) {
          MyToast.show(R.current.nothingHere);
          return;
        }
        String dirName = widget.courseInfo.main.course.name;
        // 下載自己有通知列進度，這裡不等它結束才不會卡住 handler。
        unawaited(FileDownload.download(context,
            MoodleWebApiConnector.fileUrlWithToken(file.fileurl), dirName,
            name: file.filename));
    }
  }

  final titleTextStyle = const TextStyle(fontSize: 14, height: 1.2);

  Widget buildItem(Modules ap, int index) {
    switch (ap.modname) {
      case "label":
        return Container(
            padding: const EdgeInsets.only(left: 20, top: 10, bottom: 10),
            child: HtmlWidget(
              ap.description,
              renderMode: RenderMode.column,
            ));
      default:
        if (ap.description.isNotEmpty) {
          return ExpansionTileCard(
            expandedColor: UIUtils.getListColor(index),
            baseColor: UIUtils.getListColor(index),
            title: Text(
              ap.name,
              style: titleTextStyle,
            ),
            children: [
              Container(
                padding: const EdgeInsets.only(left: 20),
                child: HtmlWidget(
                  ap.description,
                  renderMode: RenderMode.column,
                ),
              ),
              SizedBox(
                height: 50,
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        child: Icon(LucideIcons.download,
                            size: 24, color: Get.iconColor),
                        onTap: () {
                          handleTap(ap);
                        },
                      ),
                    )
                  ],
                ),
              )
            ],
          );
        }
        return Container(
          height: 50,
          padding: const EdgeInsets.only(left: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ap.name,
                  style: titleTextStyle,
                  overflow: TextOverflow.fade,
                  maxLines: 2,
                ),
              )
            ],
          ),
        );
    }
  }

  Widget buildTree() {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: widget.contents.modules.length,
      itemBuilder: (BuildContext context, int index) {
        var ap = widget.contents.modules[index];

        return InkWell(
          child: Container(
            color: UIUtils.getListColor(index),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: buildIcon(ap),
                ),
                Expanded(
                  child: buildItem(ap, index),
                ),
              ],
            ),
          ),
          onTap: () async {
            handleTap(ap);
          },
        );
      },
    );
  }
}
