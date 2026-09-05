import 'package:flutter_app/src/controller/course_table/course_controller.dart';
import 'package:flutter_app/src/enum/course_table_ui_state.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_l10n.dart';

/// CourseController 的欄位初始化會建立 CourseTableControl，
/// 而 CourseTableControl 的 dayStringList 直接讀 R.current，
/// 所以這個檔案的每個測試都要先載入 l10n。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => loadTestL10n());

  group('CourseController.reset', () {
    test('登出後狀態是 fail，不是 loading——否則課表頁會永遠轉圈', () {
      final controller = CourseController();
      controller.isLoading.value = CourseTableUIState.success;

      controller.reset();

      // 登出只 jumpToPage(0) 跳回課表頁，而 Get.put 對已註冊的 controller 是
      // no-op，onInit 不會再跑，沒有東西會把 loading 推進下一個狀態；重新整理鈕
      // 與 CourseMenu 又都包在 Visibility(visible: account.isNotEmpty) 裡，
      // 停在 loading 就是把使用者鎖死在轉圈畫面。
      // fail 會讓 BasePage 顯示 ErrorPage，未登入時提示登入。
      expect(controller.isLoading.value, CourseTableUIState.fail);
    });

    test('登出後不留下上一位使用者的課表與學號', () {
      final controller = CourseController();
      controller.studentId.value = 'B10000000';
      controller.courseInfoList.add(CourseMainInfoJson());

      controller.reset();

      expect(controller.courseTableData, isNull);
      expect(controller.studentId.value, isEmpty);
      expect(controller.courseInfoList, isEmpty);
    });
  });
}
