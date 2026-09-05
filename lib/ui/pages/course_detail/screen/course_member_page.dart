import 'package:flutter_app/src/controller/course_detail/course_detail_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/generated/l10n.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

class CourseMemberPage extends StatefulWidget {
  final String courseId;

  /// 三個（或兩個）分頁共用的狀態。頁面在進入時就把所有請求發完，
  /// 所以每個分頁只負責畫自己那一份。
  final CourseDetailController controller;

  const CourseMemberPage(
    this.courseId, {
    required this.controller,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseMemberPageState();
}

class _CourseMemberPageState extends State<CourseMemberPage>
    with AutomaticKeepAliveClientMixin {
  /// null 代表還在載入。請求不能寫進 build()，否則每一次 rebuild 都會重跑
  /// 整段流程。
  Rxn<Result<List<MoodleCoreEnrolGetUsers>>> get _state => widget.controller.members;

  // 沒有 initState 觸發請求：由頁面在進入時一次發完三個（或兩個），
  // 見 CourseDataController.loadAll / CourseDetailController.loadAll。

  Future<void> _load() => widget.controller.loadMembers();

  /// 把修課名單攤平成畫面上的列。
  ///
  /// 這些列必須每次 build 重新產生：_buildClassmateInfo 與 _buildClassmateNumber
  /// 把 UIUtils.getListColor 的顏色與 S.current 的字串寫死在 widget 上，只做一次
  /// 就再也不會跟著主題或語言變。
  ///
  /// 迴圈從 index 1 開始是**既有行為，刻意保留**：members[0] 不會被列出來，總人數
  /// 那一列仍用 members.length 全部算進去。看起來像 off-by-one，不要順手改。
  List<Widget> _buildListItem(List<MoodleCoreEnrolGetUsers> members) {
    final List<Widget> listItem = [];
    listItem.add(_buildClassmateNumber(0, members.length));
    for (int i = 1; i < members.length; i++) {
      listItem.add(_buildClassmateInfo(i, members[i]));
    }
    return listItem;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      padding: const EdgeInsets.only(top: 10),
      child: ResultView<List<MoodleCoreEnrolGetUsers>>(
        state: _state,
        onRetry: _load,
        errorBuilder: (message) => ErrorPage(errorMsg: message),
        builder: (members) => getAnimationList(_buildListItem(members)),
      ),
    );
  }

  Widget getAnimationList(List<Widget> listItem) {
    return AnimationLimiter(
      child: ListView.builder(
        itemCount: listItem.length,
        itemBuilder: (BuildContext context, int index) {
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 375),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: listItem[index],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildClassmateNumber(int index, int number) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: UIUtils.getListColor(index),
      child: Text(
        "${S.current.totalMember} $number",
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildClassmateInfo(int index, MoodleCoreEnrolGetUsers member) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: UIUtils.getListColor(index),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Expanded(
              child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(member.profileImageUrl),
                radius: 16,
              ),
              const SizedBox(width: 12),
              Text(
                member.studentId,
                textAlign: TextAlign.center,
              ),
            ],
          )),
          Expanded(
            child: Text(
              member.name,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
