import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/moodle_forum_fixtures.dart';

/// 討論串攤平、內嵌檔案還原與退路貼文的純函式規格。
void main() {
  group('buildThread', () {
    test('深度優先、同層照伺服器順序', () {
      final flat = MoodleForumUtils.buildThread(fixturePosts());

      expect(flat.map((t) => t.post.id), [900, 901, 902, 903]);
      expect(flat.map((t) => t.depth), [0, 1, 2, 1]);
    });

    test('父貼文不在清單裡的當成根，接在真正的根後面而不是被丟掉', () {
      final flat = MoodleForumUtils.buildThread(
          fixturePosts('get_discussion_posts_orphan'));

      expect(flat.map((t) => t.post.id), [910, 912]);
      expect(flat.map((t) => t.depth), [0, 0]);
    });

    test('父子互指也會結束，而且兩篇各出現一次', () {
      final a = MoodleForumPost(id: 1, hasparent: true, parentid: 2);
      final b = MoodleForumPost(id: 2, hasparent: true, parentid: 1);

      final flat = MoodleForumUtils.buildThread([a, b]);

      expect(flat.map((t) => t.post.id), unorderedEquals([1, 2]));
      expect(flat, hasLength(2));
    });

    test('空清單 → 空清單', () {
      expect(MoodleForumUtils.buildThread(const []), isEmpty);
    });
  });

  group('resolveInlinePluginFiles', () {
    MoodleForumFile file(String filename, String url) =>
        MoodleForumFile(filename: filename, filepath: '/', url: url);

    test('檔名有空白（url 是 percent-encoded）也對得起來', () {
      const url = 'https://x/pluginfile.php/1/mod_forum/post/9/a%20b.png';

      expect(
        MoodleForumUtils.resolveInlinePluginFiles(
            '<img src="@@PLUGINFILE@@/a%20b.png">', [file('a b.png', url)]),
        '<img src="https://x/pluginfile.php/1/mod_forum/post/9/a%20b.png">',
      );
    });

    test("檔名帶 !*'() 也對得起來（伺服器是 rawurlencode，比 Dart 多轉這幾個）", () {
      const url =
          'https://x/pluginfile.php/1/mod_forum/post/9/Lecture%20%281%29.png';

      expect(
        MoodleForumUtils.resolveInlinePluginFiles(
            '<img src="@@PLUGINFILE@@/Lecture%20%281%29.png">',
            [file('Lecture (1).png', url)]),
        '<img src="$url">',
      );
    });

    test('純 ASCII 檔名照樣對得起來', () {
      const url = 'https://x/pluginfile.php/1/mod_forum/post/9/a.png';

      expect(
        MoodleForumUtils.resolveInlinePluginFiles(
            '<img src="@@PLUGINFILE@@/a.png">', [file('a.png', url)]),
        '<img src="https://x/pluginfile.php/1/mod_forum/post/9/a.png">',
      );
    });

    test('沒有檔案時原樣回傳（佔位字串留著，是看得見的破圖不是靜默錯誤）', () {
      const message = '<img src="@@PLUGINFILE@@/a.png">';

      expect(MoodleForumUtils.resolveInlinePluginFiles(message, const []),
          message);
    });

    test('訊息裡沒有佔位字串就原樣回傳', () {
      const message = '<p>沒有圖片</p>';

      expect(
        MoodleForumUtils.resolveInlinePluginFiles(
            message, [file('a.png', 'https://x/a.png')]),
        message,
      );
    });

    test('url 的結尾對不上 filepath+filename 時不亂猜', () {
      const message = '<img src="@@PLUGINFILE@@/a.png">';

      expect(
        MoodleForumUtils.resolveInlinePluginFiles(
            message, [file('a.png', 'https://x/other.png')]),
        message,
      );
    });
  });

  group('rootPostOf', () {
    test('discussionid 來自 discussion 而不是 id，附件的 fileurl 對映到 url', () {
      final d = fixtureDiscussions().discussions.first;

      final p = MoodleForumUtils.rootPostOf(d);

      expect(p.id, 8801);
      expect(p.discussionid, 7701, reason: 'id 是第一篇貼文的 id，不是討論串 id');
      expect(p.subject, d.subject);
      expect(p.message, d.message);
      expect(p.timecreated, d.created);
      expect(p.timemodified, d.modified);
      expect(p.author?.fullname, '王老師');
      expect(p.hasparent, isFalse);
      expect(p.parentid, isNull);
      expect(p.attachments.single.filename, 'exam_scope.pdf');
      expect(p.attachments.single.url, d.attachments.single.fileurl);
    });
  });
}
