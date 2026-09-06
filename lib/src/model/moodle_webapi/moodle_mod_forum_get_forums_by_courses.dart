import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'moodle_mod_forum_get_forums_by_courses.g.dart';

/// `mod_forum_get_forums_by_courses` 的回應元素。回的是一個陣列，
/// 不是 `{forums: []}`；只宣告畫面與判斷會讀的欄位。
@JsonSerializable()
class MoodleForum {
  /// forum instance id，也就是 `mod_forum_get_forum_discussions` 的 `forumid`。
  @JsonKey(name: 'id', defaultValue: 0)
  int id;

  @JsonKey(name: 'course', defaultValue: 0)
  int course;

  /// news / general / eachuser / single / qanda / blog。公告區是 news。
  @JsonKey(name: 'type', defaultValue: "")
  String type;

  @JsonKey(name: 'name', defaultValue: "")
  String name;

  @JsonKey(name: 'cmid', defaultValue: 0)
  int cmid;

  @JsonKey(name: 'numdiscussions', defaultValue: 0)
  int numdiscussions;

  MoodleForum({
    this.id = 0,
    this.course = 0,
    this.type = "",
    this.name = "",
    this.cmid = 0,
    this.numdiscussions = 0,
  });

  factory MoodleForum.fromJson(Map<String, dynamic> json) =>
      _$MoodleForumFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleForumToJson(this);

  @override
  String toString() => jsonEncode(this);
}
