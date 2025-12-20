import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/controller/setting/moodle_setting_controller.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_setting_entity.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/ui/components/page/base_page.dart';
import 'package:get/get.dart';

class MoodleSettingPage extends GetView<MoodleSettingController> {
  const MoodleSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(MoodleSettingController());

    return Obx(() {
      return BasePage(
        title: R.current.moodle_setting,
        isLoading: controller.isLoading.value,
        isError: controller.isError.value,
        errorMsg: controller.errorMsg.value,
        isSubPage: true,
        bottom: controller.tabController == null
            ? null
            : TabBar(
                controller: controller.tabController,
                tabs: controller.tab
                    .map((e) => Tab(text: e.displayname))
                    .toList(),
              ),
        child: TabBarView(
            controller: controller.tabController,
            children: controller.tab
                .map((element) => _buildSettingList(element.name))
                .toList()),
      );
    });
  }

  Widget _buildSettingList(type) {
    return ListView.separated(
        controller: controller.scrollController,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        itemBuilder: (context, index) {
          var item = controller.settingList[index];
          return _buildSettingItem(item, type);
        },
        separatorBuilder: (context, index) {
          return const SizedBox(height: 14);
        },
        itemCount: controller.settingList.length);
  }

  Widget _buildSettingItem(MoodleSettingPreferencesComponents components, String type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8),
          child: Text(
            components.displayname,
            style: TextStyle(fontWeight: FontWeight.w600, color: Get.theme.colorScheme.onSurface),
          ),
        ),
        ListView.separated(
          itemBuilder: (context, index) {
            final e = components.notifications[index];
            final borderRadius = UIUtils.getBorderRadius(index, components.notifications.length);

            return Container(
                decoration: BoxDecoration(
                    color: Get.theme.colorScheme.surfaceContainer,
                    borderRadius: borderRadius),
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.displayname,
                        style: TextStyle(
                            color: Get.theme.colorScheme.onSurfaceVariant),
                      ),
                    ),

                    const SizedBox(width: 12,),

                    Switch.adaptive(
                      activeColor: Platform.isIOS ? Get.theme.colorScheme.primary : null,
                      value: e.processors
                          .where((element) =>
                              element.name == type && element.enabled)
                          .isNotEmpty,
                      onChanged: (bool value) async {
                        await HapticFeedback.lightImpact();
                        final offset = controller.scrollController.offset;
                        await controller.toggleSetting(e.preferencekey, type, value);
                        await Future.delayed(5.milliseconds);
                        controller.scrollController.jumpTo(offset);
                      },
                    )
                  ],
                ));
          },
          separatorBuilder: (context, index) {
            return const SizedBox(height: 2);
          },
          itemCount: components.notifications.length,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
        ),
      ],
    );
  }
}
