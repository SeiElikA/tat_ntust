import 'dart:io';

import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_app/src/util/remote_config_utils.dart';
import 'package:flutter_app/ui/pages/announcement/announcement_page.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/ui/pages/course_data/course_data_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_announcement_detail_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_folder_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_info_page.dart';
import 'package:flutter_app/ui/pages/course_detail/course_detail_page.dart';
import 'package:flutter_app/ui/pages/log_console/log_console.dart';
import 'package:flutter_app/ui/pages/other/page/about_page.dart';
import 'package:flutter_app/ui/pages/other/page/privacy_policy_page.dart';
import 'package:flutter_app/ui/pages/other/page/contributors_page.dart';
import 'package:flutter_app/ui/pages/other/page/dev_page.dart';
import 'package:flutter_app/ui/pages/other/page/setting/setting_page.dart';
import 'package:flutter_app/ui/pages/other/page/store_edit_page.dart';
import 'package:flutter_app/ui/pages/web_view/inapp_web_view_page.dart';
import 'package:flutter_app/ui/screen/privacy_policy/privacy_policy_screen.dart';
import 'package:flutter_app/ui/screen/login/login_screen.dart';
import 'package:flutter_app/ui/screen/main_screen.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

class RouteUtils {
  /// 取得並顯示公告。沒有公告時，只有使用者主動查看（allTime）才提示。
  static Future<void> showAnnouncement(
      {bool test = false, bool allTime = false}) async {
    final request = await RemoteConfigUtils.resolveAnnouncement(
        test: test, allTime: allTime);
    if (request == null) {
      if (allTime) MyToast.show(R.current.noAnnouncement);
      return;
    }
    await Get.to(
      () => AnnouncementPage(
        info: request.info,
        countDown: request.countDown,
      ),
      transition: Transition.downToUp,
    );
  }

  static Transition transition =
      (Platform.isAndroid) ? Transition.downToUp : Transition.cupertino;
  static Future toDevPage() async {
    return await Get.to(
      () => const DevPage(),
      transition: transition,
    );
  }

  static Future toCourseDataPage(CourseInfoJson courseInfo) async {
    return await Get.to(
      () => CourseDataPage(courseInfo),
      transition: transition,
    );
  }

  static Future toCourseFolderPage(
      CourseInfoJson courseInfo, dynamic value) async {
    return await Get.to(
      () => CourseFolderPage(courseInfo, value),
      transition: transition,
    );
  }

  static Future toCourseInfoPage(
      CourseInfoJson courseInfo, dynamic value) async {
    return await Get.to(
      () => CourseInfoPage(courseInfo, value),
      transition: transition,
    );
  }

  static Future toAnnouncementDetailPage(
      CourseInfoJson courseInfo, dynamic value) async {
    return await Get.to(
      () => CourseAnnouncementDetailPage(courseInfo, value),
      transition: transition,
    );
  }

  static Future toCourseDetailPage(
      SemesterJson semester, CourseInfoJson courseInfo) async {
    return await Get.to(
      () => CourseDetailPage(courseInfo, semester),
      transition: transition,
    );
  }

  static Future toPrivacyPolicyPage() async {
    return await Get.to(
      () => const PrivacyPolicyPage(),
      transition: transition,
    );
  }

  static Future toContributorsPage() async {
    return await Get.to(
      () => ContributorsPage(),
      transition: transition,
    );
  }

  static Future toAboutPage() async {
    return await Get.to(
      () => const AboutPage(),
      transition: transition,
    );
  }

  static Future toSettingPage() async {
    return await Get.to(
      () => const SettingPage(),
      transition: transition,
    );
  }

  static Future toWebViewPage(String title, String url,
      {bool openWithExternalWebView = true,
      Function(Uri)? onWebViewDownload,
      Function(InAppWebViewController)? loadDone}) async {
    loadDone ??= (controller) {};
    return await Get.to(
      () => InAppWebViewPage(
        title: title,
        url: WebUri(url),
        openWithExternalWebView: openWithExternalWebView,
        onWebViewDownload: onWebViewDownload,
        loadDone: loadDone!,
      ),
      transition: transition,
    );
  }

  static Future toLogConsolePage() async {
    return await Get.to(
      () => LogConsole(dark: true),
      transition: transition,
    );
  }

  static Future toStoreEditPage() async {
    return await Get.to(
      () => const StoreEditPage(),
      transition: transition,
    );
  }

  static Future toAgreePrivacyPolicyScreen() async {
    return await Get.to(
      () => const PrivacyPolicyScreen(),
      transition: transition,
    );
  }

  static Future toLoginScreen() async {
    //return will auto jump to main screen
    bool? value = await Get.to(
      () => const LoginScreen(),
      transition: transition,
    );
    return value ?? false;
  }

  static Future toMainScreen() async {
    return await Get.offAll(
      () => const MainScreen(),
      transition: transition,
    );
  }
}
