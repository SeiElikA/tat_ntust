import 'dart:async';

import 'package:flutter_app/src/controller/course_data/course_data_controller.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/ui/other/svg_tint.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/pages/course_data/screen/course_announcement_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/course_directory_page.dart';
import 'package:flutter_app/ui/pages/course_data/screen/course_score_page.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

class CourseDataPage extends StatefulWidget {
  final CourseInfoJson courseInfo;

  const CourseDataPage(
    this.courseInfo, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _CourseDataPageState();
}

class _CourseDataPageState extends State<CourseDataPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  List<Widget> _pages = [];
  /// getter 而不是 initState 裡指派的欄位：initState 只跑一次，切換語言後
  /// 分頁標籤會停在舊語言。長度固定，TabController 照樣讀得到。
  List<Map<String, dynamic>> get _tabItems => [
        {"name": R.current.file, "icon": "img_file.svg"},
        {"name": R.current.announcement, "icon": "img_message.svg"},
        {"name": R.current.score, "icon": "img_education.svg"}
      ];

  late final CourseDataController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CourseDataController(widget.courseInfo.main.course.id);
    // 三個分頁一起抓，不等使用者滑過去：PageView(children:) 是懶載入的
    // （cacheExtent 0），分頁各自在 initState 發請求的話，每換一個分頁就要
    // 從頭等一次。
    unawaited(_controller.loadAll());
    _pages = [
      CourseDirectoryPage(widget.courseInfo, controller: _controller),
      CourseAnnouncementPage(widget.courseInfo, controller: _controller),
      CourseScorePage(widget.courseInfo, controller: _controller)
    ];
    _tabController = TabController(vsync: this, length: _tabItems.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController.dispose();
    _tabController?.dispose();
    super.dispose();
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
        appBar: baseAppbar(title: course.name, bottom: _buildTabBar(_tabItems)),
        body: PageView(
          controller: _pageController,
          children: _pages,
          onPageChanged: (index) {
            _tabController?.animateTo(index);
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
