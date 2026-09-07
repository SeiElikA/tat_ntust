import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/util/rich_editor_bridge_utils.dart';
import 'package:flutter_app/ui/components/editor/moodle_rich_editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_l10n.dart';

/// 工具列的畫面規格。這一塊完全沒有 WebView，所以是整個所見即所得功能裡
/// 唯一測得動的 UI。
///
/// **不要用 `find.byType(TextButton)`**：Flutter 3.38 的 `TextButton.icon`
/// 回的是私有的 `_TextButtonWithIcon`，byType 一個都比不到，測試會假綠。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestL10n();
  });

  Future<void> pump(
    WidgetTester tester, {
    Set<String> active = const {},
    bool sourceMode = false,
    bool enabled = true,
    void Function(EditorCommand)? onCommand,
    VoidCallback? onToggleSource,
  }) async {
    // 工具列是橫向捲動的，視窗窄的話後面幾顆根本不會被建出來。
    tester.view.physicalSize = const Size(1600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MoodleRichEditorToolbar(
          active: active,
          sourceMode: sourceMode,
          enabled: enabled,
          onCommand: onCommand ?? (_) {},
          onToggleSource: onToggleSource ?? () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// `find.byTooltip` 比到的是 Tooltip，IconButton 是它的祖先。
  Finder buttonWithTooltip(String tooltip) => find.ancestor(
      of: find.byTooltip(tooltip), matching: find.byType(IconButton));

  testWidgets('每一個指令都有一顆鈕，另外還有一顆原始碼切換', (tester) async {
    await pump(tester);

    for (final command in EditorCommand.values) {
      expect(find.byTooltip(MoodleRichEditorToolbar.labelOf(command)),
          findsOneWidget,
          reason: '$command');
    }
    expect(find.byTooltip(R.current.forumEditorSource), findsOneWidget);
    // 就這些，一顆都不多。官方 App 也沒有插入圖片——這條路只能保留貼文
    // 原有的圖，多一顆按不出東西的鈕比沒有更糟。
    expect(find.byType(IconButton),
        findsNWidgets(EditorCommand.values.length + 1));
  });

  testWidgets('生效中的格式標成選取，其他不標', (tester) async {
    await pump(tester, active: const {'bold', 'h3'});

    IconButton buttonFor(String tooltip) =>
        tester.widget<IconButton>(buttonWithTooltip(tooltip));

    expect(
        buttonFor(MoodleRichEditorToolbar.labelOf(EditorCommand.bold))
            .isSelected,
        isTrue);
    expect(
        buttonFor(MoodleRichEditorToolbar.labelOf(EditorCommand.heading3))
            .isSelected,
        isTrue);
    expect(
        buttonFor(MoodleRichEditorToolbar.labelOf(EditorCommand.italic))
            .isSelected,
        isFalse);
    expect(
        buttonFor(MoodleRichEditorToolbar.labelOf(EditorCommand.heading4))
            .isSelected,
        isFalse);
  });

  testWidgets('按下去回報的是對應的那一個指令', (tester) async {
    final tapped = <EditorCommand>[];
    await pump(tester, onCommand: tapped.add);

    for (final command in EditorCommand.values) {
      await tester
          .tap(find.byTooltip(MoodleRichEditorToolbar.labelOf(command)));
      await tester.pump();
    }

    expect(tapped, EditorCommand.values);
  });

  testWidgets('原始碼模式：格式鈕全部停用，只剩切換鈕還能按', (tester) async {
    var toggles = 0;
    final tapped = <EditorCommand>[];
    await pump(tester,
        sourceMode: true,
        onCommand: tapped.add,
        onToggleSource: () => toggles++);

    for (final command in EditorCommand.values) {
      final button = tester.widget<IconButton>(
          buttonWithTooltip(MoodleRichEditorToolbar.labelOf(command)));
      expect(button.onPressed, isNull, reason: '$command');
    }
    expect(
        tester
            .widget<IconButton>(buttonWithTooltip(R.current.forumEditorSource))
            .isSelected,
        isTrue);

    await tester.tap(find.byTooltip(R.current.forumEditorSource));
    await tester.pump();
    expect(toggles, 1);
    expect(tapped, isEmpty);
  });

  testWidgets('編輯器還沒準備好時整排都按不動——包括原始碼切換', (tester) async {
    await pump(tester, enabled: false);

    for (final command in EditorCommand.values) {
      expect(
          tester
              .widget<IconButton>(
                  buttonWithTooltip(MoodleRichEditorToolbar.labelOf(command)))
              .onPressed,
          isNull);
    }
    expect(
        tester
            .widget<IconButton>(buttonWithTooltip(R.current.forumEditorSource))
            .onPressed,
        isNull);
  });
}
