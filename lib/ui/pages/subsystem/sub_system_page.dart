import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/repository/ntust_repository.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/ntust/ap_tree_json.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_app/ui/pages/password/webmail_password_dialog.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

class SubSystemPage extends StatefulWidget {
  const SubSystemPage({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _SubSystemPageState();
}

class _SubSystemPageState extends State<SubSystemPage> {
  /// null 代表還在載入。請求在 [initState] 觸發一次，`build()` 只負責畫。
  final _state = Rxn<Result<List<APTreeJson>>>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _state.close();
    super.dispose();
  }

  Future<void> _load() async {
    _state.value = null;
    _state.value = await NtustRepository.instance.getSubSystemTree();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: mainAppbar(title: R.current.informationSystem),
      body: ResultView<List<APTreeJson>>(
        state: _state,
        onRetry: _load,
        errorBuilder: (message) => ErrorPage(errorMsg: message),
        builder: (tree) => Column(
          children: [
            buildMail(APListJson(
                name: R.current.webMail,
                type: 'webMail_link',
                url: "https://mail.ntust.edu.tw")),
            Expanded(child: getAnimationList(tree)),
          ],
        ),
      ),
    );
  }

  Widget getAnimationList(List<APTreeJson> apTree) {
    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        physics: const BouncingScrollPhysics(),
        itemCount: apTree.length,
        itemBuilder: (BuildContext context, int index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: buildTree(apTree[index]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildTree(APTreeJson ap) {
    var serviceMap = {
      "service-1": R.current.curriculum,
      "service-2": R.current.person_info,
      "service-3": R.current.campus_life,
      "service-4": R.current.financial_support,
      "service-5": R.current.activities,
      "service-6": R.current.resources
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          serviceMap[ap.serviceId] ?? "",
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Get.theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: (Get.width - 12 * 2) / 100,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6),
          itemBuilder: (context, index) {
            return buildItem(index, ap.apList.length, ap.apList[index]);
          },
          itemCount: ap.apList.length,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget buildItem(int index, int length, APListJson ap) {
    return FilledButton(
      style: FilledButton.styleFrom(
          backgroundColor: Get.theme.colorScheme.surfaceContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(0, 120)),
      onPressed: () {
        RouteUtils.toWebViewPage(ap.name, ap.url,
            openWithExternalWebView: false);
      },
      child: Text(
        ap.name,
        textAlign: TextAlign.center,
        style: TextStyle(color: Get.theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget buildMail(APListJson ap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: GestureDetector(
        onTap: () async {
          if (Model.instance.getWebMailPassword().isEmpty) {
            await Get.dialog(const WebMailPasswordDialog(),
                barrierDismissible: false);
          }

          if (Model.instance.getWebMailPassword().isNotEmpty) {
            unawaited(RouteUtils.toWebViewPage(
              ap.name,
              ap.url,
              openWithExternalWebView: false,
              loadDone: (webView) async {
                Uri? uri = await webView.getUrl();
                if (uri!.host == "login.ntust.edu.tw") {
                  await webView.evaluateJavascript(
                      source:
                          'document.getElementById("loginForm").kendoBindingTarget.target.obsCtrl.obsData.username = ${jsonEncode(Model.instance.getAccount())}');
                  await webView.evaluateJavascript(
                      source:
                          'document.getElementById("loginForm").kendoBindingTarget.target.obsCtrl.obsData.password = ${jsonEncode(Model.instance.getWebMailPassword())}');
                  await webView.evaluateJavascript(
                      source:
                          'document.getElementsByName("username")[0].value = ${jsonEncode(Model.instance.getAccount())}');
                  await webView.evaluateJavascript(
                      source:
                          'document.getElementsByName("password")[0].value = ${jsonEncode(Model.instance.getWebMailPassword())}');
                }
              },
            ));
          }
        },
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              Text(ap.name),
              if (ap.type == "webMail_link")
                IconButton(
                    // 這顆按鈕是重新輸入 WebMail 密碼，但圖示是重新整理，
                    // 沒有 tooltip 的話看圖示與螢幕閱讀器都猜不到用途。
                    tooltip: R.current.changePassword,
                    onPressed: () {
                      Get.dialog(const WebMailPasswordDialog(),
                          barrierDismissible: false);
                    },
                    icon: Icon(LucideIcons.refreshCw,
                        size: 24, color: Get.theme.colorScheme.onSurface))
            ],
          ),
        ),
      ),
    );
  }
}
