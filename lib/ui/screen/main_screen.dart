import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/ui/pages/subsystem/sub_system_page.dart';
import 'package:flutter_app/ui/pages/score/score_page.dart';
import 'package:flutter_app/ui/pages/other/other_page.dart';
import 'package:flutter_app/ui/pages/course_table/course_table_page.dart';
import 'package:flutter_app/ui/pages/calendar/calendar_page.dart';
import 'package:flutter_app/src/controller/main_page/main_controller.dart';
import 'package:flutter_app/src/util/analytics_utils.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<StatefulWidget> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with RouteAware {
  // 註冊在 AppBindings（lazyPut + fenix），這裡只取用。
  final controller = Get.find<MainController>();
  final items = [
    {"icon": LucideIcons.clock, "name": R.current.titleCourse},
    {"icon": LucideIcons.info, "name": R.current.informationSystem},
    {"icon": LucideIcons.calendar, "name": R.current.calendar},
    {"icon": LucideIcons.bookOpen, "name": R.current.titleScore},
    {"icon": LucideIcons.menu, "name": R.current.titleOther}
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AnalyticsUtils.observer
        .subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    AnalyticsUtils.observer.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildPageView(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  /// 五個分頁。**順序必須與 [MainTab] 一致**——底下的導覽列與 controller 的
  /// 分析事件都是靠索引對應的。清單放在這裡，controller 才不必 import 頁面。
  static const _pages = [
    CourseTablePage(),
    SubSystemPage(),
    CalendarPage(),
    ScoreViewerPage(),
    OtherPage(),
  ];

  Widget _buildPageView() {
    return PageView(
      controller: controller.pageController,
      onPageChanged: controller.onPageChanged,
      physics: const NeverScrollableScrollPhysics(),
      children: _pages,
    );
  }

  Widget _buildBottomNavigationBar() {
    return Obx(() {
      var currentIndex = controller.currentIndex.value;

      return NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: controller.onBottomNavigationTap,
        destinations: items.map((item) {
          final index = items.indexOf(item);
          return NavigationDestination(
            icon: Icon(
              item["icon"] as IconData,
              size: 24,
              color: currentIndex == index
                  ? Get.theme.colorScheme.onSecondaryContainer
                  : Get.theme.colorScheme.onSurfaceVariant,
            ),
            label: item["name"] as String,
          );
        }).toList(),
      );
    });
  }
}
