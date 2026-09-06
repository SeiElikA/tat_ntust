import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'moodle_mod_forum_get_discussion_posts.g.dart';

/// `mod_forum_get_discussion_posts` 的回應。只宣告有人讀的欄位——宣告出來的
/// 都會進 `cache_moodle_forum_posts` 那包 blob。附件與內嵌檔案走
/// `stored_file_exporter`，網址欄位叫 `url` 不是 `fileurl`，而且沒有 mimetype
/// （見 docs/MOODLE_REFERENCE.md）。
@JsonSerializable(explicitToJson: true)
class MoodleModForumGetDiscussionPosts {
  @JsonKey(name: 'posts', defaultValue: [])
  List<MoodleForumPost> posts;

  MoodleModForumGetDiscussionPosts({List<MoodleForumPost>? posts})
      : posts = posts ?? <MoodleForumPost>[];

  factory MoodleModForumGetDiscussionPosts.fromJson(
          Map<String, dynamic> json) =>
      _$MoodleModForumGetDiscussionPostsFromJson(json);

  Map<String, dynamic> toJson() =>
      _$MoodleModForumGetDiscussionPostsToJson(this);

  @override
  String toString() => jsonEncode(this);
}

@JsonSerializable(explicitToJson: true)
class MoodleForumPost {
  @JsonKey(name: 'id', defaultValue: 0)
  int id;

  @JsonKey(name: 'subject', defaultValue: "")
  String subject;

  @JsonKey(name: 'message', defaultValue: "")
  String message;

  /// 規格上一定在，但缺席不該讓整份回應解析失敗。
  @JsonKey(name: 'author')
  MoodleForumAuthor? author;

  @JsonKey(name: 'discussionid', defaultValue: 0)
  int discussionid;

  @JsonKey(name: 'hasparent', defaultValue: false)
  bool hasparent;

  @JsonKey(name: 'parentid')
  int? parentid;

  /// `isdeleted` 的貼文伺服器不載內容，這兩個欄位是 null。
  @JsonKey(name: 'timecreated')
  int? timecreated;

  @JsonKey(name: 'timemodified')
  int? timemodified;

  @JsonKey(name: 'isdeleted', defaultValue: false)
  bool isdeleted;

  @JsonKey(name: 'isprivatereply', defaultValue: false)
  bool isprivatereply;

  @JsonKey(name: 'attachments', defaultValue: [])
  List<MoodleForumFile> attachments;

  /// `message` 裡 `@@PLUGINFILE@@` 的對照表，只有帶
  /// `includeinlineattachments=1` 才會回。
  @JsonKey(name: 'messageinlinefiles', defaultValue: [])
  List<MoodleForumFile> messageinlinefiles;

  MoodleForumPost({
    this.id = 0,
    this.subject = "",
    this.message = "",
    this.author,
    this.discussionid = 0,
    this.hasparent = false,
    this.parentid,
    this.timecreated,
    this.timemodified,
    this.isdeleted = false,
    this.isprivatereply = false,
    List<MoodleForumFile>? attachments,
    List<MoodleForumFile>? messageinlinefiles,
  })  : attachments = attachments ?? <MoodleForumFile>[],
        messageinlinefiles = messageinlinefiles ?? <MoodleForumFile>[];

  factory MoodleForumPost.fromJson(Map<String, dynamic> json) =>
      _$MoodleForumPostFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleForumPostToJson(this);

  @override
  String toString() => jsonEncode(this);
}

/// 貼文作者。`groups` 與 `urls` 沒有建模：討論串不畫頭像。
@JsonSerializable()
class MoodleForumAuthor {
  @JsonKey(name: 'id')
  int? id;

  @JsonKey(name: 'fullname', defaultValue: "")
  String fullname;

  @JsonKey(name: 'isdeleted', defaultValue: false)
  bool isdeleted;

  MoodleForumAuthor({
    this.id,
    this.fullname = "",
    this.isdeleted = false,
  });

  factory MoodleForumAuthor.fromJson(Map<String, dynamic> json) =>
      _$MoodleForumAuthorFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleForumAuthorToJson(this);

  @override
  String toString() => jsonEncode(this);
}

@JsonSerializable()
class MoodleForumFile {
  @JsonKey(name: 'filename', defaultValue: "")
  String filename;

  @JsonKey(name: 'filepath', defaultValue: "/")
  String filepath;

  @JsonKey(name: 'filesize', defaultValue: 0)
  int filesize;

  /// pluginfile 網址。stored_file_exporter 叫它 url，不是 fileurl。
  @JsonKey(name: 'url', defaultValue: "")
  String url;

  @JsonKey(name: 'isimage', defaultValue: false)
  bool isimage;

  MoodleForumFile({
    this.filename = "",
    this.filepath = "/",
    this.filesize = 0,
    this.url = "",
    this.isimage = false,
  });

  factory MoodleForumFile.fromJson(Map<String, dynamic> json) =>
      _$MoodleForumFileFromJson(json);

  Map<String, dynamic> toJson() => _$MoodleForumFileToJson(this);

  @override
  String toString() => jsonEncode(this);
}
