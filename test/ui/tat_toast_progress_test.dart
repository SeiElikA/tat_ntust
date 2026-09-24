import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/ui/components/toast/tat_toast.dart';
import 'package:flutter_app/ui/service/get_task_ui_delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// 登入時「登入台科大 → 取得學期 → 登入 Moodle」是三個掛著的進度，先前各自一顆
/// 往上堆。現在同時只畫一顆，字跟著最裡面那一步走。
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    addTearDown(TatToast.resetForTest);
    await tester.pumpWidget(const GetMaterialApp(
      home: Scaffold(body: SizedBox.expand()),
    ));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('疊著的進度只有一顆膠囊，字是最裡面那一步；收掉就換回外面那一步',
      (tester) async {
    await pumpApp(tester);

    final outer = TatToast.progress('取得學期清單中...');
    await settle(tester);
    expect(TatToast.pillCount, 1);
    expect(find.text('取得學期清單中...'), findsOneWidget);

    final inner = TatToast.progress('登入Moodle中...');
    await settle(tester);
    expect(TatToast.pillCount, 1);
    expect(find.text('登入Moodle中...'), findsOneWidget);
    expect(find.text('取得學期清單中...'), findsNothing);

    inner.dismiss();
    await settle(tester);
    expect(TatToast.pillCount, 1);
    expect(find.text('取得學期清單中...'), findsOneWidget);

    outer.dismiss();
    await settle(tester);
    expect(TatToast.pillCount, 0);
  });

  testWidgets('外面那一步先收掉，裡面那一步照樣掛著', (tester) async {
    await pumpApp(tester);

    final outer = TatToast.progress('取得學期清單中...');
    final inner = TatToast.progress('登入Moodle中...');
    await settle(tester);

    outer.dismiss();
    await settle(tester);
    expect(TatToast.pillCount, 1);
    expect(find.text('登入Moodle中...'), findsOneWidget);

    inner.dismiss();
    inner.dismiss();
    await settle(tester);
    expect(TatToast.pillCount, 0);
  });

  testWidgets('登入頁開著時進度膠囊藏起來、蓋板讓路；關掉就回來', (tester) async {
    await pumpApp(tester);
    final handle = const GetTaskUiDelegate().beginProgress('登入Moodle中...');
    await settle(tester);

    AbsorbPointer blocker() => tester.widget<AbsorbPointer>(find.descendant(
        of: find.byType(Overlay), matching: find.byType(AbsorbPointer)));
    expect(find.text('登入Moodle中...'), findsOneWidget);
    expect(blocker().absorbing, isTrue);

    final page = Completer<void>();
    final closed = TatToast.whileLoginPage(() => page.future);
    await settle(tester);
    expect(find.text('登入Moodle中...'), findsNothing,
        reason: '登入頁自己有指示器，底下不該再浮一顆');
    expect(blocker().absorbing, isFalse,
        reason: '蓋板疊在所有 route 之上，不讓路就按不到驗證碼');

    page.complete();
    await closed;
    await settle(tester);
    expect(find.text('登入Moodle中...'), findsOneWidget);
    expect(blocker().absorbing, isTrue);

    handle.dismiss();
    await settle(tester);
    expect(TatToast.pillCount, 0);
  });

  testWidgets('一句提示不會把進度擠掉，兩者往上堆', (tester) async {
    await pumpApp(tester);

    final progress = TatToast.progress('取得學期清單中...');
    await settle(tester);
    TatToast.show('已複製');
    await settle(tester);

    expect(TatToast.pillCount, 2);
    progress.dismiss();
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
  });
}
