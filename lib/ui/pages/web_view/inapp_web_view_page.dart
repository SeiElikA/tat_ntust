import 'dart:convert';

import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/ui/other/svg_tint.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/service/ssoam2_login.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_app/src/util/open_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/loading_page.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

class InAppWebViewPage extends StatefulWidget {
  final WebUri url;

  /// [url] 是 autologin 包裝網址時原本要開的那個。鑰匙被拒（過期、IP 不符、
  /// 已用過）時 autologin.php 顯示錯誤頁而不轉址，這時退回去開它。
  final WebUri? fallbackUrl;
  final String title;
  final bool openWithExternalWebView;
  final Function(Uri)? onWebViewDownload;
  final Function(InAppWebViewController) loadDone;

  const InAppWebViewPage({
    required this.title,
    required this.url,
    this.fallbackUrl,
    this.openWithExternalWebView = false,
    this.onWebViewDownload,
    required this.loadDone,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _InAppWebViewPageState();
}

class _InAppWebViewPageState extends State<InAppWebViewPage> {
  final cookieManager = CookieManager.instance();
  final cookieJar = DioConnector.instance.cookiesManager;
  InAppWebViewController? webView;
  Uri url = Uri();
  double progress = 0;
  int onLoadStopTime = -1;
  Uri? lastLoadUri;
  final String ntustLoginUri = "https://ssoam.ntust.edu.tw/nidp/app/login";

  @override
  void initState() {
    super.initState();
    BackButtonInterceptor.add(myInterceptor);
  }

  @override
  void dispose() {
    BackButtonInterceptor.remove(myInterceptor);
    super.dispose();
  }

  bool myInterceptor(bool stopDefaultButtonEvent, RouteInfo info) {
    if (onLoadStopTime >= 1) {
      webView!.goBack();
      onLoadStopTime -= 2;
      return true;
    }
    return false;
  }

  bool firstLoad = true;

  /// 只退回一次：之後使用者按上一頁回到那個錯誤頁是他自己要去的。
  bool fellBack = false;

  Future<bool> setCookies() async {
    if (!firstLoad) return true;
    firstLoad = false;
    final cookies = await cookieJar.loadForRequest(widget.url);
    // Moodle 的頁面不清平台 cookie store：autologin.php 建立的 MoodleSession
    // 只存在那裡，而伺服器 6 分鐘內只發一把鑰匙，清掉第二頁就停在登入頁。
    if (!MoodleWebApiConnector.isOwnHost(widget.url)) {
      await cookieManager.deleteAllCookies();
    }
    // 只剩「同一批 Dio cookie 內部同名去重」的作用，所以從空集合開始。
    final cookiesName = <String>{};
    for (var cookie in cookies) {
      if (!cookiesName.contains(cookie.name)) {
        cookiesName.add(cookie.name);
        await cookieManager.setCookie(
          url: widget.url,
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          path: cookie.path ?? "/",
          maxAge: cookie.maxAge,
          isSecure: cookie.secure,
          isHttpOnly: cookie.httpOnly,
        );
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: baseAppbar(title: widget.title, action: actionList),
      body: FutureBuilder<bool>(
        future: setCookies(),
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          if (snapshot.hasData) {
            return Column(
              children: <Widget>[
                Container(
                  child: progress < 1.0
                      ? LinearProgressIndicator(value: progress)
                      : Container(),
                ),
                Expanded(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: widget.url),
                    initialSettings: InAppWebViewSettings(
                        useHybridComposition: true, useOnDownloadStart: true),
                    onWebViewCreated: (InAppWebViewController controller) {
                      webView = controller;
                    },
                    onLoadStart: (InAppWebViewController controller, Uri? url) {
                      setState(() {
                        if (lastLoadUri != url) {
                          onLoadStopTime++;
                        }
                        lastLoadUri = url;
                        this.url = url!;
                      });
                    },
                    onLoadStop:
                        (InAppWebViewController controller, Uri? url) async {
                      if (shouldFallBackFrom(url)) {
                        // 成功時會 303 轉走，停在它身上就是鑰匙被拒。
                        fellBack = true;
                        Log.e("[autologin] autologin.php 沒有轉址，改開原網址：$url");
                        await controller.loadUrl(
                            urlRequest: URLRequest(url: widget.fallbackUrl));
                        return;
                      }
                      if (url.toString().startsWith(ntustLoginUri)) {
                        await controller.evaluateJavascript(
                            source:
                                'document.getElementsByName("Ecom_User_ID")[0].value = ${jsonEncode(Model.instance.getAccount())};');
                        await controller.evaluateJavascript(
                            source:
                                'document.getElementsByName("Ecom_Password")[0].value = ${jsonEncode(Model.instance.getPassword())};');
                        await controller.evaluateJavascript(
                            source:
                                'document.getElementById("loginButton2").click();');
                      } else if (Ssoam2Login.isLoginPage(url)) {
                        final outcome = await Ssoam2Login.submit(
                          controller,
                          account: Model.instance.getAccount(),
                          password: Model.instance.getPassword(),
                        );
                        if (outcome != Ssoam2LoginOutcome.submitted) {
                          MyToast.show(R.current.needValidateCaptcha);
                        }
                      }
                      widget.loadDone(controller);
                      setState(
                        () {
                          this.url = url!;
                        },
                      );
                    },
                    onProgressChanged:
                        (InAppWebViewController controller, int progress) {
                      setState(
                        () {
                          this.progress = progress / 100;
                        },
                      );
                    },
                    onDownloadStartRequest: (InAppWebViewController controller,
                        DownloadStartRequest downloadStartRequest) {
                      var url = downloadStartRequest.url;
                      Log.d("WebView download ${url.toString()}");
                      if (widget.onWebViewDownload != null) {
                        widget.onWebViewDownload!(url);
                      } else {
                        String dirName = "WebView";
                        FileDownload.download(context, url.toString(), dirName);
                      }
                    },
                  ),
                ),
              ],
            );
          }

          return const LoadingPage(
            isLoading: true,
            isShowBackground: false,
          );
        },
      ),
    );
  }

  /// 這一次 onLoadStop 停在 autologin.php 本身，而且還沒退過。
  bool shouldFallBackFrom(Uri? url) =>
      widget.fallbackUrl != null &&
      !fellBack &&
      MoodleWebApiConnector.isAutologinScript(url);

  List<Widget> get actionList {
    // 純圖示按鈕沒有 tooltip 時螢幕閱讀器一律只唸「按鈕」；上一頁／下一頁
    // 借用 GlobalMaterialLocalizations 既有的字串，不必新增 l10n key。
    final materialL10n = MaterialLocalizations.of(context);
    return [
      IconButton(
          tooltip: materialL10n.previousPageTooltip,
          splashRadius: 16,
          onPressed: () async {
            if (webView != null) {
              await webView?.goBack();
            }
          },
          icon: const Icon(
            CupertinoIcons.left_chevron,
            size: 18,
          )),
      IconButton(
          tooltip: materialL10n.nextPageTooltip,
          splashRadius: 16,
          onPressed: () async {
            if (webView != null) {
              await webView?.goForward();
            }
          },
          icon: const Icon(
            CupertinoIcons.right_chevron,
            size: 18,
          )),
      IconButton(
          tooltip: R.current.refresh,
          splashRadius: 16,
          onPressed: () async {
            if (webView != null) {
              await webView?.reload();
            }
          },
          icon: const Icon(CupertinoIcons.refresh, size: 18)),
      Visibility(
          visible: widget.openWithExternalWebView,
          child: IconButton(
            // SvgPicture 連 semanticsLabel 都沒有，沒 tooltip 就唸不出來。
            tooltip: R.current.openInBrowser,
            splashRadius: 16,
            onPressed: () async {
              await OpenUtils.launchURL(url.toString());
            },
            icon: SvgPicture.asset(
              "assets/image/img_external_link.svg",
              colorFilter: svgTint(Get.iconColor),
              height: 20,
            ),
          ))
    ];
  }
}
