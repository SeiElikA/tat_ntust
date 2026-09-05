import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/service/ssoam2_login.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_token_entity.dart';
import 'package:flutter_app/ui/other/my_progress_dialog.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';

class LoginMoodlePage extends StatefulWidget {
  final String username;
  final String password;

  const LoginMoodlePage({
    required this.username,
    required this.password,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _LoginMoodlePageState();
}

class _LoginMoodlePageState extends State<LoginMoodlePage> {
  final _launch = MoodleWebApiConnector.buildLoginLaunch();
  late final WebUri moodleLoginUri = WebUri(_launch.url);
  bool showDialog = true;
  Widget dialog = MyProgressDialog.dialog(R.current.loginMoodle);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${R.current.loginMoodle}..."),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: moodleLoginUri),
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri != null && uri.scheme == "moodlemobile") {
                  // parseMoodleToken 不能拋例外：從 shouldOverrideUrlLoading
                  // 逸出的例外沒有人接住，頁面與進度框會永遠卡在畫面上。
                  Get.back(
                      result: parseMoodleToken(uri.rawValue,
                          passport: _launch.passport));
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onLoadStop:
                  (InAppWebViewController controller, WebUri? url) async {
                if (Ssoam2Login.isLoginPage(url)) {
                  final outcome = await Ssoam2Login.submit(
                    controller,
                    account: widget.username,
                    password: widget.password,
                  );
                  // 找不到表單與 Turnstile 逾時在畫面上是同一件事：收起進度框
                  // 讓使用者自己操作。分成兩個 outcome 值是給 headless 路徑用的
                  // ——只有 turnstileTimeout 值得升級成可見頁面。
                  if (outcome != Ssoam2LoginOutcome.submitted) {
                    setState(() {
                      showDialog = false;
                    });
                    MyToast.show(R.current.needValidateCaptcha,
                        toastLength: Toast.LENGTH_LONG);
                  }
                }
              },
            ),
            Visibility(visible: showDialog, child: dialog)
          ],
        ),
      ),
    );
  }
}

/// 解析 `moodlemobile://token=<base64>` 的回傳。失敗一律回 null，不拋例外。
///
/// base64 解開之後是 `signature:::token:::privatetoken`。要用 base64.normalize
/// 補 padding，Dart 的解碼器少了 padding 會丟 FormatException。
///
/// **signature 不相符一律拒收（fail-closed）。** 伺服器算的是
/// `md5($CFG->wwwroot . $passport)`（純字串相接、沒有分隔符，見
/// `admin/tool/mobile/launch.php`）；驗證它才能確定 token 來自我們剛發出的
/// 那一次 launch，而不是別人塞進來的。
///
/// 學校若改了 wwwroot（換網域、加路徑、或前面擺了改寫 scheme 的反向代理），
/// 這裡會開始擋掉**合法的** token，症狀是登入頁一直重來。先看 log 裡的
/// `signature mismatch`，用裡面的值反推站台實際的 wwwroot，再更新
/// [MoodleWebApiConnector.host]——不要把這道檢查關掉。
MoodleTokenEntity? parseMoodleToken(String rawUrl, {String? passport}) {
  try {
    final marker = rawUrl.indexOf("token=");
    if (marker < 0) return null;
    final encoded = rawUrl.substring(marker + "token=".length);
    if (encoded.isEmpty) return null;

    final decoded = utf8.decode(base64.decode(base64.normalize(encoded)));
    final parts = decoded.split(":::");
    if (parts.length < 2 || parts[1].isEmpty) return null;

    if (passport != null &&
        !MoodleWebApiConnector.verifyLoginSignature(parts[0], passport)) {
      Log.e("moodle login signature mismatch: got ${parts[0]}");
      return null;
    }

    return MoodleTokenEntity(
      parts[0],
      parts[1],
      parts.length >= 3 ? parts[2] : "",
    );
  } catch (e, stack) {
    Log.eWithStack("moodle token parse failed: $e", stack);
    return null;
  }
}
