import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/moodle_forum_fixtures.dart';

/// 公告三支 function 回應的本機判讀規格。判讀抽成公開純函式（與 `assignmentsOf`
/// 同慣例），不碰網路。
void main() {
  void resetConnectorStatics() {
    MoodleWebApiConnector.siteInfo = null;
    MoodleWebApiConnector.userId = null;
    MoodleWebApiConnector.onApiError = null;
    MoodleWebApiConnector.wsToken = null;
  }

  setUp(resetConnectorStatics);
  tearDown(resetConnectorStatics);

  group('forumsOf', () {
    test('回的是陣列本身，不是 {forums: []}；不建模的欄位被忽略而不是拋', () {
      final forums = MoodleWebApiConnector.forumsOf(
          loadMoodleForumListFixture('get_forums_by_courses'));

      expect(forums, isNotNull);
      expect(forums!.map((f) => f.id), [5499, 5500, 5501]);
      expect(forums.last.type, 'news');
      expect(forums.last.cmid, 91001);
      expect(forums.last.numdiscussions, 2);
    });

    test('Map（錯誤回應的形狀）與其他型別一律回 null', () {
      expect(
          MoodleWebApiConnector.forumsOf({
            'exception': 'webservice_access_exception',
            'errorcode': 'accessexception',
            'message': '存取被拒',
          }),
          isNull);
      expect(MoodleWebApiConnector.forumsOf(null), isNull);
      expect(MoodleWebApiConnector.forumsOf('[]'), isNull);
    });
  });

  group('pickAnnouncementForum', () {
    test('type == news 勝過名稱比對——即使名稱像公告的那一筆排在前面', () {
      final forums = fixtureForums();

      // 這就是這次改動要修的迴歸：課程公佈欄在 index 1，公告區在 index 2。
      expect(MoodleWebApiConnector.pickAnnouncementForum(forums)?.id, 5501);
    });

    test('沒有 news 也沒有像公告的名稱 → null（這門課沒有公告區）', () {
      final forums = fixtureForums('get_forums_by_courses_no_news');

      expect(MoodleWebApiConnector.pickAnnouncementForum(forums), isNull);
    });

    test('只有名稱像公告的一般討論區時退回名稱比對', () {
      final forums = fixtureForums()
        ..removeWhere((f) => f.type == MoodleWebApiConnector.newsForumType);

      expect(MoodleWebApiConnector.pickAnnouncementForum(forums)?.id, 5500);
    });

    test('空清單 → null', () {
      expect(MoodleWebApiConnector.pickAnnouncementForum(const []), isNull);
    });
  });

  group('looksLikeAnnouncementName', () {
    test('四種寫法都認得，一般討論區不算', () {
      for (final name in ['公告', '課程公佈欄', 'Announcements', 'News forum']) {
        expect(MoodleWebApiConnector.looksLikeAnnouncementName(name), isTrue,
            reason: name);
      }
      expect(MoodleWebApiConnector.looksLikeAnnouncementName('討論區'), isFalse);
      expect(MoodleWebApiConnector.looksLikeAnnouncementName(''), isFalse);
    });
  });

  group('legacyAnnouncementForumId', () {
    test('「一般」段落裡名稱像公告的模組 → 它的 instance id', () {
      expect(
          MoodleWebApiConnector.legacyAnnouncementForumId(
              fixtureCourseContents()),
          5500);
    });

    test('沒有「一般」段落 → null', () {
      final contents = fixtureCourseContents()
        ..removeWhere((s) => s.name.contains('一般'));

      expect(MoodleWebApiConnector.legacyAnnouncementForumId(contents), isNull);
    });

    test('有「一般」段落但沒有像公告的模組 → null', () {
      final contents = fixtureCourseContents();
      contents.first.modules.removeWhere(
          (m) => m.name.contains('課程公佈欄') || m.name.contains('公告'));

      expect(MoodleWebApiConnector.legacyAnnouncementForumId(contents), isNull);
    });
  });

  group('announcementsOf', () {
    test('name 與 subject 的 HTML 實體會被還原，forumFound 預設是 true', () {
      final parsed = fixtureDiscussions();

      expect(parsed.forumFound, isTrue);
      expect(parsed.discussions, hasLength(2));
      expect(parsed.discussions[0].name, '期中考 & 補考公告');
      // subject 是抓不到回覆時退路貼文的標題，同樣是純文字 sink。
      expect(parsed.discussions[0].subject, '期中考 & 補考公告');
      expect(parsed.discussions[0].subject, isNot(contains('&amp;')));
      expect(parsed.discussions[0].pinned, isTrue);
      expect(parsed.discussions[0].numreplies, 3);
      expect(parsed.discussions[1].pinned, isFalse);
      expect(parsed.discussions[1].numreplies, 0);
    });

    test('id 是第一篇貼文的 id，discussion 才是討論串 id', () {
      final d = fixtureDiscussions().discussions.first;

      expect(d.id, 8801);
      expect(d.discussion, 7701);
      expect(d.id, isNot(d.discussion));
    });

    test('形狀不對回 null', () {
      expect(MoodleWebApiConnector.announcementsOf(const []), isNull);
      expect(MoodleWebApiConnector.announcementsOf(null), isNull);
    });
  });

  group('getCourseAnnouncement 的錯誤', () {
    tearDown(MoodleWebApiConnector.resetAutologinState);

    test('公告區兩條路都失敗時，往上帶的是原本的 MoodleApiException', () async {
      final errors = <MoodleApiException>[];
      MoodleWebApiConnector.onApiError = errors.add;
      MoodleWebApiConnector.wsPost = (_) async => const {
            'exception': 'moodle_exception',
            'errorcode': 'invalidtoken',
            'message': 'Invalid token - token not found',
          };

      expect(await MoodleWebApiConnector.getCourseAnnouncement('7788'), isNull);

      // 換成一般 Exception 的話 _reportFailure 會走 Log.eWithStack，
      // token 過期就被當成當機送進 Crashlytics，而且 onApiError 也收不到。
      expect(
        errors.map((e) => e.wsFunction),
        [
          'core_course_get_contents',
          MoodleWebApiConnector.forumsByCoursesFunction
        ],
      );
      expect(errors.last.errorcode, 'invalidtoken');
    });
  });

  group('discussionPostsOf', () {
    test('四篇貼文維持伺服器順序，subject 的實體被還原', () {
      final posts = fixturePosts();

      expect(posts.map((p) => p.id), [900, 901, 902, 903]);
      expect(posts.first.subject, '期中考 & 補考公告');
      expect(posts.first.subject, isNot(contains('&amp;')));
    });

    test('@@PLUGINFILE@@ 換成 messageinlinefiles 的網址前綴', () {
      final posts = fixturePosts();

      expect(posts.first.message, isNot(contains('@@PLUGINFILE@@')));
      expect(
        posts.first.message,
        contains('https://moodle2.ntust.edu.tw/webservice/pluginfile.php/123'
            '/mod_forum/post/900/inline%20image.png'),
      );
    });

    test('附件的網址欄位是 url（stored_file_exporter），沒有 mimetype', () {
      final f = fixturePosts().first.attachments.single;

      expect(f.filename, 'slides.pdf');
      expect(
          f.url,
          'https://moodle2.ntust.edu.tw/webservice/pluginfile.php/123'
          '/mod_forum/attachment/900/slides.pdf');
      expect(f.filesize, 88888);
      expect(f.isimage, isFalse);
    });

    test('已刪除的貼文照樣回來，timecreated 是 null', () {
      final deleted = fixturePosts().last;

      expect(deleted.isdeleted, isTrue);
      expect(deleted.timecreated, isNull);
      expect(deleted.attachments, isEmpty);
    });

    test('空 posts 與形狀不對都回 null', () {
      expect(MoodleWebApiConnector.discussionPostsOf({'posts': []}), isNull);
      expect(MoodleWebApiConnector.discussionPostsOf(const []), isNull);
      expect(MoodleWebApiConnector.discussionPostsOf(null), isNull);
    });
  });
}
