import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/controller/course_data/course_assignment_controller.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/language_utils.dart';
import 'package:flutter_app/src/util/moodle_assign_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/html/moodle_html_view.dart';
import 'package:flutter_app/ui/components/page/inline_error_view.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/assign_status_chip.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// 一份作業的唯讀詳情；繳交與編輯都走「在網頁開啟」。錯誤畫面與 WebView 開啟器
/// 由呼叫端注入，見 docs/ARCHITECTURE.md「UI 慣例」。三段 Moodle 原文 HTML
/// 都走 [MoodleHtmlView]。
class CourseAssignmentDetailPage extends StatefulWidget {
  const CourseAssignmentDetailPage(
    this.courseInfo, {
    required this.assignId,
    this.assignment,
    this.initialStatus,
    required this.errorBuilder,
    required this.openWebView,
    super.key,
  });

  final CourseInfoJson courseInfo;

  /// assign instance id（`MoodleAssignment.id` / `Modules.instance`）。
  final int assignId;

  /// 從作業分頁進來時已在手上；從「檔案」分頁進來時是 null，要抓。
  final MoodleAssignment? assignment;

  /// 只有 `hasData` 的會被沿用，Failed 會重抓。
  final Result<MoodleAssignSubmissionStatus>? initialStatus;

  final Widget Function(String message) errorBuilder;
  final WebViewOpener openWebView;

  static String formatUnix(int unix) => DateFormat.yMd()
      .add_jm()
      .format(DateTime.fromMillisecondsSinceEpoch(unix * 1000));

  @override
  State<CourseAssignmentDetailPage> createState() =>
      _CourseAssignmentDetailPageState();
}

class _CourseAssignmentDetailPageState
    extends State<CourseAssignmentDetailPage> {
  late final CourseAssignmentController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CourseAssignmentController(
      courseId: widget.courseInfo.main.course.id,
      assignId: widget.assignId,
      assignment: widget.assignment,
      status: widget.initialStatus,
    );
    unawaited(_controller.loadAll());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _courseName => widget.courseInfo.main.course.name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Obx(() => baseAppbar(
            title: _controller.assignment.value?.dataOrNull?.name ??
                R.current.assignmentDetail)),
      ),
      body: ResultView<MoodleAssignment>(
        state: _controller.assignment,
        onRetry: _controller.loadAssignment,
        errorBuilder: widget.errorBuilder,
        builder: _buildBody,
      ),
    );
  }

  Widget _buildBody(MoodleAssignment a) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        SectionHeader(
          icon: LucideIcons.calendarClock,
          title: R.current.assignDueDate,
          first: true,
        ),
        _deadlineCard(a),
        SectionHeader(
          icon: LucideIcons.clipboardCheck,
          title: R.current.assignSubmissionStatus,
          trailing: Obx(() => AssignStatusChip.fromResult(
              a, _controller.status.value,
              now: DateTime.now())),
        ),
        _statusCard(a),
        SectionHeader(
          icon: LucideIcons.fileText,
          title: R.current.assignIntro,
        ),
        _introCard(a),
        const SizedBox(height: 28),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => unawaited(_openInWeb(a)),
          icon: const Icon(LucideIcons.externalLink),
          label: Text(R.current.assignOpenInWeb),
        ),
      ],
    );
  }

  Widget _deadlineCard(MoodleAssignment a) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Obx(() {
      final now = DateTime.now();
      final s = _controller.status.value?.dataOrNull;
      // 染紅的條件與那顆籤同源，否則會出現「已評分」卻紅字說已逾期。
      final alarm = s != null &&
          MoodleAssignUtils.resolveStatus(a, s, now: now) ==
              AssignDisplayStatus.overdue;
      final ext = s?.extensionDueDate ?? 0;
      final specs = <Widget>[
        if (a.allowsubmissionsfromdate > 0)
          SectionField(
              R.current.assignAllowSubmissionsFrom,
              CourseAssignmentDetailPage.formatUnix(
                  a.allowsubmissionsfromdate)),
        if (ext > 0)
          SectionField(R.current.assignExtensionDueDate,
              CourseAssignmentDetailPage.formatUnix(ext)),
        if (a.cutoffdate > 0)
          SectionField(R.current.assignCutoffDate,
              CourseAssignmentDetailPage.formatUnix(a.cutoffdate)),
      ];
      return SectionCard([
        // 提示跟著生效的截止時間走，有延長期限時說「已逾期」是錯的。
        Text(
          dueHintText(MoodleAssignUtils.dueHint(
              MoodleAssignUtils.effectiveDueDate(a, s), now)),
          style: text.titleMedium?.copyWith(
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: alarm
                ? scheme.error
                : (a.hasDueDate ? scheme.onSurface : scheme.onSurfaceVariant),
          ),
        ),
        if (a.hasDueDate) ...[
          const SizedBox(height: 4),
          Text(CourseAssignmentDetailPage.formatUnix(a.duedate),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        if (specs.isNotEmpty) ...[const SectionDivider(), ...specs],
      ]);
    });
  }

  /// 嵌在沒有高度上限的 ListView 裡所以開 `shrinkWrap`；失敗畫
  /// [InlineErrorView] 而不是整頁 errorBuilder，頁面其餘部分都還在。
  Widget _statusCard(MoodleAssignment a) {
    return ResultView<MoodleAssignSubmissionStatus>(
      shrinkWrap: true,
      state: _controller.status,
      onRetry: _controller.loadStatus,
      errorBuilder: (message) =>
          InlineErrorView(message: message, onRetry: _controller.loadStatus),
      builder: (s) => _statusGroups(a, s),
    );
  }

  Widget _statusGroups(MoodleAssignment a, MoodleAssignSubmissionStatus s) {
    final sub = s.submissionFor(a);
    final fb = s.feedback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionCard([
          SectionField(
            R.current.assignGradingStatus,
            s.isGraded
                ? R.current.assignStatusGraded
                : R.current.assignNotGraded,
          ),
          // sub 的型別提升要靠這個 inline 條件，不能先算成 bool。
          if (sub != null && (sub.isSubmitted || sub.isDraft)) ...[
            // timemodified 只有 submitted 時才是繳交時間；草稿只是最後存檔。
            SectionField(
              sub.isSubmitted
                  ? R.current.assignSubmittedAt
                  : R.current.assignLastModified,
              CourseAssignmentDetailPage.formatUnix(sub.timemodified),
            ),
            if (sub.files.isNotEmpty) ...[
              const SectionDivider(),
              SectionSubLabel(R.current.assignSubmittedFiles),
              ..._fileTiles(sub.files),
            ],
            if (sub.onlineText.trim().isNotEmpty) ...[
              const SectionDivider(),
              SectionSubLabel(R.current.assignOnlineText),
              _html(sub.onlineText, a.name),
            ],
          ],
        ]),
        if (fb != null && _hasFeedbackContent(fb)) ...[
          SectionHeader(
            icon: LucideIcons.fileCheck2,
            title: R.current.assignSectionGradeFeedback,
          ),
          _feedbackCard(a, fb),
        ],
      ],
    );
  }

  /// 四段全部落空時整個群組不畫，否則會多一張空卡。
  static bool _hasFeedbackContent(MoodleAssignFeedback fb) =>
      fb.gradefordisplay.trim().isNotEmpty ||
      (fb.gradeddate ?? 0) > 0 ||
      fb.commentsHtml.trim().isNotEmpty ||
      fb.files.isNotEmpty;

  Widget _feedbackCard(MoodleAssignment a, MoodleAssignFeedback fb) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final grade = fb.gradefordisplay.trim();
    return SectionCard([
      // gradefordisplay 是 connector 還原過的純文字，只能走 Text，
      // 不要送進 HtmlWidget（見 html_utils_sink_inventory_test）。
      if (grade.isNotEmpty) ...[
        Text(R.current.assignGrade,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(fb.gradefordisplay,
            style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w600, color: scheme.onSurface)),
        const SizedBox(height: 6),
      ],
      if ((fb.gradeddate ?? 0) > 0)
        SectionField(R.current.assignGradedAt,
            CourseAssignmentDetailPage.formatUnix(fb.gradeddate!)),
      if (fb.commentsHtml.trim().isNotEmpty) ...[
        const SectionDivider(),
        SectionSubLabel(R.current.assignFeedback),
        _html(fb.commentsHtml, a.name),
      ],
      if (fb.files.isNotEmpty) ...[
        const SectionDivider(),
        SectionSubLabel(R.current.assignFeedbackFiles),
        ..._fileTiles(fb.files),
      ],
    ]);
  }

  /// null 與空字串畫不同的東西，見 [MoodleAssignment.intro]。
  Widget _introCard(MoodleAssignment a) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final intro = a.intro;
    final Widget body;
    if (intro == null) {
      body = Text(R.current.assignIntroHidden,
          style: text.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant));
    } else if (intro.trim().isEmpty) {
      body = Text(R.current.nothingHere,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant));
    } else {
      body = _html(intro, a.name);
    }
    return SectionCard([
      body,
      if (a.introattachments.isNotEmpty) ...[
        const SectionDivider(),
        SectionSubLabel(R.current.assignAttachments),
        ..._fileTiles(a.introattachments),
      ],
    ]);
  }

  List<Widget> _fileTiles(List<MoodleAssignFile> files) {
    return [
      for (final f in files)
        MoodleFileTile(
          filename: f.filename,
          mimetype: f.mimetype,
          onTap: () => unawaited(FileDownload.download(
            context,
            MoodleWebApiConnector.fileUrlWithToken(f.fileurl),
            _courseName,
            name: f.filename,
          )),
        ),
    ];
  }

  Widget _html(String html, String title) => MoodleHtmlView(
        html: html,
        title: title,
        dirName: _courseName,
        openWebView: widget.openWebView,
      );

  /// 網頁版作業頁。這裡不呼叫 `autologinUrl`：注入的 [openWebView] 自己會換，
  /// 再換一次等於在六分鐘的伺服器節流內多燒一把鑰匙。
  Future<void> _openInWeb(MoodleAssignment a) async {
    final url = Connector.uriAddQuery(
      MoodleWebApiConnector.assignViewUrl(a.cmid),
      {"lang": LanguageUtils.getLangIndex() == LangEnum.zh ? "zh_tw" : "en"},
    );
    await widget.openWebView(a.name, url);
  }
}
