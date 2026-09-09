import 'package:flutter_app/src/connector/course_connector.dart';
import 'package:flutter_app/src/model/course_table/course_time.dart';
import 'package:flutter_app/src/util/course_table_control.dart';
import 'package:flutter_test/flutter_test.dart';

/// 節次標籤。
///
/// 臺科的節次是 `1 2 3 4 N 5 6 7 8 9 A B C D`——第五格是午休 `N`，而且沒有
/// 第 10 節。querycourse 的 `Node` 用的是「第幾格」，它前端那張 `1…10 A…D`
/// 的表跟這裡逐格對應，照抄過來就會把 15:30 那一列標成「8」。
void main() {
  group('CourseTableControl 的節次標籤', () {
    test('與 SectionNumber、timeEnum 逐格對位', () {
      final control = CourseTableControl();

      expect(
          control.sectionStringList.length, CourseTableControl.sectionLength);
      expect(control.sectionStringList, CourseConnector.timeEnum);
      for (int i = 0; i < CourseTableControl.sectionLength; i++) {
        expect(
          control.getSectionString(i),
          SectionNumber.values[i].name.split('_')[1],
          reason: '第 $i 格的標籤對不上 ${SectionNumber.values[i]}',
        );
      }
    });

    test('第五格是午休 N，而且沒有第 10 節', () {
      final control = CourseTableControl();

      expect(control.getSectionString(SectionNumber.t_N.index), 'N');
      expect(control.sectionStringList, isNot(contains('10')));
    });

    test('標籤與上課時間對得起來——15:30 是第 7 節', () {
      final control = CourseTableControl();
      final index = control.timeList.indexWhere((t) => t.startsWith('15:30'));

      expect(index, isNot(-1));
      expect(control.getSectionString(index), '7');
    });
  });
}
