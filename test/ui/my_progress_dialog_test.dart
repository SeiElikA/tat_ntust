import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/ui/other/my_progress_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host() => MaterialApp(
      builder: BotToastInit(),
      navigatorObservers: [BotToastNavigatorObserver()],
      home: const Scaffold(body: SizedBox()),
    );

/// 讓 BotToast 的進出場動畫跑完，但不用 pumpAndSettle——進度框裡的 SpinKit
/// 是無限迴圈動畫，pumpAndSettle 會逾時。
///
/// 關閉是兩段的：先 await 300ms 的 reverse 動畫，動畫的 future 完成之後才把
/// overlay 從樹上移除。所以只 pump 一次時間夠長的 frame 是不夠的，還要再 pump
/// 一次才看得到移除後的畫面。
Future<void> settleToast(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('關掉一個進度框不會連帶關掉其他的', (tester) async {
    await tester.pumpWidget(host());

    final first = MyProgressDialog.beginProgressDialog('第一個');
    MyProgressDialog.beginProgressDialog('第二個');
    await settleToast(tester);

    expect(find.text('第一個'), findsOneWidget);
    expect(find.text('第二個'), findsOneWidget);

    first();
    await settleToast(tester);

    // 用 BotToast.cleanAll() 關的話關一個等於全部關掉：課程頁三個分頁並行
    // 載入時，先結束的那一個會讓另外兩個的遮罩提早消失。
    expect(find.text('第一個'), findsNothing);
    expect(find.text('第二個'), findsOneWidget);

    // 收尾，不要把遮罩留給下一個測試。
    MyProgressDialog.hideProgressDialog();
    await settleToast(tester);
  });

  testWidgets('舊的 hideProgressDialog 只收自己這條路徑開的框', (tester) async {
    await tester.pumpWidget(host());

    // 模擬舊的成對 API 與 run() 的 beginProgress 同時在畫面上。
    final owned = MyProgressDialog.beginProgressDialog('run 的');
    MyProgressDialog.progressDialog('成對 API 開的');
    await settleToast(tester);

    expect(find.text('run 的'), findsOneWidget);
    expect(find.text('成對 API 開的'), findsOneWidget);

    MyProgressDialog.hideProgressDialog();
    await settleToast(tester);

    // 這條路徑只能收自己開的框，cleanAll() 會連 'run 的' 一起帶走。
    expect(find.text('成對 API 開的'), findsNothing);
    expect(find.text('run 的'), findsOneWidget);

    owned();
    await settleToast(tester);
    expect(find.text('run 的'), findsNothing);
  });

  testWidgets('沒有東西可關的時候 hideProgressDialog 什麼都不做', (tester) async {
    await tester.pumpWidget(host());

    final owned = MyProgressDialog.beginProgressDialog('run 的');
    await settleToast(tester);

    // 清單是空的還照樣 cleanAll() 的話，畫面上的東西會全部陪葬。
    MyProgressDialog.hideProgressDialog();
    MyProgressDialog.hideProgressDialog();
    await settleToast(tester);

    expect(find.text('run 的'), findsOneWidget);

    owned();
    await settleToast(tester);
  });

  testWidgets('成對 API 漏掉 hide 時，下一次 hideProgressDialog 會把漏掉的一起收掉',
      (tester) async {
    await tester.pumpWidget(host());

    // connector 一丟例外就會跳過 onEnd（見 score_task.dart），而進度框是
    // allowClick=false 的全螢幕遮罩，漏一個畫面就死了。這條路徑刻意維持
    // 「一次全關」由 cleanAll 順手收掉漏的，不能改成配對關一個。
    MyProgressDialog.progressDialog('漏掉的');
    MyProgressDialog.progressDialog('後來的');
    await settleToast(tester);

    MyProgressDialog.hideProgressDialog();
    await settleToast(tester);

    expect(find.text('漏掉的'), findsNothing);
    expect(find.text('後來的'), findsNothing);
  });
}
