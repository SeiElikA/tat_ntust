import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';

/// 內嵌圖片在三種寫法之間的換算：資料庫的 `@@PLUGINFILE@@`、編輯器看得見的
/// 帶憑證 pluginfile 網址、送回伺服器時的 `draftfile.php` 網址。
///
/// 為什麼另開一檔而不是塞進 `moodle_forum_edit_utils.dart`：那一支是「編輯
/// 與附件」的判斷，這裡全部是網址改寫，而且 repository 兩支都要 import——
/// 讓它們互相 import 就是一條沒必要的 util → util 橫向邊。
///
/// **不 import connector**（那是上行邊），所以 host、token、accesskey 與
/// 加憑證的動作全部由呼叫端傳進來。
class MoodleDraftUrlUtils {
  MoodleDraftUrlUtils._();

  /// `prepare_draft_area_for_post(area: 'post')` 回的 `messagetext` 裡，那個
  /// draft 區的網址前綴。
  ///
  /// 伺服器端是 `file_prepare_draft_area()` 最後一行
  /// `file_rewrite_pluginfile_urls($text, 'draftfile.php', $usercontext->id,
  /// 'user', 'draft', $draftitemid, ...)`，組出來就是
  /// `{wwwroot}/draftfile.php/{usercontextid}/user/draft/{itemid}/`。
  ///
  /// **一定要用讀的，不可以自己組**：usercontextid 沒有第二個可靠的來源。
  /// 而且尾巴的 itemid 必須等於 [draftItemId]——別的 draft 區的前綴組出來的
  /// 網址存進貼文之後，`file_save_draft_area_files()` 的反向 `str_ireplace`
  /// 對不上，那些絕對網址會原樣留在資料庫裡，圖片永久壞掉。
  static String? draftPrefixIn(String messageText, int draftItemId,
      {required String host}) {
    if (draftItemId <= 0 || host.isEmpty) return null;
    final pattern = RegExp('${RegExp.escape(host)}'
        r'/draftfile\.php/\d+/user/draft/'
        '$draftItemId/');
    return pattern.firstMatch(messageText)?.group(0);
  }

  /// 開編輯器時用的 {原始 pluginfile 網址 → 帶憑證的網址}。
  ///
  /// [tokenize] 由呼叫端注入（`MoodleWebApiConnector.fileUrlWithToken`），
  /// 這個檔案才不必 import connector，測試也不必有一顆真的 token。
  static Map<String, String> inlineUrlMapForDisplay(
      List<MoodleForumFile> inlineFiles, String Function(String) tokenize) {
    final map = <String, String>{};
    for (final f in inlineFiles) {
      if (f.url.isEmpty) continue;
      map[f.url] = tokenize(f.url);
    }
    return map;
  }

  /// 存檔時用的反向表：帶憑證的網址**與**原始網址都要對到 draft 區的網址。
  ///
  /// 為什麼兩種寫法都要收：`fileUrlWithToken` 不是它引數的純函式——
  /// `tokenPluginFileWorks` 探測完成之前回 `?token=`、之後回
  /// `/tokenpluginfile.php/<accesskey>/`，而那個翻轉可能剛好落在「打開編輯器」
  /// 與「按下儲存」之間。編輯器裡那一個寫法不見得是現在 tokenize() 產出的。
  static Map<String, String> inlineUrlMapForSave(
      List<MoodleForumFile> inlineFiles,
      String draftPrefix,
      String Function(String) tokenize) {
    final map = <String, String>{};
    for (final f in inlineFiles) {
      if (f.url.isEmpty) continue;
      final target = draftPrefix + _rawEncodePath(_relativePathOf(f));
      map[tokenize(f.url)] = target;
      map[f.url] = target;
    }
    return map;
  }

  /// `filepath` 開頭那個 `/` 要拿掉：[draftPrefix] 已經以 `/` 結尾。
  static String _relativePathOf(MoodleForumFile f) {
    final raw = '${f.filepath}${f.filename}';
    return raw.startsWith('/') ? raw.substring(1) : raw;
  }

  /// 逐段照 PHP `rawurlencode`。Dart 的 `encodeComponent` 會留下 `!*'()`，
  /// `Lecture (1).png` 這種檔名就對不起來。
  ///
  /// 刻意複製 `MoodleForumUtils` 裡同名的私有實作而不是 import 它：那是
  /// util → util 的橫向邊，換來的只是五行。
  static String _rawEncodePath(String path) => path
      .split('/')
      .map(Uri.encodeComponent)
      .join('/')
      .replaceAllMapped(_notRawUrlEncoded, (m) => _percent(m[0]!));

  static final RegExp _notRawUrlEncoded = RegExp(r"[!*'()]");

  static String _percent(String char) =>
      '%${char.codeUnitAt(0).toRadixString(16).toUpperCase()}';

  /// 逐字比對的取代，長的鍵先套。
  ///
  /// 兩件事都是刻意的：**長的先套**，否則 `…/a.png` 會先吃掉
  /// `…/a.png?token=X` 的前半段，留下一截 `?token=X` 在貼文裡；**只掃一趟**，
  /// 取代出來的結果不再回頭比對，一個長得像另一個鍵的檔名才不會被連續換兩次。
  static String applyUrlMap(String html, Map<String, String> map) {
    if (map.isEmpty || html.isEmpty) return html;
    final keys = map.keys.where((k) => k.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (keys.isEmpty) return html;

    final out = StringBuffer();
    var i = 0;
    outer:
    while (i < html.length) {
      for (final key in keys) {
        if (html.startsWith(key, i)) {
          out.write(map[key]);
          i += key.length;
          continue outer;
        }
      }
      out.writeCharCode(html.codeUnitAt(i));
      i++;
    }
    return out.toString();
  }

  /// 存檔前最後一道關卡：回第一個不該出現的片段，乾淨時回 null。
  /// **非 null 一定要中止存檔**，不可以就地清掉再送。
  ///
  /// 為什麼一定要有：編輯器要顯示內嵌圖片就得讓 `<img src>` 帶著憑證
  /// （`?token=<wsToken>` 或 `/tokenpluginfile.php/<accesskey>/`）。只要有一張
  /// 圖沒有被反向表換回去，那個網址就會被寫進一則同學都看得到的貼文，等於
  /// 把使用者的 web service token 公開。
  ///
  /// 沒帶憑證的 pluginfile 網址也算違規——它不是外洩，是「這張圖沒換成功」：
  /// 存進去之後伺服器不會再改寫它，`webservice/pluginfile.php` 對沒有 token
  /// 的網頁版是 404，圖片會永久壞掉。
  ///
  /// 站台上**非**檔案類的網址（`/mod/forum/discuss.php` 之類）不算違規：
  /// 貼文本來就常常互相連結，把它們也擋掉等於這種貼文永遠不能編輯。
  static String? tokenLeakIn(
    String html, {
    required String host,
    required String? wsToken,
    String? accessKey,
  }) {
    if (html.isEmpty) return null;
    final token = wsToken ?? '';
    if (token.isNotEmpty && html.contains(token)) return token;
    final key = accessKey ?? '';
    if (key.isNotEmpty && html.contains(key)) return key;
    if (html.contains('token=')) return 'token=';
    if (html.contains('/tokenpluginfile.php/')) return '/tokenpluginfile.php/';

    final bare = Uri.tryParse(host)?.host ?? '';
    if (bare.isEmpty) return null;
    final urls = RegExp('https?://${RegExp.escape(bare)}' r'''[^\s"'<>]*''');
    for (final m in urls.allMatches(html)) {
      final url = m.group(0)!;
      if (url.contains('pluginfile.php')) return url;
    }
    return null;
  }
}
