import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'moodle_mod_forum_can_add_discussion.g.dart';

/// `mod_forum_can_add_discussion` 的回應。
///
/// `status` 是 `forum_user_can_post_discussion`，與 `MoodleForum
/// .cancreatediscussions` 同一個判斷，**同樣不含發文節流**——true 之後照樣
/// 可能收到 `forumblockingtoomanyposts`。`canpindiscussions` 不建模：
/// 釘選是老師的權限，App 從不送 `discussionpinned`。
@JsonSerializable()
class MoodleCanAddDiscussion {
  @JsonKey(name: 'status', defaultValue: false)
  bool status;

  /// VALUE_OPTIONAL。附件不在範圍內，留著只是為了形狀誠實。
  @JsonKey(name: 'cancreateattachment')
  bool? cancreateattachment;

  MoodleCanAddDiscussion({
    this.status = false,
    this.cancreateattachment,
  });

  factory MoodleCanAddDiscussion.fromJson(Map<String, dynamic> json) =>
      _$MoodleCanAddDiscussionFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleCanAddDiscussionToJson(this);

  @override
  String toString() => jsonEncode(this);
}
