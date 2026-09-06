import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

class CustomSnackBar {
  static showCustomErrorSnackBar(
      {required String title,
      required String message,
      Color? color,
      Duration? duration}) {
    Get.snackbar(
      title.isEmpty ? "Error" : title,
      message,
      duration: duration ?? const Duration(seconds: 3),
      margin: const EdgeInsets.only(top: 10, left: 10, right: 10),
      padding: const EdgeInsets.only(left: 18, top: 16, bottom: 16, right: 16),
      colorText: Colors.white,
      backgroundColor: color ?? Colors.redAccent,
      icon: const Icon(
        LucideIcons.circleAlert,
        color: Colors.white,
      ),
    );
  }
}
