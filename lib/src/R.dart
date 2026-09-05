// ignore_for_file: file_names
// R 是這個專案沿用已久的字串資源命名慣例（同 Android 的 R）。
// 改成 r.dart 要一併改一百多處 import，收益不足以抵銷風險。

import 'package:flutter/material.dart';
import 'package:flutter_app/generated/l10n.dart';
import 'package:get/get.dart';

class R {
  static S current = S.of(Get.context!);

  static load(Locale locale) {
    S.delegate.load(locale);
  }
}
