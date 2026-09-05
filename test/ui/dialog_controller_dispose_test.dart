import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/ui/pages/course_table/modal/course_detail_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 對話框裡的 TextEditingController 必須由 StatefulWidget 的 State 持有並釋放。
/// 在方法裡 new 一個區域變數再塞進 Get.dialog 的 widget 樹，沒有人 dispose，
/// 每開一次就漏一個。
///
/// 測試摸不到 private 欄位，所以從畫面上的 EditableText 拿到同一個物件，
/// 等對話框真的被移除之後再 dispose 一次：ChangeNotifier 在 debug mode 下
/// 重複 dispose 會丟 FlutterError，那就是「第一次已經被釋放」的證據。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestL10n();
    // FileItem 的副標題會走 FileUtils.formatTime -> DateFormat，
    // 沒有先初始化 locale 資料會直接丟 LocaleDataException。
    await initializeDateFormatting();
  });

  TextEditingController currentController(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller;

  void expectAlreadyDisposed(TextEditingController controller) {
    expect(
      () => controller.dispose(),
      throwsA(isA<FlutterError>()),
      reason: '對話框關掉之後 TextEditingController 必須已經被 dispose',
    );
  }

  group('CourseDetailDialog 的課程代碼編輯框', () {
    setUp(resetAppStatics);

    testWidgets('關閉後 controller 已被 dispose', (tester) async {
      final courseInfo = CourseInfoJson(
        main: CourseMainInfoJson(
          course: CourseMainJson(name: '測試課程', id: 'AT1234', select: false),
        ),
      );

      await tester.pumpWidget(
        GetMaterialApp(
          home: Material(
            child: CourseDetailDialog(
              courseInfo: courseInfo,
              time: '一_1 2',
              onDetailTap: () {},
              onRemoveTap: () {},
              onMoodleTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('${R.current.courseId} : AT1234'));
      await tester.pumpAndSettle();

      final controller = currentController(tester);
      expect(controller.text, 'AT1234');

      await tester.tap(find.text(R.current.cancel));
      await tester.pumpAndSettle();

      expectAlreadyDisposed(controller);
    });
  });
}

