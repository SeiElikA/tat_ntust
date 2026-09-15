import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/config/course_config.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/store/extra_table_store.dart';
import 'package:flutter_app/src/store/key_value_store.dart';
import 'package:flutter_app/src/util/course_table_control.dart';
import 'package:flutter_app/src/util/course_table_share_codec.dart';
import 'package:flutter_app/src/util/shared_table_builder.dart';
import 'package:flutter_app/ui/pages/course_table/share/shared_table_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

/// 他人課表的格線要跟自己的課表一樣填滿頁面：以前每一列寫死 56，節數少的課表底下空一大截。
/// 點課程開唯讀的課程選單，副標在學分補回來之後才顯示總學分。
void main() {
  late InMemoryKeyValueStore kv;

  setUpAll(() async {
    await R.load(const Locale('zh', 'TW'));
  });

  setUp(() {
    kv = InMemoryKeyValueStore();
    ExtraTableStore.instance = ExtraTableStore(kv);
  });

  CourseTableJson dataStructures() {
    final table = CourseTableJson(
      courseSemester: SemesterJson(year: '115', semester: '1'),
      studentId: 'B11000001',
    );
    table.addCourseDetailByCourseInfo(CourseMainInfoJson(
      course: CourseMainJson(
        id: 'CS3039701',
        name: '資料結構',
        credits: '3',
        time: {for (final day in Day.values) day: day == Day.monday ? '34' : ''},
      ),
    ));
    return table;
  }

  /// QR 掃進來、還沒補課名的課表：課名是課號，沒有學分。
  CourseTableJson scanned() => SharedTableBuilder.build(
      CourseTableShareCodec.decode('TAT21151B10000000AA1000001.434')!);

  List<CourseMainInfoJson> restored() => [
        CourseMainInfoJson(
          course: CourseMainJson(id: 'AA1000001', name: '離散數學', credits: '3'),
        ),
      ];

  ExtraTable sharedOf(CourseTableJson table) => ExtraTable(
        id: 'shared-1',
        label: 'B11000001',
        table: table,
        savedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  Future<void> pumpPage(
    WidgetTester tester,
    ExtraTable shared, {
    Future<List<CourseMainInfoJson>> Function(
            void Function(int done, int total) onProgress)?
        onRestore,
    void Function(CourseInfoJson course)? onOpenDetail,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(GetMaterialApp(
      home: SharedTablePage(
        shared: shared,
        onRestore: onRestore,
        onOpenDetail: onOpenDetail,
      ),
    ));
    await tester.pump();
  }

  testWidgets('列高照可用高度分成九節，跟課表頁一樣', (tester) async {
    final table = dataStructures();
    await pumpPage(tester, sharedOf(table));

    final control = CourseTableControl()..set(table);
    final day = control.getDayString(control.getDayIntList.first);
    final section = control.getSectionString(control.getSectionIntList.first);
    final headerTop = tester
        .getTopLeft(
            find.ancestor(of: find.text(day), matching: find.byType(SizedBox)).first)
        .dy;
    final rowHeight = tester
        .getSize(find
            .ancestor(of: find.text(section), matching: find.byType(Container))
            .first)
        .height;

    expect(
        rowHeight,
        closeTo(
            (800 - headerTop - CourseConfig.dayHeight) /
                CourseConfig.showCourseTableNum,
            0.5));
    expect(rowHeight, greaterThan(56));
  });

  testWidgets('副標是學期、門數與總學分', (tester) async {
    await pumpPage(tester, sharedOf(dataStructures()));

    expect(
        find.text('115-1 · ${sprintf(R.current.courseTableSummary, [1, 3])}'),
        findsOneWidget);
  });

  testWidgets('點課程開唯讀的選單：沒有 Moodle、移除與改課號，詳細內容交給呼叫端', (tester) async {
    final opened = <String>[];
    await pumpPage(tester, sharedOf(dataStructures()),
        onOpenDetail: (course) => opened.add(course.main.course.id));

    await tester.tap(find.text('資料結構').first);
    await tester.pumpAndSettle();

    expect(find.text(R.current.courseData), findsNothing);
    expect(find.text(R.current.remove), findsNothing);
    expect(find.byTooltip(R.current.edit), findsNothing);
    expect(find.byTooltip(R.current.copy), findsOneWidget);

    await tester.tap(find.text(R.current.details));
    await tester.pumpAndSettle();
    expect(opened, ['CS3039701']);
  });

  testWidgets('補課名時副標只有門數，補完才出現學分', (tester) async {
    final restore = Completer<List<CourseMainInfoJson>>();
    await pumpPage(tester, sharedOf(scanned()),
        onRestore: (_) => restore.future);

    expect(find.text('115-1 · ${sprintf(R.current.courseCount, [1])}'),
        findsOneWidget);
    expect(find.textContaining('學分'), findsNothing);

    restore.complete(restored());
    await tester.pumpAndSettle();

    expect(
        find.text('115-1 · ${sprintf(R.current.courseTableSummary, [1, 3])}'),
        findsOneWidget);
  });

  testWidgets('沒補過課名的快照沒有學分，副標不顯示 0 學分', (tester) async {
    await pumpPage(tester, sharedOf(scanned()));

    expect(find.text('115-1 · ${sprintf(R.current.courseCount, [1])}'),
        findsOneWidget);
    expect(find.textContaining('學分'), findsNothing);
  });

  testWidgets('補課名途中離開頁面，補好的課名與學分照樣存回去', (tester) async {
    final restore = Completer<List<CourseMainInfoJson>>();
    final shared = sharedOf(scanned());
    await ExtraTableStore.instance.upsertShared(shared);
    await pumpPage(tester, shared, onRestore: (_) => restore.future);

    await tester.pumpWidget(const SizedBox());
    restore.complete(restored());
    await tester.pump();

    final reloaded = ExtraTableStore(kv);
    await reloaded.load();
    final table = reloaded.findShared(shared.id)!.table;
    final cell = table.courseInfoMap[Day.thursday]![SectionNumber.t_3]!;
    expect(cell.main.course.name, '離散數學');
    expect(table.getTotalCredit(), 3);
  });

  testWidgets('補課名途中把這份他人課表刪掉，補完不會寫回來', (tester) async {
    final restore = Completer<List<CourseMainInfoJson>>();
    final shared = sharedOf(scanned());
    await ExtraTableStore.instance.upsertShared(shared);
    await pumpPage(tester, shared, onRestore: (_) => restore.future);

    await tester.pumpWidget(const SizedBox());
    await ExtraTableStore.instance.removeShared(shared.id);
    restore.complete(restored());
    await tester.pump();

    final reloaded = ExtraTableStore(kv);
    await reloaded.load();
    expect(reloaded.findShared(shared.id), isNull);
  });

  testWidgets('補課名的進度更新時，格子不會換顏色', (tester) async {
    final restore = Completer<List<CourseMainInfoJson>>();
    late void Function(int done, int total) report;
    await pumpPage(tester, sharedOf(scanned()), onRestore: (onProgress) {
      report = onProgress;
      return restore.future;
    });

    Color cellColor() => tester
        .widget<Material>(find
            .ancestor(of: find.text('AA1000001'), matching: find.byType(Material))
            .first)
        .color!;
    final before = cellColor();
    for (var i = 0; i < 5; i++) {
      report(i, 1);
      await tester.pump();
      expect(cellColor(), before);
    }
  });
}
