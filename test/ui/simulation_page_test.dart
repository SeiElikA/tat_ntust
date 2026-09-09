import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/store/extra_table_store.dart';
import 'package:flutter_app/src/store/key_value_store.dart';
import 'package:flutter_app/ui/pages/course_table/simulation/course_search_page.dart';
import 'package:flutter_app/ui/pages/course_table/simulation/simulation_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// 模擬排課的兩件事：草稿疊在實際課表上、以及搜尋頁看得到衝堂。
void main() {
  setUpAll(() async {
    await R.load(const Locale('zh', 'TW'));
  });

  setUp(() {
    ExtraTableStore.instance = ExtraTableStore(InMemoryKeyValueStore());
  });

  CourseMainInfoJson courseOf(String id, String name, Map<Day, String> time) =>
      CourseMainInfoJson(
        course: CourseMainJson(
          id: id,
          name: name,
          credits: '3',
          time: {for (final day in Day.values) day: time[day] ?? ''},
        ),
      );

  CourseTableJson tableOf(List<CourseMainInfoJson> courses) {
    final table = CourseTableJson(
      courseSemester: SemesterJson(year: '115', semester: '1'),
      studentId: 'B11000001',
    );
    for (final course in courses) {
      table.addCourseDetailByCourseInfo(course);
    }
    return table;
  }

  ExtraTable draftOf(CourseTableJson table) => ExtraTable(
        id: 'draft-1',
        label: '115-1 加退選草稿',
        table: table,
        savedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  Future<void> pumpSimulation(
    WidgetTester tester, {
    required CourseTableJson base,
    required CourseTableJson draft,
  }) async {
    await tester.pumpWidget(GetMaterialApp(
      home: SimulationPage(
        draft: draftOf(draft),
        base: base,
        openSearch: (_, __) async {},
      ),
    ));
    await tester.pump();
  }

  group('模擬課表', () {
    testWidgets('草稿是空的時候不出現衝堂橫幅，摘要寫 0 門', (tester) async {
      await pumpSimulation(
        tester,
        base: tableOf([
          courseOf('CS3003302', '離散數學', {Day.thursday: '3 4'})
        ]),
        draft: tableOf([]),
      );
      expect(find.textContaining('處衝堂'), findsNothing);
      expect(find.textContaining('草稿 0 門'), findsOneWidget);
      // 實際課表的課還是要畫出來，那是排課的底圖。
      expect(find.text('離散數學'), findsWidgets);
    });

    testWidgets('草稿撞到實際課表 → 橫幅寫幾處、寫在哪幾節', (tester) async {
      await pumpSimulation(
        tester,
        base: tableOf([
          courseOf('CS3003302', '離散數學', {Day.thursday: '3 4'})
        ]),
        draft: tableOf([
          courseOf('AC5012701', '矩陣理論', {Day.thursday: '3 4'})
        ]),
      );
      // 兩節都撞 → 2 處。橫幅與底部摘要各講一次，所以是 findsWidgets。
      expect(find.textContaining('2 處衝堂'), findsWidgets);
      expect(find.textContaining('四'), findsWidgets);
    });

    testWidgets('同一門課同時在實際課表與草稿裡不算衝堂', (tester) async {
      final course = courseOf('CS3003302', '離散數學', {Day.thursday: '3 4'});
      await pumpSimulation(
        tester,
        base: tableOf([course]),
        draft: tableOf([
          courseOf('CS3003302', '離散數學', {Day.thursday: '3 4'})
        ]),
      );
      expect(find.textContaining('處衝堂'), findsNothing);
    });

    testWidgets('沒有衝堂時摘要寫「沒有衝堂」', (tester) async {
      await pumpSimulation(
        tester,
        base: tableOf([
          courseOf('CS3003302', '離散數學', {Day.thursday: '3 4'})
        ]),
        draft: tableOf([
          courseOf('AC5012701', '矩陣理論', {Day.monday: '1 2'})
        ]),
      );
      expect(find.textContaining('處衝堂'), findsNothing);
      expect(find.textContaining('沒有衝堂'), findsOneWidget);
      expect(find.textContaining('草稿 1 門'), findsOneWidget);
    });
  });

  group('搜尋課程', () {
    Future<void> pumpSearch(
      WidgetTester tester, {
      required CourseTableJson base,
      required CourseTableJson draft,
      required List<CourseMainInfoJson> results,
    }) async {
      final added = <String>{};
      await tester.pumpWidget(GetMaterialApp(
        home: CourseSearchPage(
          editor: SimulationEditor(
            draft: draft,
            base: base,
            semester: SemesterJson(year: '115', semester: '1'),
            add: (course) => added.add(course.course.id),
            remove: added.remove,
            contains: added.contains,
          ),
          search: (_) async => results,
          loadColleges: () async => [],
          loadDepartments: (_) async => [],
        ),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'x');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    testWidgets('會撞到的課，卡片上寫是跟哪一門、哪一節撞', (tester) async {
      await pumpSearch(
        tester,
        base: tableOf([
          courseOf('CS3003302', '離散數學', {Day.thursday: '3 4'})
        ]),
        draft: tableOf([]),
        results: [
          courseOf('AC5012701', '矩陣理論', {Day.thursday: '3 4'})
        ],
      );
      expect(find.textContaining('與 離散數學'), findsOneWidget);
      // 撞到的節次要全部列出來，只印第一節會讓人以為退一節就排得進去。
      expect(find.textContaining('四 3·4'), findsWidgets);
    });

    testWidgets('不會撞的課沒有紅字', (tester) async {
      await pumpSearch(
        tester,
        base: tableOf([
          courseOf('CS3003302', '離散數學', {Day.thursday: '3 4'})
        ]),
        draft: tableOf([]),
        results: [
          courseOf('AC5012701', '矩陣理論', {Day.monday: '1 2'})
        ],
      );
      // 「只看不衝堂」那顆籤本身就含「衝堂」，所以只找卡片上那一行紅字。
      expect(find.textContaining('與 '), findsNothing);
      expect(find.text('矩陣理論'), findsOneWidget);
    });

    testWidgets('「只看不衝堂」把會撞的那一門收起來', (tester) async {
      await pumpSearch(
        tester,
        base: tableOf([
          courseOf('CS3003302', '離散數學', {Day.thursday: '3 4'})
        ]),
        draft: tableOf([]),
        results: [
          courseOf('AC5012701', '矩陣理論', {Day.thursday: '3 4'}),
          courseOf('AC5313701', '嵌入式系統', {Day.monday: '1 2'}),
        ],
      );
      expect(find.text('矩陣理論'), findsOneWidget);
      expect(find.text('嵌入式系統'), findsOneWidget);

      await tester.tap(find.text(R.current.courseSearchHideConflict));
      await tester.pumpAndSettle();

      expect(find.text('矩陣理論'), findsNothing);
      expect(find.text('嵌入式系統'), findsOneWidget);
    });

    testWidgets('節次印成「四 3·4」，不是內部格式的「四_34」', (tester) async {
      await pumpSearch(
        tester,
        base: tableOf([]),
        draft: tableOf([]),
        results: [
          courseOf('AC5012701', '矩陣理論', {Day.thursday: '3 4'})
        ],
      );
      expect(find.textContaining('四 3·4'), findsOneWidget);
      expect(find.textContaining('_'), findsNothing);
    });
  });
}
