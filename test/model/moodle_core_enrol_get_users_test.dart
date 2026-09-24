import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_test/flutter_test.dart';

/// 名單頁把老師與助教和學生分開列：分錯邊會把同學藏進老師區，或把老師的
/// email 印在學生那一欄。
void main() {
  MoodleCoreEnrolGetUsers user(String fullName, List<Roles> roles) =>
      MoodleCoreEnrolGetUsers(fullName: fullName, roles: roles);

  Roles role(String shortname, String name) =>
      Roles(shortname: shortname, name: name);

  group('isStaff', () {
    test('editingteacher 與 teacher 是老師', () {
      expect(user('陳大文', [role('editingteacher', '教師')]).isStaff, isTrue);
      expect(user('陳大文', [role('teacher', 'Non-editing teacher')]).isStaff,
          isTrue);
    });

    test('NTUST 自訂的「協同教學/課程助教」只認名字', () {
      expect(user('李助教', [role('ta', '協同教學/課程助教')]).isStaff, isTrue);
    });

    test('掛著學生角色的助教還是學生，中英文都算', () {
      expect(
          user('M11312345 @ 王研究',
              [role('ta', '協同教學/課程助教'), role('student', '學生')]).isStaff,
          isFalse);
      expect(
          user('M11312345 @ 王研究',
              [role('ta', '協同教學/課程助教'), role('custom', 'Student')]).isStaff,
          isFalse);
    });

    test('名字裡有「老師」的學生、roles 為空、站台的 manager 都是學生', () {
      expect(user('B11012345 @ 王老師', [role('student', '學生')]).isStaff, isFalse);
      expect(user('B11012345 @ 王小明', []).isStaff, isFalse);
      expect(user('admin @ 管理員', [role('manager', 'Manager')]).isStaff, isFalse);
    });
  });

  test('roleLabel 只列老師與助教的角色名稱', () {
    expect(
        user('陳大文', [role('editingteacher', '教師'), role('ta', '協同教學/課程助教')])
            .roleLabel,
        '教師、協同教學/課程助教');
    expect(user('B1 @ 王', [role('student', '學生')]).roleLabel, '');
  });

  test('fullName 沒有 @ 的老師沒有學號，名字不會印兩次', () {
    final teacher = user('陳大文', [role('editingteacher', '教師')]);
    expect(teacher.name, '陳大文');
    expect(teacher.studentId, '');
    expect(user('B11230223 @ 王小明', []).studentId, 'B11230223');
  });
}
