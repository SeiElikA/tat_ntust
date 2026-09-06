// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'moodle_mod_assign_get_assignments.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MoodleModAssignGetAssignments _$MoodleModAssignGetAssignmentsFromJson(
        Map<String, dynamic> json) =>
    MoodleModAssignGetAssignments(
      courses: (json['courses'] as List<dynamic>?)
              ?.map(
                  (e) => MoodleAssignCourse.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$MoodleModAssignGetAssignmentsToJson(
        MoodleModAssignGetAssignments instance) =>
    <String, dynamic>{
      'courses': instance.courses.map((e) => e.toJson()).toList(),
    };

MoodleAssignCourse _$MoodleAssignCourseFromJson(Map<String, dynamic> json) =>
    MoodleAssignCourse(
      assignments: (json['assignments'] as List<dynamic>?)
              ?.map((e) => MoodleAssignment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$MoodleAssignCourseToJson(MoodleAssignCourse instance) =>
    <String, dynamic>{
      'assignments': instance.assignments.map((e) => e.toJson()).toList(),
    };

MoodleAssignment _$MoodleAssignmentFromJson(Map<String, dynamic> json) =>
    MoodleAssignment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      cmid: (json['cmid'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      duedate: (json['duedate'] as num?)?.toInt() ?? 0,
      allowsubmissionsfromdate:
          (json['allowsubmissionsfromdate'] as num?)?.toInt() ?? 0,
      cutoffdate: (json['cutoffdate'] as num?)?.toInt() ?? 0,
      nosubmissions: (json['nosubmissions'] as num?)?.toInt() ?? 0,
      teamsubmission: (json['teamsubmission'] as num?)?.toInt() ?? 0,
      intro: json['intro'] as String?,
      introattachments: (json['introattachments'] as List<dynamic>?)
              ?.map((e) => MoodleAssignFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$MoodleAssignmentToJson(MoodleAssignment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'cmid': instance.cmid,
      'name': instance.name,
      'duedate': instance.duedate,
      'allowsubmissionsfromdate': instance.allowsubmissionsfromdate,
      'cutoffdate': instance.cutoffdate,
      'nosubmissions': instance.nosubmissions,
      'teamsubmission': instance.teamsubmission,
      'intro': instance.intro,
      'introattachments':
          instance.introattachments.map((e) => e.toJson()).toList(),
    };

MoodleAssignFile _$MoodleAssignFileFromJson(Map<String, dynamic> json) =>
    MoodleAssignFile(
      filename: json['filename'] as String? ?? '',
      fileurl: json['fileurl'] as String? ?? '',
      mimetype: json['mimetype'] as String? ?? '',
    );

Map<String, dynamic> _$MoodleAssignFileToJson(MoodleAssignFile instance) =>
    <String, dynamic>{
      'filename': instance.filename,
      'fileurl': instance.fileurl,
      'mimetype': instance.mimetype,
    };
