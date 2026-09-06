import 'dart:convert';

import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/moodle_assign_fixtures.dart';

/// `mod_assign_get_assignments` 回應的解析契約（原始 fromJson；`name` 的
/// HTML 實體還原在 connector，見 moodle_webapi_assign_test）。
///
/// fixture 的第一份作業帶齊所有選用欄位（含 `configs`），第二份少了
/// intro / introfiles / introattachments（`show_intro()` 為 false 時伺服器
/// 根本不送這三個 key）且 duedate 為 0。
void main() {
  late MoodleModAssignGetAssignments parsed;

  setUpAll(() {
    parsed = MoodleModAssignGetAssignments.fromJson(
        loadMoodleAssignFixture('get_assignments'));
  });

  /// 模型宣告的欄位，也就是會被寫進 `cache_moodle_assign` 的全部 key。
  /// 每一個都要有畫面或狀態邏輯在讀；沒人讀的不要加回來。
  const declaredKeys = {
    'id',
    'cmid',
    'name',
    'duedate',
    'allowsubmissionsfromdate',
    'cutoffdate',
    'nosubmissions',
    'teamsubmission',
    'intro',
    'introattachments',
  };

  group('fixture 解析', () {
    test('一門課、兩份作業，未建模的欄位不會拋', () {
      expect(parsed.courses, hasLength(1));
      expect(parsed.courses.single.assignments, hasLength(2));
    });

    test('第一份：每個保留的欄位都對得上', () {
      final a1 = parsed.courses.single.assignments[0];

      expect(a1.id, 4101);
      expect(a1.cmid, 93001);
      // 伺服器 format_string 過的字串；模型不還原，connector 才做。
      expect(a1.name, 'HW1 &amp; Report');
      expect(a1.duedate, 1757548800);
      expect(a1.allowsubmissionsfromdate, 1756339200);
      expect(a1.cutoffdate, 1757635200);
      expect(a1.hasDueDate, isTrue);
      expect(a1.hasIntro, isTrue);
      expect(a1.intro, contains('<b>PDF</b>'));
      expect(a1.isTeamSubmission, isFalse);
      expect(a1.noSubmissionRequired, isFalse);
      expect(a1.introattachments.single.filename, 'hw1.pdf');
      expect(a1.introattachments.single.mimetype, 'application/pdf');
      expect(
          a1.introattachments.single.fileurl,
          startsWith(
              'https://moodle2.ntust.edu.tw/webservice/pluginfile.php/'));
    });

    test('第二份：沒送 intro 是 null（不是空字串）、沒有截止日期、團隊作業', () {
      final a2 = parsed.courses.single.assignments[1];

      expect(a2.id, 4102);
      expect(a2.intro, isNull);
      expect(a2.hasIntro, isFalse);
      expect(a2.introattachments, isEmpty);
      expect(a2.duedate, 0);
      expect(a2.hasDueDate, isFalse);
      expect(a2.teamsubmission, 1);
      expect(a2.isTeamSubmission, isTrue);
    });

    test('老師真的沒寫說明是空字串，hasIntro 仍為 true', () {
      final a = MoodleAssignment.fromJson({'id': 1, 'intro': ''});
      expect(a.intro, '');
      expect(a.hasIntro, isTrue);
    });

    test('nosubmissions = 1 是離線評分', () {
      expect(
          MoodleAssignment.fromJson({'nosubmissions': 1}).noSubmissionRequired,
          isTrue);
      expect(
          MoodleAssignment.fromJson({'nosubmissions': 0}).noSubmissionRequired,
          isFalse);
    });
  });

  group('快取形狀', () {
    test('toJson 只有宣告過的 key：configs、grade、introfiles 這些沒人讀的都不進快取', () {
      final keys = parsed.courses.single.assignments[0].toJson().keys.toSet();

      expect(keys, declaredKeys);
      expect(keys, isNot(contains('configs')));
      expect(keys, isNot(contains('submissionstatement')));
      expect(keys, isNot(contains('hidegrader')));
      expect(keys, isNot(contains('introfiles')));
      expect(keys, isNot(contains('gradingduedate')));
    });

    test('附件只留 filename / fileurl / mimetype', () {
      final f = parsed.courses.single.assignments[0].introattachments.single;
      expect(f.toJson().keys, {'filename', 'fileurl', 'mimetype'});
    });

    test('toJson → jsonEncode → jsonDecode → fromJson 保留畫面要用的欄位', () {
      final a1 = parsed.courses.single.assignments[0];
      final back = MoodleAssignment.fromJson(
          jsonDecode(jsonEncode(a1.toJson())) as Map<String, dynamic>);

      expect(back.id, a1.id);
      expect(back.cmid, a1.cmid);
      expect(back.duedate, a1.duedate);
      expect(back.intro, a1.intro);
      expect(back.introattachments.single.filename, 'hw1.pdf');
      expect(back.introattachments.single.fileurl,
          a1.introattachments.single.fileurl);
    });

    test('第二份 roundtrip 之後 intro 仍是 null', () {
      final a2 = parsed.courses.single.assignments[1];
      final back = MoodleAssignment.fromJson(
          jsonDecode(jsonEncode(a2.toJson())) as Map<String, dynamic>);

      expect(back.intro, isNull);
      expect(back.hasIntro, isFalse);
    });

    test('舊快取 blob 帶著已移除的欄位（grade、introfiles…）照樣解得開', () {
      final a = MoodleAssignment.fromJson({
        'id': 1,
        'grade': 100,
        'introfiles': <dynamic>[],
        'maxattempts': -1,
        'introattachments': [
          {'filename': 'a.pdf', 'filepath': '/', 'filesize': 1}
        ],
      });
      expect(a.id, 1);
      expect(a.introattachments.single.filename, 'a.pdf');
    });
  });

  group('寬鬆解析', () {
    test('空 map 全部退回預設值', () {
      final a = MoodleAssignment.fromJson({});

      expect(a.id, 0);
      expect(a.name, '');
      expect(a.duedate, 0);
      expect(a.intro, isNull);
      expect(a.introattachments, isEmpty);
    });

    test('Moodle 送 null 的欄位不會拋', () {
      final a = MoodleAssignment.fromJson({
        'duedate': null,
        'intro': null,
        'introattachments': null,
        'cutoffdate': null,
      });

      expect(a.duedate, 0);
      expect(a.cutoffdate, 0);
      expect(a.intro, isNull);
      expect(a.introattachments, isEmpty);
    });

    test('MoodleAssignFile：空 map 退回預設，未建模的 key 被忽略', () {
      expect(MoodleAssignFile.fromJson({}).filename, '');

      final f = MoodleAssignFile.fromJson({
        'filename': 'a.pdf',
        'isexternalfile': false,
        'repositorytype': null,
        'icon': 'f/pdf',
      });
      expect(f.filename, 'a.pdf');
      expect(f.toJson().keys, isNot(contains('icon')));
      expect(f.toJson().keys, isNot(contains('isexternalfile')));
    });

    test('整包回應是空的也不會拋', () {
      final empty = MoodleModAssignGetAssignments.fromJson({});
      expect(empty.courses, isEmpty);
    });
  });
}
