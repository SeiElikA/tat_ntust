import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/ui/components/file_type_icon.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_folder_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  final courseInfo = CourseInfoJson(
    main:
        CourseMainInfoJson(course: CourseMainJson(id: 'CS1001', name: '作業系統')),
  );

  testWidgets('每個檔案依 mimetype 或檔名畫出自己的 icon', (tester) async {
    final folder = Modules(
      name: '講義',
      modname: 'folder',
      contents: [
        Contents(filename: 'week1', mimetype: 'application/pdf'),
        Contents(filename: 'week2.pptx'),
        Contents(filename: 'dataset.bin'),
      ],
    );

    await tester
        .pumpWidget(GetMaterialApp(home: CourseFolderPage(courseInfo, folder)));
    await tester.pump();

    final icons =
        tester.widgetList<FileTypeIcon>(find.byType(FileTypeIcon)).toList();
    expect(icons.map((i) => i.iconName), ['pdf', 'powerpoint', 'unknown']);
    expect(find.text('week1'), findsOneWidget);
    expect(find.text('week2.pptx'), findsOneWidget);
    expect(find.text('dataset.bin'), findsOneWidget);
    expect(find.text('講義'), findsOneWidget);
  });

  testWidgets('空資料夾不會拋，也不畫任何 icon', (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      home:
          CourseFolderPage(courseInfo, Modules(name: '空的', modname: 'folder')),
    ));
    await tester.pump();

    expect(find.byType(FileTypeIcon), findsNothing);
  });
}
