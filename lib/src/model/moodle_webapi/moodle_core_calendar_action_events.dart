import 'package:json_annotation/json_annotation.dart';

part 'moodle_core_calendar_action_events.g.dart';

/// `core_calendar_get_action_events_by_timesort` 的回應。寬鬆解析：欄位缺席
/// 或 null 一律退回預設值；沒宣告的欄位刻意不建模。
@JsonSerializable(explicitToJson: true)
class MoodleCoreCalendarActionEvents {
  @JsonKey(defaultValue: [])
  List<MoodleActionEvent> events;

  /// 翻頁用：下一頁的 `aftereventid`；清單為空時是 null。
  int? lastid;

  MoodleCoreCalendarActionEvents({
    this.events = const [],
    this.lastid,
  });

  factory MoodleCoreCalendarActionEvents.fromJson(Map<String, dynamic> json) =>
      _$MoodleCoreCalendarActionEventsFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleCoreCalendarActionEventsToJson(this);
}

/// 一筆行動事件。`overdue` 刻意不建模：那是伺服器匯出當下算的，
/// 快取拿出來時早就過時，分組一律看 [timesort]。
@JsonSerializable(explicitToJson: true)
class MoodleActionEvent {
  @JsonKey(defaultValue: 0)
  int id;

  /// connector 已還原 HTML 實體。
  @JsonKey(defaultValue: '')
  String name;

  String? activityname;

  String? modulename;

  /// Unix 秒。
  @JsonKey(defaultValue: 0)
  int timesort;

  @JsonKey(defaultValue: '')
  String url;

  MoodleActionEventCourse? course;

  MoodleActionEventAction? action;

  MoodleActionEvent({
    this.id = 0,
    this.name = '',
    this.activityname,
    this.modulename,
    this.timesort = 0,
    this.url = '',
    this.course,
    this.action,
  });

  factory MoodleActionEvent.fromJson(Map<String, dynamic> json) =>
      _$MoodleActionEventFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleActionEventToJson(this);

  String get title {
    final a = activityname?.trim();
    return (a != null && a.isNotEmpty) ? a : name;
  }

  String get openUrl {
    final a = action?.url.trim();
    return (a != null && a.isNotEmpty) ? a : url;
  }

  DateTime get dueTime => DateTime.fromMillisecondsSinceEpoch(timesort * 1000);
}

/// PARAM_BOOL 正常是 bool；容忍 1/0 與 "1"/"0"。
bool _boolFromJson(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

/// connector 已還原 HTML 實體。
@JsonSerializable()
class MoodleActionEventCourse {
  @JsonKey(defaultValue: '')
  String fullname;
  @JsonKey(defaultValue: '')
  String shortname;

  MoodleActionEventCourse({
    this.fullname = '',
    this.shortname = '',
  });

  factory MoodleActionEventCourse.fromJson(Map<String, dynamic> json) =>
      _$MoodleActionEventCourseFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleActionEventCourseToJson(this);
}

/// event_action_exporter：模組回報的「該做的事」。
@JsonSerializable()
class MoodleActionEventAction {
  /// 伺服器依使用者的 Moodle 介面語言產生，只顯示、不比對。
  @JsonKey(defaultValue: '')
  String name;
  @JsonKey(defaultValue: '')
  String url;

  /// false 代表現在還不能做（例如還沒到開放繳交的時間）。
  @JsonKey(fromJson: _boolFromJson)
  bool actionable;

  MoodleActionEventAction({
    this.name = '',
    this.url = '',
    this.actionable = false,
  });

  factory MoodleActionEventAction.fromJson(Map<String, dynamic> json) =>
      _$MoodleActionEventActionFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleActionEventActionToJson(this);
}
