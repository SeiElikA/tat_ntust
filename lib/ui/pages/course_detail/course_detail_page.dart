import 'dart:async';

import 'package:flutter_app/src/controller/course_detail/course_detail_controller.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/ui/other/svg_tint.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/pages/course_detail/screen/course_info_page.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import 'screen/course_member_page.dart';

class CourseDetailPage extends StatefulWidget {
  final CourseInfoJson courseInfo;
  final SemesterJson semester;

  const CourseDetailPage(
    this.courseInfo,
    this.semester, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<CourseDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  List<Widget> _pages = [];
  /// getter 而不是 initState 裡指派的欄位，理由同 CourseDataPage：
  /// initState 只跑一次，分頁標籤會停在 State 建立時的語言。
  List<Map<String, dynamic>> get _tabItems => [
        {"name": R.current.course, "icon": "img_info.svg"},
        {"name": R.current.member, "icon": "img_group.svg"}
      ];

  late final CourseDetailController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CourseDetailController(
      courseId: widget.courseInfo.main.course.id,
      semester: widget.semester,
    );
    // 課程資訊與成員一起抓，不等使用者滑到成員那一頁。理由同 CourseDataPage。
    unawaited(_controller.loadAll());
    _pages = [
      CourseInfoPage(
        widget.courseInfo.main.course.id,
        widget.semester,
        controller: _controller,
      ),
      CourseMemberPage(
        widget.courseInfo.main.course.id,
        controller: _controller,
      ),
    ];
    _tabController = TabController(vsync: this, length: _tabItems.length);
  }

  @override
  Widget build(BuildContext context) {
    return tabPageView();
  }

  Widget tabPageView() {
    CourseMainJson course = widget.courseInfo.main.course;

    return DefaultTabController(
      length: _tabItems.length,
      child: Scaffold(
        appBar: baseAppbar(
          title: course.name,
          bottom: _buildTabBar(_tabItems),
        ),
        body: PageView(
          controller: _pageController,
          children: _pages,
          onPageChanged: (index) {
            _tabController.animateTo(index);
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }

  TabBar _buildTabBar(List<dynamic> items) {
    return TabBar(
      isScrollable: false,
      controller: _tabController,
      indicatorSize: TabBarIndicatorSize.tab,
      tabs: items.map((item) {
        final index = items.indexOf(item);
        return Tab(
          icon: SvgPicture.asset("assets/image/${item["icon"]}",
              colorFilter: svgTint(_currentIndex == index
                  ? Get.theme.colorScheme.primary
                  : Get.theme.colorScheme.onSurface),
              height: 24),
          iconMargin: const EdgeInsets.only(bottom: 6),
          child: AutoSizeText(
            item["name"] as String,
            maxLines: 1,
            minFontSize: 6,
          ),
        );
      }).toList(),
      onTap: (index) {
        _pageController.jumpToPage(index);
        _currentIndex = index;
      },
    );
  }
}
