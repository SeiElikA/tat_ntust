import 'dart:io';

import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/util/moodle_assign_submit_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/moodle_assign_fixtures.dart';

/// 交作業那條路的純函式規格。不碰 R.current、不碰網路。
void main() {
  MoodleAssignConfig cfg(String plugin, String name, String value,
          {String subtype = 'assignsubmission'}) =>
      MoodleAssignConfig(
          plugin: plugin, subtype: subtype, name: name, value: value);

  MoodleAssignment assignment({
    int teamsubmission = 0,
    int timelimit = 0,
    int blindmarking = 0,
    int nosubmissions = 0,
    List<MoodleAssignConfig>? configs,
  }) =>
      MoodleAssignment(
        id: 1,
        teamsubmission: teamsubmission,
        timelimit: timelimit,
        blindmarking: blindmarking,
        nosubmissions: nosubmissions,
        configs: configs ??
            [cfg('file', 'enabled', '1'), cfg('onlinetext', 'enabled', '1')],
      );

  MoodleAssignSubmissionStatus status({
    bool canedit = true,
    bool cansubmit = false,
    bool locked = false,
    bool submissionsenabled = true,
    bool blindmarking = false,
    int timelimit = 0,
    bool hasLastAttempt = true,
  }) =>
      MoodleAssignSubmissionStatus(
        lastattempt: hasLastAttempt
            ? MoodleAssignLastAttempt(
                canedit: canedit,
                cansubmit: cansubmit,
                locked: locked,
                submissionsenabled: submissionsenabled,
                blindmarking: blindmarking,
                timelimit: timelimit,
              )
            : null,
      );

  group('blockOf', () {
    test('全部允許時回 null', () {
      expect(MoodleAssignSubmitUtils.blockOf(assignment(), status()), isNull);
    });

    test('團隊作業', () {
      expect(
          MoodleAssignSubmitUtils.blockOf(
              assignment(teamsubmission: 1), status()),
          AssignSubmitBlock.team);
    });

    test('作業層的 timelimit', () {
      expect(
          MoodleAssignSubmitUtils.blockOf(assignment(timelimit: 600), status()),
          AssignSubmitBlock.timed);
    });

    test('lastattempt 的 timelimit 也算', () {
      expect(
          MoodleAssignSubmitUtils.blockOf(assignment(), status(timelimit: 600)),
          AssignSubmitBlock.timed);
    });

    test('匿名評分（作業層與 lastattempt 各一）', () {
      expect(
          MoodleAssignSubmitUtils.blockOf(
              assignment(blindmarking: 1), status()),
          AssignSubmitBlock.blind);
      expect(
          MoodleAssignSubmitUtils.blockOf(
              assignment(), status(blindmarking: true)),
          AssignSubmitBlock.blind);
    });

    test('nosubmissions 是離線評分', () {
      expect(
          MoodleAssignSubmitUtils.blockOf(
              assignment(nosubmissions: 1), status()),
          AssignSubmitBlock.noSubmission);
    });

    test('兩個外掛都沒開', () {
      expect(
          MoodleAssignSubmitUtils.blockOf(
              assignment(configs: [
                cfg('comments', 'enabled', '1', subtype: 'assignfeedback')
              ]),
              status()),
          AssignSubmitBlock.noPlugin);
    });

    test('lastattempt 缺席 = 沒有 viewownsubmissionsummary，什麼都不顯示', () {
      expect(
          MoodleAssignSubmitUtils.blockOf(
              assignment(), status(hasLastAttempt: false)),
          AssignSubmitBlock.closed);
    });

    test('submissionsenabled / locked / canedit 任一不對就是 closed', () {
      for (final s in [
        status(submissionsenabled: false),
        status(locked: true),
        status(canedit: false),
      ]) {
        expect(MoodleAssignSubmitUtils.blockOf(assignment(), s),
            AssignSubmitBlock.closed);
      }
    });

    test('判定順序：團隊作業又 canedit=false 時回 team，使用者才看得到可行動的理由', () {
      expect(
        MoodleAssignSubmitUtils.blockOf(
            assignment(teamsubmission: 1), status(canedit: false)),
        AssignSubmitBlock.team,
      );
    });

    test('fixture：可繳交的那一份真的可以交', () {
      expect(
        MoodleAssignSubmitUtils.blockOf(
            fixtureSubmittableAssignment(), fixtureStatus('status_can_edit')),
        isNull,
      );
    });

    test('fixture：被鎖定的與有時限的都擋下來', () {
      final a = fixtureSubmittableAssignment();
      expect(MoodleAssignSubmitUtils.blockOf(a, fixtureStatus('status_locked')),
          AssignSubmitBlock.closed);
      expect(MoodleAssignSubmitUtils.blockOf(a, fixtureStatus('status_timed')),
          AssignSubmitBlock.timed);
    });
  });

  group('configOf / pluginEnabled', () {
    test('只認 assignsubmission，assignfeedback 的同名外掛不算', () {
      final a = assignment(configs: [
        cfg('file', 'enabled', '1', subtype: 'assignfeedback'),
        cfg('file', 'maxfilesubmissions', '9', subtype: 'assignfeedback'),
      ]);
      expect(MoodleAssignSubmitUtils.pluginEnabled(a, 'file'), isFalse);
      expect(
          MoodleAssignSubmitUtils.configOf(a,
              plugin: 'file', name: 'maxfilesubmissions'),
          isNull);
    });

    test('configs 為空時全部回預設', () {
      final a = assignment(configs: []);
      expect(MoodleAssignSubmitUtils.pluginEnabled(a, 'file'), isFalse);
      expect(MoodleAssignSubmitUtils.pluginEnabled(a, 'onlinetext'), isFalse);
      expect(MoodleAssignSubmitUtils.maxFiles(a), 1);
      expect(MoodleAssignSubmitUtils.maxBytes(a), 0);
      expect(MoodleAssignSubmitUtils.fileTypes(a), isEmpty);
      expect(MoodleAssignSubmitUtils.wordLimit(a), 0);
    });

    test('fixture 的三個檔案設定都讀得出來', () {
      final a = fixtureSubmittableAssignment();
      expect(MoodleAssignSubmitUtils.maxFiles(a), 3);
      expect(MoodleAssignSubmitUtils.maxBytes(a), 2097152);
      expect(MoodleAssignSubmitUtils.fileTypes(a), ['.pdf', '.docx']);
      expect(MoodleAssignSubmitUtils.wordLimit(a), 500);
    });

    test('wordlimitenabled 為 0 時字數上限是 0', () {
      final a = assignment(configs: [
        cfg('onlinetext', 'enabled', '1'),
        cfg('onlinetext', 'wordlimitenabled', '0'),
        cfg('onlinetext', 'wordlimit', '500'),
      ]);
      expect(MoodleAssignSubmitUtils.wordLimit(a), 0);
    });
  });

  group('countWords', () {
    // 分隔符照 Moodle count_words 的 ~[\p{Z}\p{Cc}—–]+~u：多切一刀就是把交得
    // 出去的作業擋下來。
    test('照空白切，連續空白只算一刀', () {
      expect(MoodleAssignSubmitUtils.countWords('hello world'), 2);
      expect(MoodleAssignSubmitUtils.countWords('  hello   world  '), 2);
      expect(MoodleAssignSubmitUtils.countWords(''), 0);
      expect(MoodleAssignSubmitUtils.countWords('   '), 0);
    });

    test('換行與 tab 也是分隔符', () {
      expect(MoodleAssignSubmitUtils.countWords('a\nb\tc'), 3);
    });

    test('破折號兩側要切開，標點不切', () {
      expect(MoodleAssignSubmitUtils.countWords('long—dash'), 2);
      expect(MoodleAssignSubmitUtils.countWords('a–b'), 2);
      expect(MoodleAssignSubmitUtils.countWords("don't stop"), 2);
    });

    test('不加空白的中文整段算一個字，跟伺服器同一套', () {
      expect(MoodleAssignSubmitUtils.countWords('這是一份作業報告'), 1);
      expect(MoodleAssignSubmitUtils.countWords('第一段 第二段'), 2);
    });
  });

  test('maxBytes 缺席時 exceedsSize 一律 false', () {
    expect(MoodleAssignSubmitUtils.exceedsSize(1 << 30, 0), isFalse);
    expect(MoodleAssignSubmitUtils.exceedsSize(10, 10), isFalse);
    expect(MoodleAssignSubmitUtils.exceedsSize(11, 10), isTrue);
  });

  group('checkFileType', () {
    test('空清單一律放行', () {
      expect(MoodleAssignSubmitUtils.checkFileType('a.exe', const []),
          FileTypeCheck.allowed);
    });

    test('副檔名兩種寫法、大小寫都比得中', () {
      const types = ['.pdf', 'docx'];
      expect(MoodleAssignSubmitUtils.checkFileType('報告.PDF', types),
          FileTypeCheck.allowed);
      expect(MoodleAssignSubmitUtils.checkFileType('a.docx', types),
          FileTypeCheck.allowed);
      expect(MoodleAssignSubmitUtils.checkFileType('a.zip', types),
          FileTypeCheck.rejected);
    });

    test('mime 與 image/* 前綴', () {
      expect(
          MoodleAssignSubmitUtils.checkFileType(
              'a.pdf', const ['application/pdf']),
          FileTypeCheck.allowed);
      expect(MoodleAssignSubmitUtils.checkFileType('a.png', const ['image/*']),
          FileTypeCheck.allowed);
      expect(MoodleAssignSubmitUtils.checkFileType('a.pdf', const ['image/*']),
          FileTypeCheck.rejected);
    });

    test('Moodle 的群組名整份降級成 unverifiable，不擋', () {
      expect(MoodleAssignSubmitUtils.checkFileType('a.exe', const ['document']),
          FileTypeCheck.unverifiable);
      // 混著群組名時，對得中的仍然放行。
      expect(
          MoodleAssignSubmitUtils.checkFileType(
              'a.pdf', const ['document', '.pdf']),
          FileTypeCheck.allowed);
      expect(
          MoodleAssignSubmitUtils.checkFileType(
              'a.exe', const ['document', '.pdf']),
          FileTypeCheck.unverifiable);
    });
  });

  group('duplicateFilename', () {
    AssignDraftFile local(String name) =>
        LocalDraftFile(File('/tmp/$name'), name);

    test('沒有重複回 null', () {
      expect(
          MoodleAssignSubmitUtils.duplicateFilename(
              [local('a.pdf'), local('b.pdf')]),
          isNull);
    });

    test('大小寫視為相同，回第一個重複的名字', () {
      expect(
        MoodleAssignSubmitUtils.duplicateFilename(
            [local('a.pdf'), local('b.pdf'), local('A.PDF')]),
        'A.PDF',
      );
    });
  });

  group('plainToHtml / htmlToPlain', () {
    test('跳脫四個字元', () {
      expect(MoodleAssignSubmitUtils.plainToHtml('a & b < c > d "e"'),
          '<p>a &amp; b &lt; c &gt; d &quot;e&quot;</p>');
    });

    test('空字串回空字串，不可以變成 <p></p>', () {
      expect(MoodleAssignSubmitUtils.plainToHtml(''), '');
    });

    test('空行分段，段內換行用 <br>', () {
      expect(MoodleAssignSubmitUtils.plainToHtml('一\n二\n\n三'),
          '<p>一<br>二</p><p>三</p>');
    });

    test('純文字往返', () {
      for (final text in ['hello', '第一行\n第二行', 'a & b', '一\n二\n\n三']) {
        expect(
            MoodleAssignSubmitUtils.htmlToPlain(
                MoodleAssignSubmitUtils.plainToHtml(text)),
            text,
            reason: text);
      }
    });
  });

  group('onlineTextIsPlain', () {
    test('純 <p>/<br> 可以在 App 內編輯', () {
      expect(
          MoodleAssignSubmitUtils.onlineTextIsPlain('<p>你好<br>再見</p>'), isTrue);
      expect(MoodleAssignSubmitUtils.onlineTextIsPlain(''), isTrue);
    });

    test('內嵌檔案一律不給編輯', () {
      for (final html in [
        '<p><img src="x.png"></p>',
        '<video src="x.mp4"></video>',
        '<audio src="x.mp3"></audio>',
        '<p>@@PLUGINFILE@@/x.png</p>',
        '<p><a href="https://moodle2.ntust.edu.tw/pluginfile.php/1/x">x</a></p>',
      ]) {
        expect(MoodleAssignSubmitUtils.onlineTextIsPlain(html), isFalse,
            reason: html);
      }
    });
  });

  group('fileListChanged', () {
    MoodleAssignFile server(String name) =>
        MoodleAssignFile(filename: name, fileurl: 'https://x/$name');
    AssignDraftFile online(String name) =>
        OnlineDraftFile(name, 'https://x/$name');

    test('完全相同的線上清單 = 沒變', () {
      expect(
          MoodleAssignSubmitUtils.fileListChanged(
              [online('a.pdf'), online('b.pdf')],
              [server('a.pdf'), server('b.pdf')]),
          isFalse);
    });

    test('順序不同也算有變：重排要重傳才會是使用者看到的順序', () {
      expect(
          MoodleAssignSubmitUtils.fileListChanged(
              [online('b.pdf'), online('a.pdf')],
              [server('a.pdf'), server('b.pdf')]),
          isTrue);
    });

    test('名字相同但一邊是本機檔案 = 有變', () {
      expect(
          MoodleAssignSubmitUtils.fileListChanged(
              [LocalDraftFile(File('/tmp/a.pdf'), 'a.pdf')], [server('a.pdf')]),
          isTrue);
    });

    test('長度不同 = 有變', () {
      expect(
          MoodleAssignSubmitUtils.fileListChanged(const [], [server('a.pdf')]),
          isTrue);
    });
  });
}
