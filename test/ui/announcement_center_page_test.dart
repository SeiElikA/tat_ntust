import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/controller/announcement/announcement_center_controller.dart';
import 'package:flutter_app/src/controller/announcement/notification_badge_controller.dart';
import 'package:flutter_app/src/model/announcement/announcement_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_message_popup_notifications.dart';
import 'package:flutter_app/src/repository/app_notice_repository.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/ui/components/html/moodle_html_view.dart';
import 'package:flutter_app/ui/components/page/empty_state.dart';
import 'package:flutter_app/ui/components/page/inline_error_view.dart';
import 'package:flutter_app/ui/components/page/loading_page.dart';
import 'package:flutter_app/ui/components/page/section_empty_state.dart';
import 'package:flutter_app/ui/pages/announcement/announcement_center_page.dart';
import 'package:flutter_app/ui/pages/announcement/notification_tile.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/moodle_notification_fixtures.dart';
import '../helpers/recording_ui.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

class _FakeRepo extends MoodleRepository {
  MoodleNotificationList? nextList;
  bool markAllResult = true;

  @override
  Future<MoodleNotificationList?> fetchNotifications() async => nextList;

  @override
  Future<bool> writeNotificationRead(int notificationId) async => true;

  @override
  Future<bool> writeAllNotificationsRead() async => markAllResult;
}

class _FakeNoticeRepo extends AppNoticeRepository {
  List<AnnouncementInfoJson> next = [];

  @override
  Future<List<AnnouncementInfoJson>> fetchNotices() async => next;
}

/// 公告與通知頁的畫面規格。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo repo;
  late _FakeNoticeRepo noticeRepo;
  late RecordingUi ui;

  setUpAll(() async {
    await loadTestL10n();
    // DateFormat.yMd() 需要 zh_TW 的日期符號。
    await initializeDateFormatting();
  });

  setUp(() {
    resetAppStatics();
    repo = _FakeRepo();
    noticeRepo = _FakeNoticeRepo();
    ui = RecordingUi();
    MoodleRepository.instance = repo;
    AppNoticeRepository.instance = noticeRepo;
    AuthSession.instance = FakeAuthSession();
    TaskUiDelegate.instance = ui;
    ConnectivityProbe.instance = FakeConnectivityProbe();
    NotificationBadgeController.instance = NotificationBadgeController();
  });

  tearDown(() {
    MoodleRepository.instance = MoodleRepository();
    AppNoticeRepository.instance = AppNoticeRepository();
    AuthSession.instance = const UninstalledAuthSession();
    TaskUiDelegate.instance = const NoopTaskUiDelegate();
    ConnectivityProbe.instance = const PlatformConnectivityProbe();
  });

  final now = DateTime(2025, 9, 15, 12, 0);

  AnnouncementInfoJson notice(String title, DateTime start) =>
      AnnouncementInfoJson(
        title: title,
        content: '公告的 Markdown 內文',
        startTime: start,
        endTime: start.add(const Duration(days: 30)),
        test: false,
      );

  /// 先把 controller 載好再 pump：這一頁在收到注入的 controller 時不會自己
  /// 再發請求（同 course_assignment_page_test 的做法）。
  Future<AnnouncementCenterController> pump(
    WidgetTester tester, {
    bool load = true,
    List<(String, String)>? opened,
  }) async {
    final controller = AnnouncementCenterController();
    if (load) await controller.loadAll();
    await tester.pumpWidget(GetMaterialApp(
      home: AnnouncementCenterPage(
        controller: controller,
        clock: () => now,
        openWebView: (title, url) async => opened?.add((title, url)),
      ),
    ));
    if (load) {
      await tester.pumpAndSettle();
    } else {
      // 載入中的畫面有一個永不停的轉圈，pumpAndSettle 會逾時。
      await tester.pump();
    }
    // 先把畫面拆掉再關掉 Rx：Obx 還掛在上面時關掉來源會在 unmount 時炸。
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
    return controller;
  }

  testWidgets('兩半都在載入時，兩個區塊標題都已經在畫面上', (tester) async {
    await pump(tester, load: false);

    expect(find.text('TAT 公告'), findsOneWidget);
    expect(find.text('Moodle 通知'), findsOneWidget);
    expect(find.byType(LoadingPage), findsNWidgets(2));
  });

  testWidgets('三則通知：標題、摘要、來源與時間；伺服器語系的 timecreatedpretty 不出現', (tester) async {
    repo.nextList = fixtureNotifications();

    await pump(tester);

    expect(find.byType(NotificationTile), findsNWidgets(3));
    expect(find.text('作業已評分：HW1 & Report'), findsOneWidget);
    expect(find.textContaining('&amp;'), findsNothing);
    // 來源與時間分開排版：長活動名稱被 ellipsis 吃掉時，時間不會跟著消失。
    expect(find.text('HW1 & Report'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^ · \d\d/\d\d \d\d:\d\d$')),
        findsNWidgets(3));
    // timecreatedpretty 是伺服器端語系算好的，永遠不該被畫出來。
    expect(find.textContaining('hours ago'), findsNothing);
    expect(find.textContaining('day ago'), findsNothing);
    // 沒有 contexturlname 的 core 通知有自己的標籤。
    expect(find.text('系統通知'), findsOneWidget);
  });

  testWidgets('未讀有圓點與粗體標題，已讀沒有', (tester) async {
    repo.nextList = fixtureNotifications();

    await pump(tester);

    expect(find.byKey(const ValueKey('unread-101')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-102')), findsNothing);
    final unreadTitle = tester.widget<Text>(find.text('作業已評分：HW1 & Report'));
    expect(unreadTitle.style!.fontWeight, FontWeight.w600);
    final readTitle = tester.widget<Text>(find.text('作業系統: 期中考範圍公告'));
    expect(readTitle.style!.fontWeight, FontWeight.w400);
  });

  testWidgets('點有 contexturl 的一列：開的是原始網址、圓點消失、未讀數減一', (tester) async {
    repo.nextList = fixtureNotifications();
    final opened = <(String, String)>[];

    await pump(tester, opened: opened);
    await tester.tap(find.text('作業已評分：HW1 & Report'));
    await tester.pumpAndSettle();

    expect(opened, [
      // 頁面不可以自己包 autologin：那是 RouteUtils.toWebViewPage 的事。
      (
        '作業已評分：HW1 & Report',
        'https://moodle2.ntust.edu.tw/mod/assign/view.php?id=77001'
      ),
    ]);
    expect(find.byKey(const ValueKey('unread-101')), findsNothing);
    expect(NotificationBadgeController.instance.unread.value, 1);
  });

  testWidgets('點沒有 contexturl 的一列：不開網頁，就地展開內文', (tester) async {
    repo.nextList = fixtureNotifications();
    final opened = <(String, String)>[];

    await pump(tester, opened: opened);
    expect(find.byType(MoodleHtmlView), findsNothing);
    await tester.tap(find.text('新的登入'));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.byType(MoodleHtmlView), findsOneWidget);
  });

  testWidgets('空清單 → 目前沒有通知', (tester) async {
    repo.nextList = fixtureNotifications('popup_notifications_none');

    await pump(tester);

    expect(find.text('目前沒有通知'), findsOneWidget);
    expect(find.byType(NotificationTile), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('清單空但有未讀數 → 說是使用者在 Moodle 關掉了，而不是「沒有通知」', (tester) async {
    repo.nextList = fixtureNotifications('popup_notifications_disabled');

    await pump(tester);

    expect(find.textContaining('你在 Moodle 關閉了站內通知'), findsOneWidget);
    expect(find.text('目前沒有通知'), findsNothing);
  });

  testWidgets('Moodle 那半失敗 → InlineErrorView，App 公告那半照樣畫得出來', (tester) async {
    noticeRepo.next = [notice('維護公告', DateTime.utc(2026, 9, 1))];
    repo.nextList = null;

    await pump(tester);

    expect(find.byType(InlineErrorView), findsOneWidget);
    expect(find.text('重新整理'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('沒登入 Moodle → InlineErrorView 的按鈕是「登入」，而不是整頁錯誤畫面',
      (tester) async {
    AuthSession.instance = FakeAuthSession(
        ensureResults: [AuthFailure.notSignedIn], isSignedIn: false);

    await pump(tester);

    expect(find.byType(InlineErrorView), findsOneWidget);
    expect(find.text('登入'), findsOneWidget);
    expect(find.text('重新整理'), findsNothing);
  });

  testWidgets('Stale：橫幅出現，而且「全部標為已讀」不出現（那個寫入一定會失敗）', (tester) async {
    // 先成功一次寫進快取，再讓下一次失敗，得到真的 Stale。
    repo.nextList = fixtureNotifications();
    final warmUp = AnnouncementCenterController();
    await warmUp.loadNotifications();
    warmUp.dispose();
    repo.nextList = null;

    await pump(tester);

    expect(find.byType(NotificationTile), findsNWidgets(3));
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.text('全部標為已讀'), findsNothing);
  });

  testWidgets('Stale 下點一則之後，橫幅還在、「全部標為已讀」仍然不出現', (tester) async {
    repo.nextList = fixtureNotifications();
    final warmUp = AnnouncementCenterController();
    await warmUp.loadNotifications();
    warmUp.dispose();
    repo.nextList = null;

    await pump(tester);
    await tester.tap(find.text('作業已評分：HW1 & Report'));
    await tester.pumpAndSettle();

    // 樂觀標記已讀不可以把 Stale 升級成 Ok：橫幅是使用者唯一知道自己在看
    // 舊資料的訊號，而那顆按鈕離線按下去一定失敗。
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.text('全部標為已讀'), findsNothing);
  });

  testWidgets('全部標為已讀：確認後全部變已讀、未讀數歸零', (tester) async {
    repo.nextList = fixtureNotifications();

    await pump(tester);
    expect(find.text('全部標為已讀'), findsOneWidget);

    await tester.tap(find.text('全部標為已讀'));
    await tester.pumpAndSettle();
    // 伺服器預設在已讀 7 天後刪除通知，所以要先確認。對話框不寫數字：
    // 那支 WS 標的是 {notifications} 全部，比這一頁的未讀數多。
    expect(find.textContaining('含沒有顯示在這一頁的'), findsOneWidget);
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unread-101')), findsNothing);
    expect(find.byKey(const ValueKey('unread-103')), findsNothing);
    expect(find.text('全部標為已讀'), findsNothing);
    expect(NotificationBadgeController.instance.unread.value, 0);
    expect(ui.toasts, ['已全部標為已讀']);
  });

  testWidgets('全部標為已讀失敗 → 圓點回來、toast 說失敗', (tester) async {
    repo.nextList = fixtureNotifications();
    repo.markAllResult = false;

    await pump(tester);
    await tester.tap(find.text('全部標為已讀'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unread-101')), findsOneWidget);
    expect(ui.toasts, ['標記全部已讀失敗']);
  });

  testWidgets('App 公告：Markdown、未讀點，而且日期沒有被 toLocal 位移', (tester) async {
    // RemoteConfigUtils 把公告時間重建成 UTC 欄位裝台北的牆上時間，
    // toLocal() 會讓這一則變成 9/5。
    noticeRepo.next = [
      notice('新版上線', DateTime.utc(2026, 9, 6, 1, 0)),
      notice('舊公告', DateTime.utc(2020, 1, 1)),
    ];

    final controller = await pump(tester);

    expect(find.byType(MarkdownBody), findsNWidgets(2));
    // 新的排前面。
    expect(tester.getTopLeft(find.text('新版上線').first).dy,
        lessThan(tester.getTopLeft(find.text('舊公告').first).dy));
    expect(find.text('2026/9/6'), findsOneWidget);
    expect(find.text('2026/9/5'), findsNothing);
    expect(find.text('發布時間'), findsNWidgets(2));
    // 進頁前沒讀過的那一則有未讀點；兩則都在快照之後，所以兩則都有。
    expect(find.byKey(const ValueKey('notice-unread-0')), findsOneWidget);
    expect(controller.lastReadSnapshot, DateTime.utc(2000));
  });

  testWidgets('App 公告空 → 目前沒有 TAT 公告', (tester) async {
    noticeRepo.next = [];
    repo.nextList = fixtureNotifications('popup_notifications_none');

    await pump(tester);

    expect(find.text('目前沒有 TAT 公告'), findsOneWidget);
    // 兩半都是頁面中段的區塊，用的是小一號的空狀態而不是整頁那張圖。
    expect(find.byType(SectionEmptyState), findsNWidgets(2));
    expect(find.byType(EmptyState), findsNothing);
  });

  test('icon 由 component 決定，不抓伺服器的 iconurl', () {
    // iconurl 是站台主題圖：每一列要多一次網路請求，深色模式也不會反相。
    expect(NotificationTile.iconFor('mod_assign'), Icons.assignment_outlined);
    expect(NotificationTile.iconFor('mod_forum'), Icons.forum_outlined);
    expect(NotificationTile.iconFor('mod_quiz'), Icons.quiz_outlined);
    expect(NotificationTile.iconFor('mod_choice'), Icons.poll_outlined);
    // 沒對到的模組仍然看得出是模組，core 與 null 才退回大聲公。
    expect(NotificationTile.iconFor('mod_wiki'), Icons.extension_outlined);
    expect(NotificationTile.iconFor('moodle'), Icons.campaign_outlined);
    expect(NotificationTile.iconFor(null), Icons.campaign_outlined);
  });

  test('這一頁不可以 import route_utils / error_page / base_page', () {
    // deps.py 的 MAX_SCC 棘輪擋得住，但那個數字看不出是誰違規；
    // 這條測試會直接指名檔案。
    for (final path in [
      'lib/ui/pages/announcement/announcement_center_page.dart',
      'lib/ui/pages/announcement/notification_tile.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final forbidden in [
        'ui/routes/route_utils.dart',
        'ui/components/page/error_page.dart',
        'ui/components/page/base_page.dart',
      ]) {
        expect(source.contains(forbidden), isFalse,
            reason: '$path 不該 import $forbidden');
      }
    }
  });
}
