import 'package:flutter/material.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_calendar_action_events.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/ui/components/page/loading_page.dart';
import 'package:flutter_app/ui/pages/calendar/upcoming_events_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/recording_ui.dart';
import '../helpers/test_l10n.dart';
import '../helpers/finders.dart';

/// 行事曆頁「待辦」區塊的畫面規格。
///
/// 區塊放在外層 ListView 裡，高度沒有上限；這裡每個測試都照正式路徑把它放進
/// ListView，順便盯著 ResultView 的 shrinkWrap 分支不會 RenderFlex 溢位。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 2026-09-09 是星期三。
  final now = DateTime(2026, 9, 9, 10, 0);
  late RecordingUi ui;

  setUpAll(() async {
    await loadTestL10n();
  });

  setUp(() {
    ui = RecordingUi();
    TaskUiDelegate.instance = ui;
    AuthSession.instance = FakeAuthSession(isSignedIn: true);
  });

  tearDown(() {
    TaskUiDelegate.instance = const NoopTaskUiDelegate();
    AuthSession.instance = const UninstalledAuthSession();
  });

  int secondsOf(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  MoodleActionEvent event({
    required int id,
    required String title,
    required DateTime due,
    bool withCourse = true,
    String modulename = 'assign',
    String actionName = '新增繳交',
    bool actionable = true,
  }) =>
      MoodleActionEvent(
        id: id,
        name: '$title 到期',
        activityname: title,
        modulename: modulename,
        timesort: secondsOf(due),
        url: 'https://moodle2.ntust.edu.tw/mod/$modulename/view.php?id=$id',
        course: withCourse
            ? MoodleActionEventCourse(
                fullname: '115.1【AT1001301】軟體工程',
                shortname: '115.1【AT1001301】軟體工程',
              )
            : null,
        action: MoodleActionEventAction(
          name: actionName,
          url: 'https://moodle2.ntust.edu.tw/mod/$modulename/view.php?id=$id'
              '&action=editsubmission',
          actionable: actionable,
        ),
      );

  /// 四筆：昨天 23:59、今天 23:59、星期日 23:59（站台事件）、下週一 09:00。
  List<MoodleActionEvent> fourEvents() => [
        event(id: 1, title: '作業一', due: DateTime(2026, 9, 8, 23, 59)),
        event(
          id: 2,
          title: '小考一',
          due: DateTime(2026, 9, 9, 23, 59),
          modulename: 'quiz',
          actionName: '嘗試測驗',
        ),
        event(
          id: 3,
          title: '期中教學意見調查',
          due: DateTime(2026, 9, 13, 23, 59),
          withCourse: false,
          modulename: 'feedback',
          actionName: '前往',
        ),
        event(
          id: 4,
          title: '期末報告',
          due: DateTime(2026, 9, 14, 9, 0),
          actionable: false,
        ),
      ];

  Future<void> pump(
    WidgetTester tester,
    Rx<Result<List<MoodleActionEvent>>?> state, {
    Future<void> Function()? onRetry,
    Future<void> Function(MoodleActionEvent)? onOpen,
    bool settle = true,
  }) async {
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            UpcomingEventsSection(
              state: state,
              onRetry: onRetry ?? () async {},
              onOpen: onOpen ?? (_) async {},
              clock: () => now,
            ),
          ],
        ),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  ColorScheme schemeOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(UpcomingEventsSection))).colorScheme;

  Color? dueColor(WidgetTester tester, int id) =>
      tester.widget<Text>(find.byKey(ValueKey('due-$id'))).style?.color;

  testWidgets('Ok：四組標籤、標題、副標與截止時間都畫出來', (tester) async {
    await pump(tester, Rxn(Ok(fourEvents())));

    expect(find.text('待辦'), findsOneWidget);
    for (final label in ['逾期', '今天', '本週', '之後']) {
      expect(find.text(label), findsOneWidget, reason: '缺少「$label」這一組');
    }
    for (final title in ['作業一', '小考一', '期中教學意見調查', '期末報告']) {
      expect(find.text(title), findsOneWidget);
    }
    // 副標：課名去掉學期與課號前綴，接上現在做得到的動作。
    expect(find.text('軟體工程 · 新增繳交'), findsOneWidget);
    expect(find.text('軟體工程 · 嘗試測驗'), findsOneWidget);
    // actionable 為 false 的不顯示動作。
    expect(find.text('軟體工程'), findsOneWidget);
    // 站台事件沒有 course，只剩動作。
    expect(find.text('前往'), findsOneWidget);
    expect(find.textContaining('軟體工程'), findsNWidgets(3),
        reason: '站台事件不該掛任何課名');

    for (final due in [
      '09/08 23:59',
      '09/09 23:59',
      '09/13 23:59',
      '09/14 09:00'
    ]) {
      expect(find.text(due), findsOneWidget, reason: '缺少截止時間 $due');
    }
  });

  testWidgets('跨年的截止時間帶年份', (tester) async {
    await pump(
        tester,
        Rxn(Ok([
          event(id: 9, title: '下學期報告', due: DateTime(2027, 1, 15, 23, 59)),
        ])));

    expect(find.text('2027/01/15 23:59'), findsOneWidget);
  });

  testWidgets('逾期那一筆的截止時間用 error 色，今天那一筆不用', (tester) async {
    await pump(tester, Rxn(Ok(fourEvents())));
    final scheme = schemeOf(tester);

    expect(dueColor(tester, 1), scheme.error);
    expect(dueColor(tester, 2), isNot(scheme.error));
    expect(dueColor(tester, 2), scheme.onSurfaceVariant);
  });

  testWidgets('Ok 但清單是空的 → 空狀態文字，沒有任何分組標籤', (tester) async {
    await pump(tester, Rxn(const Ok(<MoodleActionEvent>[])));

    expect(find.text('目前沒有待辦事項'), findsOneWidget);
    for (final label in ['逾期', '今天', '本週', '之後']) {
      expect(find.text(label), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('點一筆 → onOpen 收到那一筆', (tester) async {
    final opened = <int>[];
    await pump(tester, Rxn(Ok(fourEvents())),
        onOpen: (e) async => opened.add(e.id));

    await tester.tap(find.text('小考一'));
    await tester.pump();

    expect(opened, [2]);
  });

  testWidgets('Failed(NotSignedIn) 且沒登入 → 「請登入」加「登入」鈕，按了開登入頁再重試',
      (tester) async {
    AuthSession.instance = FakeAuthSession(isSignedIn: false);
    var retried = 0;
    await pump(tester, Rxn(const Failed(NotSignedIn())),
        onRetry: () async => retried++);

    expect(find.text('請登入'), findsOneWidget);
    expect(find.text('登入'), findsOneWidget);
    expect(find.text('重新整理'), findsNothing);

    await tester.tap(find.text('登入'));
    await tester.pump();

    expect(ui.openLoginCalls, 1);
    expect(retried, 1, reason: '從登入設定回來要重抓一次');
  });

  testWidgets('Failed(FetchFailed) 且已登入 → 訊息加「重新整理」', (tester) async {
    var retried = 0;
    await pump(tester, Rxn(const Failed(FetchFailed('boom'))),
        onRetry: () async => retried++);

    expect(find.text('boom'), findsOneWidget);
    expect(find.text('登入'), findsNothing);
    final refresh = buttonWithText('重新整理');
    expect(refresh, findsOneWidget);

    await tester.tap(refresh);
    await tester.pump();

    expect(retried, 1);
  });

  testWidgets('Stale → 橫幅寫著原因，底下的清單照畫，放在 ListView 裡不會溢位', (tester) async {
    await pump(tester, Rxn(Stale(fourEvents(), const Offline())));

    expect(find.text('網路發生錯誤'), findsOneWidget);
    expect(find.text('作業一'), findsOneWidget);
    expect(find.text('期末報告'), findsOneWidget);
    expect(find.text('逾期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('還在載入（null）→ LoadingPage，放在 ListView 裡不會炸', (tester) async {
    // LoadingPage 的轉圈永遠不會停，不能 pumpAndSettle。
    await pump(tester, Rxn<Result<List<MoodleActionEvent>>>(), settle: false);

    expect(find.byType(LoadingPage), findsOneWidget);
    expect(find.text('待辦'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('狀態從載入中變成 Ok 時畫面跟著換', (tester) async {
    final state = Rxn<Result<List<MoodleActionEvent>>>();
    await pump(tester, state, settle: false);
    expect(find.byType(LoadingPage), findsOneWidget);

    state.value = Ok(fourEvents());
    await tester.pumpAndSettle();

    expect(find.byType(LoadingPage), findsNothing);
    expect(find.text('作業一'), findsOneWidget);
  });
}
