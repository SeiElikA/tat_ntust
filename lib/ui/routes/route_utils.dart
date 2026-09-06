import 'dart:io';

import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/util/remote_config_utils.dart';
import 'package:flutter_app/ui/pages/announcement/announcement_center_page.dart';
import 'package:flutter_app/ui/pages/announcement/announcement_page.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/ui/pages/course_data/course_data_page.dart';
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
import 'package:flutter_app/ui/pages/score/moodle_course_grades_page.dart';
import 'package:flutter_app/ui/pages/web_view/inapp_web_view_page.dart';
import 'package:flutter_app/ui/screen/privacy_policy/privacy_policy_screen.dart';
import 'package:flutter_app/ui/screen/login/login_screen.dart';
import 'package:flutter_app/ui/screen/main_screen.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

class RouteUtils {
  /// 啟動時的公告彈窗。沒有要顯示的公告就什麼都不做——使用者主動查看的入口
  /// 已經是 [toAnnouncementCenter]，那一頁有自己的空狀態。
  static Future<void> showAnnouncement({bool test = false}) async {
    final request = await RemoteConfigUtils.resolveAnnouncement(test: test);
    if (request == null) return;
    await Get.to(
      () => AnnouncementPage(
        info: request.info,
        countDown: request.countDown,
      ),
      transition: Transition.downToUp,
    );
  }

  /// 「公告與通知」頁。啟動彈窗（[showAnnouncement]）完全不受影響，這一頁只是
  /// 給同一批 Remote Config 公告一個常駐的家，外加 Moodle 站內通知。
  static Future<void> toAnnouncementCenter() async {
    await Get.to(
      () => const AnnouncementCenterPage(openWebView: toWebViewPage),
      transition: transition,
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

  static Future toCourseDataPage(CourseInfoJson courseInfo,
      {int initialTab = 0}) async {
    return await Get.to(
      () => CourseDataPage(courseInfo, initialTab: initialTab),
      transition: transition,
    );
  }

  /// 「Moodle 目前成績」。點一列開那門課的 Moodle 成績分頁——那一段導頁在這裡
  /// 注入，頁面本身不 import 這個檔案（見 docs/ARCHITECTURE.md「UI 慣例」）。
  /// 課程頁只讀 `main.course` 的 id 與 name，所以現組一個最小的 CourseInfoJson
  /// 就夠；內部 id 由 MoodleRepository 用課號查回來（多半是快取命中）。
  static Future<void> toMoodleCourseGrades() async {
    await Get.to(
      () => MoodleCourseGradesPage(
        onOpenCourse: (course) => toCourseDataPage(
          CourseInfoJson(
            main: CourseMainInfoJson(
              course: CourseMainJson(id: course.courseId, name: course.name),
            ),
          ),
          initialTab: CourseDataPage.scoreTab,
        ),
      ),
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
    // Moodle 的頁面先換成 autologin 網址，WebView 才不會停在登入頁；換不到
    // 就原樣回來。有換到時把原網址一起帶著，鑰匙被拒時 WebView 才有地方退。
    final target = await MoodleWebApiConnector.autologinUrl(url);
    return await Get.to(
      () => InAppWebViewPage(
        title: title,
        url: WebUri(target),
        fallbackUrl: target == url ? null : WebUri(url),
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
