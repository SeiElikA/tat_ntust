import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/connector/core/connector_parameter.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/score/score_json.dart';
import 'package:flutter_app/src/repository/ntust_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/service/web_page_loader.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_session.dart';
import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 成績頁。[rows] 為 null 代表這次載不到。
class _ScorePage implements WebPageLoader {
  List<(String semester, String courseId)>? rows;
  int loads = 0;

  @override
  Future<WebPageResult> load(WebPageRequest request) async {
    loads++;
    final rows = this.rows;
    if (rows == null) return WebPageResult.timedOut;
    final body = [
      for (final (i, (semester, id)) in rows.indexed)
        '<tr><td>${i + 1}</td><td>$semester</td><td>$id</td><td>$id</td>'
            '<td>3</td><td>成績未到</td><td></td><td></td></tr>',
    ].join();
    return WebPageResult(WebPageOutcome.ok,
        html: '<html><body><div class="box-content alerts"><table><tbody>'
            '$body</tbody></table></div></body></html>');
  }
}

/// querycourse：問哪個課號就回哪一門，節次錯開免得撞堂。
class _QueryCourse implements HttpClientAdapter {
  _QueryCourse(this.template);

  final Map<String, dynamic> template;
  final List<String> asked = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final id = (options.data as Map)['CourseNo'] as String;
    asked.add(id);
    final course = {...template, 'CourseNo': id, 'Node': 'M${asked.length}'};
    return ResponseBody.fromString(jsonEncode([course]), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const account = 'B11230223';
  final semester = SemesterJson(year: '115', semester: '1');

  late _ScorePage scorePage;
  late HttpClientAdapter originalAdapter;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestL10n();
  });

  setUp(() {
    resetAppStatics();
    Model.instance.setAccount(account);
    AuthSession.instance = FakeAuthSession();
    ConnectivityProbe.instance = FakeConnectivityProbe(online: true);
    TaskUiDelegate.instance = const NoopTaskUiDelegate();
    scorePage = _ScorePage();
    WebPageLoader.instance = scorePage;
    final sample = jsonDecode(
        File('test/fixtures/querycourse/courses_1151_sample.json')
            .readAsStringSync()) as List<dynamic>;
    originalAdapter = DioConnector.instance.dio.httpClientAdapter;
    DioConnector.instance.dio.httpClientAdapter =
        _QueryCourse(sample.first as Map<String, dynamic>);

    // 加退選之前存下來的成績單。
    Model.instance.setScore(ScoreRankJson(info: [
      SemesterScoreJson(semester: semester, item: [
        for (final id in ['CS0000001', 'CS0000002'])
          ScoreItemJson(
              courseId: id,
              score: '-',
              name: id,
              credit: '3',
              generalDimension: '',
              remark: ''),
      ]),
    ]));
  });

  tearDown(() {
    DioConnector.instance.dio.httpClientAdapter = originalAdapter;
    WebPageLoader.instance = const InAppWebViewPageLoader();
    AuthSession.instance = const UninstalledAuthSession();
    ConnectivityProbe.instance = const PlatformConnectivityProbe();
  });

  Future<List<String>> courseIds({required bool refresh}) async {
    final result = await NtustRepository.instance
        .getCourseTable(account, semester, refresh: refresh);
    return result.dataOrNull!.getCourseIdList();
  }

  test('重新整理照成績單現在的課排，不是上次存下來的那幾門', () async {
    scorePage.rows = [('1151', 'CS0000002'), ('1151', 'CS0000003')];

    expect(await courseIds(refresh: true),
        unorderedEquals(['CS0000002', 'CS0000003']));

    await Model.instance.loadScore();
    expect(await Model.instance.getScore().getCourseIdBySemester(semester),
        unorderedEquals(['CS0000002', 'CS0000003']),
        reason: '重抓到的成績單要寫回硬碟，成績頁與歷年課表用的是同一份');
  });

  test('不是重新整理就照舊用存著的成績單，不去載成績頁', () async {
    scorePage.rows = [('1151', 'CS0000003')];

    expect(await courseIds(refresh: false),
        unorderedEquals(['CS0000001', 'CS0000002']));
    expect(scorePage.loads, 0);
  });

  test('成績頁載不到就改問 Moodle，不拿存著的那一份來排，也不把它蓋掉', () async {
    scorePage.rows = null;
    MoodleWebApiConnector.wsToken = 'token';
    MoodleWebApiConnector.userId = '1';
    MoodleWebApiConnector.wsPost = (ConnectorParameter parameter) async => [
          {'id': 1, 'idnumber': '1151CS0000005'},
        ];

    expect(await courseIds(refresh: true), ['CS0000005']);
    expect(scorePage.loads, 1);
    expect(await Model.instance.getScore().getCourseIdBySemester(semester),
        unorderedEquals(['CS0000001', 'CS0000002']),
        reason: '抓不到不等於成績是空的，存著的那一份不可以被蓋掉');
  });

  test('成績頁與 Moodle 都拿不到，重新整理就是失敗，不用存著的成績單湊一張', () async {
    scorePage.rows = null;
    MoodleWebApiConnector.wsToken = 'token';
    MoodleWebApiConnector.userId = '1';
    MoodleWebApiConnector.wsPost =
        (ConnectorParameter parameter) async => throw Exception('moodle down');

    final result = await NtustRepository.instance
        .getCourseTable(account, semester, refresh: true);

    expect(result, isA<Failed<CourseTableJson>>());
  });

  test('成績單還沒有這學期時，重新整理要重問 Moodle，不能用記憶體裡那一份', () async {
    scorePage.rows = [('1142', 'CS9999999')];
    MoodleWebApiConnector.wsToken = 'token';
    MoodleWebApiConnector.userId = '1';
    var enrolled = '1151CS0000001';
    MoodleWebApiConnector.wsPost = (ConnectorParameter parameter) async => [
          {'id': 1, 'idnumber': enrolled},
        ];
    expect(await MoodleWebApiConnector.getCourseIds(semester), ['CS0000001']);

    enrolled = '1151CS0000004';

    expect(await courseIds(refresh: true), ['CS0000004']);
  });
}
