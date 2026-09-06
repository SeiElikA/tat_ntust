import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:get/get.dart';

/// 作業詳情頁的狀態：作業本體與繳交狀態；由頁面的 State 建立與 [dispose]。
class CourseAssignmentController {
  CourseAssignmentController({
    required this.courseId,
    required this.assignId,
    MoodleAssignment? assignment,
    Result<MoodleAssignSubmissionStatus>? status,
  })  : assignment = Rxn(assignment == null ? null : Ok(assignment)),
        // Failed 的 seed 要重抓：清單是背景抓的，這次是使用者主動要看。
        status = Rxn((status?.hasData ?? false) ? status : null);

  final String courseId;
  final int assignId;

  final Rxn<Result<MoodleAssignment>> assignment;
  final Rxn<Result<MoodleAssignSubmissionStatus>> status;

  Future<void> loadAll() => Future.wait([
        if (assignment.value == null) loadAssignment(),
        if (status.value == null) loadStatus(),
      ]);

  Future<void> loadAssignment() async {
    assignment.value = null;
    assignment.value =
        await MoodleRepository.instance.getAssignment(courseId, assignId);
  }

  Future<void> loadStatus() async {
    status.value = null;
    status.value =
        await MoodleRepository.instance.getSubmissionStatus(assignId);
  }

  void dispose() {
    assignment.close();
    status.close();
  }
}
