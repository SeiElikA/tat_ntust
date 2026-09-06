import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';

/// test/fixtures/moodle_assign/ 底下的 JSON。形狀照 MOODLE_405_STABLE 的
/// mod/assign/externallib.php，帶著所有 TAT 不建模的欄位（configs、
/// gradingsummary、usergroups……），解析時必須被忽略而不是拋。
Map<String, dynamic> loadMoodleAssignFixture(String name) => json.decode(
        File('test/fixtures/moodle_assign/$name.json').readAsStringSync())
    as Map<String, dynamic>;

/// `get_assignments.json` 剝出來的兩份作業（伺服器順序）。
///
/// 走 connector 的 `assignmentsOf` 而不是直接 fromJson：正式路徑上 repository
/// 拿到（並寫進快取）的就是它的輸出，`name` 已還原 HTML 實體。要看原始解析
/// 結果的測試自己呼叫 [MoodleModAssignGetAssignments.fromJson]。
List<MoodleAssignment> fixtureAssignments() =>
    MoodleWebApiConnector.assignmentsOf(
        loadMoodleAssignFixture('get_assignments'))!;

/// 同上，走 `submissionStatusOf`：`gradefordisplay` 已還原（`&nbsp;` → U+00A0）。
MoodleAssignSubmissionStatus fixtureStatus(String name) =>
    MoodleWebApiConnector.submissionStatusOf(loadMoodleAssignFixture(name))!;

/// 原始 fromJson，沒有經過 connector 的還原。給模型的解析契約用。
MoodleAssignSubmissionStatus rawFixtureStatus(String name) =>
    MoodleAssignSubmissionStatus.fromJson(loadMoodleAssignFixture(name));
