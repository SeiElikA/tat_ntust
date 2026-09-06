import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_assignment_detail_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/assign_status_chip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/moodle_assign_fixtures.dart';
import '../helpers/recording_ui.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 作業詳情頁的畫面規格。作業本體與狀態直接以 seed 傳入，不碰網路；
/// 離線，所以被丟掉的 seed 再抓時只會落到快取或 Failed。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const courseId = 'CS3001701';

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
    main:
        CourseMainInfoJson(course: CourseMainJson(id: courseId, name: '作業系統')),
  );

  MoodleAssignment a1() => fixtureAssignments()[0];
  MoodleAssignment a2() => fixtureAssignments()[1];

  Future<void> pump(
    WidgetTester tester,
    MoodleAssignment? a, {
    int? assignId,
    Result<MoodleAssignSubmissionStatus>? status,
    List<(String, String)>? opened,
    Size viewSize = const Size(800, 3000),
    bool settle = true,
  }) async {
    // ListView 是懶載入的，超出視窗的段落根本不會被建出來；把視窗拉高，
    // 整頁都在畫面上。
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GetMaterialApp(
      home: CourseAssignmentDetailPage(
        courseInfo,
        assignId: assignId ?? a!.id,
        assignment: a,
        initialStatus: status,
        errorBuilder: (m) => Text('ERR:$m'),
        openWebView: (title, url) async => opened?.add((title, url)),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  /// 把標籤與值釘在同一列：只比對標籤或只比對值，都抓不到「延長期限那列
  /// 填成 duedate」這種串線。
  void expectField(String label, String value) {
    expect(
      find.ancestor(
          of: find.text(label), matching: find.widgetWithText(Row, value)),
      findsOneWidget,
      reason: '「$label」那列的值應該是 $value',
    );
  }

  testWidgets('已繳交且已評分：每一段都畫出來', (tester) async {
    await pump(tester, a1(), status: Ok(fixtureStatus('status_graded')));

    // 標題在 AppBar。
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.text('HW1 & Report')),
      findsOneWidget,
    );
    // 日期列。「截止日期」是段標題，主行是相對提示、副行才是原本的 duedate。
    for (final label in ['開放繳交', '截止日期', '最後繳交期限']) {
      expect(find.text(label), findsOneWidget, reason: '缺少 $label');
    }
    expect(find.textContaining('已逾期'), findsOneWidget);
    expect(find.text(CourseAssignmentDetailPage.formatUnix(a1().duedate)),
        findsOneWidget,
        reason: '相對提示底下要有絕對時間');
    expectField('開放繳交',
        CourseAssignmentDetailPage.formatUnix(a1().allowsubmissionsfromdate));
    expectField(
        '最後繳交期限', CourseAssignmentDetailPage.formatUnix(a1().cutoffdate));
    // 說明（HTML）與附件。
    expect(find.text('作業說明'), findsOneWidget);
    expect(find.textContaining('PDF', findRichText: true), findsOneWidget);
    expect(find.text('附件'), findsOneWidget);
    expect(find.text('hw1.pdf'), findsOneWidget);
    // 狀態卡。
    expect(find.widgetWithText(AssignStatusChip, '已評分'), findsOneWidget);
    expect(find.text('評分狀態'), findsOneWidget);
    expect(find.text('已評分'), findsNWidgets(2), reason: '籤與評分狀態列各一');
    expect(find.text('繳交時間'), findsOneWidget);
    expect(find.text('繳交的檔案'), findsOneWidget);
    expect(find.text('hw1_b10000000.pdf'), findsOneWidget);
    expect(find.text('線上文字'), findsOneWidget);
    expect(find.textContaining('已附上報告', findRichText: true), findsOneWidget);
    expect(find.text('成績'), findsOneWidget);
    // connector 把 `85.00&nbsp;/&nbsp;100.00` 的實體還原成 U+00A0。
    expect(find.text('85.00\u00a0/\u00a0100.00'), findsOneWidget);
    expect(find.textContaining('&nbsp;'), findsNothing);
    expect(find.text('評分時間'), findsOneWidget);
    expect(find.text('老師回饋'), findsOneWidget);
    expect(find.textContaining('不錯', findRichText: true), findsOneWidget);
    expect(find.text('回饋檔案'), findsOneWidget);
    expect(find.text('hw1_marked.pdf'), findsOneWidget);
    expect(find.text('在網頁開啟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('草稿：時間那一列叫「最後修改時間」，不是「繳交時間」', (tester) async {
    await pump(tester, a1(), status: Ok(fixtureStatus('status_draft')));

    // Moodle 這一列是 timemodified：草稿只是最後一次存檔，不是繳交。
    expect(find.text('最後修改時間'), findsOneWidget);
    expect(find.text('繳交時間'), findsNothing);
    expect(find.text('hw1_b10000000.pdf'), findsOneWidget);
  });

  testWidgets('沒繳交、沒回饋：已逾期籤、尚未評分，沒有繳交與成績段落', (tester) async {
    await pump(tester, a1(), status: Ok(fixtureStatus('status_none')));

    expect(find.widgetWithText(AssignStatusChip, '已逾期'), findsOneWidget);
    expect(find.text('尚未評分'), findsOneWidget);
    expect(find.text('繳交的檔案'), findsNothing);
    expect(find.text('繳交時間'), findsNothing);
    expect(find.text('成績'), findsNothing);
    expect(find.text('老師回饋'), findsNothing);
  });

  testWidgets('intro 是 null：說明暫不顯示、沒有附件段、沒有截止日期', (tester) async {
    await pump(tester, a2(), status: Ok(fixtureStatus('status_none')));

    expect(find.text('尚未開放繳交，說明暫不顯示'), findsOneWidget);
    expect(find.text('附件'), findsNothing);
    expect(find.text('沒有截止日期'), findsOneWidget);
    expect(find.text('最後繳交期限'), findsNothing);
    expect(find.widgetWithText(AssignStatusChip, '未繳交'), findsOneWidget);
  });

  testWidgets('intro 是空字串：顯示 nothingHere 而不是「暫不顯示」', (tester) async {
    await pump(tester, a1()..intro = '',
        status: Ok(fixtureStatus('status_none')));

    expect(find.text(R.current.nothingHere), findsOneWidget);
    expect(find.text('尚未開放繳交，說明暫不顯示'), findsNothing);
  });

  testWidgets('有延長期限：多一列', (tester) async {
    final status = fixtureStatus('status_extension');
    await pump(tester, a1(), status: Ok(status));

    expectField(
        '延長期限', CourseAssignmentDetailPage.formatUnix(status.extensionDueDate));
    // 延長到 2025-09-16，早就過了 → 已逾期。
    expect(find.widgetWithText(AssignStatusChip, '已逾期'), findsOneWidget);
  });

  testWidgets('延長期限還沒到：截止列的相對提示跟著延長期限，籤是未繳交', (tester) async {
    final status = MoodleAssignSubmissionStatus(
      lastattempt: MoodleAssignLastAttempt(
        extensionduedate: DateTime.now()
                .add(const Duration(days: 5))
                .millisecondsSinceEpoch ~/
            1000,
        gradingstatus: 'notgraded',
      ),
    );
    await pump(tester, a1(), status: Ok(status));

    expect(find.widgetWithText(AssignStatusChip, '未繳交'), findsOneWidget);
    // 「截止日期」那列仍顯示原本的 duedate（照 Moodle），但提示不再說已逾期。
    expect(find.textContaining('天後截止'), findsOneWidget);
    expect(find.textContaining('已逾期'), findsNothing);
    expect(find.text(CourseAssignmentDetailPage.formatUnix(a1().duedate)),
        findsOneWidget);
    expectField(
        '延長期限', CourseAssignmentDetailPage.formatUnix(status.extensionDueDate));
  });

  testWidgets('團隊作業由隊友代交：自己那筆是草稿，籤仍是已繳交，檔案來自群組那筆', (tester) async {
    final team = a2()..duedate = a1().duedate;
    await pump(tester, team, status: Ok(fixtureStatus('status_team_draft')));

    expect(find.widgetWithText(AssignStatusChip, '已繳交'), findsOneWidget);
    expect(find.text('繳交時間'), findsOneWidget);
    expect(find.text('hw1_b10000000.pdf'), findsOneWidget);
  });

  testWidgets('狀態是 Stale：多一列舊資料提示與重新整理鈕，籤帶時鐘', (tester) async {
    await pump(tester, a1(),
        status: Stale(fixtureStatus('status_graded'), const Offline()));

    expect(find.text(R.current.networkError), findsOneWidget);
    expect(find.widgetWithText(TextButton, R.current.refresh), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AssignStatusChip),
        matching: find.byIcon(LucideIcons.history),
      ),
      findsOneWidget,
    );
  });

  testWidgets('seed 是 Failed 就重抓；離線沒快取 → 狀態卡畫就地重試的錯誤畫面', (tester) async {
    await pump(tester, a1(), status: const Failed(FetchFailed('x')));

    expect(find.text(R.current.networkError), findsOneWidget);
    expect(find.text('x'), findsNothing, reason: 'Failed 的 seed 不該被沿用');
    // 不是整頁的 errorBuilder：那個沒有重試鈕，要離開頁面才能再抓一次。
    expect(find.textContaining('ERR:'), findsNothing);
    final refresh = find.widgetWithText(TextButton, R.current.refresh);
    expect(refresh, findsOneWidget);
    // 作業本體是 seed 的 Ok，頁面其餘部分照畫。
    expect(find.text('作業說明'), findsOneWidget);

    // 按重新整理會再抓一次（離線 → 仍然失敗，但畫面沒有卡在轉圈）。
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.text(R.current.networkError), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('從「檔案」分頁進來（沒有 seed）而且抓不到：AppBar 是「作業詳情」不是分頁名', (tester) async {
    await pump(tester, null, assignId: 4101);

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('作業詳情')),
      findsOneWidget,
    );
    expect(find.text('ERR:${R.current.networkError}'), findsOneWidget);
  });

  testWidgets('在網頁開啟 → 交給注入的 openWebView：cmid 網址加 lang', (tester) async {
    final opened = <(String, String)>[];
    await pump(tester, a1(),
        status: Ok(fixtureStatus('status_graded')), opened: opened);

    await tester.tap(find.text('在網頁開啟'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.$1, 'HW1 & Report');
    expect(
        opened.single.$2,
        startsWith(
            'https://moodle2.ntust.edu.tw/mod/assign/view.php?id=93001'));
    expect(opened.single.$2, contains('lang='));
  });

  testWidgets(
      '說明裡的 <img>：只有自家 pluginfile 由 App 帶 token 載入，data: URI 交回預設 factory',
      (tester) async {
    // 1x1 透明 PNG。
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
    final a = a1()
      ..intro = '<p><img src="data:image/png;base64,$png" alt="inline"></p>'
          '<p><img src="https://moodle2.ntust.edu.tw/webservice/pluginfile.php/555/mod_assign/intro/0/x.png" width="120" height="80"></p>';
    await pump(tester, a, status: Ok(fixtureStatus('status_none')));

    // data: URI 由預設 factory 解成 MemoryImage，不會是破圖。
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage),
      findsOneWidget,
    );
    // pluginfile 那張走 Image.network（測試環境沒有網路 → 破圖 icon 剛好一個），
    // 而且 width / height 有帶上。
    final network = tester.widget<Image>(
        find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage));
    expect(network.width, 120);
    expect(network.height, 80);
    expect(find.byIcon(LucideIcons.imageOff), findsOneWidget);
  });

  testWidgets('說明裡的連結：https 交給 openWebView，javascript: 被擋下', (tester) async {
    final opened = <(String, String)>[];
    final a = a1()
      ..intro = '<p><a href="https://example.com/x">safe</a></p>'
          '<p><a href="javascript:alert(1)">evil</a></p>';
    await pump(tester, a,
        status: Ok(fixtureStatus('status_none')), opened: opened);

    // 段落是整行寬的區塊，文字靠左；tap 要落在文字上而不是 widget 中心。
    Future<void> tapLink(String text) async {
      final finder = find.text(text, findRichText: true);
      await tester.tapAt(tester.getTopLeft(finder) + const Offset(6, 8));
      await tester.pumpAndSettle();
    }

    await tapLink('safe');
    expect(opened, [('HW1 & Report', 'https://example.com/x')]);

    await tapLink('evil');
    expect(opened, hasLength(1), reason: 'javascript: 不能進 WebView');
  });

  testWidgets('狀態還在載入：截止與說明照畫，繳交狀態那一段是轉圈', (tester) async {
    final repo = _PendingStatusRepository();
    MoodleRepository.instance = repo;
    await pump(tester, a1(), settle: false);

    expect(find.text('截止日期'), findsOneWidget);
    expect(find.text('作業說明'), findsOneWidget);
    expect(find.text('繳交狀態'), findsOneWidget);
    expect(find.text('成績與回饋'), findsNothing);
    // 籤位置的 14dp 小轉圈，加上狀態卡的 LoadingPage。
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    // 狀態還沒到就不知道逾期與否，提示一律中性色，不會先紅一下再變灰。
    final hint = find.textContaining('已逾期');
    expect(tester.widget<Text>(hint).style?.color,
        Theme.of(tester.element(hint)).colorScheme.onSurface);

    repo.pending.complete(const Failed(FetchFailed('x')));
    await tester.pumpAndSettle();
  });

  testWidgets('成績與回饋自成一段', (tester) async {
    await pump(tester, a1(), status: Ok(fixtureStatus('status_graded')));

    expect(find.text('成績與回饋'), findsOneWidget);
    for (final label in ['成績', '評分時間', '老師回饋', '回饋檔案']) {
      expect(find.text(label), findsOneWidget, reason: '缺少 $label');
    }
  });

  testWidgets('回饋四段全空：不畫成績與回饋群組，評分狀態仍在', (tester) async {
    final status = MoodleAssignSubmissionStatus(
      lastattempt: MoodleAssignLastAttempt(gradingstatus: 'notgraded'),
      feedback: MoodleAssignFeedback(),
    );
    await pump(tester, a1(), status: Ok(status));

    expect(find.text('成績與回饋'), findsNothing);
    expect(find.text('成績'), findsNothing);
    expect(find.text('評分狀態'), findsOneWidget);
    expect(find.text('尚未評分'), findsOneWidget);
  });

  testWidgets('有分數但 gradefordisplay 是空的：不畫空的成績列，評分時間仍在', (tester) async {
    final status = MoodleAssignSubmissionStatus(
      lastattempt: MoodleAssignLastAttempt(gradingstatus: 'graded'),
      feedback: MoodleAssignFeedback(
        grade: MoodleAssignGrade(grade: '85.00000'),
        gradeddate: 1756700000,
      ),
    );
    await pump(tester, a1(), status: Ok(status));

    expect(find.text('成績與回饋'), findsOneWidget);
    expect(find.text('成績'), findsNothing, reason: '沒有可顯示的字串就不畫空值那一列');
    expect(find.text('評分時間'), findsOneWidget);
    expect(find.widgetWithText(AssignStatusChip, '已評分'), findsOneWidget);
  });

  testWidgets('不需繳交的作業：過了截止也不染紅', (tester) async {
    await pump(tester, a1()..nosubmissions = 1,
        status: Ok(fixtureStatus('status_none')));

    expect(find.widgetWithText(AssignStatusChip, '不需繳交'), findsOneWidget);
    final hint = find.textContaining('已逾期');
    expect(hint, findsOneWidget, reason: '資料不刪，只是不喊狼來了');
    final scheme = Theme.of(tester.element(hint)).colorScheme;
    expect(tester.widget<Text>(hint).style?.color, scheme.onSurface);
    expect(tester.widget<Text>(hint).style?.color, isNot(scheme.error));
  });

  testWidgets('狀態失敗：只有那一段掛掉，截止與說明都還在', (tester) async {
    await pump(tester, a1(), status: const Failed(FetchFailed('x')));

    expect(find.text('開放繳交'), findsOneWidget);
    expect(find.text('作業說明'), findsOneWidget);
    expect(find.text('繳交狀態'), findsOneWidget, reason: '標題還在才知道哪一段掛了');
    expect(find.text('延長期限'), findsNothing);
    expect(find.text('評分狀態'), findsNothing);
    expect(find.text('成績與回饋'), findsNothing);
  });

  testWidgets('每一個檔案列都有下載提示', (tester) async {
    final a = a1();
    final s = fixtureStatus('status_graded');
    await pump(tester, a, status: Ok(s));

    final files = a.introattachments.length +
        s.submissionFor(a)!.files.length +
        s.feedback!.files.length;
    expect(files, greaterThan(0));
    expect(find.byIcon(LucideIcons.download), findsNWidgets(files));
  });

  testWidgets('超長中文檔名：截成兩行，不擠掉下載 icon 也不 overflow', (tester) async {
    final a = a1()
      ..introattachments = [
        MoodleAssignFile(
          filename: '${'期末專題報告與附錄' * 12}.pdf',
          fileurl:
              'https://moodle2.ntust.edu.tw/webservice/pluginfile.php/1/x.pdf',
          mimetype: 'application/pdf',
        ),
      ];
    await pump(tester, a,
        status: Ok(fixtureStatus('status_none')),
        viewSize: const Size(360, 3000));

    expect(tester.takeException(), isNull);
    expect(find.byIcon(LucideIcons.download), findsOneWidget);
    final title = tester.widget<Text>(find.textContaining('期末專題報告與附錄'));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
  });
}

/// 讓繳交狀態一直停在「載入中」：離線時真的去抓會在第一幀之前就落到
/// [Failed]，測不到轉圈那一幀。
class _PendingStatusRepository extends MoodleRepository {
  final pending = Completer<Result<MoodleAssignSubmissionStatus>>();

  @override
  Future<Result<MoodleAssignSubmissionStatus>> getSubmissionStatus(
    int assignId, {
    bool background = false,
  }) =>
      pending.future;
}
