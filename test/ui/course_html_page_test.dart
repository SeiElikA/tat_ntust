import 'dart:io';

import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_html_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// `CourseHtmlPage` 的連結防線測試。
///
/// 這頁把 Moodle 的 HTML 教材原文丟給 `HtmlWidget` 算繪，而那份 HTML 是課程上
/// 任何有上傳權限的人寫的，所以兩道防線都不能少：
///
///   1. `onTapUrl` 必須經過白名單只放行 http(s)，否則教材裡寫什麼就進 App 內的
///      WebView（那個 WebView 開著 JavaScript，還會灌 App cookie jar 的 cookie）。
///   2. `HtmlWidget` 的 factory 必須關掉 `webView`（預設是 true），
///      否則教材裡的 `<iframe>` 不必使用者點就會變成一個在跑的 WebView。
///
/// 這裡刻意測靜態函式而不是 pump 整個頁面：要凍結的是「哪些 URL 准進 WebView」
/// 與「擋掉時回傳什麼」，而頁面本體要先發一個網路請求才畫得出 HtmlWidget。
void main() {
  group('CourseHtmlPage.isWebViewSafeUrl', () {
    test('http 與 https 放行', () {
      expect(
        CourseHtmlPage.isWebViewSafeUrl('https://moodle.ntust.edu.tw/x.pdf'),
        isTrue,
      );
      expect(CourseHtmlPage.isWebViewSafeUrl('http://example.com'), isTrue);
    });

    test('javascript: 必須擋掉（舊行為：原樣丟進 WebView）', () {
      expect(
        CourseHtmlPage.isWebViewSafeUrl('javascript:alert(1)'),
        isFalse,
      );
    });

    test('scheme 大小寫混寫也要擋，不能靠大小寫繞過', () {
      expect(CourseHtmlPage.isWebViewSafeUrl('JaVaScRiPt:alert(1)'), isFalse);
    });

    test('前後空白不能用來繞過 scheme 檢查', () {
      expect(
          CourseHtmlPage.isWebViewSafeUrl('   javascript:alert(1)'), isFalse);
      // 反過來，合法網址被空白包住時仍要放行。
      expect(CourseHtmlPage.isWebViewSafeUrl('  https://a.example  '), isTrue);
    });

    test('data: / file: / 自訂 scheme 一律擋掉', () {
      expect(
        CourseHtmlPage.isWebViewSafeUrl(
            'data:text/html,<script>alert(1)</script>'),
        isFalse,
      );
      expect(CourseHtmlPage.isWebViewSafeUrl('file:///etc/passwd'), isFalse);
      expect(
        CourseHtmlPage.isWebViewSafeUrl(
            'intent://scan#Intent;scheme=zxing;end'),
        isFalse,
      );
      expect(CourseHtmlPage.isWebViewSafeUrl('tel:0212345678'), isFalse);
    });

    test('沒有 scheme 的殘缺字串擋掉（baseUrl 沒解析成功的相對路徑）', () {
      expect(CourseHtmlPage.isWebViewSafeUrl('page2.html'), isFalse);
      expect(CourseHtmlPage.isWebViewSafeUrl('#section'), isFalse);
      expect(CourseHtmlPage.isWebViewSafeUrl(''), isFalse);
    });
  });

  group('CourseHtmlPage.handleTapUrl', () {
    test('http(s) 連結才會真的開 WebView', () {
      final opened = <String>[];
      final handled = CourseHtmlPage.handleTapUrl(
        'https://moodle.ntust.edu.tw/a.html',
        openInWebView: opened.add,
      );

      expect(opened, ['https://moodle.ntust.edu.tw/a.html']);
      expect(handled, isTrue);
    });

    test('被擋下的連結不會開 WebView（舊行為：任何 scheme 都會開）', () {
      final opened = <String>[];
      CourseHtmlPage.handleTapUrl(
        'javascript:alert(1)',
        openInWebView: opened.add,
      );

      expect(opened, isEmpty);
    });

    test('擋下來時仍要回傳 true，否則 fwfh 會 fallback 去 launchUrl', () {
      // 最容易被「順手改乾淨」而破功的一條。fwfh 的 WidgetFactory 混入
      // UrlLauncherFactory，callback 回傳 false 時它會改呼叫 url_launcher 的
      // launchUrl(Uri.parse(url))——回傳 false 不是擋掉，而是把 javascript: /
      // intent: / tel: 升級成交給作業系統開。
      final opened = <String>[];
      for (final url in [
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'file:///etc/passwd',
        'intent://scan#Intent;scheme=zxing;end',
        'page2.html',
      ]) {
        expect(
          CourseHtmlPage.handleTapUrl(url, openInWebView: opened.add),
          isTrue,
          reason: '$url 被擋下時必須回報「已處理」，不能讓 fwfh 交給 launchUrl',
        );
      }
      expect(opened, isEmpty);
    });
  });

  group('CourseHtmlPage 的 HtmlWidget factory', () {
    test('關掉 iframe 自動變成內嵌 WebView（舊行為：預設 webView == true）', () {
      // 這是唯一一道「不需使用者互動」的防線：教材裡只要有一個 <iframe>，
      // 預設 factory 就會生出一個開著 JavaScript 的 WebView 在跑第三方頁面。
      expect(courseHtmlWidgetFactory().webView, isFalse);
    });
  });

  group('CourseHtmlPage 的防線接線', () {
    // 上面那些測試驗的是「防線本身正確」，對「有人把防線拆掉不接了」完全無感
    // ——繞過 handleTapUrl 直接開 WebView 的話它們照樣全綠。所以這裡掃一次
    // 原始碼確認接線還在，刻意只比對寬鬆的片段，免得被 dart format 的換行影響。
    late final String source = File(
      'lib/ui/pages/course_data/screen/sub_page/course_html_page.dart',
    ).readAsStringSync();

    test('onTapUrl 仍然走 handleTapUrl 的白名單', () {
      expect(
        source.contains('handleTapUrl('),
        isTrue,
        reason: 'onTapUrl 必須經過 handleTapUrl，不能直接把 URL 交給 WebView',
      );
      expect(
        source.contains('onTapUrl:'),
        isTrue,
        reason: '拿掉 onTapUrl 會讓 fwfh 直接用 url_launcher 開任何 scheme',
      );
    });

    test('HtmlWidget 仍然使用關掉 iframe WebView 的 factory', () {
      expect(
        source.contains('factoryBuilder: courseHtmlWidgetFactory'),
        isTrue,
        reason: '少了這行，教材裡的 <iframe> 會自動變成開著 JS 的 WebView',
      );
    });

    test('HtmlWidget 仍然設定 baseUrl', () {
      // baseUrl 是相對連結能被解析成絕對網址的前提；沒有它，
      // 相對連結會以沒有 scheme 的殘缺字串進到 onTapUrl。
      expect(source.contains('baseUrl: _baseUrl'), isTrue);
    });
  });
}
