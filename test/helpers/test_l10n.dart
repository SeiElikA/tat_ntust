import 'package:flutter/material.dart';
import 'package:flutter_app/generated/l10n.dart';
import 'package:flutter_app/src/R.dart';

/// `R.current` 是 `static S current = S.of(Get.context!)` 的 lazy static，
/// 在測試中沒有 `Get.context` 會直接 NPE。
///
/// 這個 helper 在「第一次存取 R.current 之前」先把它指派掉，避開 lazy
/// 初始化。R.current 不是 final，所以不需要修改 lib/ 的程式碼。
///
/// 任何會走到 `R.current.xxx` 的測試都要在 setUpAll 呼叫它。
Future<void> loadTestL10n([Locale locale = const Locale('zh', 'TW')]) async {
  await S.load(locale);
  R.current = S.current;
}
