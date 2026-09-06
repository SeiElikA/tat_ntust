import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/moodle_assign_submit_utils.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/service/file_pick_service.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/ui/components/page/section_empty_state.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_assign_submit_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/moodle_assign_fixtures.dart';
import '../helpers/recording_ui.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';
import '../helpers/finders.dart';

/// 挑檔案的假實作：測試裡永遠不碰平台通道。
class _FakePickService implements FilePickService {
  _FakePickService(this.files);

  final List<File> files;
  int calls = 0;
  int? lastLimit;
  List<String>? lastExtensions;

  @override
  Future<List<File>> pick({
    required int limit,
    List<String> extensions = const [],
  }) async {
    calls++;
    lastLimit = limit;
    lastExtensions = extensions;
    return files;
  }
}

/// 交作業編輯頁的畫面規格。作業與狀態都是值傳進來的，這一頁不碰網路。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingUi ui;
  late Directory tempDir;

  setUpAll(() async {
    await loadTestL10n();
  });

  setUp(() {
    resetAppStatics();
    ui = RecordingUi();
    AuthSession.instance = FakeAuthSession();
    TaskUiDelegate.instance = ui;
    ConnectivityProbe.instance = FakeConnectivityProbe(online: false);
    MoodleRepository.instance = MoodleRepository();
    tempDir = Directory.systemTemp.createTempSync('assign_submit_page_test');
  });

  tearDown(() {
    AuthSession.instance = const UninstalledAuthSession();
    TaskUiDelegate.instance = const NoopTaskUiDelegate();
    ConnectivityProbe.instance = const PlatformConnectivityProbe();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  MoodleAssignment submittable() => fixtureSubmittableAssignment();

  MoodleAssignment noDrafts() => fixtureNoDraftsAssignment();

  File makeFile(String name, {int bytes = 64}) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(List<int>.filled(bytes, 1));
    return file;
  }

  Future<void> pump(
    WidgetTester tester,
    MoodleAssignment a,
    MoodleAssignSubmissionStatus status, {
    List<(String, String)>? opened,
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(GetMaterialApp(
      home: CourseAssignSubmitPage(
        assignment: a,
        status: status,
        courseName: '作業系統',
        openWebView: (title, url) async => opened?.add((title, url)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, Finder finder) =>
      tester.widget<ButtonStyleButton>(finder).onPressed != null;

  /// 挑完檔案要 `File.length()`，那是真的 I/O：假時鐘不會讓它完成，
  /// 得先把真的事件迴圈跑一輪再 pump。
  Future<void> tapAndFlush(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Finder saveButton(String label) => buttonWithText(label);

  Finder addFilesButton() => buttonWithText(R.current.assignAddFiles);

  /// 現有線上文字含內嵌圖片：不能編也不能原封送回去（`moodlewssettingfileurl`
  /// 已經把 @@PLUGINFILE@@ 換成絕對網址）。
  MoodleAssignSubmissionStatus statusWithEmbeddedImage() {
    final json = loadMoodleAssignFixture('status_draft');
    final plugins = (json['lastattempt'] as Map<String, dynamic>)['submission']
        ['plugins'] as List<dynamic>;
    for (final p in plugins) {
      if ((p as Map<String, dynamic>)['type'] == 'onlinetext') {
        (p['editorfields'] as List<dynamic>).first['text'] =
            '<p>看圖 <img src="@@PLUGINFILE@@/a.png"></p>';
      }
    }
    return MoodleAssignSubmissionStatus.fromJson(json);
  }

  group('區塊可見性', () {
    testWidgets('檔案外掛沒開就整個檔案區塊不畫', (tester) async {
      final a = submittable()
        ..configs = [
          MoodleAssignConfig(
              plugin: 'onlinetext',
              subtype: 'assignsubmission',
              name: 'enabled',
              value: '1'),
        ];
      await pump(tester, a, fixtureStatus('status_can_edit'));

      expect(find.text(R.current.assignAttachmentSection), findsNothing);
      expect(find.text(R.current.assignOnlineText), findsOneWidget);
    });

    testWidgets('線上文字外掛沒開就整個文字區塊不畫', (tester) async {
      await pump(tester, noDrafts(), fixtureStatus('status_can_edit'));

      expect(find.text(R.current.assignAttachmentSection), findsOneWidget);
      expect(find.text(R.current.assignOnlineText), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('有草稿階段的作業不畫繳交聲明卡（那一步在送出評分時才擋）', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_can_edit'));

      expect(submittable().requiresStatement, isTrue);
      expect(find.text(R.current.assignSubmissionStatement), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('沒有繳交檔案時畫空狀態', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_can_edit'));

      expect(find.byType(SectionEmptyState), findsOneWidget);
      expect(find.byType(MoodleFileTile), findsNothing);
    });

    testWidgets('已經交過的檔案是清單的初值，一列一個', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_draft'));

      expect(find.byType(SectionEmptyState), findsNothing);
      expect(find.text('hw1_b10000000.pdf'), findsOneWidget);
    });
  });

  group('按鈕文案與可按性', () {
    testWidgets('有草稿階段：那顆鈕叫「儲存草稿」', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_can_edit'));

      expect(find.text(R.current.assignSaveDraft), findsOneWidget);
      expect(find.text(R.current.assignSubmit), findsNothing);
    });

    testWidgets('沒有草稿階段：存檔就是繳交，文案不可以騙人', (tester) async {
      await pump(tester, noDrafts(), fixtureStatus('status_can_edit'));

      expect(find.text(R.current.assignSubmit), findsOneWidget);
      expect(find.text(R.current.assignSaveDraft), findsNothing);
    });

    testWidgets('沒有任何變更就不給按：那一趟必定被判成 submissionempty', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_draft'));

      expect(enabled(tester, saveButton(R.current.assignSaveDraft)), isFalse);
    });

    testWidgets('改了線上文字之後就可以按', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_draft'));

      await tester.enterText(find.byType(TextField), '改過的內容');
      await tester.pump();

      expect(enabled(tester, saveButton(R.current.assignSaveDraft)), isTrue);
    });

    testWidgets('達到 maxfilesubmissions 時「新增檔案」是 disabled', (tester) async {
      // no_drafts 的 maxfilesubmissions 是 1，status_draft 已經有一個檔案。
      await pump(tester, noDrafts(), fixtureStatus('status_draft'));

      expect(enabled(tester, addFilesButton()), isFalse);
    });

    testWidgets('還沒滿的時候可以按，而且只要求剩下的額度', (tester) async {
      final pick = _FakePickService([]);
      FilePickService.instance = pick;
      await pump(tester, submittable(), fixtureStatus('status_draft'));

      expect(enabled(tester, addFilesButton()), isTrue);
      await tapAndFlush(tester, addFilesButton());

      // maxfilesubmissions 3，已經有 1 個。
      expect(pick.lastLimit, 2);
      // filetypeslist 全是副檔名，所以直接交給挑選器過濾。
      expect(pick.lastExtensions, ['pdf', 'docx']);
    });
  });

  group('繳交聲明', () {
    testWidgets('沒有草稿階段又要求同意：勾選框在，沒勾就不能送，勾了才可以', (tester) async {
      FilePickService.instance = _FakePickService([makeFile('report.pdf')]);
      await pump(tester, noDrafts(), fixtureStatus('status_can_edit'));

      expect(find.text(R.current.assignSubmissionStatement), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);

      await tapAndFlush(tester, addFilesButton());
      expect(find.text('report.pdf'), findsOneWidget);
      // 有變更了，但還沒同意聲明。
      expect(enabled(tester, saveButton(R.current.assignSubmit)), isFalse);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(enabled(tester, saveButton(R.current.assignSubmit)), isTrue);
    });
  });

  group('線上文字', () {
    testWidgets('現有內容含內嵌圖片時不給編輯，改成說明加一顆導網頁的鈕', (tester) async {
      final opened = <(String, String)>[];
      await pump(tester, submittable(), statusWithEmbeddedImage(),
          opened: opened);

      expect(find.byType(TextField), findsNothing);
      expect(find.text(R.current.assignOnlineTextNotEditable), findsOneWidget);

      await tester.tap(find.text(R.current.assignOpenInWeb));
      await tester.pumpAndSettle();
      expect(opened.single.$2, contains('/mod/assign/view.php?id=93201'));
    });

    testWidgets('有字數上限時提示裡帶著上限', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_can_edit'));

      expect(find.textContaining('500'), findsOneWidget);
    });
  });

  group('挑檔案的本地把關', () {
    testWidgets('超大的檔案不進清單，只出一個 toast', (tester) async {
      // no_drafts 的單檔上限是 1 MB。
      FilePickService.instance =
          _FakePickService([makeFile('huge.pdf', bytes: 1048577)]);
      await pump(tester, noDrafts(), fixtureStatus('status_can_edit'));

      await tapAndFlush(tester, addFilesButton());

      expect(find.text('huge.pdf'), findsNothing);
      expect(find.byType(SectionEmptyState), findsOneWidget);
      expect(ui.toasts.single, contains('huge.pdf'));
    });

    testWidgets('副檔名不在允許清單裡的也擋下來', (tester) async {
      FilePickService.instance = _FakePickService([makeFile('note.txt')]);
      await pump(tester, submittable(), fixtureStatus('status_can_edit'));

      await tapAndFlush(tester, addFilesButton());

      expect(find.text('note.txt'), findsNothing);
      expect(ui.toasts.single, contains('note.txt'));
    });

    testWidgets('挑選器叫不起來時只 toast，不加任何檔案', (tester) async {
      FilePickService.instance = _ThrowingPickService();
      await pump(tester, submittable(), fixtureStatus('status_can_edit'));

      await tapAndFlush(tester, addFilesButton());

      expect(ui.toasts.single, R.current.assignFilePickerUnavailable);
      expect(find.byType(MoodleFileTile), findsNothing);
    });
  });

  group('寫入進行中', () {
    testWidgets('進度列與取消鈕都在，而且清單被擋住不給再改', (tester) async {
      final repo = _PendingRepo();
      MoodleRepository.instance = repo;
      await pump(tester, submittable(), fixtureStatus('status_draft'));

      await tester.enterText(find.byType(TextField), '改過的內容');
      await tester.pump();
      await tester.tap(saveButton(R.current.assignSaveDraft));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text(R.current.cancel), findsOneWidget);
      // 進行中的時候儲存鈕是 disabled，按第二次不會再送一趟。
      expect(enabled(tester, saveButton(R.current.assignSaveDraft)), isFalse);

      // 上傳到第一個檔案時，進度列會說正在傳哪一個。
      repo.onProgress?.call(const AssignTransferProgress(
          done: 0,
          total: 1,
          ratio: 0.5,
          phase: AssignTransferPhase.upload,
          filename: 'hw1_b10000000.pdf'));
      await tester.pump();
      expect(
          find.text(
              sprintf(R.current.assignUploadingFile, ['hw1_b10000000.pdf'])),
          findsOneWidget);

      // 舊檔案要先下載再重傳，那一段不可以說成「正在上傳」。
      repo.onProgress?.call(const AssignTransferProgress(
          done: 0,
          total: 1,
          ratio: 0.1,
          phase: AssignTransferPhase.download,
          filename: 'hw1_b10000000.pdf'));
      await tester.pump();
      expect(
          find.text(
              sprintf(R.current.assignPreparingFile, ['hw1_b10000000.pdf'])),
          findsOneWidget);

      await tester.tap(find.text(R.current.cancel));
      await tester.pump();
      expect(repo.cancelToken?.isCancelled, isTrue);

      repo.completer.complete(const Failed(FetchFailed('x')));
      await tester.pumpAndSettle();
      // 失敗就留在這一頁，變更還在。
      expect(find.byType(CourseAssignSubmitPage), findsOneWidget);
      // 使用者自己按的取消不是「繳交失敗」。
      expect(ui.toasts.last, R.current.assignSubmitCancelled);
    });
  });

  group('線上文字外掛開著就一定要送', () {
    testWidgets('只動檔案時照樣帶著伺服器原本那份文字，不是 null', (tester) async {
      // 伺服器端 assign_submission_onlinetext::save() 沒有 isset 把關：不送
      // 這個鍵不是「保留」，是被空值覆蓋。
      final repo = _PendingRepo();
      MoodleRepository.instance = repo;
      FilePickService.instance = _FakePickService([makeFile('extra.pdf')]);
      await pump(tester, submittable(), fixtureStatus('status_draft'));

      await tapAndFlush(tester, addFilesButton());
      await tester.tap(saveButton(R.current.assignSaveDraft));
      await tester.pump();

      expect(repo.draft!.files, isNotNull);
      expect(repo.draft!.onlineText, '<p>已附上報告</p>');
    });

    testWidgets('現有內容是富文字：整頁都不能存，不是只有文字框不給編', (tester) async {
      await pump(tester, submittable(), statusWithEmbeddedImage());

      await tester.tap(find.byTooltip(R.current.assignRemoveFile));
      await tester.pumpAndSettle();
      FilePickService.instance = _FakePickService([makeFile('new.pdf')]);
      await tapAndFlush(tester, addFilesButton());

      expect(find.text('new.pdf'), findsOneWidget);
      expect(enabled(tester, saveButton(R.current.assignSaveDraft)), isFalse);
      expect(
          find.text(R.current.assignSubmitBlockedByOnlineText), findsOneWidget);
    });
  });

  group('字數上限', () {
    testWidgets('超過就不給送，並且即時把字數說出來', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_can_edit'));

      await tester.enterText(
          find.byType(TextField), List.filled(501, 'w').join(' '));
      await tester.pump();

      expect(enabled(tester, saveButton(R.current.assignSaveDraft)), isFalse);
      expect(find.textContaining(R.current.assignWordCountExceeded),
          findsOneWidget);

      await tester.enterText(find.byType(TextField), '短短一句');
      await tester.pump();
      expect(enabled(tester, saveButton(R.current.assignSaveDraft)), isTrue);
    });
  });

  group('寫入中不給離開', () {
    testWidgets('返回鍵按不掉：CancelToken 到不了 save_submission', (tester) async {
      final repo = _PendingRepo();
      MoodleRepository.instance = repo;
      await pump(tester, submittable(), fixtureStatus('status_draft'));

      await tester.enterText(find.byType(TextField), '改過的內容');
      await tester.pump();
      await tester.tap(saveButton(R.current.assignSaveDraft));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      // 不定量的進度條永遠不會靜止，所以只 pump 不 settle。
      await tester.pump();
      await tester.pump();

      // 連確認框都不該出現：這裡沒有「捨棄變更」這回事。
      expect(find.text(R.current.assignDiscardChanges), findsNothing);
      expect(find.byType(CourseAssignSubmitPage), findsOneWidget);

      repo.completer.complete(const Failed(FetchFailed('x')));
      await tester.pumpAndSettle();
    });
  });

  group('檔案列', () {
    testWidgets('本機剛挑的那一列不吃點擊：沒有事情可做就不要給漣漪', (tester) async {
      FilePickService.instance = _FakePickService([makeFile('report.pdf')]);
      await pump(tester, noDrafts(), fixtureStatus('status_can_edit'));

      await tapAndFlush(tester, addFilesButton());

      final tile = tester.widget<MoodleFileTile>(find.byType(MoodleFileTile));
      expect(tile.onTap, isNull);
    });

    testWidgets('已經交上去的那一列點得開', (tester) async {
      await pump(tester, submittable(), fixtureStatus('status_draft'));

      final tile = tester.widget<MoodleFileTile>(find.byType(MoodleFileTile));
      expect(tile.onTap, isNotNull);
    });
  });

  group('移除檔案', () {
    testWidgets('把伺服器上的檔案清光不給存：那等於把繳交檔案全部刪掉', (tester) async {
      await pump(tester, noDrafts(), fixtureStatus('status_draft'));

      await tester.tap(find.byTooltip(R.current.assignRemoveFile));
      await tester.pumpAndSettle();

      expect(find.byType(MoodleFileTile), findsNothing);
      expect(find.text(R.current.assignFilesEmptiedWebOnly), findsOneWidget);
      expect(enabled(tester, saveButton(R.current.assignSubmit)), isFalse);
    });
  });
}

/// 挑選器叫不起來。
class _ThrowingPickService implements FilePickService {
  @override
  Future<List<File>> pick({
    required int limit,
    List<String> extensions = const [],
  }) async =>
      throw const FilePickFailure(FilePickFailureReason.unavailable);
}

/// 一直不完成的寫入：測進行中的畫面。
class _PendingRepo extends MoodleRepository {
  final completer = Completer<Result<MoodleAssignSubmitResult>>();
  void Function(AssignTransferProgress progress)? onProgress;
  CancelToken? cancelToken;
  AssignSubmissionDraft? draft;

  @override
  Future<Result<MoodleAssignSubmitResult>> saveAssignSubmission({
    required MoodleAssignment assignment,
    required MoodleAssignSubmissionStatus status,
    required AssignSubmissionDraft draft,
    void Function(AssignTransferProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) {
    this.draft = draft;
    this.onProgress = onProgress;
    this.cancelToken = cancelToken;
    return completer.future;
  }
}
