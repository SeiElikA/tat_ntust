import 'dart:async';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_profile_entity.dart';
import 'package:flutter_app/src/service/error_dialog_parameter.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/analytics_utils.dart';
import 'package:get/get.dart';

/// 五個分頁的身分。
///
/// controller 不可以持有 Widget：那會讓 `lib/src/controller` 反向 import
/// `lib/ui`，也就是 `tool/deps.py` 的 controller -> ui 上行邊。畫面由
/// [MainScreen] 持有，controller 只認「第幾個分頁」。
///
/// 這些名稱會直接送進 Analytics 當 screen name，改名等於改掉既有的報表維度。
enum MainTab { courseTable, subSystem, calendar, score, other }

class MainController extends GetxController {
  final pageController = PageController();
  RxInt currentIndex = 0.obs;

  var isProfileLoading = false.obs;
  Rxn<MoodleProfileEntity> profile = Rxn();

  @override
  Future<void> onInit() async {
    super.onInit();

    // Moodle 的事在背景做，不擋 App 外殼：課表不需要 Moodle，個人資料也
    // 只有「其他」頁在用。改成 await 的話使用者輸入完帳密要盯著載入畫面
    // 等一整輪 Moodle 登入才看得到課表。
    unawaited(_loadMoodleProfile());
  }

  /// Moodle 登入與個人資料。在背景跑，不擋 App 外殼。
  ///
  /// 個人資料只有「其他」頁在用，而那一頁自己有 isProfileLoading 的載入狀態
  /// 與 reloadProfile 的重試入口。
  Future<void> _loadMoodleProfile() async {
    try {
      // **先確保 SSO，再碰 Moodle。** Moodle 的 launch.php 會轉址經過 ssoam2，
      // 平台 WebView store 有 SSO cookie 那一段才會靜默通過；順序反過來就是
      // 使用者撞上 ssoam2 的表單再登入一次。失敗照樣往下走，Moodle 那條路
      // 自己會再試一次，也有自己的錯誤提示。
      await AuthSession.instance.ensure({SystemId.ntustSso});
      if (await _checkMoodle()) {
        await _getMoodleProfile();
      }
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
    }
  }

  /// Event Handler
  void onBottomNavigationTap(int index) {
    pageController.jumpToPage(index);
    HapticFeedback.mediumImpact();
  }

  void onPageChanged(int index) {
    currentIndex.value = index;

    final screenName = MainTab.values[index].name;
    AnalyticsUtils.setScreenName(screenName);
  }

  /// Private Method
  ///
  /// **登入一定要走 [AuthSession.ensure]。** 繞過去就繞過 `inFlight`，首次
  /// 登入時會與課表頁的 `preloadSemesterList` 各開一個 LoginMoodlePage，
  /// 先回來的那個 `Get.back` pop 掉另一頁，另一邊收到 null 就跳錯誤框。
  Future<bool> _checkMoodle() async {
    if (!AuthSession.instance.isSignedIn) return false;

    final isMoodleAvailable =
        await MoodleWebApiConnector.isMoodleTokenAvailable();
    if (isMoodleAvailable) {
      return true;
    }

    final error = await AuthSession.instance.ensure({SystemId.moodleWebApi});
    if (error != null) {
      // 走 TaskUiDelegate 而不是直接 new 一個 ErrorDialog：那個 widget 在
      // lib/ui，controller 讀它是 controller -> ui 的上行邊。
      // offCancelBtn 讓它只有一顆「確定」，回傳值沒有意義。
      await TaskUiDelegate.instance.confirmRetry(ErrorDialogParameter(
        title: R.current.error,
        dialogType: DialogType.error,
        desc: R.current.loginMoodleError,
        okResult: false,
        btnOkText: R.current.sure,
        offCancelBtn: true,
      ));
      return false;
    }

    return true;
  }

  /// 重新載入個人資料。給「其他」頁載入失敗時的重試入口用。
  Future<void> reloadProfile() => _getMoodleProfile();

  Future<void> _getMoodleProfile() async {
    try {
      isProfileLoading.value = true;
      profile.value = await MoodleWebApiConnector.getProfile();
    } catch (e) {
      Log.e(e);
    } finally {
      isProfileLoading.value = false;
    }
  }
}
