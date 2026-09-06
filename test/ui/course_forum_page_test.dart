import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_can_add_discussion.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_profile_entity.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/store/cache_store.dart';
import 'package:flutter_app/ui/components/page/empty_state.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_thread_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/forum_discussion_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/moodle_forum_fixtures.dart';
import '../helpers/recording_ui.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 一般討論區清單頁的畫面規格。清單以快取 seed，離線所以不碰網路；
/// 「能不能開新主題」沒有快取，所以由一顆假 repository 回答。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo repo;

  setUpAll(() async {
    await loadTestL10n();
    await initializeDateFormatting();
  });

  setUp(() {
    resetAppStatics();
    repo = _FakeRepo();
    MoodleRepository.instance = repo;
    AuthSession.instance = FakeAuthSession();
    TaskUiDelegate.instance = RecordingUi();
    ConnectivityProbe.instance = FakeConnectivityProbe(online: false);
  });

  tearDown(() {
    MoodleRepository.instance = MoodleRepository();
    AuthSession.instance = const UninstalledAuthSession();
    TaskUiDelegate.instance = const NoopTaskUiDelegate();
    ConnectivityProbe.instance = const PlatformConnectivityProbe();
  });

  final courseInfo = CourseInfoJson(
    main: CourseMainInfoJson(
        course: CourseMainJson(id: 'CS3001701', name: '作業系統')),
  );

  Future<void> seedDiscussions(int forumId, List<Discussions> list) =>
      CacheStore.instance.write(
        CacheKey<List<Discussions>>(
          'cache_moodle_forum_discussions',
          forumId.toString(),
          decode: (json) => (json as List)
              .map((e) => Discussions.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
        ),
        list,
      );

  Future<void> pump(WidgetTester tester,
      {List<(String, String)>? opened}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GetMaterialApp(
      home: CourseForumPage(
        courseInfo,
        forumId: 5499,
        forumName: '課程討論區',
        forumUrl: 'https://moodle2.ntust.edu.tw/mod/forum/view.php?id=90999',
        errorBuilder: (message) => Text('ERROR:$message'),
        openWebView: (title, url) async => opened?.add((title, url)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('清單從快取畫出來（離線）', (tester) async {
    await seedDiscussions(5499, fixtureDiscussions().discussions);

    await pump(tester);

    expect(find.byType(ForumDiscussionCard), findsNWidgets(2));
    expect(find.text('期中考 & 補考公告'), findsOneWidget);
  });

  testWidgets('點一列會推進討論串頁，帶的是 discussion 不是 id', (tester) async {
    await seedDiscussions(5499, fixtureDiscussions().discussions);

    await pump(tester);
    await tester.tap(find.byType(ForumDiscussionCard).first);
    await tester.pumpAndSettle();

    final page = tester
        .widget<CourseForumThreadPage>(find.byType(CourseForumThreadPage));
    expect(page.discussionId, 7701);
    expect(page.title, '期中考 & 補考公告');
  });

  testWidgets('空清單畫空狀態', (tester) async {
    await seedDiscussions(5499, const []);

    await pump(tester);

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text(R.current.forumEmpty), findsOneWidget);
  });

  testWidgets('can_add_discussion 說可以 → 有新主題的 FAB', (tester) async {
    repo.canAdd = Ok(MoodleCanAddDiscussion(status: true));
    await seedDiscussions(5499, fixtureDiscussions().discussions);

    await pump(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text(R.current.forumCannotPost), findsNothing);
  });

  testWidgets('說不行 → 沒有 FAB，改說一句為什麼並留網頁入口', (tester) async {
    repo.canAdd = Ok(MoodleCanAddDiscussion(status: false));
    await seedDiscussions(5499, fixtureDiscussions().discussions);

    await pump(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text(R.current.forumCannotPost), findsOneWidget);
  });

  testWidgets('問不到能不能發文：不給 FAB，但說一句為什麼並給重試', (tester) async {
    // repo 預設就是離線失敗：那一問沒有快取。
    await seedDiscussions(5499, fixtureDiscussions().discussions);

    await pump(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text(R.current.forumCannotCheckPosting), findsOneWidget);
    expect(find.text(R.current.forumCannotPost), findsNothing,
        reason: '問不到不等於不行，那句話會是假的');

    // 重試就地重問——不然只能離開頁面再進來一次。
    repo.canAdd = Ok(MoodleCanAddDiscussion(status: true));
    await tester.tap(find.ancestor(
        of: find.byIcon(LucideIcons.refreshCw),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text(R.current.forumCannotCheckPosting), findsNothing);
  });

  testWidgets('還在問（沒有答案）時不給 FAB', (tester) async {
    repo.holdCanAdd = true;
    await seedDiscussions(5499, fixtureDiscussions().discussions);

    await pump(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('伺服器說可以、但站台沒開放 add_discussion → 還是沒有 FAB', (tester) async {
    repo.canAdd = Ok(MoodleCanAddDiscussion(status: true));
    MoodleWebApiConnector.siteInfo = MoodleProfileEntity(functions: [
      MoodleProfileFunctions(
          name: MoodleWebApiConnector.discussionPostsFunction, version: '4.5'),
    ]);
    await seedDiscussions(5499, fixtureDiscussions().discussions);

    await pump(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('AppBar 的「在網頁開啟」用注入的開啟器，網址帶語系', (tester) async {
    final opened = <(String, String)>[];
    await seedDiscussions(5499, fixtureDiscussions().discussions);

    await pump(tester, opened: opened);
    await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(LucideIcons.externalLink)));
    await tester.pumpAndSettle();

    expect(opened.single.$1, '課程討論區');
    expect(opened.single.$2, contains('/mod/forum/view.php?id=90999'));
    expect(opened.single.$2, contains('lang='));
  });
}

/// 只換掉「能不能開新主題」那一支：它刻意沒有快取，離線時會直接 Failed。
class _FakeRepo extends MoodleRepository {
  Result<MoodleCanAddDiscussion>? canAdd;

  /// 永遠不回答，用來測「還在問」的狀態。
  bool holdCanAdd = false;

  @override
  Future<Result<MoodleCanAddDiscussion>> canAddDiscussion(int forumId) {
    if (holdCanAdd) return Completer<Result<MoodleCanAddDiscussion>>().future;
    return Future.value(
        canAdd ?? const Failed<MoodleCanAddDiscussion>(Offline()));
  }
}
