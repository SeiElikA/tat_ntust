import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/connector/core/connector_parameter.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

/// 建立這頁專用的 [WidgetFactory]。
///
/// 用具名 top-level 函式而非匿名 closure：`factoryBuilder` 每次 rebuild 都拿到
/// 同一個 tear-off（身分穩定），測試也能不啟動整個頁面就驗證 `webView` 是關的。
WidgetFactory courseHtmlWidgetFactory() => _NoEmbeddedWebViewFactory();

/// 關掉「`<iframe>` 自動變成內嵌 WebView」這個預設行為。
///
/// flutter_widget_from_html 的預設 [WidgetFactory] 混入 `WebViewFactory`，
/// `webView` 與 `webViewJs` 預設都是 true：教材 HTML 裡只要有一個
/// `<iframe src="...">`，使用者什麼都還沒點，畫面上就有一個**開著 JavaScript**
/// 的 WebView 在跑第三方頁面。這頁的 HTML 由課程上任何有上傳權限的人提供，
/// 不該有這種免點擊的執行環境。
///
/// 關掉之後 iframe 會退化成 `buildWebViewLinkOnly` 產生的可點連結，那一點
/// 同樣要過 [CourseHtmlPage.handleTapUrl] 的 scheme 白名單。
class _NoEmbeddedWebViewFactory extends WidgetFactory {
  @override
  bool get webView => false;
}

/// 顯示 Moodle 上的 HTML 教材。
///
/// 這頁的輸入（遠端 HTML 原文）等同不可信：內容由課程裡任何有上傳權限的人
/// 提供，而算繪結果會落在一個有使用者身分的 App 裡。因此有兩道防線，
/// 拿掉之前請先讀懂它們各自擋的是什麼：
///   1. [_NoEmbeddedWebViewFactory]：擋掉不需使用者互動就會執行的 iframe。
///   2. [handleTapUrl] / [isWebViewSafeUrl]：擋掉非 http(s) 的連結。
class CourseHtmlPage extends StatefulWidget {
  const CourseHtmlPage({super.key, required this.ap});

  final Modules ap;

  /// 這個連結能不能交給 App 內的 WebView 開？只放行 http / https。
  ///
  /// 擋掉的例子：`javascript:`（[RouteUtils.toWebViewPage] 開的
  /// InAppWebViewPage 沒有關 JavaScript，等於讓教材作者指定一段程式碼在
  /// WebView 裡跑）、`file:`（讀 App 沙箱內的本機檔案）、`data:`（夾帶整份含
  /// script 的 HTML 當頁面）、`intent:` 等自訂 scheme（喚起其他 App）。
  ///
  /// InAppWebViewPage 還會把 App cookie jar 中對應網域的 cookie 灌進 WebView，
  /// 所以「開什麼網址」是帶身分的操作，不是單純顯示。
  static bool isWebViewSafeUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      // 沒有 scheme 代表 HtmlWidget 沒能用 baseUrl 解析成絕對網址（contents
      // 為空、baseUrl 為 null）；這種殘缺字串只會開出壞掉的頁面。
      return false;
    }
    // Dart 的 Uri 已經把 scheme 正規化成小寫；再 toLowerCase 一次是不想讓
    // 這條判斷依賴別人的正規化行為。
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  /// [HtmlWidget.onTapUrl] 的實作。
  ///
  /// **回傳值的語意跟直覺相反，改之前務必先讀這段。** `UrlLauncherFactory` 的
  /// 規則是：callback 回傳 false 就 fallback 去呼叫 url_launcher 的
  /// `launchUrl(Uri.parse(url))`。所以「擋下來的連結回傳 false」不是擋掉，而是
  /// 升級成交給**作業系統**開，`tel:`、`intent:`、各種自訂 scheme 都會被喚起。
  /// 擋掉的情況**也要回傳 true**，意思是「這個 tap 我處理完了，處理方式是忽略」。
  ///
  /// 已知取捨：頁內錨點（`#section`）會被當成一般連結開新 WebView 而不是捲動；
  /// 支援錨點得回傳 false，那條路就是上面的 launchUrl fallback。
  static bool handleTapUrl(
    String url, {
    required void Function(String url) openInWebView,
  }) {
    // 交出去的必須是 trim 過的同一個字串：isWebViewSafeUrl 驗的是 url.trim()，
    // 直接遞原字串等於「用 A 驗證、拿 B 使用」——前後有空白的網址通得過檢查，
    // 之後 Uri.parse 拋的 FormatException 被 WebUri 吞成空 Uri，開出一頁空白。
    final target = url.trim();
    if (isWebViewSafeUrl(target)) {
      openInWebView(target);
    } else {
      Log.d("blocked non-http(s) link in course html: $url");
    }
    return true;
  }

  @override
  State<CourseHtmlPage> createState() => _CourseHtmlPageState();
}

class _CourseHtmlPageState extends State<CourseHtmlPage> {
  /// 只取一次。future 若直接寫在 build 裡，每次 rebuild 都會重打網路請求，
  /// 畫面也會閃回 loading。
  late final Future<String> _pageData = _getPageData();

  /// 給 [HtmlWidget.baseUrl] 用的文件基底位址。
  ///
  /// 沒有 baseUrl 時，`<a href="page2.html">` 這類相對連結會以沒有 scheme 的
  /// 殘缺字串交給 onTapUrl，變成開不起來的 WebView。
  ///
  /// 刻意用**沒有 token 的**原始 fileurl 當 base，而不是
  /// [MoodleWebApiConnector.fileUrlWithToken] 的結果：避免 `?token=` 被帶進
  /// 任何由教材內容解析出來的網址。
  late final Uri? _baseUrl = widget.ap.contents.isEmpty
      ? null
      : Uri.tryParse(widget.ap.contents.first.fileurl);

  Future<String> _getPageData() async {
    // contents 為空時這裡會拋 StateError，但因為身處 async 函式，
    // 例外會被收進 Future，由下面的 FutureBuilder 轉成 ErrorPage。
    final params = MoodleWebApiConnector.fileUrlWithToken(
        widget.ap.contents.first.fileurl);
    final html =
        await DioConnector.instance.getDataByGet(ConnectorParameter(params));
    return html;
  }

  void _openInWebView(String url) {
    // fire-and-forget：這個 Future 要等使用者從 WebView 返回才完成，
    // 在 tap handler 裡沒有等它的意義。
    unawaited(RouteUtils.toWebViewPage(widget.ap.name, url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: baseAppbar(title: widget.ap.name),
      body: FutureBuilder<String>(
        future: _pageData,
        builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Text("");
          }
          final html = snapshot.data;
          if (html == null) {
            return const ErrorPage();
          }
          return Padding(
            padding: const EdgeInsets.all(10.0),
            child: HtmlWidget(
              html,
              baseUrl: _baseUrl,
              factoryBuilder: courseHtmlWidgetFactory,
              textStyle: const TextStyle(height: 1.2),
              renderMode: RenderMode.column,
              onTapUrl: (String url) => CourseHtmlPage.handleTapUrl(
                url,
                openInWebView: _openInWebView,
              ),
            ),
          );
        },
      ),
    );
  }
}
