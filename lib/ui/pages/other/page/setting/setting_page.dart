import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/controller/main_page/main_controller.dart';
import 'package:flutter_app/src/file/file_store.dart';
import 'package:flutter_app/src/util/document_utils.dart';
import 'package:flutter_app/src/util/language_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/other/listview_animator.dart';
import 'package:flutter_app/ui/pages/other/page/setting/moodle_setting_page.dart';
import 'package:flutter_app/ui/pages/other/page/setting/theme_setting_page.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  String downloadPath = "";

  @override
  void initState() {
    super.initState();
    WidgetsFlutterBinding.ensureInitialized()
        .addPostFrameCallback((timeStamp) async {
      // callback 是掛在 binding 上而不是這個 State 上，即使頁面在第一幀後
      // 馬上被 pop 掉也照樣會跑；此時讀 State.context 會 assert 失敗。
      if (!mounted) return;
      await _getDownloadPath();
    });
  }

  Future<void> _getDownloadPath() async {
    String path = await FileStore.findLocalPath(context);
    // 這個 await 可能停在系統的儲存權限對話框上，長度不可控。使用者在對話框
    // 開著的時候退出設定頁，setState 就會打在已經 dispose 的 State 上。
    if (!mounted) return;
    setState(() {
      downloadPath = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> listViewData = [
      _buildLanguageSetting(),
      _buildThemeSetting(),
      _buildMoodleSetting(),
      _buildFolderPathSetting()
    ];

    return Scaffold(
      appBar: baseAppbar(title: R.current.setting),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: listViewData.length,
        itemBuilder: (context, index) {
          return WidgetAnimator(listViewData[index]);
        },
        separatorBuilder: (context, index) {
          return const SizedBox(
            height: 4,
          );
        },
      ),
    );
  }

  Widget _buildLanguageSetting() {
    return _buildItemWrapper(
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    R.current.languageSwitch,
                    style: TextStyle(color: Get.theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    R.current.willRestart,
                    style: TextStyle(
                        fontSize: 14,
                        color: Get.theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
                value: LanguageUtils.getLangIndex() == LangEnum.en,
                onChanged: (value) async {
                  await HapticFeedback.lightImpact();
                  int langIndex = 1 - LanguageUtils.getLangIndex().index;
                  await LanguageUtils.setLangByIndex(
                      LangEnum.values.toList()[langIndex]);
                  Get.find<MainController>().pageController.jumpToPage(0);
                  Get.back();
                  setState(() {});
                })
          ],
        ),
        () {});
  }

  Widget _buildThemeSetting() {
    return _buildItemWrapper(
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    R.current.theme_setting,
                    style: TextStyle(color: Get.theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    R.current.theme_setting_description,
                    style: TextStyle(
                        fontSize: 14,
                        color: Get.theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: Get.theme.colorScheme.onSurface,
            ),
          ],
        ), () {
      Get.to(() => const ThemeSettingPage());
    });
  }

  Widget _buildMoodleSetting() {
    return _buildItemWrapper(
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    R.current.moodle_setting,
                    style: TextStyle(color: Get.theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    R.current.moodle_setting_description,
                    style: TextStyle(
                        fontSize: 14,
                        color: Get.theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: Get.theme.colorScheme.onSurface,
            ),
          ],
        ), () {
      Get.to(() => const MoodleSettingPage());
    });
  }

  Widget _buildFolderPathSetting() {
    return Visibility(
      visible: downloadPath.isNotEmpty,
      child: _buildItemWrapper(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                R.current.downloadPath,
                style: TextStyle(color: Get.theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                downloadPath,
                style: TextStyle(
                    fontSize: 14,
                    color: Get.theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ), () async {
        String? directory = await DocumentUtils.choiceFolder();
        // mounted 同 _getDownloadPath：系統資料夾選擇器會停留任意久，
        // 期間使用者可以退出設定頁，回來時 State 已經 dispose。
        if (directory != null && mounted) {
          setState(() {
            downloadPath = directory;
          });
        }
      }),
    );
  }

  Widget _buildItemWrapper(Widget child, Function() onClick) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onClick,
      child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
              color: Get.theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: child),
    );
  }
}
