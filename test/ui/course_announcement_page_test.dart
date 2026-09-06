import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/controller/course_data/course_data_controller.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/store/cache_store.dart';
import 'package:flutter_app/ui/pages/course_data/screen/course_announcement_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_thread_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/moodle_forum_fixtures.dart';
import '../helpers/recording_ui.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 課程頁「公告」分頁的畫面規格。離線、快取預先塞好，與 course_assignment_page_test
/// 同一套。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const courseId = 'CS3001701';

  setUpAll(() async {
    await loadTestL10n();
    await initializeDateFormatting();
  });

  setUp(() {
    resetAppStatics();
    AuthSession.instance = FakeAuthSession();
    TaskUiDelegate.instance = RecordingUi();
    ConnectivityProbe.instance = FakeConnectivityProbe(online: false);
    MoodleRepository.instance = MoodleRepository();
  });

  tearDown(() {
    AuthSession.instance = const UninstalledAuthSession();
    TaskUiDelegate.instance = const NoopTaskUiDelegate();
    ConnectivityProbe.instance = const PlatformConnectivityProbe();
  });

  final courseInfo = CourseInfoJson(
    main:
        CourseMainInfoJson(course: CourseMainJson(id: courseId, name: '作業系統')),
  );

  Future<void> seed(MoodleModForumGetForumDiscussions data) =>
      CacheStore.instance.write(
        CacheKey<MoodleModForumGetForumDiscussions>(
          'cache_moodle_message',
          courseId,
          decode: (json) => MoodleModForumGetForumDiscussions.fromJson(json),
        ),
        data,
      );

  Future<CourseDataController> pump(WidgetTester tester) async {
    final controller = CourseDataController(courseId);
    await controller.loadAnnouncements();
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: CourseAnnouncementPage(
          courseInfo,
          controller: controller,
          errorBuilder: (m) => Text('ERR:$m'),
          openWebView: (title, url) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(controller.dispose);
    return controller;
  }

  /// fixture 的兩則加一則自己捏的，用來驗「沒有回覆就沒有回覆數」。
  MoodleModForumGetForumDiscussions threeDiscussions() {
    final data = fixtureDiscussions();
    data.discussions.add(Discussions(
      id: 8803,
      discussion: 7703,
      name: '停課通知',
      subject: '停課通知',
      message: '<p>本週停課。</p>',
      userfullname: '李助教',
      created: 1755000000,
      modified: 1755000000,
    ));
    return data;
  }

  testWidgets('三則公告：置頂圖示、回覆數、作者與時間', (tester) async {
    await seed(threeDiscussions());

    await pump(tester);

    // 伺服器 format_string 過的 `&amp;`，connector 已還原。
    expect(find.text('期中考 & 補考公告'), findsOneWidget);
    expect(find.textContaining('&amp;'), findsNothing);
    expect(find.text('第一週上課說明'), findsOneWidget);
    expect(find.text('停課通知'), findsOneWidget);

    expect(find.byIcon(LucideIcons.pin), findsOneWidget,
        reason: '只有第一則是 pinned');
    expect(find.text('3 則回覆'), findsOneWidget);
    expect(find.byIcon(LucideIcons.messageSquare), findsOneWidget,
        reason: 'numreplies 是 0 的那兩則不畫回覆數');

    // fixture 那則是老師編輯過的（created < modified）。清單印建立時間，
    // 才會跟詳情頁第一篇印的是同一個時間。
    final created = DateFormat.yMd()
        .add_jm()
        .format(DateTime.fromMillisecondsSinceEpoch(1756900000 * 1000));
    expect(find.text('王老師 · $created'), findsOneWidget);
    final edited = DateFormat.yMd()
        .add_jm()
        .format(DateTime.fromMillisecondsSinceEpoch(1757000000 * 1000));
    expect(find.textContaining(edited), findsNothing);
  });

  testWidgets('沒有公告區：畫專屬空狀態，不畫清單也不彈任何對話框', (tester) async {
    await seed(MoodleModForumGetForumDiscussions(forumFound: false));

    await pump(tester);

    expect(find.text('這門課沒有公告區'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.textContaining('ERR:'), findsNothing);
    // 這次改動的重點：沒有公告區不是失敗，不該跳重試框。
    expect((TaskUiDelegate.instance as RecordingUi).confirmCalls, 0);
  });

  testWidgets('有公告區但沒有公告 → 暫無公告', (tester) async {
    await seed(MoodleModForumGetForumDiscussions());

    await pump(tester);

    expect(find.text('暫無公告'), findsOneWidget);
    expect(find.text('這門課沒有公告區'), findsNothing);
  });

  testWidgets('抓不到也沒有快取 → 注入的 errorBuilder', (tester) async {
    await pump(tester);

    expect(find.text('ERR:${R.current.networkError}'), findsOneWidget);
  });

  testWidgets('點一張卡 → 進討論串頁', (tester) async {
    await seed(threeDiscussions());

    await pump(tester);
    await tester.tap(find.text('期中考 & 補考公告'));
    await tester.pumpAndSettle();

    expect(find.byType(CourseForumThreadPage), findsOneWidget);
  });
}
