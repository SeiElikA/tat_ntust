import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';

/// 攤平後的一則貼文與它的縮排層級。
class ThreadPost {
  const ThreadPost(this.post, this.depth);

  final MoodleForumPost post;
  final int depth;
}

/// 討論串的純函式：攤平、內嵌檔案還原與退路貼文。不碰 R.current 也不碰時鐘。
class MoodleForumUtils {
  MoodleForumUtils._();

  static const String pluginFileToken = '@@PLUGINFILE@@';

  /// post_exporter 不跑 format_text，訊息裡的 `@@PLUGINFILE@@` 原封不動送回來；
  /// 檔案的 url 是 `<前綴><filepath><filename>`，佔位字串代表的就是那個前綴。
  static String resolveInlinePluginFiles(
      String message, List<MoodleForumFile> files) {
    if (!message.contains(pluginFileToken)) return message;
    for (final f in files) {
      final base = _pluginFileBase(f);
      if (base != null) return message.replaceAll(pluginFileToken, base);
    }
    return message;
  }

  static String? _pluginFileBase(MoodleForumFile f) {
    final raw = '${f.filepath}${f.filename}';
    if (raw.isEmpty || f.url.isEmpty) return null;
    for (final suffix in [raw, _encodePath(raw), _rawEncodePath(raw)]) {
      if (f.url.endsWith(suffix)) {
        return f.url.substring(0, f.url.length - suffix.length);
      }
    }
    return null;
  }

  /// 逐段 encode，`/` 留著當分隔符。
  static String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  /// 伺服器那邊是 PHP `rawurlencode`，只留 `A-Za-z0-9-_.~`；Dart 的
  /// `encodeComponent` 還會留 `!*'()`，`Lecture (1).png` 這種檔名就對不起來。
  static final RegExp _notRawUrlEncoded = RegExp(r"[!*'()]");

  static String _rawEncodePath(String path) => _encodePath(path)
      .replaceAllMapped(_notRawUrlEncoded, (m) => _percent(m[0]!));

  static String _percent(String char) =>
      '%${char.codeUnitAt(0).toRadixString(16).toUpperCase()}';

  /// 依 parentid 攤平成「深度優先、同層照伺服器順序」的串。
  /// 找不到父貼文的（私訊回覆被濾掉時會發生）當成根，接在後面；
  /// visited 擋住互指的父子關係，最後再補走沒走到的，一篇都不會掉。
  static List<ThreadPost> buildThread(List<MoodleForumPost> posts) {
    final byId = {for (final p in posts) p.id: p};
    final children = <int, List<MoodleForumPost>>{};
    final roots = <MoodleForumPost>[];
    for (final p in posts) {
      final parent = p.parentid;
      if (!p.hasparent || parent == null || !byId.containsKey(parent)) {
        roots.add(p);
      } else {
        children.putIfAbsent(parent, () => []).add(p);
      }
    }

    final visited = <int>{};
    final flat = <ThreadPost>[];
    void walk(MoodleForumPost p, int depth) {
      if (!visited.add(p.id)) return;
      flat.add(ThreadPost(p, depth));
      for (final c in children[p.id] ?? const <MoodleForumPost>[]) {
        walk(c, depth + 1);
      }
    }

    for (final r in roots) {
      walk(r, 0);
    }
    // 全部互指成環時一個根都挑不出來，補走剩下的，免得整串貼文憑空消失。
    for (final p in posts) {
      walk(p, 0);
    }
    return flat;
  }

  /// 抓不到回覆時的退路：討論串清單那一列本身就是第一篇貼文。
  /// 它的 message 已經過 format_text，不需要再換 `@@PLUGINFILE@@`。
  static MoodleForumPost rootPostOf(Discussions d) => MoodleForumPost(
        id: d.id,
        subject: d.subject,
        message: d.message,
        discussionid: d.discussion,
        hasparent: false,
        timecreated: d.created,
        timemodified: d.modified,
        author: MoodleForumAuthor(fullname: d.userfullname),
        attachments: [
          for (final a in d.attachments)
            MoodleForumFile(filename: a.filename, url: a.fileurl),
        ],
      );
}
