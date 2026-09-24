import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/config/app_tokens.dart';
import 'package:flutter_app/src/controller/course_member/course_member_controller.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/input/input_field.dart';
import 'package:flutter_app/ui/components/page/notice_bar.dart';
import 'package:flutter_app/ui/components/shimmer/list_skeleton.dart';
import 'package:flutter_app/ui/components/toast/tat_toast.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';
import 'package:flutter_app/ui/other/theme_context.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

/// 修課學生名單。
///
/// Moodle 的名單 API 很慢，所以它獨占一個畫面：等待可以用滿版骨架表達，失敗
/// 有地方放重試，搜尋也放得下。人數由上一頁帶過來，標題列因此一開始就是完整
/// 的，不必等 API；名單到手後換成實際的學生數。老師與助教自成一區排在前面。
class CourseMemberPage extends StatefulWidget {
  const CourseMemberPage({
    required this.controller,
    required this.courseName,
    required this.knownMemberCount,
    required this.errorBuilder,
    super.key,
  });

  /// 由課程頁持有，返回再進來不重查。
  final CourseMemberController controller;

  final String courseName;

  /// 上一頁那支主要 API 就給了的人數，骨架的列數也用它決定。
  final int knownMemberCount;

  /// 失敗時要畫什麼。由呼叫端注入而不是直接用 `ErrorPage`，
  /// 見 docs/ARCHITECTURE.md「UI 慣例」。
  final Widget Function(String message, Future<void> Function() onRetry)
      errorBuilder;

  @override
  State<CourseMemberPage> createState() => _CourseMemberPageState();
}

class _CourseMemberPageState extends State<CourseMemberPage> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 請求發在這裡而不是 build()：每一次 rebuild 都重打一次 API 是個災難。
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _retry() => widget.controller.load(force: true);

  /// 骨架列數貼著真實筆數，載完版面才不會整個跳掉；人數不明時給三列。
  int get _skeletonRows =>
      widget.knownMemberCount > 0 ? math.min(widget.knownMemberCount, 5) : 3;

  /// 名單到手就用學生的實際筆數，之前先用上一頁給的。
  int get _studentCount {
    final result = widget.controller.members.value;
    if (result == null || !result.hasData) return widget.knownMemberCount;
    return widget.controller.students('').length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: baseAppbar(title: R.current.enrolledStudents),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          Expanded(
              child: Obx(() => _buildBody(widget.controller.members.value))),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Obx(() {
            final count = _studentCount;
            final subtitle = [
              widget.courseName.trim(),
              if (count > 0) sprintf(R.current.peopleCount, [count]),
            ].where((text) => text.isNotEmpty).join(' · ');
            if (subtitle.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                subtitle,
                style: context.text.bodyMedium
                    ?.copyWith(color: context.scheme.onSurfaceVariant),
              ),
            );
          }),
          InputField(
            hint: R.current.searchStudent,
            controller: _query,
            // 搜尋框不該叫出帳號密碼的自動填入。
            autofillHints: const [],
            onChange: (_) => setState(() {}),
            // 放大鏡在前面，和資訊系統的搜尋欄同一個形狀。
            prefix: const Icon(LucideIcons.search, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(Result<List<MoodleCoreEnrolGetUsers>>? result) {
    if (result == null) {
      // 骨架而不是轉圈圈：沒有遮罩，畫面也不會整片空白。
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListSkeleton(rows: _skeletonRows),
      );
    }
    if (result is Failed<List<MoodleCoreEnrolGetUsers>>) {
      return widget.errorBuilder(result.reason.message, _retry);
    }

    final staff = widget.controller.staff(_query.text);
    final students = widget.controller.students(_query.text);
    final rows = <Widget>[
      if (staff.isNotEmpty) ...[
        SectionHeader(title: R.current.teachersAndAssistants, first: true),
        for (final member in staff) _StaffRow(member: member),
        SectionHeader(title: R.current.enrolledStudents),
      ],
      for (final member in students) _MemberRow(member: member),
    ];
    return Column(
      children: [
        if (result is Stale<List<MoodleCoreEnrolGetUsers>>)
          NoticeBar(
            message: result.reason.message,
            icon: LucideIcons.history,
            actionLabel: R.current.refresh,
            onAction: _retry,
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: rows.length,
            itemBuilder: (context, index) => rows[index],
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});

  final MoodleCoreEnrolGetUsers member;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final studentId = member.studentId;
    return Container(
      constraints: const BoxConstraints(minHeight: TatTokens.heightRow),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _Avatar(member: member),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(member.name, style: context.text.bodyLarge),
                if (studentId.isNotEmpty)
                  Text(
                    studentId,
                    style: context.text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 老師與助教：角色與 email；有 email 時整列都是複製鈕。
class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.member});

  final MoodleCoreEnrolGetUsers member;

  Future<void> _copy(String email) async {
    await Clipboard.setData(ClipboardData(text: email));
    TatToast.show(R.current.copy);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final secondary =
        context.text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final role = member.roleLabel;
    final email = member.email.trim();
    final row = Container(
      constraints: const BoxConstraints(minHeight: TatTokens.heightRow),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _Avatar(member: member),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(member.name, style: context.text.bodyLarge),
                if (role.isNotEmpty) Text(role, style: secondary),
                if (email.isNotEmpty) Text(email, style: secondary),
              ],
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(width: 12),
            Icon(LucideIcons.copy, size: 18, color: scheme.primary),
          ],
        ],
      ),
    );
    if (email.isEmpty) return row;
    return InkWell(
      onTap: () => _copy(email),
      borderRadius: BorderRadius.circular(TatTokens.radiusButton),
      child: row,
    );
  }
}

class _Avatar extends StatefulWidget {
  const _Avatar({required this.member});

  final MoodleCoreEnrolGetUsers member;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  /// 圖抓不到就退回姓名首字。Moodle 給的網址在沒有 session 或使用者沒設頭貼
  /// 時會 404 或回一張預設圖。
  bool _imageFailed = false;

  void _onImageError() {
    // 錯誤是在繪製途中回報的，直接 setState 會撞到「build 期間呼叫 setState」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _imageFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final name = widget.member.name;
    final url = widget.member.profileImageUrlSmall.trim();
    final showPlaceholder = url.isEmpty || _imageFailed;
    return CircleAvatar(
      radius: 18,
      backgroundColor: scheme.surfaceContainerHighest,
      backgroundImage: showPlaceholder ? null : NetworkImage(url),
      // 少了 onBackgroundImageError，404 會把例外丟進 FlutterError.onError。
      onBackgroundImageError:
          showPlaceholder ? null : (_, __) => _onImageError(),
      child: showPlaceholder
          ? Text(
              name.isEmpty ? '?' : name.characters.first,
              style: context.text.titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            )
          : null,
    );
  }
}
