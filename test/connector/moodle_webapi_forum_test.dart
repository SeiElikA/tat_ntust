import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_profile_entity.dart';
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
  tearDown(() {
    resetConnectorStatics();
    MoodleWebApiConnector.resetAutologinState();
  });

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

  group('discussionPostsOf 的 capabilities 與 messageformat', () {
    test('capabilities.reply 逐篇讀進來：900/901/902 可回，已刪除的 903 不行', () {
      final posts = fixturePosts();

      expect(
          posts.map((p) => p.capabilities?.reply), [true, true, true, false]);
    });

    test('replysubject 的實體被還原（它會原樣送回伺服器當 subject）', () {
      final posts = fixturePosts();

      expect(posts.first.replysubject, 'Re: 期中考 & 補考公告');
      expect(posts.first.replysubject, isNot(contains('&amp;')));
    });

    test('沒有 capabilities 區塊的貼文 → null，不是「全部 false」', () {
      final raw = loadMoodleForumFixture('get_discussion_posts');
      (raw['posts'] as List)
          .map((e) => e as Map<String, dynamic>)
          .forEach((e) => e.remove('capabilities'));

      final posts = MoodleWebApiConnector.discussionPostsOf(raw)!;

      expect(posts.map((p) => p.capabilities), everyElement(isNull));
    });

    test('FORMAT_PLAIN 的貼文只被轉一次——轉完蓋成 HTML，快取讀回來不會再轉', () {
      final raw = loadMoodleForumFixture('get_discussion_posts');
      final first = (raw['posts'] as List).first as Map<String, dynamic>;
      first['message'] = 'a < b\n第二行';
      first['messageformat'] = 2;

      final once = MoodleWebApiConnector.discussionPostsOf(raw)!.first;

      expect(once.message, 'a &lt; b<br>第二行');
      expect(once.messageformat, 1, reason: '轉過了，存進快取的就是 HTML');

      // 快取的往返：把轉好的那一份再餵回去（reader 走的就是這條路），
      // 內容必須一個字都不變。
      final twice = MoodleWebApiConnector.discussionPostsOf({
        'posts': [once.toJson()]
      })!
          .first;
      expect(twice.message, once.message);
    });
  });

  group('addedPostOf', () {
    test('subject 與 replysubject 還原實體，@@PLUGINFILE@@ 換掉', () {
      final post = MoodleWebApiConnector.addedPostOf(
          loadMoodleForumFixture('add_discussion_post'))!;

      expect(post.id, 950);
      expect(post.subject, 'Re: 期中考 & 補考公告');
      expect(post.replysubject, 'Re: 期中考 & 補考公告');
      expect(post.message, isNot(contains('@@PLUGINFILE@@')));
      expect(
        post.message,
        contains('https://moodle2.ntust.edu.tw/webservice/pluginfile.php/123'
            '/mod_forum/post/950/inline%20image.png'),
      );
      expect(post.parentid, 900);
      expect(post.capabilities?.reply, isTrue);
    });

    test('站台的預設編輯器是 textarea 時貼文留在 FORMAT_PLAIN，由客戶端轉', () {
      final post = MoodleWebApiConnector.addedPostOf(
          loadMoodleForumFixture('add_discussion_post_plain'))!;

      expect(post.message, '老師好，<br>請問 a &lt; b 的那一題<br>也在範圍內嗎？');
      expect(post.messageformat, 1);
    });

    test('沒有 post 這個 key、或形狀不對 → null', () {
      expect(MoodleWebApiConnector.addedPostOf(const {'postid': 950}), isNull);
      expect(MoodleWebApiConnector.addedPostOf(const {'post': 'x'}), isNull);
      expect(MoodleWebApiConnector.addedPostOf(const []), isNull);
      expect(MoodleWebApiConnector.addedPostOf(null), isNull);
    });
  });

  group('addDiscussionPost', () {
    test('送出去的參數：messageformat=2 加 topreferredformat，沒有其他 option', () async {
      Map<String, dynamic>? sent;
      MoodleWebApiConnector.wsToken = 'tok';
      MoodleWebApiConnector.wsPost = (parameter) async {
        sent = Map<String, dynamic>.from(parameter.data as Map);
        return loadMoodleForumFixture('add_discussion_post');
      };

      final post = await MoodleWebApiConnector.addDiscussionPost(
          postId: 900, subject: 'Re: 期中考', message: 'a < b\nc');

      expect(post.id, 950);
      expect(
          sent!['wsfunction'], MoodleWebApiConnector.addDiscussionPostFunction);
      expect(sent!['postid'], '900');
      expect(sent!['subject'], 'Re: 期中考');
      // 純文字原樣送出：escape 是伺服器在 topreferredformat 那一步做的。
      expect(sent!['message'], 'a < b\nc');
      expect(sent!['messageformat'], '2');
      expect(sent!['options[0][name]'], 'topreferredformat');
      expect(sent!['options[0][value]'], '1');
      // 訂閱行為要跟網頁版一樣，附件與私訊回覆不在範圍內。
      expect(sent!.keys.join(','), isNot(contains('discussionsubscribe')));
      expect(sent!.keys.join(','), isNot(contains('private')));
      expect(sent!.keys.join(','), isNot(contains('attachmentsid')));
    });

    test('errorcode 一路往上拋，不會被吞成 null', () async {
      MoodleWebApiConnector.wsToken = 'tok';
      MoodleWebApiConnector.wsPost = (_) async =>
          loadMoodleForumFixture('add_discussion_post_nopostforum');

      expect(
        () => MoodleWebApiConnector.addDiscussionPost(
            postId: 900, subject: 's', message: 'm'),
        throwsA(isA<MoodleApiException>()
            .having((e) => e.errorcode, 'errorcode', 'nopostforum')),
      );
    });

    test('warnings[] 非空也算失敗（寫入路徑的慣例）', () async {
      MoodleWebApiConnector.wsToken = 'tok';
      MoodleWebApiConnector.wsPost =
          (_) async => loadMoodleForumFixture('add_discussion_post_warning');

      expect(
        () => MoodleWebApiConnector.addDiscussionPost(
            postId: 900, subject: 's', message: 'm'),
        throwsA(isA<MoodleApiException>()
            .having((e) => e.errorcode, 'errorcode', 'nopostforum')),
      );
    });

    test('回應裡沒有 post 一律當成失敗，不可以報成送出成功', () async {
      MoodleWebApiConnector.wsToken = 'tok';
      MoodleWebApiConnector.wsPost =
          (_) async => const {'postid': 950, 'warnings': []};

      expect(
        () => MoodleWebApiConnector.addDiscussionPost(
            postId: 900, subject: 's', message: 'm'),
        throwsA(isA<MoodleApiException>()
            .having((e) => e.errorcode, 'errorcode', 'couldnotadd')),
      );
    });

    test('invalidtoken 會送出 onApiError，但例外照樣往上拋', () async {
      final errors = <MoodleApiException>[];
      MoodleWebApiConnector.onApiError = errors.add;
      MoodleWebApiConnector.wsToken = 'tok';
      MoodleWebApiConnector.wsPost = (_) async => const {
            'exception': 'moodle_exception',
            'errorcode': 'invalidtoken',
            'message': 'Invalid token - token not found',
          };

      await expectLater(
        () => MoodleWebApiConnector.addDiscussionPost(
            postId: 900, subject: 's', message: 'm'),
        throwsA(isA<MoodleApiException>()),
      );
      expect(errors.single.errorcode, 'invalidtoken');
      expect(errors.single.isInvalidToken, isTrue);
    });
  });

  group('addDiscussion', () {
    test('送出去的是 forumid/subject/message/groupid，沒有任何 option', () async {
      Map<String, dynamic>? sent;
      MoodleWebApiConnector.wsToken = 'tok';
      MoodleWebApiConnector.wsPost = (parameter) async {
        sent = Map<String, dynamic>.from(parameter.data as Map);
        return loadMoodleForumFixture('add_discussion');
      };

      final id = await MoodleWebApiConnector.addDiscussion(
          forumId: 5499, subject: '請問作業', htmlMessage: 'a &lt; b<br>c');

      expect(id, 4321);
      expect(sent!['wsfunction'], MoodleWebApiConnector.addDiscussionFunction);
      expect(sent!['forumid'], '5499');
      expect(sent!['subject'], '請問作業');
      expect(sent!['message'], 'a &lt; b<br>c');
      expect(sent!['groupid'], '0');
      expect(sent!.keys.join(','), isNot(contains('options')));
      expect(sent!.keys.join(','), isNot(contains('messageformat')));
    });

    test('沒有 discussionid 就是失敗——證明不了寫入發生過', () async {
      MoodleWebApiConnector.wsToken = 'tok';
      MoodleWebApiConnector.wsPost =
          (_) async => loadMoodleForumFixture('add_discussion_no_id');

      expect(
        () => MoodleWebApiConnector.addDiscussion(
            forumId: 5499, subject: 's', htmlMessage: 'm'),
        throwsA(isA<MoodleApiException>()
            .having((e) => e.errorcode, 'errorcode', 'couldnotadd')),
      );
    });
  });

  group('canAddDiscussionOf', () {
    test('status 為 true，VALUE_OPTIONAL 的旗標讀得到', () {
      final r = MoodleWebApiConnector.canAddDiscussionOf(
          loadMoodleForumFixture('can_add_discussion'));

      expect(r!.status, isTrue);
      expect(r.cancreateattachment, isTrue);
    });

    test('status 為 false 而且 VALUE_OPTIONAL 全部缺席', () {
      final r = MoodleWebApiConnector.canAddDiscussionOf(
          loadMoodleForumFixture('can_add_discussion_denied'));

      expect(r!.status, isFalse);
      expect(r.cancreateattachment, isNull);
    });

    test('沒有 status 或不是 Map → null', () {
      expect(MoodleWebApiConnector.canAddDiscussionOf(const {'warnings': []}),
          isNull);
      expect(MoodleWebApiConnector.canAddDiscussionOf(const []), isNull);
      expect(MoodleWebApiConnector.canAddDiscussionOf(null), isNull);
    });
  });

  group('站台沒開放這兩支 function 時', () {
    test('canPostToForum / canCreateDiscussion 為 false，而且一個請求都不送', () async {
      var calls = 0;
      MoodleWebApiConnector.wsToken = 'tok';
      MoodleWebApiConnector.wsPost = (_) async {
        calls++;
        return const {};
      };
      // functions[] 有東西（knowsWsFunctions 為真）但沒有這兩支。
      MoodleWebApiConnector.siteInfo = MoodleProfileEntity(functions: [
        MoodleProfileFunctions(
            name: MoodleWebApiConnector.discussionPostsFunction,
            version: '4.5'),
      ]);

      expect(MoodleWebApiConnector.canPostToForum, isFalse);
      expect(MoodleWebApiConnector.canCreateDiscussion, isFalse);
      await expectLater(
        () => MoodleWebApiConnector.addDiscussionPost(
            postId: 900, subject: 's', message: 'm'),
        throwsA(isA<MoodleApiException>()
            .having((e) => e.skippedBeforeRequest, 'skipped', isTrue)),
      );
      expect(calls, 0);
    });

    test('site_info 還沒載入時 fail-open', () {
      expect(MoodleWebApiConnector.canPostToForum, isTrue);
      expect(MoodleWebApiConnector.canCreateDiscussion, isTrue);
    });
  });
}
