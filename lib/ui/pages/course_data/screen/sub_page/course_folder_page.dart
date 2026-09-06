import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/util/file_utils.dart';
import 'package:flutter_app/src/util/moodle_folder_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/empty_state.dart';
import 'package:flutter_app/ui/components/tile/moodle_file_tile.dart';
import 'package:flutter_app/ui/service/file_download.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:sprintf/sprintf.dart';

/// 資料夾模組的某一層。Moodle 只回檔案，子資料夾是從 `filepath` 推出來的，
/// 見 [MoodleFolderUtils]。
class CourseFolderPage extends StatelessWidget {
  const CourseFolderPage(
    this.courseInfo,
    this.modules, {
    this.path = MoodleFolderUtils.rootPath,
    super.key,
  });

  final CourseInfoJson courseInfo;
  final Modules modules;

  /// 目前所在的子路徑，頭尾都有 '/'。進子資料夾是把自己再推一次，
  /// 所以系統返回鍵天生就會回到上一層。
  final String path;

  List<String> get _segments => MoodleFolderUtils.segments(path);

  String get _title => _segments.isEmpty ? modules.name : _segments.last;

  String get _breadcrumb => [modules.name, ..._segments].join(' / ');

  @override
  Widget build(BuildContext context) {
    final listing = MoodleFolderUtils.listing(modules.contents, path: path);
    return Scaffold(
      appBar: baseAppbar(title: _title),
      body: listing.isEmpty
          ? EmptyState(
              asset: "assets/image/img_folder.svg",
              message: R.current.folderEmpty,
            )
          : _tree(context, listing),
    );
  }

  /// 一層可能有上百個檔案，所以列留在 sliver 裡逐列建構。
  Widget _tree(BuildContext context, MoodleFolderListing listing) {
    final divided = listing.folders.isNotEmpty && listing.files.isNotEmpty;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              icon: Icons.folder_outlined,
              title: _breadcrumb,
              first: true,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
          sliver: SectionCardSliver(
            sliver: SliverList.builder(
              itemCount: listing.folders.length +
                  (divided ? 1 : 0) +
                  listing.files.length,
              itemBuilder: (context, index) =>
                  _rowAt(context, listing, index, divided),
            ),
          ),
        ),
      ],
    );
  }

  /// 先子資料夾、有兩者時一條分隔線、再檔案。
  Widget _rowAt(BuildContext context, MoodleFolderListing listing, int index,
      bool divided) {
    if (index < listing.folders.length) {
      return _folderTile(context, listing.folders[index]);
    }
    var i = index - listing.folders.length;
    if (divided) {
      if (i == 0) return const SectionDivider();
      i -= 1;
    }
    return _fileTile(context, listing.files[i]);
  }

  Widget _fileTile(BuildContext context, Contents c) {
    return MoodleFileTile(
      filename: c.filename,
      mimetype: c.mimetype,
      subtitle: _fileSubtitle(c),
      onTap: () => unawaited(FileDownload.download(
        context,
        MoodleWebApiConnector.fileUrlWithToken(c.fileurl),
        courseInfo.main.course.name,
        name: c.filename,
      )),
    );
  }

  Widget _folderTile(BuildContext context, MoodleSubFolder folder) {
    final scheme = Theme.of(context).colorScheme;
    return MoodleFileTile(
      filename: folder.name,
      subtitle: sprintf(R.current.folderFileCount, [folder.fileCount]),
      leading: Icon(Icons.folder_rounded, size: 24, color: scheme.primary),
      trailing:
          Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
      // GetX 拿 widget 型別當路由名，同一頁再推一次會被 preventDuplicates
      // 當成重複而靜默不推，子資料夾就點不進去。
      onTap: () => unawaited(Get.to(
        () => CourseFolderPage(courseInfo, modules, path: folder.path),
        preventDuplicates: false,
      )),
    );
  }

  /// 兩者都沒有時回 null，那一列就維持單行。
  String? _fileSubtitle(Contents c) {
    final parts = [
      if (c.filesize > 0) FileUtils.formatBytes(c.filesize, 1),
      if (c.timemodified > 0) _formatTime(c.timemodified),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _formatTime(int unix) => DateFormat.yMd()
      .add_jm()
      .format(DateTime.fromMillisecondsSinceEpoch(unix * 1000));
}
