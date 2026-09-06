import 'dart:convert';

import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:json_annotation/json_annotation.dart';

part 'moodle_mod_assign_get_submission_status.g.dart';

/// `mod_assign_get_submission_status` 的回應。只宣告有人讀的欄位——宣告出來的
/// 都會進 `cache_moodle_assign_status` 那包 blob。`plugins[]` 一律以 `type`
/// 分辨，不要看 `name`：那是隨介面語言變的本地化顯示名。
@JsonSerializable(explicitToJson: true)
class MoodleAssignSubmissionStatus {
  /// 缺席代表還沒繳交，是正常回應。
  @JsonKey(name: 'lastattempt')
  MoodleAssignLastAttempt? lastattempt;

  /// 缺席 = 學生目前看不到任何成績或回饋（隱藏、未釋出、或還沒評）。
  @JsonKey(name: 'feedback')
  MoodleAssignFeedback? feedback;

  MoodleAssignSubmissionStatus({
    this.lastattempt,
    this.feedback,
  });

  /// 沒有評分流程時 `get_grading_status` 回 graded / notgraded；
  /// 有評分流程時回流程狀態，released 才代表學生看得到。
  static const String gradingStatusGraded = 'graded';
  static const String gradingStatusReleased = 'released';

  /// 團隊作業看 `teamsubmission`，否則看自己的 `submission`。順序不能反過來：
  /// 伺服器兩筆都回，哪一筆算數要看作業設定，不能用 null 合併。
  MoodleAssignSubmission? submissionFor(MoodleAssignment a) =>
      a.isTeamSubmission
          ? (lastattempt?.teamsubmission ?? lastattempt?.submission)
          : lastattempt?.submission;

  /// 以 `gradingstatus` 為準（成績被藏起來時它照樣是 graded），
  /// 再退回 feedback 有沒有可見成績。
  bool get isGraded {
    final gs = lastattempt?.gradingstatus;
    if (gs == gradingStatusGraded || gs == gradingStatusReleased) return true;
    return feedback?.hasGrade ?? false;
  }

  /// 延長期限（Unix 秒），0 = 沒有延長。
  int get extensionDueDate => lastattempt?.extensionduedate ?? 0;

  factory MoodleAssignSubmissionStatus.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignSubmissionStatusFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignSubmissionStatusToJson(this);

  @override
  String toString() => jsonEncode(this);
}

@JsonSerializable(explicitToJson: true)
class MoodleAssignLastAttempt {
  /// 自己的那一筆。缺席 = 還沒有任何繳交紀錄（連 `new` 那一筆都沒有）。
  @JsonKey(name: 'submission')
  MoodleAssignSubmission? submission;

  /// 群組那一筆，只有團隊作業才有；見 [MoodleAssignSubmissionStatus.submissionFor]。
  @JsonKey(name: 'teamsubmission')
  MoodleAssignSubmission? teamsubmission;

  /// Unix 秒，0 = 沒有延長。整列 user flags 不存在時伺服器會送 null。
  @JsonKey(name: 'extensionduedate', defaultValue: 0)
  int extensionduedate;

  /// graded / notgraded，或評分流程的 notmarked / inmarking / readyforreview /
  /// inreview / readyforrelease / released。
  @JsonKey(name: 'gradingstatus', defaultValue: "")
  String gradingstatus;

  MoodleAssignLastAttempt({
    this.submission,
    this.teamsubmission,
    this.extensionduedate = 0,
    this.gradingstatus = "",
  });

  factory MoodleAssignLastAttempt.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignLastAttemptFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignLastAttemptToJson(this);

  @override
  String toString() => jsonEncode(this);
}

@JsonSerializable(explicitToJson: true)
class MoodleAssignSubmission {
  /// Unix 秒。submitted 時等於繳交時間；draft 時只是最後一次存草稿。
  @JsonKey(name: 'timemodified', defaultValue: 0)
  int timemodified;

  /// new / reopened / draft / submitted；new 與 reopened 都不算繳交。
  @JsonKey(name: 'status', defaultValue: "")
  String status;

  @JsonKey(name: 'plugins', defaultValue: [])
  List<MoodleAssignPlugin> plugins;

  MoodleAssignSubmission({
    this.timemodified = 0,
    this.status = "",
    List<MoodleAssignPlugin>? plugins,
  }) : plugins = plugins ?? <MoodleAssignPlugin>[];

  static const String statusDraft = 'draft';
  static const String statusSubmitted = 'submitted';

  bool get isSubmitted => status == statusSubmitted;

  bool get isDraft => status == statusDraft;

  /// 繳交的檔案（file 外掛）。
  List<MoodleAssignFile> get files => [
        for (final p in plugins)
          if (p.type == 'file') ...p.allFiles
      ];

  /// 線上文字（onlinetext 外掛），HTML；沒有就空字串。
  String get onlineText {
    for (final p in plugins) {
      if (p.type == 'onlinetext') return p.editorText('onlinetext');
    }
    return "";
  }

  factory MoodleAssignSubmission.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignSubmissionFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignSubmissionToJson(this);

  @override
  String toString() => jsonEncode(this);
}

@JsonSerializable(explicitToJson: true)
class MoodleAssignPlugin {
  /// file / onlinetext / comments / editpdf ……只能用這個欄位分辨。
  @JsonKey(name: 'type', defaultValue: "")
  String type;

  @JsonKey(name: 'fileareas', defaultValue: [])
  List<MoodleAssignFileArea> fileareas;

  @JsonKey(name: 'editorfields', defaultValue: [])
  List<MoodleAssignEditorField> editorfields;

  MoodleAssignPlugin({
    this.type = "",
    List<MoodleAssignFileArea>? fileareas,
    List<MoodleAssignEditorField>? editorfields,
  })  : fileareas = fileareas ?? <MoodleAssignFileArea>[],
        editorfields = editorfields ?? <MoodleAssignEditorField>[];

  List<MoodleAssignFile> get allFiles =>
      [for (final a in fileareas) ...a.files];

  /// 名為 [fieldName] 的編輯欄位文字，沒有就空字串。
  String editorText(String fieldName) {
    for (final f in editorfields) {
      if (f.name == fieldName) return f.text;
    }
    return "";
  }

  factory MoodleAssignPlugin.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignPluginFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignPluginToJson(this);

  @override
  String toString() => jsonEncode(this);
}

/// 一個 file area；`area` 名稱不宣告，UI 把同外掛底下的 area 全部攤平。
@JsonSerializable(explicitToJson: true)
class MoodleAssignFileArea {
  @JsonKey(name: 'files', defaultValue: [])
  List<MoodleAssignFile> files;

  MoodleAssignFileArea({
    List<MoodleAssignFile>? files,
  }) : files = files ?? <MoodleAssignFile>[];

  factory MoodleAssignFileArea.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignFileAreaFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignFileAreaToJson(this);

  @override
  String toString() => jsonEncode(this);
}

@JsonSerializable(explicitToJson: true)
class MoodleAssignEditorField {
  @JsonKey(name: 'name', defaultValue: "")
  String name;

  /// HTML（`moodlewssettingfilter=true` 時伺服器已 format_text）。
  @JsonKey(name: 'text', defaultValue: "")
  String text;

  MoodleAssignEditorField({
    this.name = "",
    this.text = "",
  });

  factory MoodleAssignEditorField.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignEditorFieldFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignEditorFieldToJson(this);

  @override
  String toString() => jsonEncode(this);
}

@JsonSerializable(explicitToJson: true)
class MoodleAssignGrade {
  /// 形如 "85.00000"；"-1.00000" 是 ASSIGN_GRADE_NOT_SET（只給評語沒給分數）。
  @JsonKey(name: 'grade', defaultValue: "")
  String grade;

  MoodleAssignGrade({
    this.grade = "",
  });

  bool get isSet => (double.tryParse(grade) ?? -1) >= 0;

  factory MoodleAssignGrade.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignGradeFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignGradeToJson(this);

  @override
  String toString() => jsonEncode(this);
}

/// `feedback`：學生看得到的成績與回饋。
@JsonSerializable(explicitToJson: true)
class MoodleAssignFeedback {
  /// 只有評語、沒有分數時也在，`grade` 是 "-1.00000"。
  @JsonKey(name: 'grade')
  MoodleAssignGrade? grade;

  /// 伺服器回的是 HTML 片段（如 `85.00&nbsp;/&nbsp;100.00`），connector 的
  /// `submissionStatusOf` 已 HtmlUtils.clean 成純文字，這裡只進 Text。
  @JsonKey(name: 'gradefordisplay', defaultValue: "")
  String gradefordisplay;

  /// Unix 秒；成績簿沒有評分日期時是 null。
  @JsonKey(name: 'gradeddate')
  int? gradeddate;

  @JsonKey(name: 'plugins', defaultValue: [])
  List<MoodleAssignPlugin> plugins;

  MoodleAssignFeedback({
    this.grade,
    this.gradefordisplay = "",
    this.gradeddate,
    List<MoodleAssignPlugin>? plugins,
  }) : plugins = plugins ?? <MoodleAssignPlugin>[];

  bool get hasGrade =>
      gradefordisplay.trim().isNotEmpty || (grade?.isSet ?? false);

  /// 老師的文字回饋（comments 外掛），HTML；沒有就空字串。
  String get commentsHtml {
    for (final p in plugins) {
      if (p.type == 'comments') return p.editorText('comments');
    }
    return "";
  }

  /// 回饋檔案：file、editpdf 等所有非 comments 外掛的檔案。
  List<MoodleAssignFile> get files => [
        for (final p in plugins)
          if (p.type != 'comments') ...p.allFiles
      ];

  factory MoodleAssignFeedback.fromJson(Map<String, dynamic> json) =>
      _$MoodleAssignFeedbackFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleAssignFeedbackToJson(this);

  @override
  String toString() => jsonEncode(this);
}
