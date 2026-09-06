import 'dart:async';

import 'package:flutter_app/src/controller/course_data/course_forum_thread_controller.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_discussion_posts.dart';
import 'package:flutter_app/src/repository/moodle_repository.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/reset_statics.dart';
import '../helpers/test_l10n.dart';

/// 送出回覆之後的重抓：整串（含剛送出的那一則）不可以在來回途中變成 null，
/// 那在畫面上就是 `ResultView` 的一頁轉圈，等於「自己的回覆消失」。
class _GatedRepo extends MoodleRepository {
  final gate = Completer<void>();
  int calls = 0;

  @override
  Future<Result<List<MoodleForumPost>>> getDiscussionPosts(
      int discussionId) async {
    calls++;
    await gate.future;
    return Ok<List<MoodleForumPost>>(
        [MoodleForumPost(id: 900), MoodleForumPost(id: 950)]);
  }
}

void main() {
  late _GatedRepo repo;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestL10n();
  });

  setUp(() {
    resetAppStatics();
    repo = _GatedRepo();
    MoodleRepository.instance = repo;
  });

  tearDown(() {
    MoodleRepository.instance = MoodleRepository();
  });

  CourseForumThreadController controller() {
    final c = CourseForumThreadController(discussionId: 7701);
    addTearDown(c.dispose);
    return c;
  }

  test('keepVisible：重抓途中畫面上的貼文留著', () async {
    final c = controller();
    await c.appendPost(MoodleForumPost(id: 900));

    final loading = c.loadPosts(keepVisible: true);
    await Future<void>.delayed(Duration.zero);

    expect(repo.calls, 1, reason: '真的在飛');
    expect(c.posts.value, isA<Ok<List<MoodleForumPost>>>());
    expect(c.posts.value?.dataOrNull, hasLength(1));

    repo.gate.complete();
    await loading;
    expect(c.posts.value?.dataOrNull, hasLength(2));
  });

  test('預設會先清成 null：進頁面與使用者按的重試都要看得到轉圈', () async {
    final c = controller();
    await c.appendPost(MoodleForumPost(id: 900));

    final loading = c.loadPosts();
    await Future<void>.delayed(Duration.zero);

    expect(c.posts.value, isNull);

    repo.gate.complete();
    await loading;
    expect(c.posts.value?.dataOrNull, hasLength(2));
  });
}
