import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `HtmlUtils.clean` 的 sink 盤點守門測試。
///
/// html_utils.dart 的文件註解說「新增 sink 前請重跑這個盤點」，但那句話本身
/// 沒有任何強制力：真的有人把 `Modules.name` 接到 `HtmlWidget` 上時，
/// 不會有任何測試變紅，只會有一段沒人重讀的註解。
/// 而 html_utils_sink_contract_test.dart 只斷言 `clean()` 的字串輸出，
/// 同樣管不到「下游多了一個 HTML sink」。
///
/// 這個檔案負責把那份人工紀律變成 CI 會擋的檢查，方式是把註解裡的盤點結果
/// 寫成可執行的清單：清單一旦跟現實不符就失敗，強迫改動的人重跑盤點。
///
/// 它不是型別安全，只是原始碼掃描——但 `clean()` 回傳的是 `String`，
/// 而 `Modules.name` 也是 `String`，型別系統本來就分不出「這個字串是不是
/// 還原過實體的」。要真的用型別擋，得替 `Modules.name` 換一個 wrapper 型別，
/// 那會擴散到 json_serializable 產生的程式碼與整個 model 層，成本不成比例。
void main() {
  List<File> libDartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// 用 `/` 統一路徑分隔，避免在 Windows 上比對失敗。
  String normalize(String path) => path.replaceAll(r'\', '/');

  test('HtmlUtils.clean 的呼叫端清單沒有變動', () {
    // 盤點結果：只有這一個呼叫端，它把 Moodle 課程模組名（Modules.name）
    // 的 HTML 實體還原成純文字。
    const expected = {'lib/src/connector/moodle_webapi_connector.dart'};

    final actual = <String>{
      for (final file in libDartFiles())
        if (file.readAsStringSync().contains('HtmlUtils.clean('))
          normalize(file.path),
    };

    expect(
      actual,
      expected,
      reason: '''
HtmlUtils.clean 的呼叫端變了。

clean() 是 escape 的反向操作：它會把 `&lt;script&gt;` 還原成 `<script>`，
所以每一個呼叫端都有義務保證輸出只流進純文字 sink（Text、AppBar 標題……）。

請重跑 html_utils.dart 註解裡的盤點：追一次新呼叫端的所有下游，確認沒有任何
一條路徑通往 HtmlWidget、WebView 或檔案路徑，然後更新該註解與這裡的清單。''',
    );
  });

  test('HtmlWidget（HTML sink）出現的檔案清單沒有變動', () {
    // 盤點結果，這四個檔案吃的分別是：
    // - course_info_page：ap.description（未經 clean 的 Moodle 原文）
    // - course_html_page：遠端 HTML 教材原文
    // - course_score_page：成績項目的老師回饋（gradeitems[].feedback，帶 <img>）
    // - course_announcement_detail_page：論壇貼文 HTML
    // 沒有任何一個吃 clean() 的輸出。
    const expected = {
      'lib/ui/pages/course_data/screen/course_score_page.dart',
      'lib/ui/pages/course_data/screen/sub_page/course_announcement_detail_page.dart',
      'lib/ui/pages/course_data/screen/sub_page/course_html_page.dart',
      'lib/ui/pages/course_data/screen/sub_page/course_info_page.dart',
    };

    final actual = <String>{
      for (final file in libDartFiles())
        if (file.readAsStringSync().contains('HtmlWidget('))
          normalize(file.path),
    };

    expect(
      actual,
      expected,
      reason: '''
lib 底下的 HTML sink 清單變了。

這條測試就是 html_utils.dart 註解裡那句「新增 sink 前請重跑這個盤點」的
可執行版本。新增或移除 HtmlWidget 本身不是錯，但必須確認新的那一個
**不是**吃 HtmlUtils.clean() 的輸出（典型就是 Modules.name），
確認完再把檔案加進上面的清單。''',
    );
  });

  test('沒有任何 HtmlWidget 直接吃 Modules.name', () {
    // 上一條測「有沒有新的 sink」，這條測「sink 有沒有接上那條資料」：
    // clean() 過的模組名被拿去當 HTML 算繪。
    final htmlWidgetFirstArg = RegExp(r'HtmlWidget\(\s*([^,)]*)');
    final modulesName = RegExp(r'^(widget\.)?(ap|module|modules)\.name$');

    final offenders = <String>[];
    for (final file in libDartFiles()) {
      final source = file.readAsStringSync();
      for (final match in htmlWidgetFirstArg.allMatches(source)) {
        final firstArg = match.group(1)!.trim();
        if (modulesName.hasMatch(firstArg)) {
          offenders.add('${normalize(file.path)}: HtmlWidget($firstArg)');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '''
Modules.name 被當成 HTML 餵進 HtmlWidget 了。

Modules.name 在 moodle_webapi_connector.getCourseDirectory 裡經過
HtmlUtils.clean()，也就是說裡面的 `&lt;script&gt;` 已經被還原成 `<script>`。
它只能進純文字 sink。要顯示課名請用 Text；要顯示 HTML 請改用沒有 clean 過的
欄位（例如 description）。''',
    );
  });
}
