import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/controller/course_data/course_data_controller.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_assignments.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_assign_get_submission_status.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/util/moodle_assign_utils.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/ui/components/page/empty_state.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/pages/course_data/screen/sub_page/course_assignment_detail_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/widgets/assign_status_chip.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// 課程頁的「作業」分頁：清單加上每一份作業的狀態籤。錯誤畫面與 WebView
/// 開啟器由呼叫端注入，見 docs/ARCHITECTURE.md「UI 慣例」。
class CourseAssignmentPage extends StatefulWidget {
  const CourseAssignmentPage(
    this.courseInfo, {
    required this.controller,
    required this.errorBuilder,
    required this.openWebView,
    super.key,
  });

  final CourseInfoJson courseInfo;

  /// 四個分頁共用的狀態；請求在進入頁面時已一次發完。
  final CourseDataController controller;

  final Widget Function(String message) errorBuilder;
  final WebViewOpener openWebView;

  @override
  State<CourseAssignmentPage> createState() => _CourseAssignmentPageState();
}

class _CourseAssignmentPageState extends State<CourseAssignmentPage>
    with AutomaticKeepAliveClientMixin {
  Rxn<Result<List<MoodleAssignment>>> get _state =>
      widget.controller.assignments;

  // 沒有 initState 觸發請求，見 CourseDataController.loadAll。

  Future<void> _load() => widget.controller.loadAssignments();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      padding: const EdgeInsets.only(top: 10),
      child: ResultView<List<MoodleAssignment>>(
        state: _state,
        onRetry: _load,
        errorBuilder: widget.errorBuilder,
        builder: buildTree,
      ),
    );
  }

  Widget buildTree(List<MoodleAssignment> list) {
    if (list.isEmpty) {
      return EmptyState(
        icon: LucideIcons.clipboardList,
        message: R.current.assignmentEmpty,
      );
    }

    // now 只取一次：排序、每一列的提示與狀態籤用同一個時間點。
    final now = DateTime.now();
    // 在 ResultView 的 Obx 之內，所以背景抓到狀態時清單會跟著重排。
    final items = MoodleAssignUtils.sortForList(
      list,
      now,
      dueOf: (a) => MoodleAssignUtils.effectiveDueDate(a, _statusDataOf(a)),
    );
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => _buildRow(items[index], index, now),
    );
  }

  MoodleAssignSubmissionStatus? _statusDataOf(MoodleAssignment a) =>
      widget.controller.statusOf(a.id).value?.dataOrNull;

  /// 「日期 · 相對提示」，有延長期限時兩者都以延長期限為準並標明，
  /// 否則旁邊的籤說「未繳交」、這裡卻說「已逾期」。
  String _dueLine(
      MoodleAssignment a, MoodleAssignSubmissionStatus? s, DateTime now) {
    final due = MoodleAssignUtils.effectiveDueDate(a, s);
    if (due <= 0) return R.current.assignNoDueDate;
    final formatted = DateFormat.yMd()
        .add_jm()
        .format(DateTime.fromMillisecondsSinceEpoch(due * 1000));
    final line =
        "$formatted · ${dueHintText(MoodleAssignUtils.dueHint(due, now))}";
    final extended = (s?.extensionDueDate ?? 0) > 0;
    return extended ? "${R.current.assignExtensionDueDate} $line" : line;
  }

  Widget _buildRow(MoodleAssignment a, int index, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => unawaited(Get.to(() => CourseAssignmentDetailPage(
            widget.courseInfo,
            assignId: a.id,
            assignment: a,
            initialStatus: widget.controller.statusOf(a.id).value,
            errorBuilder: widget.errorBuilder,
            openWebView: widget.openWebView,
            // 詳情頁交完之後，這一列的狀態籤要跟著換。
            onStatusChanged: (s) =>
                widget.controller.statusOf(a.id).value = Ok(s),
          ))),
      child: Container(
        color: UIUtils.getListColor(index),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Icon(
                LucideIcons.clipboardList,
                size: 24,
                color: scheme.onSurface,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    maxLines: 2,
                    style: TextStyle(
                      height: 1.2,
                      color: scheme.onSurface,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // itemBuilder 在 layout 階段跑，不在外層 Obx 的追蹤範圍內。
                  Obx(() => Text(
                        _dueLine(a, _statusDataOf(a), now),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Obx(() => AssignStatusChip.fromResult(
                  a,
                  widget.controller.statusOf(a.id).value,
                  now: now,
                )),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
