import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/moodle_forum_edit_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/editor/moodle_rich_editor.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_rich_edit_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_l10n.dart';

/// 編輯面與附件怎麼分高度。
///
/// WebView 在 flutter_test 底下畫不出來（平台實作沒註冊），所以這一頁的量測
/// 只能在**第一格畫面**做：`onLoadFailed` 是 post-frame 才送出來的，再 pump
/// 一次整頁就換成 InlineErrorView 了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestL10n();
  });

  group('attachSlot', () {
    const gap = 8.0;
    const editorMin = 220.0;

    test('空間排得下清單時，編輯面至少 220', () {
      for (var room = 0.0; room <= 1400; room += 1) {
        final slot = CourseForumRichEditPage.attachSlot(room, keyboard: false);
        if (slot.dense) continue;
        expect(room - gap - slot.cap, greaterThanOrEqualTo(editorMin),
            reason: 'room=$room');
      }
    });

    test('任何高度下編輯面都拿得到一半以上——沒有反過來蓋掉保留的地板', () {
      for (var room = 0.0; room <= 1400; room += 1) {
        for (final keyboard in [true, false]) {
          final slot =
              CourseForumRichEditPage.attachSlot(room, keyboard: keyboard);
          expect(slot.cap, lessThanOrEqualTo((room - gap) / 2),
              reason: 'room=$room keyboard=$keyboard');
        }
      }
    });

    test('連「標題＋一列」都排不下就收成一列標題', () {
      expect(CourseForumRichEditPage.attachSlot(300, keyboard: false).dense,
          isTrue);
      expect(CourseForumRichEditPage.attachSlot(600, keyboard: false).dense,
          isFalse);
    });

    test('鍵盤升起時一律收成一列標題', () {
      expect(CourseForumRichEditPage.attachSlot(900, keyboard: true).dense,
          isTrue);
    });

    test('高度不夠時上限會掉到卡片自己的 padding 以下——那時整張卡不畫', () {
      expect(CourseForumRichEditPage.attachSlot(40, keyboard: false).cap,
          lessThan(24));
    });
  });

  group('版面', () {
    MoodleForumFile file(int i) => MoodleForumFile(
        filename: '附件$i.pdf', filepath: '/', url: 'https://example.invalid/$i');

    /// 只 pump 一格：`onLoadFailed` 是 post-frame 才送出來的，再 pump 一次
    /// 整頁就換成 InlineErrorView，什麼都量不到了。
    Future<void> pumpPage(
      WidgetTester tester, {
      required Size size,
      double textScale = 1,
      int attachments = 9,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: CourseForumRichEditPage(
              postId: 951,
              isTopicPost: true,
              initialSubject: '期中考公告',
              initialHtml: '<p>內容</p>',
              existingAttachments: [
                for (var i = 0; i < attachments; i++) file(i)
              ],
              attachPolicy: const ForumAttachPolicy(
                  enabled: true, maxFiles: 9, maxBytes: 10485760),
              onSend: (subject, html, keep, added,
                      {required onProgress}) async =>
                  const Ok(ForumEditOutcome()),
              onPickFiles: (_) async => <File>[],
              onCancelUpload: () {},
              onOpenAttachment: (_) async {},
            ),
          ),
        ),
      ));
    }

    double editorHeight(WidgetTester tester) =>
        tester.getSize(find.byType(MoodleRichEditor)).height;

    /// 附件卡是最後一張。
    double attachHeight(WidgetTester tester) =>
        tester.getSize(find.byType(SectionCard).last).height;

    testWidgets('402×874、九個附件：清單列得出來，編輯面拿得到 220', (tester) async {
      await pumpPage(tester, size: const Size(402, 874));

      expect(find.byType(MoodleFileTile), findsWidgets);
      expect(editorHeight(tester), greaterThanOrEqualTo(220));
      expect(tester.takeException(), isNull);
    });

    testWidgets('375×667、九個附件：清單列得出來，編輯面一樣拿得到 220', (tester) async {
      await pumpPage(tester, size: const Size(375, 667));

      expect(find.byType(MoodleFileTile), findsWidgets);
      expect(editorHeight(tester), greaterThanOrEqualTo(220));
      expect(tester.takeException(), isNull);
    });

    testWidgets('320×568、九個附件：附件收成一列，編輯面仍比它高', (tester) async {
      await pumpPage(tester, size: const Size(320, 568));

      // 排不下清單就只留「附件 9/9」那一列，把高度還給編輯面。
      expect(find.byType(MoodleFileTile), findsNothing);
      expect(find.textContaining('9/9'), findsOneWidget);
      expect(editorHeight(tester), greaterThan(attachHeight(tester)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('320×568、字級 3.0：編輯面沒有被壓成 0，版面也沒被撐破', (tester) async {
      await pumpPage(tester, size: const Size(320, 568), textScale: 3.0);

      expect(editorHeight(tester), greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });
}
