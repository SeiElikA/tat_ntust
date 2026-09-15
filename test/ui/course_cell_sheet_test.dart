import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/ui/pages/course_table/modal/course_cell_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_l10n.dart';

/// 課程選單的按鈕看課從哪裡來：學校課表的課給 Moodle、自己加的課給移除，
/// 他人課表的課不是自己的，只留詳細內容。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestL10n();
  });

  CourseInfoJson courseOf({bool select = true}) => CourseInfoJson(
        main: CourseMainInfoJson(
          course: CourseMainJson(
              id: 'CS3039701', name: '資料結構', credits: '3', select: select),
        ),
      );

  Future<List<CourseCellAction?>> open(
    WidgetTester tester,
    CourseInfoJson course, {
    bool readOnly = false,
  }) async {
    final results = <CourseCellAction?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(await showCourseCellSheet(
              context: context,
              courseInfo: course,
              time: '08:10 - 09:00',
              color: Colors.teal,
              readOnly: readOnly,
            )),
            child: const Text('開'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('學校課表的課：有 Moodle 與改課號', (tester) async {
    await open(tester, courseOf());

    expect(find.text(R.current.courseData), findsOneWidget);
    expect(find.byTooltip(R.current.edit), findsOneWidget);
    expect(find.text(R.current.remove), findsNothing);
    expect(find.text(R.current.details), findsOneWidget);
  });

  testWidgets('自己加的課：給移除，不給 Moodle', (tester) async {
    await open(tester, courseOf(select: false));

    expect(find.text(R.current.remove), findsOneWidget);
    expect(find.text(R.current.courseData), findsNothing);
  });

  testWidgets('他人課表：只有詳細內容與複製，點了回報 detail', (tester) async {
    final results = await open(tester, courseOf(), readOnly: true);

    expect(find.text(R.current.courseData), findsNothing);
    expect(find.text(R.current.remove), findsNothing);
    expect(find.byTooltip(R.current.edit), findsNothing);
    expect(find.byTooltip(R.current.copy), findsOneWidget);

    await tester.tap(find.text(R.current.details));
    await tester.pumpAndSettle();
    expect(results, [CourseCellAction.detail]);
  });
}
