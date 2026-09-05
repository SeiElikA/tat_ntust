import 'package:flutter/material.dart';
import 'package:flutter_app/src/controller/course_data/course_data_controller.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_gradereport_get_grade_items.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/store/cache_store.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/ui/pages/course_data/screen/course_score_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 成績頁的畫面規格，資料來自 `gradereport_user_get_grade_items`。
///
/// 課程總分只能看結構化的 `itemtype == 'course'`，不可以比對項目名稱：那串字是
/// Moodle 依**使用者的 Moodle 介面語言**產生的（get_string('coursetotal',
/// 'grades')），與 App 的語系無關，比對文字的話同學把 Moodle 介面切成英文就會
/// 靜靜地不再加粗。所以下面刻意用**英文**的項目名稱來測課程總分。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestL10n();
  });

  setUp(() {
    resetAppStatics();
    // 離線時 run() 有快取就直接回 Stale，不碰網路，因此整個測試不需要網路。
    ConnectivityProbe.instance = FakeConnectivityProbe(online: false);
    Model.instance.setAccount('B10000000');
  });

  tearDown(() {
    ConnectivityProbe.instance = const PlatformConnectivityProbe();
  });

  CourseInfoJson courseInfoOf(String id) => CourseInfoJson(
        main: CourseMainInfoJson(course: CourseMainJson(id: id)),
      );

  /// 把成績直接放進 `cache_moodle_score`，讓離線的 run() 命中它。
  /// 這裡刻意走正式路徑上的 [decodeCachedScore]，不另外寫一份 decoder。
  Future<void> seedScore(String courseId, MoodleUserGradesEntity grades) =>
      CacheStore.instance.write<MoodleUserGradesEntity>(
        CacheKey<MoodleUserGradesEntity>(
          'cache_moodle_score',
          courseId,
          decode: decodeCachedScore,
        ),
        grades,
      );

  Future<void> pumpScorePage(WidgetTester tester, String courseId) async {
    // 狀態現在住在 CourseDataController 裡：正式路徑上是 CourseDataPage
    // 在進入時一次發完三個分頁的請求，分頁自己不發。
    final controller = CourseDataController(courseId);
    await controller.loadScore();
    // 正式路徑上這一頁掛在 CourseDataPage 的 Scaffold 底下；
    // ExpansionTile 內部的 ListTile 需要 Material 祖先。
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
          body: CourseScorePage(courseInfoOf(courseId),
              controller: controller)),
    ));
    await tester.pumpAndSettle();
  }

  /// ExpansionTile 的內容要展開才會被建出來。
  Future<void> expand(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  FontWeight? weightOfTitle(WidgetTester tester, String title) =>
      tester.widget<Text>(find.text(title)).style?.fontWeight;

  MoodleUserGradesEntity gradesWith(List<MoodleGradeItemEntity> items) =>
      MoodleUserGradesEntity(
        courseId: 28914,
        userId: 5252,
        userFullName: '測試學生',
        maxDepth: 2,
        gradeItems: items,
      );

  testWidgets('Moodle 介面是英文時，課程總分仍然加粗（舊行為在這裡不會加粗）', (tester) async {
    await seedScore(
      'AT1001',
      gradesWith([
        MoodleGradeItemEntity(
          id: 1,
          itemName: 'Quiz 1',
          itemType: 'mod',
          gradeFormatted: '90.00',
        ),
        MoodleGradeItemEntity(
          id: 2,
          itemName: 'Course total',
          itemType: 'course',
          gradeFormatted: '85.00',
        ),
      ]),
    );

    await pumpScorePage(tester, 'AT1001');

    expect(weightOfTitle(tester, 'Course total'), FontWeight.bold);
    expect(weightOfTitle(tester, 'Quiz 1'), isNull);
  });

  testWidgets('類別總分是半粗，不會被誤判成課程總分', (tester) async {
    await seedScore(
      'AT1002',
      gradesWith([
        MoodleGradeItemEntity(
          id: 1,
          itemName: 'Category total',
          itemType: 'category',
          gradeFormatted: '70.00',
        ),
        MoodleGradeItemEntity(
          id: 2,
          itemName: 'Course total',
          itemType: 'course',
          gradeFormatted: '85.00',
        ),
      ]),
    );

    await pumpScorePage(tester, 'AT1002');

    expect(weightOfTitle(tester, 'Category total'), FontWeight.w600);
    expect(weightOfTitle(tester, 'Course total'), FontWeight.bold);
  });

  testWidgets('展開後顯示的是 *formatted 那一組（graderaw 是 null 也不會空白）', (tester) async {
    // moodle2.ntust.edu.tw 實測：學生 token 拿不到 graderaw，
    // 只有 gradeformatted / percentageformatted / weightformatted /
    // rangeformatted 有值。用原始數值欄位畫的話整頁會是空的。
    await seedScore(
      'AT1003',
      gradesWith([
        MoodleGradeItemEntity(
          id: 1,
          itemName: '期中考',
          itemType: 'mod',
          gradeRaw: null,
          gradeFormatted: '90.00',
          percentageFormatted: '90.00 %',
          weightFormatted: '30.00 %',
          rangeFormatted: '0-100',
          feedback: '寫得不錯',
          feedbackFormat: 1,
        ),
      ]),
    );

    await pumpScorePage(tester, 'AT1003');
    await expand(tester, '期中考');

    // 標籤是純 Text，值走 HtmlWidget（回饋可能含 <img>），所以要 findRichText。
    for (final label in ['成績', '百分比', '權量', '全距', '意見反饋']) {
      expect(find.text(label), findsOneWidget, reason: '缺少 $label 這一列');
    }
    expect(find.text('90.00', findRichText: true), findsOneWidget);
    expect(find.text('90.00 %', findRichText: true), findsOneWidget);
    expect(find.text('30.00 %', findRichText: true), findsOneWidget);
    expect(find.text('0-100', findRichText: true), findsOneWidget);
    expect(find.text('寫得不錯', findRichText: true), findsOneWidget);
  });

  testWidgets('空字串與整串 &nbsp; 的欄位整列不畫', (tester) async {
    await seedScore(
      'AT1004',
      gradesWith([
        MoodleGradeItemEntity(
          id: 1,
          itemName: '作業一',
          itemType: 'mod',
          gradeFormatted: '-',
          percentageFormatted: '',
          weightFormatted: '10.00 %',
          rangeFormatted: '0-100',
          // Moodle 對「沒有回饋」送的就是這一串，不是空字串。
          feedback: '&nbsp;',
        ),
      ]),
    );

    await pumpScorePage(tester, 'AT1004');
    await expand(tester, '作業一');

    expect(find.text('成績'), findsOneWidget);
    expect(find.text('權量'), findsOneWidget);
    expect(find.text('全距'), findsOneWidget);
    expect(find.text('百分比'), findsNothing, reason: '空字串的百分比不該畫出標籤');
    expect(find.text('意見反饋'), findsNothing, reason: '整串 &nbsp; 等於沒有回饋');
  });

  testWidgets('itemname 是 null 的項目直接跳過，不會畫出無名的一列', (tester) async {
    await seedScore(
      'AT1005',
      gradesWith([
        MoodleGradeItemEntity(id: 1, itemType: 'mod', gradeFormatted: '60.00'),
        MoodleGradeItemEntity(
          id: 2,
          itemName: '課程總分',
          itemType: 'course',
          gradeFormatted: '85.00',
        ),
      ]),
    );

    await pumpScorePage(tester, 'AT1005');

    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(find.text('課程總分'), findsOneWidget);
  });
}
