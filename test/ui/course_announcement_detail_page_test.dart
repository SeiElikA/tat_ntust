import 'package:flutter/material.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/store/cache_store.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/page/inline_error_view.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_announcement_detail_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/moodle_forum_fixtures.dart';
import '../helpers/recording_ui.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 公告討論串頁的畫面規格。貼文以快取 seed，離線所以不碰網路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    main: CourseMainInfoJson(
        course: CourseMainJson(id: 'CS3001701', name: '作業系統')),
  );

  Discussions discussion() => fixtureDiscussions().discussions.first;

  Future<void> seedPosts(int discussionId, List<MoodleForumPost> posts) =>
      CacheStore.instance.write(
        CacheKey<List<MoodleForumPost>>(
          'cache_moodle_forum_posts',
          discussionId.toString(),
          decode: (json) => (json as List)
              .map((e) =>
                  MoodleForumPost.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
        ),
        posts,
      );

  Future<void> pump(
    WidgetTester tester, {
    Discussions? d,
    List<(String, String)>? opened,
  }) async {
    // ListView 是懶載入的，超出視窗的段落根本不會被建出來；把視窗拉高，
    // 整頁都在畫面上。
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GetMaterialApp(
      home: CourseAnnouncementDetailPage(
        courseInfo,
        d ?? discussion(),
        openWebView: (title, url) async => opened?.add((title, url)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('四篇貼文：作者依 DFS 順序，只有第一篇印標題', (tester) async {
    await seedPosts(7701, fixturePosts());

    await pump(tester);

    expect(find.byType(SectionCard), findsNWidgets(4));
    // 王老師（根）→ 陳同學 → 王老師 → 已刪除那篇（作者是空的）。
    double y(Finder f) => tester.getTopLeft(f).dy;
    expect(y(find.text('陳同學')), lessThan(y(find.text('不明的發文者'))));

    // 只有第一篇印 subject，回覆的「Re: …」不重複印。
    expect(find.text('期中考 & 補考公告'), findsNWidgets(2),
        reason: 'AppBar 一個、第一篇的子標題一個');
    expect(find.textContaining('Re: '), findsNothing);

    expect(find.textContaining('期中考範圍如圖', findRichText: true), findsOneWidget);
    expect(find.textContaining('可以帶計算機嗎', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppBar 標題是公告名稱', (tester) async {
    await seedPosts(7701, fixturePosts());

    await pump(tester);

    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.text('期中考 & 補考公告')),
      findsOneWidget,
    );
  });

  testWidgets('縮排：回覆有左邊距，巢狀那一篇更深', (tester) async {
    await seedPosts(7701, fixturePosts());

    await pump(tester);

    /// 每一則的最外層縮排是 `EdgeInsets.only(left:)`；ListView 自己的 padding
    /// 有上下邊所以不會被選中。
    double indentOf(String body) {
      final block = find
          .ancestor(
            of: find.textContaining(body, findRichText: true),
            matching: find.byWidgetPredicate((w) =>
                w is Padding &&
                w.padding is EdgeInsets &&
                (w.padding as EdgeInsets).top == 0 &&
                (w.padding as EdgeInsets).right == 0 &&
                (w.padding as EdgeInsets).bottom == 0),
          )
          .last;
      return (tester.widget<Padding>(block).padding as EdgeInsets).left;
    }

    expect(indentOf('期中考範圍如圖'), 0, reason: '根貼文不縮排');
    expect(indentOf('可以帶計算機嗎'), greaterThan(0));
    expect(indentOf('不能用可程式化的'), greaterThan(indentOf('可以帶計算機嗎')));
  });

  testWidgets('已刪除的貼文：畫刪除提示、沒有時間字串', (tester) async {
    await seedPosts(7701, fixturePosts());

    await pump(tester);

    expect(find.text('這則貼文已被刪除'), findsOneWidget);
    expect(find.text('此貼文已被刪除'), findsNothing,
        reason: '伺服器語系的字串不直接顯示，改用自己的 l10n');
  });

  testWidgets('第一篇的附件畫成檔案列', (tester) async {
    await seedPosts(7701, fixturePosts());

    await pump(tester);

    expect(find.text('附件'), findsOneWidget);
    expect(find.widgetWithText(MoodleFileTile, 'slides.pdf'), findsOneWidget);
    expect(find.byIcon(LucideIcons.download), findsOneWidget);
  });

  testWidgets('抓不到回覆：仍然畫出公告本文加就地重試，不是整頁錯誤', (tester) async {
    await pump(tester);

    expect(find.byType(InlineErrorView), findsOneWidget);
    // 清單那一列本身就是第一篇貼文，內容還在。
    expect(
        find.textContaining('期中考於下週三舉行', findRichText: true), findsOneWidget);
    expect(find.text('王老師'), findsOneWidget);
    // 子標題走 discussion.subject，實體同樣要在 connector 就還原掉。
    expect(find.text('期中考 & 補考公告'), findsNWidgets(2),
        reason: 'AppBar 的 name 與卡片子標題的 subject');
    expect(find.textContaining('&amp;'), findsNothing);
    expect(
        find.widgetWithText(MoodleFileTile, 'exam_scope.pdf'), findsOneWidget);
  });

  testWidgets('本文的連結交給注入的 openWebView', (tester) async {
    final opened = <(String, String)>[];
    final posts = [
      MoodleForumPost(
        id: 900,
        subject: '公告',
        message: '<p><a href="https://example.com/x">safe</a></p>',
        discussionid: 7701,
        timecreated: 1756900000,
        author: MoodleForumAuthor(fullname: '王老師'),
      ),
    ];
    await seedPosts(7701, posts);

    await pump(tester, opened: opened);

    final link = find.text('safe', findRichText: true);
    await tester.tapAt(tester.getTopLeft(link) + const Offset(6, 8));
    await tester.pumpAndSettle();

    expect(opened, [('期中考 & 補考公告', 'https://example.com/x')]);
  });
}
