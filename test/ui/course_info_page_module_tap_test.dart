import 'package:flutter/services.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course/course_main_extra_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_can_add_discussion.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_quiz_get_quizzes_by_courses.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_quiz_get_user_attempts.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_quiz_get_user_best_grade.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_folder_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_forum_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_info_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_quiz_detail_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/test_l10n.dart';

/// contents 為空的模組被點到時的行為。只點空模組，所以不會進到真的會寫檔的
/// FileDownload。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// fluttertoast 走 MethodChannel，測試裡沒有實作會丟 MissingPluginException。
  const toastChannel = MethodChannel('PonnamKarthik/fluttertoast');
  final toasts = <String>[];

  setUpAll(() async {
    await loadTestL10n();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(toastChannel, (call) async {
      final args = call.arguments;
      if (args is Map) toasts.add(args['msg'] as String);
      return true;
    });
  });

  setUp(toasts.clear);

  final courseInfo = CourseInfoJson(
    main:
        CourseMainInfoJson(course: CourseMainJson(id: 'CS1001', name: '作業系統')),
  );

  Future<void> pumpWithModule(WidgetTester tester, Modules module) async {
    await tester.pumpWidget(GetMaterialApp(
      home: CourseInfoPage(
        courseInfo,
        MoodleCoreCourseGetContents(name: '第一週', modules: [module]),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text(module.name));
    await tester.pumpAndSettle();
    // Fluttertoast 內部留一個 1 秒的 Timer，不走完會被判成 pending timer。
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('點 contents 為空的 resource 模組只會 toast，不會拋', (tester) async {
    await pumpWithModule(tester, Modules(name: '尚未上傳的檔案', modname: 'resource'));

    expect(tester.takeException(), isNull);
    expect(toasts, [R.current.nothingHere]);
  });

  testWidgets('點 contents 為空的 url 模組也是 toast，而不是靜默', (tester) async {
    await pumpWithModule(tester, Modules(name: '課程網站', modname: 'url'));

    expect(tester.takeException(), isNull);
    expect(toasts, [R.current.nothingHere]);
  });

  testWidgets('點空的 folder 模組會推進資料夾頁並畫空狀態', (tester) async {
    await pumpWithModule(tester, Modules(name: '空資料夾', modname: 'folder'));

    expect(find.byType(CourseFolderPage), findsOneWidget);
    expect(find.text(R.current.folderEmpty), findsOneWidget);
    expect(toasts, isEmpty);
  });

  testWidgets('點 forum 模組會推進討論區頁，不再直接開網頁', (tester) async {
    // forum 的 contents 也是空的；先前這一支是 openWebView。
    AuthSession.instance = FakeAuthSession();
    MoodleRepository.instance = _FailingQuizRepository();
    addTearDown(() {
      AuthSession.instance = const UninstalledAuthSession();
      MoodleRepository.instance = MoodleRepository();
    });

    await pumpWithModule(
        tester, Modules(name: '課程討論區', modname: 'forum', instance: 5499));

    final page = tester.widget<CourseForumPage>(find.byType(CourseForumPage));
    expect(page.forumId, 5499, reason: 'Modules.instance 就是 forum id');
    expect(page.forumName, '課程討論區');
    expect(toasts, isEmpty);
  });

  testWidgets('點 quiz 模組會推進測驗頁，不再掉進 default 分支 toast', (tester) async {
    // quiz 的 contents 一定是空的，先前會落到 resource/default 那一支。
    AuthSession.instance = FakeAuthSession();
    MoodleRepository.instance = _FailingQuizRepository();
    addTearDown(() {
      AuthSession.instance = const UninstalledAuthSession();
      MoodleRepository.instance = MoodleRepository();
    });

    await pumpWithModule(
        tester, Modules(name: '期中考', modname: 'quiz', instance: 4101));

    expect(find.byType(CourseQuizDetailPage), findsOneWidget);
    expect(toasts, isEmpty);
  });
}

/// 測驗頁一開就會發三個請求、討論區頁發兩個；這裡只驗導頁，所以全部立刻失敗。
class _FailingQuizRepository extends MoodleRepository {
  @override
  Future<Result<List<Discussions>>> getForumDiscussions(int forumId) async =>
      const Failed(FetchFailed('x'));

  @override
  Future<Result<MoodleCanAddDiscussion>> canAddDiscussion(int forumId) async =>
      const Failed(FetchFailed('x'));

  @override
  Future<Result<MoodleQuiz>> getQuiz(String courseId, int quizId) async =>
      const Failed(FetchFailed('x'));

  @override
  Future<Result<List<MoodleQuizAttempt>>> getQuizAttempts(int quizId,
          {bool background = false}) async =>
      const Failed(FetchFailed('x'));

  @override
  Future<Result<MoodleQuizBestGrade>> getQuizBestGrade(int quizId,
          {bool background = false}) async =>
      const Failed(FetchFailed('x'));
}
