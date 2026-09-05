import 'package:flutter_app/src/model/score/score_json.dart';
import 'package:flutter_app/src/util/score_utils.dart';
import 'package:flutter_test/flutter_test.dart';

ScoreItemJson item(String score, String credit) => ScoreItemJson(
      courseId: 'TC$score$credit',
      name: 'course',
      credit: credit,
      score: score,
      generalDimension: '',
      remark: '',
    );

/// 特徵化測試：凍結 ScoreUtils 與 ScoreItemJson 目前的行為（含已知的怪異之處），
/// 讓後續重構若改變 GPA 計算或及格判定時 CI 會紅燈。
void main() {
  group('ScoreUtils.calculateGPA', () {
    test('一般情況：以學分加權平均', () {
      // A+ = 4.3 * 3 = 12.9, C = 2.0 * 2 = 4.0 -> 16.9 / 5 = 3.38
      final gpa = ScoreUtils.calculateGPA([item('A+', '3'), item('C', '2')]);
      expect(gpa, '3.38');
    });

    test('括號學分（抵免課）會被去掉括號後計入', () {
      expect(ScoreUtils.calculateGPA([item('A', '(3)')]), '4.00');
    });

    test('分母只算 isValidScore 的學分，分子卻算全部（現況）', () {
      // 「成績未到」不是 valid，不進分母；但分子仍會查表，查不到得 0，
      // 因此不影響結果。這裡凍結兩者分母/分子取樣範圍不一致的現況。
      final gpa = ScoreUtils.calculateGPA([item('A', '3'), item('-', '3')]);
      expect(gpa, '4.00');
    });

    test('全部都是無效成績時分母為 0，回傳 NaN（現況，非 "0.00"）', () {
      expect(ScoreUtils.calculateGPA([item('-', '3')]), 'NaN');
    });

    test('空清單同樣回傳 NaN', () {
      expect(ScoreUtils.calculateGPA([]), 'NaN');
    });

    test('未列於對照表的成績（如「通過」）以 0 計分', () {
      // 分母 0（不是 valid），分子 0 -> NaN
      expect(ScoreUtils.calculateGPA([item('通過', '2')]), 'NaN');
    });

    test('小數學分會被 int.tryParse 判為 null 而以 0 計（現況）', () {
      // "2.5" 無法 int.tryParse -> 0 學分，分母 0 -> NaN
      expect(ScoreUtils.calculateGPA([item('A', '2.5')]), 'NaN');
    });

    test('gradeToGP 對照表涵蓋 A+ 到 X 共 12 個等第', () {
      expect(ScoreUtils.gradeToGP.length, 12);
      expect(ScoreUtils.gradeToGP['A+'], 4.3);
      expect(ScoreUtils.gradeToGP['E'], 0.0);
      expect(ScoreUtils.gradeToGP['X'], 0.0);
    });
  });

  group('ScoreItemJson 的及格與有效判定', () {
    test('isPassScore 以子字串比對 A/B/C', () {
      expect(item('A+', '3').isPassScore, isTrue);
      expect(item('B-', '3').isPassScore, isTrue);
      expect(item('C', '3').isPassScore, isTrue);
      expect(item('D', '3').isPassScore, isFalse);
      expect(item('E', '3').isPassScore, isFalse);
    });

    test('isValidScore 額外納入 D/E/X', () {
      expect(item('D', '3').isValidScore, isTrue);
      expect(item('E', '3').isValidScore, isTrue);
      expect(item('X', '3').isValidScore, isTrue);
      expect(item('-', '3').isValidScore, isFalse);
      expect(item('成績未到', '3').isValidScore, isFalse);
    });

    test('子字串比對會讓含 A/B/C 的中文成績被誤判為及格（現況）', () {
      expect(item('Abandon', '3').isPassScore, isTrue);
    });
  });
}
