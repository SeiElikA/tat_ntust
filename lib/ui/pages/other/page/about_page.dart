import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/src/version/app_version.dart';
import 'package:flutter_app/src/version/store_update.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/other/listview_animator.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_app/ui/pages/password/check_password_dialog.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

enum AboutMenuAction { appUpdate, contribution, privacyPolicy, version, dev }

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<StatefulWidget> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  List<Map> listViewData = [];

  static bool inDevMode = false | kDebugMode;

  @override
  void initState() {
    super.initState();
    initList();
  }

  void initList() {
    listViewData = [
      {
        "icon": LucideIcons.refreshCw,
        "title": R.current.checkVersion,
        "onPress": AboutMenuAction.appUpdate
      },
      {
        "icon": LucideIcons.award,
        "title": R.current.Contribution,
        "onPress": AboutMenuAction.contribution
      },
      {
        "icon": LucideIcons.shieldCheck,
        "title": R.current.PrivacyPolicy,
        "onPress": AboutMenuAction.privacyPolicy
      },
      {
        "icon": LucideIcons.info,
        "title": R.current.versionInfo,
        "onPress": AboutMenuAction.version
      }
    ];
    _addDevListItem();
  }

  void _addDevListItem() {
    if (inDevMode) {
      setState(() {
        listViewData.add({
          "icon": LucideIcons.codeXml,
          "title": R.current.developerMode,
          "onPress": AboutMenuAction.dev
        });
      });
    }
  }

  int pressTime = 0;

  void _onListViewPress(AboutMenuAction value) async {
    switch (value) {
      case AboutMenuAction.appUpdate:
        MyToast.show(R.current.checkingVersion);
        if (!await StoreUpdate.offer()) {
          MyToast.show(R.current.isNewVersion);
        }
        break;
      case AboutMenuAction.contribution:
        unawaited(RouteUtils.toContributorsPage());
        break;
      case AboutMenuAction.version:
        String mainVersion = await APPVersion.getAppVersion();
        if (pressTime == 0) {
          MyToast.show(mainVersion);
        }
        pressTime++;
        // 這是連點計時器，必須即發即忘：若 await 它，下面的 pressTime > 3
        // 判斷會在兩秒後、計數已被歸零之後才執行，連點解鎖永遠不會成立。
        unawaited(Future.delayed(const Duration(seconds: 2)).then((_) {
          pressTime = 0;
        }));
        // release 版不提供解鎖路徑：DevPage 底下的 StoreEditPage 會把
        // SharedPreferences 原文顯示在沒有 obscureText 的輸入框裡，其中
        // user_data 就是明文的帳號、密碼與 WebMail 密碼。
        if (kDebugMode && pressTime > 3) {
          if (!inDevMode &&
              (await Get.dialog<bool>(const CheckPasswordDialog()) ?? false)) {
            inDevMode = true;
            _addDevListItem();
          }
        }
        break;
      case AboutMenuAction.privacyPolicy:
        unawaited(RouteUtils.toPrivacyPolicyPage());
        break;
      case AboutMenuAction.dev:
        unawaited(RouteUtils.toDevPage());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: baseAppbar(title: R.current.about),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: listViewData.length,
        itemBuilder: (context, index) {
          return WidgetAnimator(_buildAbout(listViewData[index]));
        },
        separatorBuilder: (context, index) {
          return const SizedBox(height: 4);
        },
      ),
    );
  }

  Widget _buildAbout(Map data) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        _onListViewPress(data['onPress']);
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
            color: Get.theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Get.theme.colorScheme.surface),
              padding: const EdgeInsets.all(8),
              child: Icon(data['icon'] as IconData,
                  size: 24, color: Get.theme.colorScheme.onSurface),
            ),
            const SizedBox(width: 12),
            Text(
              data['title'],
              style: TextStyle(
                  color: Get.theme.colorScheme.onSurface, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
