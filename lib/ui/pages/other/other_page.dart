import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/config/app_link.dart';
import 'package:flutter_app/src/controller/announcement/notification_badge_controller.dart';
import 'package:flutter_app/src/controller/course_table/course_controller.dart';
import 'package:flutter_app/src/controller/score_page/score_page_controller.dart';
import 'package:flutter_app/src/auth/session_cleaner.dart';
import 'package:flutter_app/src/controller/main_page/main_controller.dart';
import 'package:flutter_app/debug/log/console_output.dart';
import 'package:flutter_app/src/service/image_pick_service.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/src/version/app_version.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/shimmer/profile_loading.dart';
import 'package:flutter_app/ui/other/error_dialog.dart';
import 'package:flutter_app/ui/pages/other/components/avatar_action_sheet.dart';
import 'package:flutter_app/ui/pages/other/components/user_profile.dart';
import 'package:flutter_app/ui/pages/password/check_password_dialog.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

enum OtherMenuAction { setting, logout, report, about, login, changePassword }

class OtherPage extends StatefulWidget {
  const OtherPage({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _OtherPageState();
}

class _OtherPageState extends State<OtherPage> {
  List<Map> optionList = [
    {
      "icon": LucideIcons.settings,
      "title": R.current.setting,
      "onPress": OtherMenuAction.setting
    },
    if (Model.instance.getPassword().isNotEmpty)
      {
        "icon": LucideIcons.refreshCw,
        "title": R.current.changePassword,
        "onPress": OtherMenuAction.changePassword
      },
    if (Model.instance.getPassword().isNotEmpty)
      {
        "icon": LucideIcons.logOut,
        "title": R.current.logout,
        "onPress": OtherMenuAction.logout
      },
    if (Model.instance.getPassword().isEmpty)
      {
        "icon": LucideIcons.logIn,
        "title": R.current.login,
        "onPress": OtherMenuAction.login
      },
    {
      "icon": LucideIcons.messageSquare,
      "title": R.current.feedback,
      "onPress": OtherMenuAction.report
    },
    {
      "icon": LucideIcons.info,
      "title": R.current.about,
      "onPress": OtherMenuAction.about
    }
  ];

  void _onListViewPress(OtherMenuAction value) async {
    switch (value) {
      case OtherMenuAction.logout:
        ErrorDialogParameter parameter = ErrorDialogParameter(
            desc: R.current.logoutWarning,
            dialogType: DialogType.warning,
            title: R.current.warning,
            btnOkText: R.current.sure,
            btnOkOnPress: () async {
              Get.back();
              await SessionCleaner.platform().logoutAll();
              // 重設仍然存活的 controller。不要 Get.delete<MainController>()：
              // MainScreen 以 State 欄位持有它，這一頁與設定頁登出後仍會
              // Get.find 它。
              final mainController = Get.find<MainController>();
              mainController.cancelAvatarChange();
              mainController.profile.value = null;
              if (Get.isRegistered<CourseController>()) {
                Get.find<CourseController>().reset();
              }
              if (Get.isRegistered<ScorePageController>()) {
                Get.find<ScorePageController>().reset();
              }
              // 紅點是 process 級狀態，重設由 SessionCleaner 的呼叫端觸發
              // （auth → controller 是 tool/deps.py 擋死的上行邊）。
              NotificationBadgeController.instance.reset();
              mainController.pageController.jumpToPage(0);
              setState(() {});
            });
        unawaited(ErrorDialog(parameter).show());
        break;
      case OtherMenuAction.login:
        unawaited(RouteUtils.toLoginScreen());
        break;
      case OtherMenuAction.changePassword:
        if (await Get.dialog<bool>(const CheckPasswordDialog()) ?? false) {
          bool first = true;
          String changePasswordUrl =
              "https://stuinfosys.ntust.edu.tw/NTUSTSSOServ/SSO/ChangePWD";
          unawaited(RouteUtils.toWebViewPage(
              R.current.changePassword, changePasswordUrl,
              loadDone: (webView) async {
            if (!first) {
              return;
            }
            first = false;
            await webView.evaluateJavascript(
                source:
                    'document.getElementsByName("userName")[0].value = ${jsonEncode(Model.instance.getAccount())};');
            await webView.evaluateJavascript(
                source:
                    'document.getElementsByName("pwd")[0].value = ${jsonEncode(Model.instance.getPassword())};');
          }));
        }
        break;
      case OtherMenuAction.about:
        unawaited(RouteUtils.toAboutPage());
        break;
      case OtherMenuAction.setting:
        unawaited(RouteUtils.toSettingPage());
        break;
      case OtherMenuAction.report:
        String link = AppLink.feedbackBaseUrl;
        try {
          String mainVersion = await APPVersion.getAppVersion();
          link = AppLink.feedback(mainVersion, LogBuffer.getLog());
        } catch (e) {
          Log.d(e);
        }
        unawaited(RouteUtils.toWebViewPage(R.current.feedback, link));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: mainAppbar(title: R.current.titleOther),
      body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(
              height: 20,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: _buildAccountTile(),
            ),
            const SizedBox(
              height: 18,
            ),
            Expanded(
              child: AnimationLimiter(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: optionList.length,
                  itemBuilder: (BuildContext context, int index) {
                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 375),
                      child: ScaleAnimation(
                        child: _buildSetting(optionList[index]),
                      ),
                    );
                  },
                  separatorBuilder: (context, index) {
                    return const SizedBox(height: 4);
                  },
                ),
              ),
            ),
          ]),
    );
  }

  Widget _buildSetting(Map data) {
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
              // 不指定 fontFamily：Text.style 預設 inherit，字型從主題來。
              style: TextStyle(
                  color: Get.theme.colorScheme.onSurface, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountTile() {
    if (!AuthSession.instance.isSignedIn) {
      return Text(R.current.pleaseLogin);
    }

    var controller = Get.find<MainController>();

    return Obx(() {
      if (controller.isProfileLoading.value) {
        return const ProfileLoading();
      }

      final profile = controller.profile.value;
      if (profile == null) {
        // 載入結束但沒有資料：Moodle token 過期、斷網，或 site_info 少了欄位。
        // 載入中與載入失敗必須分開判斷，否則失敗之後骨架動畫永遠不會結束——
        // 畫面看起來像還在載入，既沒有錯誤訊息也沒有重試入口。
        return InkWell(
          onTap: controller.reloadProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    R.current.somethingError,
                    style: TextStyle(
                        color: Get.theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Icon(LucideIcons.refreshCw,
                    size: 20, color: Get.theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        );
      }

      return UserProfile(
        data: profile,
        progress: controller.avatarProgress.value,
        onAvatarTap: () => unawaited(_onAvatarTap(controller)),
      );
    });
  }

  Future<void> _onAvatarTap(MainController controller) async {
    final action = await showAvatarActionSheet(context,
        canRemove: controller.hasCustomAvatar);
    if (action == null) return;

    if (action == AvatarAction.remove) {
      // 換一張不必確認：使用者已經連按三下（頭貼 → 來源 → 選圖），而且結果
      // 可逆（再換一張或移除）。移除要確認：它是唯一破壞性的分支，伺服器端
      // delete_area_files 直接把舊圖刪掉、沒有復原，而且這一列就貼在兩個
      // 「選擇」旁邊，很容易誤按。
      final confirmed = await Get.dialog<bool>(AlertDialog.adaptive(
        title: Text(R.current.avatarRemove),
        content: Text(R.current.avatarRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text(R.current.cancel),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: Text(R.current.sure),
          ),
        ],
      ));
      if (confirmed != true) return;
      final error = await controller.changeAvatar();
      TaskUiDelegate.instance.toast(error ?? R.current.avatarRemoved);
      return;
    }

    File? file;
    try {
      file = await ImagePickService.instance.pick(
        action == AvatarAction.camera
            ? ImagePickSource.camera
            : ImagePickSource.gallery,
        // 頭貼要縮圖與重新編碼，理由見 image_pick_service.dart 的常數註解。
        maxEdge: kAvatarImageMaxEdge,
        quality: kAvatarImageQuality,
      );
    } on ImagePickFailure catch (e) {
      TaskUiDelegate.instance.toast(_pickFailureMessage(e.reason));
      return;
    }
    // 使用者按取消不是錯誤，什麼都不做也不提示。
    if (file == null) return;

    final error = await controller.changeAvatar(file: file);
    TaskUiDelegate.instance.toast(error ?? R.current.avatarUpdated);
  }

  String _pickFailureMessage(ImagePickFailureReason reason) => switch (reason) {
        ImagePickFailureReason.cameraDenied => R.current.avatarCameraDenied,
        ImagePickFailureReason.galleryDenied => R.current.avatarGalleryDenied,
        ImagePickFailureReason.unavailable => R.current.avatarPickerUnavailable,
      };
}
