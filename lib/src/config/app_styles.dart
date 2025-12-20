import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppStyles {
  AppStyles._();

  static DialogThemeData dialogTheme() {
    return const DialogThemeData(
      actionsPadding: EdgeInsets.all(12),
    );
  }

  static IconThemeData iconTheme() {
    return IconThemeData(
      color: Get.theme.colorScheme.onSurface
    );
  }
}
