import 'package:flutter_app/src/controller/course_data/course_data_controller.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/connector/core/connector_parameter.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_gradereport_get_grade_items.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/loading_page.dart';
import 'package:flutter_app/ui/pages/photo_view.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:get/get.dart';

import '../../../../src/R.dart';

class CourseScorePage extends StatefulWidget {
  final CourseInfoJson courseInfo;

  /// 三個（或兩個）分頁共用的狀態。頁面在進入時就把所有請求發完，
  /// 所以每個分頁只負責畫自己那一份。
  final CourseDataController controller;

  const CourseScorePage(
    this.courseInfo, {
    required this.controller,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseScorePageState();
}

class _CourseScorePageState extends State<CourseScorePage>
    with AutomaticKeepAliveClientMixin {
  /// null 代表還在載入。
  ///
  /// 請求不能寫進 build()，否則每一次 rebuild（切主題、切語言、鍵盤彈出、上層
  /// setState）都會重新發一次請求。狀態住在 controller 而不是這個 State：
  /// 三個分頁的請求要在進入頁面時一起發出去，而 PageView 只 mount 當前那一個。
  Rxn<Result<MoodleUserGradesEntity>> get _state => widget.controller.score;

  // 沒有 initState 觸發請求：由頁面在進入時一次發完三個（或兩個），
  // 見 CourseDataController.loadAll / CourseDetailController.loadAll。

  Future<void> _load() => widget.controller.loadScore();

  @override
  Widget build(BuildContext context) {
    super.build(context); //如果使用AutomaticKeepAliveClientMixin需要呼叫
    return Container(
      padding: const EdgeInsets.only(top: 10),
      child: ResultView<MoodleUserGradesEntity>(
        state: _state,
        onRetry: _load,
        errorBuilder: (message) => ErrorPage(errorMsg: message),
        builder: buildTree,
      ),
    );
  }

  /// 成績清單。一列就是一個 [MoodleGradeItemEntity]。
  ///
  /// **刻意攤平、不做階層**：grade_items 沒有資料夾標題列，類別只是一列
  /// `itemtype == 'category'` 的類別總分，階層得靠 categoryid 自己重建，而類別
  /// 名稱伺服器根本沒送。與其猜，不如攤平，只保留與語系無關的強調：課程總分
  /// 粗體、類別總分半粗。
  Widget buildTree(MoodleUserGradesEntity scoreData) {
    // 不能用「itemname 是不是空的」當過濾條件：課程總分與類別總分那兩類列，
    // 伺服器送的 itemname 就是 null（Moodle 網頁版是前端自己補字），照名字濾
    // 會讓課程總分整列消失。
    final items = scoreData.gradeItems
        .where((item) => item.hasDisplayableContent)
        .toList();

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => Divider(color: Get.iconColor),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemBuilder: (context, index) => _buildGradeItem(items[index]),
    );
  }

  /// 這一列要顯示的標題。
  ///
  /// 伺服器對課程總分與類別總分不送 itemname，那兩類要由 App 自己補字。判斷一律
  /// 用 itemType，不要比對中文字串——「課程總分」那幾個字是 Moodle 依**使用者的
  /// Moodle 介面語言**產生的，與 App 語系無關，比字串在英文介面下會靜靜失效。
  String _titleOf(MoodleGradeItemEntity item) {
    final name = item.itemName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (item.isCourseTotal) return R.current.courseTotal;
    if (item.isCategoryTotal) return R.current.categoryTotal;
    return "";
  }

  Widget _buildGradeItem(MoodleGradeItemEntity item) {
    return ExpansionTile(
      title: Text(
        _titleOf(item),
        style: TextStyle(height: 1.2, fontWeight: _titleWeight(item)),
      ),
      dense: true,
      clipBehavior: Clip.antiAlias,
      trailing: const Icon(
        CupertinoIcons.chevron_down,
        size: 12,
      ),
      expandedAlignment: Alignment.centerLeft,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // 一律用 *formatted 這一組。實測 graderaw 是 null 而 gradeformatted
        // 有值（學生 token 拿不到原始分數），用原始欄位會整頁空白。
        ..._optionalGradeItem(R.current.score, item.gradeFormatted),
        ..._optionalGradeItem(R.current.percentage, item.percentageFormatted),
        ..._optionalGradeItem(R.current.weight, item.weightFormatted),
        ..._optionalGradeItem(R.current.fullRange, item.rangeFormatted),
        ..._optionalGradeItem(R.current.feedback, item.feedback),
      ],
    );
  }

  /// 課程總分粗體、類別總分半粗，其餘一般。用 itemType 判斷的理由見 [_titleOf]。
  FontWeight? _titleWeight(MoodleGradeItemEntity item) {
    if (item.isCourseTotal) return FontWeight.bold;
    if (item.itemType == "category") return FontWeight.w600;
    return null;
  }

  /// 內容是空的就整列不畫。
  List<Widget> _optionalGradeItem(String title, String content) =>
      _hasContent(content) ? [_gradeItem(title, content)] : const [];

  /// Moodle 對「沒有值」送的是空字串或整串 `&nbsp;`，兩種都要當成空。
  static bool _hasContent(String? content) =>
      (content ?? "").trim().replaceAll("&nbsp;", "").trim().isNotEmpty;

  /// 值仍然走 HtmlWidget：`feedback` 是 HTML（feedbackformat 是 Moodle 的
  /// format id），而且可能含 `<img>`，點下去要能開 PhotoView。
  /// 其餘 `*formatted` 欄位是純文字，交給 HtmlWidget 只是照原樣顯示。
  Widget _gradeItem(String title, String content) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        HtmlWidget(content, textStyle: Get.textTheme.bodyMedium,
            customWidgetBuilder: (element) {
          if (element.localName == 'img') {
            var url = element.attributes["src"] ?? "";
            return FutureBuilder<Uint8List?>(
                future: DioConnector.instance.getData(ConnectorParameter(url)),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: GestureDetector(
                          onTap: () {
                            Get.to(PhotoView(imageData: snapshot.data!));
                          },
                          child: Image.memory(snapshot.data!)),
                    );
                  }
                  // 少了這個分支，下載失敗會永遠停在轉圈。
                  if (snapshot.hasError ||
                      snapshot.connectionState == ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.broken_image_outlined),
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: LoadingPage(
                      isLoading: true,
                      isShowBackground: false,
                    ),
                  );
                });
          }
          return null;
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}
