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

  /// **新主題那條路的附件閘門，一趟都不用多打。**
  ///
  /// 伺服器算的是 `forum_can_create_attachment()`，也就是三件事的 AND：
  /// `has_capability('mod/forum:createattachment')` ∧ `maxattachments > 0`
  /// ∧ `maxbytes != 1`。VALUE_OPTIONAL，**null ＝不知道 ⇒ 不給附件**。
  ///
  /// 為什麼一定要看它：`add_discussion` 在沒有 createattachment 時把
  /// `attachmentsid` **靜靜改成 0**，附件整批消失而貼文照樣回成功。
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
