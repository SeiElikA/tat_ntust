import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/controller/course_member/course_member_controller.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/components/shimmer/list_skeleton.dart';
import 'package:flutter_app/ui/pages/course_member/course_member_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 名單那支 Moodle API 很慢，這一頁存在的理由就是把那份等待放到一個
/// 有地方畫骨架、有地方放重試的畫面上。
class _FakeMoodleRepository extends MoodleRepository {
  _FakeMoodleRepository(this.result);

  Result<List<MoodleCoreEnrolGetUsers>> result;
  int calls = 0;

  /// 由測試自己 complete，用來停在「還在載入」那一格。
  Completer<Result<List<MoodleCoreEnrolGetUsers>>>? pending;

  @override
  Future<Result<List<MoodleCoreEnrolGetUsers>>> getMembers(
      String courseId) async {
    calls++;
    final gate = pending;
    if (gate != null) return gate.future;
    return result;
  }
}

MoodleCoreEnrolGetUsers _member(String studentId, String name) =>
    MoodleCoreEnrolGetUsers(fullName: '$studentId @ $name');

MoodleCoreEnrolGetUsers _staff(
        String name, String shortname, String role, String email) =>
    MoodleCoreEnrolGetUsers(
      fullName: name,
      email: email,
      roles: [Roles(shortname: shortname, name: role)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestL10n();
  });

  late _FakeMoodleRepository repo;
  late CourseMemberController controller;

  setUp(() {
    resetAppStatics();
    repo = _FakeMoodleRepository(Ok([
      _member('B10000001', '陳怡君'),
      _member('B10000002', '林建宏'),
      _member('B10000003', '張雅涵'),
    ]));
    MoodleRepository.instance = repo;
    controller = CourseMemberController(courseId: 'AT1001');
  });

  tearDown(() {
    MoodleRepository.instance = MoodleRepository();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    int knownMemberCount = 3,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CourseMemberPage(
          controller: controller,
          courseName: '微積分（一）',
          knownMemberCount: knownMemberCount,
          errorBuilder: (message, onRetry) => TextButton(
            onPressed: onRetry,
            child: Text(message),
          ),
        ),
      ),
    );
  }

  testWidgets('標題列不等 API：課名與人數立刻就在畫面上', (tester) async {
    repo.pending = Completer();
    await pumpPage(tester);
    await tester.pump();

    expect(find.text(R.current.enrolledStudents), findsOneWidget);
    expect(find.text('微積分（一） · 3 人'), findsOneWidget);

    repo.pending!.complete(repo.result);
    await tester.pumpAndSettle();
  });

  testWidgets('載入中畫骨架，列數用已知人數決定，最多五列', (tester) async {
    repo.pending = Completer();
    await pumpPage(tester, knownMemberCount: 40);
    await tester.pump();

    final skeleton = tester.widget<ListSkeleton>(find.byType(ListSkeleton));
    expect(skeleton.rows, 5);

    repo.pending!.complete(repo.result);
    await tester.pumpAndSettle();
    expect(find.byType(ListSkeleton), findsNothing);
  });

  testWidgets('取回之後列出每一位學生', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text('陳怡君'), findsOneWidget);
    expect(find.text('B10000001'), findsOneWidget);
    expect(find.text('張雅涵'), findsOneWidget);
  });

  testWidgets('老師與助教自成一區排在前面，帶角色與 email；人數只算學生', (tester) async {
    repo.result = Ok([
      _staff('陳大文', 'editingteacher', '教師', 'dawen@mail.ntust.edu.tw'),
      _member('B10000001', '陳怡君'),
      _staff('李助教', 'ta', '協同教學/課程助教', 'ta@mail.ntust.edu.tw'),
      _member('B10000002', '林建宏'),
    ]);
    await pumpPage(tester, knownMemberCount: 40);
    await tester.pumpAndSettle();

    expect(find.text(R.current.teachersAndAssistants), findsOneWidget);
    expect(find.text('教師'), findsOneWidget);
    expect(find.text('dawen@mail.ntust.edu.tw'), findsOneWidget);
    expect(find.text('協同教學/課程助教'), findsOneWidget);
    // 標題列一個、學生區的標題一個。
    expect(find.text(R.current.enrolledStudents), findsNWidgets(2));
    // 上一頁給的 40 只撐到名單到手。
    expect(find.text('微積分（一） · 2 人'), findsOneWidget);
    expect(tester.getTopLeft(find.text('李助教')).dy,
        lessThan(tester.getTopLeft(find.text('陳怡君')).dy));
  });

  testWidgets('點老師那一列會複製 email', (tester) async {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String?);
      }
      return null;
    });
    repo.result = Ok([
      _staff('陳大文', 'editingteacher', '教師', 'dawen@mail.ntust.edu.tw'),
      _member('B10000001', '陳怡君'),
    ]);
    await pumpPage(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('dawen@mail.ntust.edu.tw'));
    await tester.pump();

    expect(copied, ['dawen@mail.ntust.edu.tw']);
  });

  testWidgets('搜尋是本地過濾，不會再打一次 API', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(repo.calls, 1);

    await tester.enterText(find.byType(TextField), '林');
    await tester.pumpAndSettle();

    expect(find.text('林建宏'), findsOneWidget);
    expect(find.text('陳怡君'), findsNothing);
    expect(repo.calls, 1, reason: '本地過濾不該打 API');

    // 學號也搜得到。
    await tester.enterText(find.byType(TextField), 'B10000003');
    await tester.pumpAndSettle();
    expect(find.text('張雅涵'), findsOneWidget);
    expect(find.text('林建宏'), findsNothing);
    expect(repo.calls, 1);
  });

  testWidgets('失敗時畫呼叫端注入的錯誤畫面，按重試會重打', (tester) async {
    repo.result = const Failed(FetchFailed('壞掉了'));
    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text('壞掉了'), findsOneWidget);
    expect(repo.calls, 1);

    repo.result = Ok([_member('B10000004', '黃志豪')]);
    await tester.tap(find.text('壞掉了'));
    await tester.pumpAndSettle();

    expect(repo.calls, 2);
    expect(find.text('黃志豪'), findsOneWidget);
  });

  testWidgets('controller 已經有資料時不重查（返回再進來不重打）', (tester) async {
    await controller.load();
    expect(repo.calls, 1);

    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(repo.calls, 1, reason: 'controller 由課程頁持有，返回再進來應該直接畫上一次的結果');
    expect(find.text('陳怡君'), findsOneWidget);
  });
}
