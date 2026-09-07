import 'dart:io';

import 'package:flutter_app/src/controller/course_data/course_assign_submit_controller.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/util/moodle_assign_submit_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/moodle_assign_fixtures.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// raw 那一趟的假 repository。回 null 就是那一趟失敗——儲存不可以因此變成
/// 不可能，那才是這一頁最糟的失敗模式。
class _EditTextRepo extends MoodleRepository {
  _EditTextRepo(this.answer);

  final AssignOnlineTextEdit? answer;
  int calls = 0;

  @override
  Future<AssignOnlineTextEdit?> fetchOnlineTextForEdit({
    required MoodleAssignment assignment,
  }) async {
    calls++;
    return answer;
  }
}

/// 交作業編輯頁的儲存判斷。重點只有一個：**含圖片的線上文字照樣存得回去**，
/// 「文字框開不開」與「能不能存」是兩回事。
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestL10n();
  });

  setUp(resetAppStatics);

  tearDown(() {
    MoodleRepository.instance = MoodleRepository();
  });

  const area = 'https://moodle2.ntust.edu.tw/webservice/pluginfile.php'
      '/555/assignsubmission_onlinetext/submissions_onlinetext/8801';
  const restoredImage =
      '<p>看圖 <img src="@@PLUGINFILE@@/Lecture%20%281%29.png" alt=""></p>';

  CourseAssignSubmitController controller(
    MoodleAssignSubmissionStatus status, {
    MoodleAssignment? assignment,
  }) {
    final c = CourseAssignSubmitController(
      assignment: assignment ?? fixtureSubmittableAssignment(),
      status: status,
    );
    addTearDown(c.dispose);
    return c;
  }

  /// 挑一個本機檔案進清單＝這一次真的有變更。
  void addLocalFile(CourseAssignSubmitController c) =>
      c.files.add(LocalDraftFile(File('/tmp/report.pdf'), 'report.pdf'));

  group('原樣送回', () {
    test('主線：文字裡有圖，只加一個檔案——存得下去，而且送回去的是資料庫原文', () {
      final c = controller(fixtureStatus('status_onlinetext_inline'));
      addLocalFile(c);

      expect(c.onlineTextEditable, isFalse, reason: '純文字框開不了');
      expect(c.outgoingOnlineText, restoredImage);
      expect(c.saveBlock, isNull);
      expect(c.canSave, isTrue);
    });

    test('沒動過又沒有內嵌檔案時，送回去的字串跟伺服器那一份逐字相同', () {
      final c = controller(fixtureStatus('status_draft'));
      addLocalFile(c);

      expect(c.outgoingOnlineText, '<p>已附上報告</p>');
    });

    test('使用者自己打的字走 plainToHtml，不套還原', () {
      final c = controller(fixtureStatus('status_draft'));
      c.onlineText.value = '改過的內容';

      expect(c.textChanged, isTrue);
      expect(
          c.outgoingOnlineText, MoodleAssignSubmitUtils.plainToHtml('改過的內容'));
    });

    test('「不能編輯」跟「不能儲存」是兩件事', () {
      final c = controller(fixtureStatus('status_onlinetext_inline'));

      expect(c.onlineTextEditable, isFalse);
      expect(c.onlineTextUnrestorable, isFalse);
      expect(c.saveBlock, AssignSaveBlock.noChanges, reason: '只差在還沒改東西');
    });

    test('前綴推導不出來就整頁擋下——原樣送回去會永久寫死那些網址', () {
      final json = loadMoodleAssignFixture('status_onlinetext_inline');
      final plugins = (json['lastattempt']
          as Map<String, dynamic>)['submission']['plugins'] as List<dynamic>;
      for (final p in plugins) {
        if ((p as Map<String, dynamic>)['type'] == 'onlinetext') {
          (p['fileareas'] as List<dynamic>).first['files'] = <dynamic>[];
        }
      }
      final c = controller(MoodleAssignSubmissionStatus.fromJson(json));
      addLocalFile(c);

      expect(c.onlineTextUnrestorable, isTrue);
      expect(c.saveBlock, AssignSaveBlock.unrestorableOnlineText);
      expect(c.canSave, isFalse);
    });
  });

  group('loadEditableText', () {
    test('成功時送出去的是原文，不是狀態物件裡那份算繪過的', () async {
      MoodleRepository.instance = _EditTextRepo((
        rawText: '<p>看圖 <img src="@@PLUGINFILE@@/Lecture%20%281%29.png"></p>',
        inlineFiles: const <MoodleAssignFile>[],
      ));
      final c = controller(fixtureStatus('status_onlinetext_inline'));
      await c.loadEditableText();
      addLocalFile(c);

      expect(c.outgoingOnlineText,
          '<p>看圖 <img src="@@PLUGINFILE@@/Lecture%20%281%29.png"></p>');
      expect(c.canSave, isTrue);
    });

    test('那一趟失敗就退回還原絕對網址，儲存照樣成立', () async {
      final repo = _EditTextRepo(null);
      MoodleRepository.instance = repo;
      final c = controller(fixtureStatus('status_onlinetext_inline'));
      await c.loadEditableText();
      addLocalFile(c);

      expect(repo.calls, 1);
      expect(c.outgoingOnlineText, restoredImage);
      expect(c.canSave, isTrue);
    });

    test('原文本身就帶絕對網址時照樣存得下去——送回去的跟資料庫裡是同一串', () async {
      // 學生自己貼進編輯器的絕對網址在資料庫裡本來就是絕對的。原文那一趟
      // 成功時原封送回去只是寫回原處，擋下來就是又造一條新的死路。
      const pasted = '<p><img src="$area/pasted.png"></p>';
      MoodleRepository.instance = _EditTextRepo(
          (rawText: pasted, inlineFiles: const <MoodleAssignFile>[]));
      final c = controller(fixtureStatus('status_onlinetext_inline'));
      await c.loadEditableText();
      addLocalFile(c);

      expect(c.outgoingOnlineText, pasted);
      expect(c.onlineTextUnrestorable, isFalse);
      expect(c.canSave, isTrue);
    });

    test('文字框開得起來時根本不打那一趟——畫面上就是使用者自己的字', () async {
      final repo = _EditTextRepo(null);
      MoodleRepository.instance = repo;
      final c = controller(fixtureStatus('status_draft'));
      await c.loadEditableText();

      expect(repo.calls, 0);
    });

    test('不會去動輸入框的初值與 textChanged 的基準', () async {
      MoodleRepository.instance = _EditTextRepo((
        rawText: '<p>伺服器上的另一段字</p>',
        inlineFiles: const <MoodleAssignFile>[],
      ));
      final c = controller(fixtureStatus('status_onlinetext_inline'));
      final seeded = c.onlineText.value;
      await c.loadEditableText();

      expect(c.onlineText.value, seeded);
      expect(c.textChanged, isFalse);
    });
  });

  /// 伺服器的 `check_word_count` 會擋下整趟 `save_submission`，而那時檔案那半
  /// 可能已經寫進去了——文字框開不開都要先算一次。
  test('老師事後調低字數上限：沒動過的文字也要擋', () {
    final a = fixtureSubmittableAssignment()
      ..configs = [
        MoodleAssignConfig(
            plugin: 'onlinetext',
            subtype: 'assignsubmission',
            name: 'enabled',
            value: '1'),
        MoodleAssignConfig(
            plugin: 'onlinetext',
            subtype: 'assignsubmission',
            name: 'wordlimitenabled',
            value: '1'),
        MoodleAssignConfig(
            plugin: 'onlinetext',
            subtype: 'assignsubmission',
            name: 'wordlimit',
            value: '1'),
        MoodleAssignConfig(
            plugin: 'file',
            subtype: 'assignsubmission',
            name: 'enabled',
            value: '1'),
      ];
    // 圖片還在（所以文字框開不了），但字數超過老師新設的上限。
    final json = loadMoodleAssignFixture('status_onlinetext_inline');
    final plugins = (json['lastattempt'] as Map<String, dynamic>)['submission']
        ['plugins'] as List<dynamic>;
    for (final p in plugins) {
      if ((p as Map<String, dynamic>)['type'] == 'onlinetext') {
        (p['editorfields'] as List<dynamic>).first['text'] =
            '<p>one two three <img src="$area/Lecture%20%281%29.png"></p>';
      }
    }
    final c =
        controller(MoodleAssignSubmissionStatus.fromJson(json), assignment: a);
    addLocalFile(c);

    expect(c.onlineTextEditable, isFalse);
    expect(c.wordCount, 3);
    expect(c.overWordLimit, isTrue);
    expect(c.saveBlock, AssignSaveBlock.overWordLimit);
  });
}
