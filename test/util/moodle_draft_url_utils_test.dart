import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/util/moodle_draft_url_utils.dart';
import 'package:flutter_app/src/util/moodle_forum_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 內嵌圖片三種網址寫法的換算規格。錯一格就是「貼文永久壞掉」或「token 被
/// 寫進一則同學都看得到的貼文」，所以每一條都要用真實的形狀。
void main() {
  const host = 'https://moodle2.ntust.edu.tw';
  const token = 'abc123token';
  const accessKey = 'privatekey99';

  /// 伺服器的 `url` 是 `make_webservice_pluginfile_url()` 組的，路徑逐段
  /// **rawurlencode 過**——測試一定要照這個形狀，不然括號檔名那條會假綠。
  String rawEncode(String name) => Uri.encodeComponent(name).replaceAllMapped(
      RegExp(r"[!*'()]"),
      (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}');

  /// `webservice/pluginfile.php/<modctx>/mod_forum/post/<postid>/<檔名>`。
  String pluginFile(String name) =>
      '$host/webservice/pluginfile.php/8801/mod_forum/post/951/'
      '${rawEncode(name)}';

  MoodleForumFile file(String name) =>
      MoodleForumFile(filename: name, filepath: '/', url: pluginFile(name));

  /// `fileUrlWithToken` 探測完成前的樣子。
  String withQueryToken(String url) => '$url?token=$token';

  /// 探測完成後的樣子。
  String withAccessKey(String url) => url.replaceFirst(
      '/webservice/pluginfile.php', '/tokenpluginfile.php/$accessKey');

  group('draftPrefixIn', () {
    // 伺服器端 file_prepare_draft_area() 最後一行組出來的就是這個形狀。
    const messageText = '<p>圖：<img src="$host/draftfile.php/123/user/draft/'
        '999/scope.png"></p>';

    test('itemid 對得上時挑得出前綴', () {
      expect(MoodleDraftUrlUtils.draftPrefixIn(messageText, 999, host: host),
          '$host/draftfile.php/123/user/draft/999/');
    });

    test('itemid 不一樣就回 null——別的 draft 區的前綴會存出永久壞掉的網址', () {
      expect(MoodleDraftUrlUtils.draftPrefixIn(messageText, 1000, host: host),
          isNull);
    });

    test('不是自家站台就回 null', () {
      expect(
          MoodleDraftUrlUtils.draftPrefixIn(messageText, 999,
              host: 'https://evil.example.com'),
          isNull);
    });

    test('itemid <= 0 一律回 null', () {
      expect(MoodleDraftUrlUtils.draftPrefixIn(messageText, 0, host: host),
          isNull);
      expect(MoodleDraftUrlUtils.draftPrefixIn(messageText, -1, host: host),
          isNull);
    });

    test('messagetext 是空的（area=attachment）時回 null', () {
      expect(MoodleDraftUrlUtils.draftPrefixIn('', 999, host: host), isNull);
    });
  });

  group('applyUrlMap', () {
    test('長的鍵先套，短的不會先吃掉半截', () {
      final short = pluginFile('a.png');
      final long = withQueryToken(short);
      final out = MoodleDraftUrlUtils.applyUrlMap(
        '<img src="$long">',
        {short: 'DRAFT/a.png', long: 'DRAFT/a.png'},
      );

      expect(out, '<img src="DRAFT/a.png">');
      expect(out.contains('token='), isFalse);
    });

    test('只掃一趟：換出來的值就算長得像另一個鍵也不會再被換一次', () {
      final out = MoodleDraftUrlUtils.applyUrlMap(
        'AAA',
        {'AAA': 'BBB', 'BBB': 'CCC'},
      );
      expect(out, 'BBB');
    });

    test('空的表是恆等', () {
      expect(MoodleDraftUrlUtils.applyUrlMap('<p>x</p>', const {}), '<p>x</p>');
    });
  });

  group('顯示表 → 存檔表的來回', () {
    const draftPrefix = '$host/draftfile.php/123/user/draft/999/';

    test('兩張圖（含帶括號與空白的檔名）都換成 draft 網址，一個 pluginfile 都不剩', () {
      final files = [file('scope.png'), file('Lecture (1).png')];
      // 伺服器回的原文長這樣：post_exporter 不跑 format_text。
      const raw = '<p>期中考範圍</p>'
          '<p><img src="${MoodleForumUtils.pluginFileToken}/scope.png"></p>'
          '<p><img src="${MoodleForumUtils.pluginFileToken}'
          '/Lecture%20%281%29.png"></p>';

      final resolved = MoodleForumUtils.resolveInlinePluginFiles(raw, files);
      final display = MoodleDraftUrlUtils.applyUrlMap(
        resolved,
        MoodleDraftUrlUtils.inlineUrlMapForDisplay(files, withQueryToken),
      );
      expect(display, contains('token=$token'));

      final saved = MoodleDraftUrlUtils.applyUrlMap(
        display,
        MoodleDraftUrlUtils.inlineUrlMapForSave(
            files, draftPrefix, withQueryToken),
      );

      expect(saved, contains('src="${draftPrefix}scope.png"'));
      // PHP rawurlencode 會逃 `(` `)`，Uri.encodeComponent 不會。
      expect(saved, contains('src="${draftPrefix}Lecture%20%281%29.png"'));
      expect(saved.contains('pluginfile.php'), isFalse);
    });

    test('存檔表同時收「帶憑證」與「原始」兩種寫法——探測翻轉可能落在開editor與存檔之間', () {
      final files = [file('scope.png')];
      final map = MoodleDraftUrlUtils.inlineUrlMapForSave(
          files, draftPrefix, withAccessKey);

      expect(map.keys, contains(pluginFile('scope.png')));
      expect(map.keys, contains(withAccessKey(pluginFile('scope.png'))));
      expect(map.values.toSet(), {'${draftPrefix}scope.png'});
    });

    test('沒有網址的檔案直接跳過，不會生出一個以空字串為鍵的表', () {
      final map = MoodleDraftUrlUtils.inlineUrlMapForSave(
          [MoodleForumFile(filename: 'x.png')], draftPrefix, withQueryToken);
      expect(map, isEmpty);
    });
  });

  group('tokenLeakIn', () {
    const draftPrefix = '$host/draftfile.php/123/user/draft/999/';

    String? leak(String html) => MoodleDraftUrlUtils.tokenLeakIn(html,
        host: host, wsToken: token, accessKey: accessKey);

    test('token 本身出現就擋', () {
      expect(leak('<p>$token</p>'), isNotNull);
    });

    test('?token= 就擋，不必比對值', () {
      expect(
          leak('<img src="${pluginFile('a.png')}?token=whatever">'), isNotNull);
    });

    test('tokenpluginfile.php 就擋', () {
      expect(
          leak('<img src="${withAccessKey(pluginFile('a.png'))}">'), isNotNull);
    });

    test('沒帶憑證的 pluginfile 也擋——那代表這張圖沒換成功，存進去就永久壞掉', () {
      expect(leak('<img src="${pluginFile('a.png')}">'), isNotNull);
    });

    test('只有 draftfile 網址時放行', () {
      expect(leak('<p>好</p><img src="${draftPrefix}a.png">'), isNull);
    });

    test('站台上的一般連結不算違規——貼文本來就常常互相連結', () {
      expect(
          leak('<a href="$host/mod/forum/discuss.php?d=7701">前一則</a>'), isNull);
    });

    test('沒有 token 時（登出後）仍然擋得住 pluginfile 網址', () {
      expect(
          MoodleDraftUrlUtils.tokenLeakIn('<img src="${pluginFile('a.png')}">',
              host: host, wsToken: null),
          isNotNull);
    });
  });
}
