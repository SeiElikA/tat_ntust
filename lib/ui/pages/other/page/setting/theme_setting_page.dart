import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/service/theme_service.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:get/get.dart';

class ThemeSettingPage extends StatefulWidget {
  const ThemeSettingPage({super.key});

  @override
  State<ThemeSettingPage> createState() => _ThemeSettingPageState();
}

class _ThemeSettingPageState extends State<ThemeSettingPage> {
  var groupValue = ThemeMode.system;
  final themeText = {
    ThemeMode.dark: R.current.theme_dark,
    ThemeMode.light: R.current.theme_light,
    ThemeMode.system: R.current.theme_system,
  };

  @override
  void initState() {
    super.initState();
    groupValue = ThemeService.instance.theme;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: baseAppbar(title: R.current.theme_setting),
      body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemBuilder: (context, index) {
            final item = ThemeMode.values[index];
            final borderRadius = UIUtils.getBorderRadius(index, ThemeMode.values.length);

            return CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => onRadioChanged(item),
              child: Container(
                  decoration: BoxDecoration(
                      color: Get.theme.colorScheme.surfaceContainer,
                      borderRadius: borderRadius),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  child: Row(
                    children: [
                      Text(
                        themeText[item] ?? "-",
                        style: TextStyle(
                            fontFamily: 'MyFont',
                            color: Get.theme.colorScheme.onSurfaceVariant
                        ),
                      ),
                      const Spacer(),
                      Radio(
                          value: item,
                          groupValue: groupValue,
                          onChanged: onRadioChanged)
                    ],
                  )),
            );
          },
          separatorBuilder: (context, index) {
            return const SizedBox(height: 2);
          },
          itemCount: ThemeMode.values.length),
    );
  }

  Future<void> onRadioChanged(ThemeMode? value) async {
    if(value == null) {
      return;
    }

    await HapticFeedback.mediumImpact();

    setState(() {
      groupValue = value;
    });

    ThemeService.instance.changeThemeMode(value);
  }
}
