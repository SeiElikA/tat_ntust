import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppStyles {
  AppStyles._();

  static DialogTheme dialogTheme() {
    return const DialogTheme(
      actionsPadding: EdgeInsets.all(12),
    );
  }

  static IconThemeData iconTheme() {
    return IconThemeData(
      color: Get.theme.colorScheme.onSurface
    );
  }
}
