import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_profile_entity.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_compose_page.dart';
import 'package:sprintf/sprintf.dart';
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
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_thread_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/moodle_forum_fixtures.dart';
import '../helpers/recording_ui.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';
import '../helpers/finders.dart';

/// 討論串頁的畫面規格。貼文以快取 seed，離線所以不碰網路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestL10n();
    await initializeDateFormatting();
  });

  late RecordingUi ui;

  setUp(() {
    resetAppStatics();
    AuthSession.instance = FakeAuthSession();
    ui = RecordingUi();
    TaskUiDelegate.instance = ui;
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
      home: CourseForumThreadPage(
        courseInfo,
        discussionId: (d ?? discussion()).discussion,
        title: (d ?? discussion()).name,
        fallbackDiscussion: d ?? discussion(),
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

  MoodleForumPost postWith({
    required int id,
    bool? reply,
    int? parentid,
    String message = '<p>內容</p>',
    bool isdeleted = false,
  }) {
    final p = MoodleForumPost(
      id: id,
      subject: '主題',
      message: message,
      discussionid: 7701,
      hasparent: parentid != null,
      parentid: parentid,
      timecreated: 1756900000,
      isdeleted: isdeleted,
      author: MoodleForumAuthor(fullname: '陳同學'),
    );
    if (reply != null) {
      p.capabilities = MoodleForumPostCapabilities(reply: reply);
    }
    return p;
  }

  /// 站台把 functions[] 回報成「沒有 add_discussion_post」。
  void siteWithoutPosting() {
    MoodleWebApiConnector.siteInfo = MoodleProfileEntity(functions: [
      MoodleProfileFunctions(
          name: MoodleWebApiConnector.discussionPostsFunction, version: '4.5'),
    ]);
  }

  Finder replyButton() => buttonWithText(R.current.forumReply);

  testWidgets('capabilities.reply 為 true 的才有回覆鈕；已刪除與沒有 capabilities 的都沒有',
      (tester) async {
    await seedPosts(7701, fixturePosts());

    await pump(tester);

    // fixture 的 900 / 901 / 902 可回覆，已刪除的 903 不行。
    expect(replyButton(), findsNWidgets(3));
  });

  testWidgets('完全沒有 capabilities 區塊（舊快取）→ 一顆回覆鈕都不畫', (tester) async {
    await seedPosts(7701, [postWith(id: 900)]);

    await pump(tester);

    expect(replyButton(), findsNothing);
    expect(find.text(R.current.forumThreadLocked), findsOneWidget);
  });

  testWidgets('站台沒開放 add_discussion_post 時整排回覆鈕都不畫', (tester) async {
    siteWithoutPosting();
    await seedPosts(7701, fixturePosts());

    await pump(tester);

    expect(replyButton(), findsNothing);
  });

  testWidgets('沒有任何一篇能回覆時：畫「不開放回覆」加網頁入口，不是一顆會失敗的鈕', (tester) async {
    final opened = <(String, String)>[];
    await seedPosts(7701, [postWith(id: 900, reply: false)]);

    await pump(tester, opened: opened);

    expect(find.text(R.current.forumThreadLocked), findsOneWidget);
    final webButton = buttonWithText(R.current.forumOpenInWeb);
    expect(webButton, findsOneWidget);

    await tester.tap(webButton);
    await tester.pumpAndSettle();

    expect(opened.single.$2, contains('/mod/forum/discuss.php?d=7701'));
  });

  testWidgets('點回覆會推出撰寫頁，而且引用了被回覆的那一篇', (tester) async {
    await seedPosts(7701, fixturePosts());

    await pump(tester);
    await tester.tap(replyButton().first);
    await tester.pumpAndSettle();

    expect(find.byType(CourseForumComposePage), findsOneWidget);
    // 「回覆 王老師」：送出前使用者看得到自己在回誰。
    expect(
        find.text(sprintf(R.current.forumReplyingTo, ['王老師'])), findsOneWidget);
    expect(find.textContaining('期中考範圍如圖', findRichText: true), findsOneWidget);
    expect(find.text(R.current.forumPlainTextOnly), findsOneWidget);
  });

  testWidgets('送出成功：新貼文併進討論串、吐「已送出」，重抓也成功', (tester) async {
    final repo = _FakeRepo()
      ..nextReply = Ok(postWith(id: 950, reply: true, parentid: 900));
    MoodleRepository.instance = repo;
    await seedPosts(7701, fixturePosts());

    await pump(tester);
    await tester.tap(replyButton().first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '謝謝老師');
    await tester.pump();
    await tester.tap(buttonWithText(R.current.forumSend));
    await tester.pumpAndSettle();

    // 回到討論串，剛送出的那一則在畫面上。
    expect(find.byType(CourseForumComposePage), findsNothing);
    expect(repo.replyCalls, 1);
    expect(ui.toasts, contains(R.current.forumSendDone));
    expect(ui.toasts, isNot(contains(R.current.forumSendDoneRefreshFailed)));
    expect(find.byType(SectionCard), findsNWidgets(5));
  });

  testWidgets('送出成功但重抓失敗：回覆留在畫面上、畫舊資料橫幅，不變成錯誤頁', (tester) async {
    final repo = _FakeRepo()
      ..nextReply = Ok(postWith(id: 950, reply: true, parentid: 900))
      ..reloadFails = true;
    MoodleRepository.instance = repo;
    await seedPosts(7701, fixturePosts());

    await pump(tester);
    await tester.tap(replyButton().first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '謝謝老師');
    await tester.pump();
    await tester.tap(buttonWithText(R.current.forumSend));
    await tester.pumpAndSettle();

    expect(find.byType(SectionCard), findsNWidgets(5),
        reason: '寫入成功了，剛送出的那一則不可以消失');
    expect(find.byType(InlineErrorView), findsNothing, reason: '不是錯誤畫面');
    expect(find.text(R.current.refresh), findsOneWidget, reason: '舊資料橫幅');
    expect(ui.toasts, contains(R.current.forumSendDone));
    expect(ui.toasts, contains(R.current.forumSendDoneRefreshFailed));
  });

  testWidgets('送出失敗：留在撰寫頁、文字還在，吐對應好的訊息', (tester) async {
    MoodleRepository.instance = _FakeRepo()
      ..nextReply = Failed(FetchFailed(R.current.forumErrorNoPermission));
    await seedPosts(7701, fixturePosts());

    await pump(tester);
    await tester.tap(replyButton().first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '謝謝老師');
    await tester.pump();
    await tester.tap(buttonWithText(R.current.forumSend));
    await tester.pumpAndSettle();

    expect(find.byType(CourseForumComposePage), findsOneWidget);
    expect(find.text('謝謝老師'), findsOneWidget);
    expect(ui.toasts, contains(R.current.forumErrorNoPermission));
    expect(ui.toasts, isNot(contains(R.current.forumSendDone)));
  });
}

/// 只換掉兩件事：送出回覆，以及送出之後的重抓。其餘（快取）走真的路徑。
class _FakeRepo extends MoodleRepository {
  Result<MoodleForumPost>? nextReply;
  bool reloadFails = false;
  int replyCalls = 0;
  int reloadCalls = 0;

  @override
  Future<Result<MoodleForumPost>> postReply({
    required int postId,
    required String subject,
    required String text,
  }) async {
    replyCalls++;
    return nextReply ?? Failed(FetchFailed(R.current.forumSendError));
  }

  @override
  Future<Result<List<MoodleForumPost>>> getDiscussionPosts(
      int discussionId) async {
    reloadCalls++;
    // 第一趟是進頁面時的載入，一律成功；之後那一趟才是「送出後的重抓」。
    if (reloadFails && reloadCalls > 1) {
      return Failed<List<MoodleForumPost>>(FetchFailed(R.current.networkError));
    }
    final result = await super.getDiscussionPosts(discussionId);
    // 測試是離線的，快取命中會回 Stale；這裡要的是「重抓成功」。
    final data = result.dataOrNull;
    return data == null ? result : Ok<List<MoodleForumPost>>(data);
  }
}
