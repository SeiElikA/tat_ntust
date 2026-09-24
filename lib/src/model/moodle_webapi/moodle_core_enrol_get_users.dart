import 'package:json_annotation/json_annotation.dart';

part 'moodle_core_enrol_get_users.g.dart';

@JsonSerializable()
class MoodleCoreEnrolGetUsers {
  @JsonKey(name: 'id')
  int id;

  @JsonKey(name: 'fullname')
  String fullName;

  @JsonKey(name: 'email')
  String email;

  @JsonKey(name: 'description')
  String description;

  @JsonKey(name: 'descriptionformat')
  int descriptionFormat;

  @JsonKey(name: 'profileimageurlsmall')
  String profileImageUrlSmall;

  @JsonKey(name: 'profileimageurl')
  String profileImageUrl;

  @JsonKey(name: 'roles')
  late List<Roles> roles;

  /// 學生的 fullname 是「學號 @ 姓名」；老師沒有 @，就沒有學號。
  String get studentId {
    List<String> c = fullName.split("@");
    return c.length < 2 ? "" : c.first.replaceAll(" ", "");
  }

  String get name {
    List<String> c = fullName.split("@");
    return c.last.replaceAll(" ", "");
  }

  /// 老師與助教，名單上和學生分開列。掛著學生角色的人一律算學生（修這門課的
  /// 研究生兼助教）；roles 拿不到時也當學生，藏起來會讓名單變空。
  bool get isStaff =>
      roles.any((role) => role.isTeacher || role.isAssistant) &&
      !roles.any((role) => role.isStudent);

  /// 老師與助教那一列的角色名稱，照 Moodle 給的字。
  String get roleLabel => roles
      .where((role) => role.isTeacher || role.isAssistant)
      .map((role) => role.name.trim())
      .where((name) => name.isNotEmpty)
      .join('、');

  MoodleCoreEnrolGetUsers(
      {this.id = 0,
      this.fullName = "",
      this.email = "",
      this.description = "",
      this.descriptionFormat = 0,
      this.profileImageUrlSmall = "",
      this.profileImageUrl = "",
      List<Roles>? roles}) {
    this.roles = roles ?? [];
  }

  factory MoodleCoreEnrolGetUsers.fromJson(Map<String, dynamic> srcJson) =>
      _$MoodleCoreEnrolGetUsersFromJson(srcJson);

  Map<String, dynamic> toJson() => _$MoodleCoreEnrolGetUsersToJson(this);
}

@JsonSerializable()
class Roles {
  @JsonKey(name: 'roleid')
  int roleId;

  @JsonKey(name: 'name')
  String name;

  @JsonKey(name: 'shortname')
  String shortname;

  @JsonKey(name: 'sortorder')
  int sortOrder;

  Roles({
    this.roleId = 0,
    this.name = "",
    this.shortname = "",
    this.sortOrder = 0,
  });

  /// manager、coursecreator 是站台層級角色，不是這門課的老師。
  static const Set<String> teacherShortNames = {'editingteacher', 'teacher'};

  bool get isTeacher => teacherShortNames.contains(shortname);

  /// NTUST 自訂的「協同教學/課程助教」，shortname 不明，只認名字。
  bool get isAssistant => name.contains('協同教學') || name.contains('助教');

  bool get isStudent =>
      shortname == 'student' ||
      name.contains('學生') ||
      name.toLowerCase().contains('student');

  factory Roles.fromJson(Map<String, dynamic> srcJson) =>
      _$RolesFromJson(srcJson);

  Map<String, dynamic> toJson() => _$RolesToJson(this);
}
