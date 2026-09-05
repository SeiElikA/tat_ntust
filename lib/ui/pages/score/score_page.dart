import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/ui/components/page/loading_page.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:flutter_app/ui/components/tile/score_item_tile.dart';
import 'package:flutter_app/src/util/score_utils.dart';
import 'package:flutter_app/src/model/score/score_json.dart';
import 'package:flutter_app/src/controller/score_page/score_page_controller.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/error_page.dart';
import 'package:get/get.dart';

class ScoreViewerPage extends GetView<ScorePageController> {
  const ScoreViewerPage({super.key});

  @override
  Widget build(BuildContext context) {

    return Obx(
      () {
        switch (controller.state.value) {
          case ScoreUIState.success:
            return _buildContentPage();
          case ScoreUIState.loading:
            return _buildLoadingPage();
          case ScoreUIState.fail:
            return _buildErrorPage();
          case ScoreUIState.notLogin:
            return _buildNotLoginPage();
        }
      },
    );
  }

  Widget _buildContentPage() {
    return Obx(() {
      return DefaultTabController(
        length: controller.semesterScoreList.length,
        child: Scaffold(
          appBar: mainAppbar(
              title: R.current.searchScore,
              action: [
                IconButton(
                  icon: const Icon(CupertinoIcons.refresh),
                  splashRadius: 18,
                  iconSize: 24,
                  onPressed: () async {
                    await controller.initTask(refresh: true);
                  },
                  tooltip: R.current.update,
                ),
              ],
              bottom: TabBar(
                controller: controller.tabController,
                // controller 為 null 時 TabBar 會回退到 DefaultTabController，
                // 不會拋 LateInitializationError。
                isScrollable: true,
                // Widget 由頁面依 semesterScoreList 現算：controller 建 Widget
                // 會讓 lib/src/controller 反向 import lib/ui，形成 controller -> ui
                // 的上行邊。
                tabs: [
                  for (final s in controller.semesterScoreList)
                    _buildTabLabel("${s.semester.year}-${s.semester.semester}")
                ],
                onTap: controller.toIndex,
              )),
          body: TabBarView(
            controller: controller.tabController,
            children: [
              for (final s in controller.semesterScoreList)
                _buildSemesterScores(s.item)
            ],
          ),
        ),
      );
    });
  }

  Widget _buildErrorPage() {
    return Scaffold(
      appBar: mainAppbar(title: R.current.searchScore, action: [
        IconButton(
          icon: const Icon(CupertinoIcons.refresh),
          splashRadius: 18,
          iconSize: 24,
          onPressed: () async {
            await controller.initTask(refresh: true);
          },
          tooltip: R.current.update,
        ),
      ]),
      body: const ErrorPage(),
    );
  }

  Widget _buildLoadingPage() {
    return Scaffold(
      appBar: mainAppbar(title: R.current.searchScore),
      // 這裡要真的畫出載入畫面：沒有任何全螢幕進度框會蓋在上面，空白就是
      // 使用者看到的全部。
      body: const LoadingPage(isLoading: true, isShowBackground: false),
    );
  }

  Widget _buildNotLoginPage() {
    return Scaffold(
      appBar: mainAppbar(title: R.current.searchScore),
      body: const ErrorPage(),
    );
  }

  Widget _buildTabLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 12,
        right: 12,
      ),
      child: Tab(
        text: title,
      ),
    );
  }

  Widget _buildSemesterScores(List<ScoreItemJson> courseScore) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
      child: AnimationLimiter(
        child: Column(
          children: AnimationConfiguration.toStaggeredList(
            childAnimationBuilder: (widget) => SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: widget,
              ),
            ),
            children: _buildCourseScores(courseScore),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCourseScores(List<ScoreItemJson> courseScore) {
    return [
      _buildTitle(courseScore),
      const SizedBox(height: 12),
      for (var score in courseScore) ...{
        ScoreItemTile(score: score),
        const SizedBox(height: 8)
      }
    ];
  }

  Widget _buildTitle(List<ScoreItemJson> courseList) {
    final totalCredit = courseList
        .where((x) => x.isPassScore)
        .map((c) => int.tryParse(c.credit) ?? 0)
        .fold(0, (a, b) => a + b);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "GPA ${ScoreUtils.calculateGPA(courseList)}",
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Get.theme.colorScheme.onSurface),
        ),
        Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Get.theme.colorScheme.secondaryContainer),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            "$totalCredit ${R.current.credit}",
            style: TextStyle(
                fontSize: 16,
                color: Get.theme.colorScheme.onSecondaryContainer),
          ),
        ),
      ],
    );
  }
}
