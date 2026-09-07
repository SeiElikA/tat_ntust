import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/util/rich_editor_bridge_utils.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// [MoodleRichEditor] 的遙控器。頁面拿它下指令、取內容，widget 本身不知道
/// 那些內容是什麼意思。
class MoodleRichEditorController {
  _MoodleRichEditorState? _state;

  bool get isReady => _state?._ready ?? false;

  void exec(EditorCommand command) => _state?._exec(command);

  void setSourceMode(bool on) => _state?._setSourceMode(on);

  /// 編輯器現在的內容；還沒接上時回 null（呼叫端不可以把 null 當成空內容
  /// 送出去——那會把整篇貼文清掉）。
  Future<String?> content() async => _state?._content();
}

/// `assets/editor/` 那一頁的殼。**HTML 進、HTML 出，沒有別的**：不認識
/// Moodle、不改網址、不判斷格式。
///
/// 它在 `flutter_test` 底下幾乎測不到（平台視圖畫不出來），所以它裡面能少放
/// 一點邏輯就少放一點——判斷與改寫全部住在 `lib/src/util/` 的純函式裡。
class MoodleRichEditor extends StatefulWidget {
  const MoodleRichEditor({
    super.key,
    required this.initialHtml,
    required this.controller,
    required this.onStateChanged,
    required this.onChanged,
    required this.onReady,
    required this.onLoadFailed,
  });

  /// 進到 contenteditable 的 HTML。內嵌圖片的網址必須已經是可以直接載入的
  /// 樣子——這一層不會替任何網址加憑證。
  final String initialHtml;

  final MoodleRichEditorController controller;

  /// 游標處生效的格式（[RichEditorBridgeUtils.parseEditorState] 的輸出）。
  final ValueChanged<Set<String>> onStateChanged;

  /// 使用者真的動過內容（`input`，不是移動游標）。放棄草稿的確認靠它。
  final VoidCallback onChanged;

  final VoidCallback onReady;

  /// 握手一直沒來。頁面要據此換成 inline 錯誤，而不是留一塊白。
  final VoidCallback onLoadFailed;

  /// 資產頁的路徑。`assets/editor/` 有列進 pubspec 的 flutter.assets。
  static const String assetPath = 'assets/editor/editor.html';

  /// 從載入到握手的等待上限。超過就當成載不起來。
  static const Duration readyTimeout = Duration(seconds: 10);

  @override
  State<MoodleRichEditor> createState() => _MoodleRichEditorState();
}

class _MoodleRichEditorState extends State<MoodleRichEditor> {
  InAppWebViewController? _webView;
  Timer? _readyTimer;
  bool _ready = false;
  bool _failed = false;

  /// 平台實作沒註冊時（`flutter test`、或還沒支援的平台）不畫 WebView：
  /// 那不是「空的編輯器」，是載不起來，走同一條失敗路徑講同一句話。
  bool get _platformAvailable => InAppWebViewPlatform.instance != null;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    if (!_platformAvailable) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _reportFailure('platform unavailable'));
      return;
    }
    _readyTimer =
        Timer(MoodleRichEditor.readyTimeout, () => _reportFailure('timeout'));
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    if (widget.controller._state == this) widget.controller._state = null;
    super.dispose();
  }

  void _reportFailure(String why) {
    if (_ready || _failed || !mounted) return;
    _failed = true;
    Log.e('rich editor failed to load: $why');
    widget.onLoadFailed();
  }

  Future<void> _exec(EditorCommand command) async {
    if (!_ready) return;
    await _webView?.evaluateJavascript(
        source: RichEditorBridgeUtils.buildCommandCall(command));
  }

  Future<void> _setSourceMode(bool on) async {
    if (!_ready) return;
    await _webView?.evaluateJavascript(
        source: 'window.__tatEditor.setSourceMode($on);');
  }

  Future<String?> _content() async {
    if (!_ready) return null;
    final raw = await _webView?.evaluateJavascript(
        source: 'window.__tatEditor.getContent();');
    // 橋接回來的東西是不可信的資料：只當字串用，不再拼回任何一段 JS。
    return raw is String ? raw : null;
  }

  Future<void> _onReady() async {
    if (_failed || _ready || !mounted) return;
    _readyTimer?.cancel();
    _ready = true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    await _webView?.evaluateJavascript(
        source: 'document.documentElement.setAttribute('
            '"data-theme", "${dark ? 'dark' : 'light'}");');
    // 貼文 HTML 進到頁面的唯一途徑：包成 JS 字串常值，絕不字串相接。
    await _webView?.evaluateJavascript(
        source: RichEditorBridgeUtils.buildSetContentCall(widget.initialHtml));
    if (mounted) widget.onReady();
  }

  @override
  Widget build(BuildContext context) {
    if (!_platformAvailable) return const SizedBox.shrink();
    return InAppWebView(
      initialFile: MoodleRichEditor.assetPath,
      initialSettings: InAppWebViewSettings(
        // 這一頁是 file://。開了這兩個等於讓貼文作者寫的內容讀得到 App
        // 沙盒裡的檔案。
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        javaScriptCanOpenWindowsAutomatically: false,
        mediaPlaybackRequiresUserGesture: true,
        supportZoom: false,
        transparentBackground: true,
        // 沒有這一顆，貼文裡的 <a> 被點到就會把整個編輯器導航走，
        // 使用者還沒存的草稿跟著消失，而且沒有回頭路。
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (controller) {
        _webView = controller;
        controller.addJavaScriptHandler(
          handlerName: 'tatEditorReady',
          callback: (_) => unawaited(_onReady()),
        );
        controller.addJavaScriptHandler(
          handlerName: 'tatEditorInput',
          callback: (_) {
            widget.onChanged();
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'tatEditorState',
          callback: (args) {
            widget.onStateChanged(RichEditorBridgeUtils.parseEditorState(
                args.isEmpty ? null : args.first));
            return null;
          },
        );
      },
      // 只有資產本身那一次放行，其他全部擋下來。iOS 連初次載入都會經過
      // 這裡，所以不可以寫成「一律 CANCEL」。
      shouldOverrideUrlLoading: (controller, action) async {
        final uri = action.request.url;
        final isAsset = uri != null &&
            uri.scheme == 'file' &&
            uri.path.endsWith('/editor.html');
        return isAsset
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onReceivedError: (controller, request, error) =>
          _reportFailure('${error.type}'),
      // CSP 違規只會出現在 console，看不到就等於這一層防護悄悄失效了。
      onConsoleMessage: (controller, message) =>
          Log.d('rich editor console: ${message.message}'),
    );
  }
}
