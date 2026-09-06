import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'moodle_mod_assign_get_assignments.g.dart';

/// `mod_assign_get_assignments` 的回應。日期欄位伺服器已套過
/// `update_effective_access`，含使用者與群組的 override，App 不必再算。
/// 只宣告有人讀的欄位——未宣告的 key 不會進 `cache_moodle_assign` 那包 blob。
@JsonSerializable(explicitToJson: true)
class MoodleModAssignGetAssignments {
  @JsonKey(name: 'courses', defaultValue: [])
  List<MoodleAssignCourse> courses;

  MoodleModAssignGetAssignments({
    List<MoodleAssignCourse>? courses,
  }) : courses = courses ?? <MoodleAssignCourse>[];

  factory MoodleModAssignGetAssignments.fromJson(Map<String, dynamic> json) =>
      _$MoodleModAssignGetAssignmentsFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleModAssignGetAssignmentsToJson(this);

  @override
  String toString() => jsonEncode(this);
}

/// `courses[]` 的元素。只用來剝出 [assignments]，不快取。
@JsonSerializable(explicitToJson: true)
class MoodleAssignCourse {
  @JsonKey(name: 'assignments', defaultValue: [])
  List<MoodleAssignment> assignments;

  MoodleAssignCourse({
    List<MoodleAssignment>? assignments,
  }) : assignments = assignments ?? <MoodleAssignment>[];

  factory MoodleAssignCourse.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignCourseFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignCourseToJson(this);

  @override
  String toString() => jsonEncode(this);
}

/// 一份作業（`assignments[]` 的元素），只留畫面要用的欄位。
@JsonSerializable(explicitToJson: true)
class MoodleAssignment {
  /// assign instance id；`mod_assign_get_submission_status` 的 `assignid` 吃它。
  @JsonKey(name: 'id', defaultValue: 0)
  int id;

  /// course module id；網頁的 `mod/assign/view.php?id=` 吃它。
  @JsonKey(name: 'cmid', defaultValue: 0)
  int cmid;

  /// connector 的 `assignmentsOf` 已 HtmlUtils.clean 還原成純文字。
  @JsonKey(name: 'name', defaultValue: "")
  String name;

  /// Unix 秒，0 = 沒有截止日期。
  @JsonKey(name: 'duedate', defaultValue: 0)
  int duedate;

  @JsonKey(name: 'allowsubmissionsfromdate', defaultValue: 0)
  int allowsubmissionsfromdate;

  @JsonKey(name: 'cutoffdate', defaultValue: 0)
  int cutoffdate;

  /// 1 = 沒有任何繳交外掛（離線評分）；狀態籤不該說「未繳交」或「已逾期」。
  @JsonKey(name: 'nosubmissions', defaultValue: 0)
  int nosubmissions;

  /// 1 = 團隊作業：Moodle 學生頁看的是 `teamsubmission` 那一筆，不是自己的。
  @JsonKey(name: 'teamsubmission', defaultValue: 0)
  int teamsubmission;

  /// null = 伺服器沒送（尚未開放繳交），空字串 = 老師真的沒寫，兩者畫面不同。
  @JsonKey(name: 'intro')
  String? intro;

  @JsonKey(name: 'introattachments', defaultValue: [])
  List<MoodleAssignFile> introattachments;

  MoodleAssignment({
    this.id = 0,
    this.cmid = 0,
    this.name = "",
    this.duedate = 0,
    this.allowsubmissionsfromdate = 0,
    this.cutoffdate = 0,
    this.nosubmissions = 0,
    this.teamsubmission = 0,
    this.intro,
    List<MoodleAssignFile>? introattachments,
  }) : introattachments = introattachments ?? <MoodleAssignFile>[];

  bool get hasDueDate => duedate > 0;

  /// 不要用 `isNotEmpty`：null 與空字串語意不同，見 [intro]。
  bool get hasIntro => intro != null;

  bool get isTeamSubmission => teamsubmission != 0;

  /// 離線評分、沒有東西要交。
  bool get noSubmissionRequired => nosubmissions != 0;

  factory MoodleAssignment.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignmentFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignmentToJson(this);

  @override
  String toString() => jsonEncode(this);
}

/// `external_files` 的一個元素（intro 附件、繳交檔案、回饋檔案共用）。
@JsonSerializable(explicitToJson: true)
class MoodleAssignFile {
  @JsonKey(name: 'filename', defaultValue: "")
  String filename;

  /// pluginfile.php 網址，交給 `MoodleWebApiConnector.fileUrlWithToken` 加憑證。
  @JsonKey(name: 'fileurl', defaultValue: "")
  String fileurl;

  @JsonKey(name: 'mimetype', defaultValue: "")
  String mimetype;

  MoodleAssignFile({
    this.filename = "",
    this.fileurl = "",
    this.mimetype = "",
  });

  factory MoodleAssignFile.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignFileFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignFileToJson(this);

  @override
  String toString() => jsonEncode(this);
}
