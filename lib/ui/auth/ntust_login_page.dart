import 'dart:convert';


import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/service/cookie_bridge.dart';
import 'package:flutter_app/src/enum/ntust_login_status.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/connector/ntust_connector.dart';
import 'package:flutter_app/ui/other/my_progress_dialog.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:html/parser.dart';

class LoginNTUSTPage extends StatefulWidget {
  final String username;
  final String password;

  const LoginNTUSTPage({
    required this.username,
    required this.password,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _LoginNTUSTPageState();
}

class _LoginNTUSTPageState extends State<LoginNTUSTPage> {
  final cookieManager = CookieManager.instance();
  final cookieJar = DioConnector.instance.cookiesManager;
  final WebUri ntustLoginUri = WebUri(NTUSTConnector.ntustLoginUrl);
  late InAppWebViewController webView;
  bool showDialog = true;
  Widget dialog = MyProgressDialog.dialog(R.current.loginNTUST);

  /// 這個頁面只能結束一次。
  ///
  /// onLoadStop 每次載入完成都會觸發，登入成功後的 client-side 導向會讓它在
  /// 同一次登入裡再觸發一遍；不擋住的話第二個 Get.back 會把這頁**底下那一頁**
  /// 也 pop 掉。
  bool _finished = false;

  void _finish(Map<String, dynamic> result) {
    if (_finished) return;
    _finished = true;
    Get.back(result: result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${R.current.login}..."),
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            InAppWebView(
              initialUrlRequest: URLRequest(url: ntustLoginUri),
              onWebViewCreated: (InAppWebViewController controller) {
                webView = controller;
              },
              onLoadStop: (InAppWebViewController controller, Uri? url) async {
                if (url == ntustLoginUri) {
                  await webView.evaluateJavascript(
                      source:
                          'document.getElementsByName("UserName")[0].value = ${jsonEncode(widget.username)};');
                  await webView.evaluateJavascript(
                      source:
                          'document.getElementsByName("Username")[0].value = ${jsonEncode(widget.username)};');
                  await webView.evaluateJavascript(
                      source:
                          'document.getElementsByName("Password")[0].value = ${jsonEncode(widget.password)};');
                  await webView.evaluateJavascript(
                      source: 'document.getElementById("btnLogIn").click();');
                  await webView.evaluateJavascript(
                      source:
                          'document.getElementById("loginButton").click();');
                  await Future.delayed(const Duration(seconds: 5));
                  if (mounted) {
                    setState(() {
                      showDialog = false;
                    });
                    MyToast.show(R.current.needValidateCaptcha);
                  }
                } else {
                  if (_finished) return;
                  // 這裡不可以先清 Dio jar：清空由 CookieBridge 在寫入前做，
                  // 且只有真的拿到 cookie 才清，否則登入失敗會把還能用的舊
                  // session 一起清掉，變成完全登出。
                  String? result = await webView.getHtml();
                  var tagNode = parse(result);
                  var nodes = tagNode
                      .getElementsByClassName("validation-summary-errors");
                  if (nodes.length == 1) {
                    _finish({
                      "status": NTUSTLoginStatus.fail,
                      "message": nodes[0].text.replaceAll("\n", "")
                    });
                  } else {
                    // 鏡射邏輯（網域改寫、secure 旗標保留、先清空再寫入）只有
                    // CookieBridge 一份，headless 路徑共用同一份。
                    final moved = await CookieBridge.mirrorToDio(
                      url: ntustLoginUri,
                      jar: cookieJar,
                      manager: cookieManager,
                    );
                    _finish({
                      "status": moved > 0
                          ? NTUSTLoginStatus.success
                          : NTUSTLoginStatus.fail
                    });
                  }
                }
              },
            ),
            if (showDialog) dialog
          ],
        ),
      ),
    );
  }
}
