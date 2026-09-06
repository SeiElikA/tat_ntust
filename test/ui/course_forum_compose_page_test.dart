import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_compose_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/recording_ui.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 撰寫頁的規格。這一頁不碰 repository：送出的動作由呼叫端注入，
/// 所以整組測試都不需要網路、快取或登入。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingUi ui;

  setUpAll(() async {
    await loadTestL10n();
    await initializeDateFormatting();
  });

  setUp(() {
    resetAppStatics();
    ui = RecordingUi();
    TaskUiDelegate.instance = ui;
  });

  tearDown(() {
    TaskUiDelegate.instance = const NoopTaskUiDelegate();
  });

  MoodleForumPost parent() => MoodleForumPost(
        id: 900,
        subject: '期中考公告',
        replysubject: '回覆: 期中考公告',
        message: '<p>期中考於下週三舉行</p>',
        discussionid: 7701,
        timecreated: 1756900000,
        author: MoodleForumAuthor(fullname: '王老師'),
      );

  Finder sendButton() => find.widgetWithText(TextButton, R.current.forumSend);

  /// 回覆模式。[onSend] 收到內文，回傳要給頁面的結果。
  Future<void> pumpReply(
    WidgetTester tester, {
    required Future<Result<MoodleForumPost>> Function(String text) onSend,
    List<(String, String)>? opened,
    List<MoodleForumPost?>? popped,
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await Get.to<MoodleForumPost>(
                () => CourseForumComposePage.reply(
                  parent: parent(),
                  subject: '回覆: 期中考公告',
                  onSendReply: onSend,
                  dirName: '作業系統',
                  openWebView: (title, url) async => opened?.add((title, url)),
                  webUrl:
                      'https://moodle2.ntust.edu.tw/mod/forum/discuss.php?d=7701',
                  webTitle: '期中考公告',
                ),
              );
              popped?.add(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpNew(
    WidgetTester tester, {
    required Future<Result<int>> Function(String subject, String text) onSend,
    List<int?>? popped,
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await Get.to<int>(
                () => CourseForumComposePage.newDiscussion(
                  forumName: '課程討論區',
                  onSendDiscussion: onSend,
                  dirName: '作業系統',
                  openWebView: (title, url) async {},
                  webUrl:
                      'https://moodle2.ntust.edu.tw/mod/forum/view.php?id=90999',
                  webTitle: '課程討論區',
                ),
              );
              popped?.add(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('內文是空的或只有空白時，送出是停用的', (tester) async {
    var calls = 0;
    await pumpReply(tester, onSend: (text) async {
      calls++;
      return Ok(parent());
    });

    expect(tester.widget<TextButton>(sendButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<TextButton>(sendButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '有內容了');
    await tester.pump();
    expect(tester.widget<TextButton>(sendButton()).onPressed, isNotNull);
    expect(calls, 0);
  });

  testWidgets('新主題模式：只有內文、沒有標題時送出仍然停用', (tester) async {
    await pumpNew(tester, onSend: (s, t) async => const Ok(4321));

    final message = find.byType(TextField).last;
    await tester.enterText(message, '請問這題怎麼算');
    await tester.pump();

    expect(tester.widget<TextButton>(sendButton()).onPressed, isNull,
        reason: '沒有標題不能送');

    await tester.enterText(find.byType(TextField).first, '作業問題');
    await tester.pump();
    expect(tester.widget<TextButton>(sendButton()).onPressed, isNotNull);
  });

  testWidgets('連點兩下送出只會送出一次——這一支沒有冪等鍵', (tester) async {
    var calls = 0;
    await pumpReply(tester, onSend: (text) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return Ok(parent());
    });

    await tester.enterText(find.byType(TextField), '謝謝老師');
    await tester.pump();

    await tester.tap(sendButton());
    await tester.pump();
    // 第一次還在飛，第二次點下去必須什麼都不做。
    expect(tester.widget<TextButton>(sendButton()).onPressed, isNull);
    await tester.tap(sendButton(), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('送出成功會帶著新貼文 pop 回上一頁', (tester) async {
    final added = MoodleForumPost(id: 950, message: '<p>謝謝老師</p>');
    final popped = <MoodleForumPost?>[];
    await pumpReply(tester, onSend: (text) async => Ok(added), popped: popped);

    await tester.enterText(find.byType(TextField), '謝謝老師');
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pumpAndSettle();

    expect(find.byType(CourseForumComposePage), findsNothing);
    expect(popped.single?.id, 950);
  });

  testWidgets('送出失敗：留在原地、打的字還在，吐對應好的訊息', (tester) async {
    await pumpReply(tester,
        onSend: (text) async =>
            Failed<MoodleForumPost>(FetchFailed(R.current.forumErrorPostGone)));

    await tester.enterText(find.byType(TextField), '謝謝老師');
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pumpAndSettle();

    expect(find.byType(CourseForumComposePage), findsOneWidget);
    expect(find.text('謝謝老師'), findsOneWidget);
    expect(ui.toasts, [R.current.forumErrorPostGone]);
    // 再送一次要送得出去：失敗不可以把頁面鎖死。
    expect(tester.widget<TextButton>(sendButton()).onPressed, isNotNull);
  });

  testWidgets('有草稿時返回會先問；按取消留在原地、文字還在', (tester) async {
    await pumpReply(tester, onSend: (text) async => Ok(parent()));

    await tester.enterText(find.byType(TextField), '還沒送出的字');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text(R.current.forumDiscardDraft), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, R.current.cancel));
    await tester.pumpAndSettle();

    expect(find.byType(CourseForumComposePage), findsOneWidget);
    expect(find.text('還沒送出的字'), findsOneWidget);
  });

  testWidgets('有草稿時返回按確定：離開，而且沒有任何結果被帶回去', (tester) async {
    final popped = <MoodleForumPost?>[];
    await pumpReply(tester,
        onSend: (text) async => Ok(parent()), popped: popped);

    await tester.enterText(find.byType(TextField), '還沒送出的字');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, R.current.sure));
    await tester.pumpAndSettle();

    expect(find.byType(CourseForumComposePage), findsNothing);
    expect(popped.single, isNull, reason: '沒有送出，不該帶回任何貼文');
    expect(ui.toasts, isEmpty);
  });

  testWidgets('送出中按返回：不放棄草稿、不離開，送出完成之後 pop 掉的還是撰寫頁自己', (tester) async {
    final gate = Completer<Result<MoodleForumPost>>();
    final popped = <MoodleForumPost?>[];
    await pumpReply(tester, onSend: (text) => gate.future, popped: popped);

    await tester.enterText(find.byType(TextField), '謝謝老師');
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pump();

    // 送出中要看得出來：這一頁沒有進度遮罩，只有鈕上這顆轉圈。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pageBack();
    await tester.pump();

    expect(find.text(R.current.forumDiscardDraft), findsNothing,
        reason: '飛在路上的回覆不是可以放棄的草稿');
    expect(find.byType(CourseForumComposePage), findsOneWidget);
    expect(ui.toasts, [R.current.forumSending]);

    gate.complete(Ok(MoodleForumPost(id: 950, message: '<p>謝謝老師</p>')));
    await tester.pumpAndSettle();

    // 收到回應才離開，而且離開的是這一頁：上一頁還在，回覆也帶回去了。
    expect(find.byType(CourseForumComposePage), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(popped.single?.id, 950);
  });

  testWidgets('新主題送出成功：pop 掉的是撰寫頁自己，帶回討論串 id', (tester) async {
    final popped = <int?>[];
    await pumpNew(tester,
        onSend: (s, t) async => const Ok(4321), popped: popped);

    await tester.enterText(find.byType(TextField).first, '作業問題');
    await tester.enterText(find.byType(TextField).last, '請問這題怎麼算');
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pumpAndSettle();

    expect(find.byType(CourseForumComposePage), findsNothing);
    expect(find.text('open'), findsOneWidget, reason: '只 pop 自己這一頁');
    expect(popped.single, 4321);
  });

  testWidgets('新主題標題撞到 255 就停住：超過會是伺服器的 dmlwriteexception', (tester) async {
    await pumpNew(tester, onSend: (s, t) async => const Ok(4321));

    final subject = find.byType(TextField).first;
    await tester.enterText(subject, '題' * 300);
    await tester.pump();

    expect(tester.widget<TextField>(subject).controller?.text.length,
        MoodleForumUtils.subjectMaxLength);
    expect(find.text('255/255'), findsOneWidget, reason: '快撞到上限才出現計數器');
  });

  testWidgets('沒有草稿時返回不會多問一次', (tester) async {
    await pumpReply(tester, onSend: (text) async => Ok(parent()));

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text(R.current.forumDiscardDraft), findsNothing);
    expect(find.byType(CourseForumComposePage), findsNothing);
  });

  testWidgets('轉螢幕之後打的字還在（草稿活在 State 裡）', (tester) async {
    await pumpReply(tester, onSend: (text) async => Ok(parent()));

    await tester.enterText(find.byType(TextField), '轉個螢幕試試');
    await tester.pump();

    tester.view.physicalSize = const Size(2000, 800);
    await tester.pumpAndSettle();

    expect(find.text('轉個螢幕試試'), findsOneWidget);
  });

  testWidgets('頁尾說明只能發純文字，並留一個網頁入口', (tester) async {
    final opened = <(String, String)>[];
    await pumpReply(tester,
        onSend: (text) async => Ok(parent()), opened: opened);

    expect(find.text(R.current.forumPlainTextOnly), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, R.current.forumOpenInWeb));
    await tester.pumpAndSettle();

    expect(opened.single.$2, contains('discuss.php?d=7701'));
  });
}
