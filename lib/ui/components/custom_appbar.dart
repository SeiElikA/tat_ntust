import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

AppBar mainAppbar(
    {String title = "",
    List<Widget>? action,
    bool isShowBack = false,
    PreferredSizeWidget? bottom,
    BuildContext? context}) {
  return AppBar(
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarIconBrightness: Get.theme.brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light,
    ),
    actions: action,
    centerTitle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    leading: !isShowBack
        ? const SizedBox(
            width: 0,
          )
        : null,
    leadingWidth: !isShowBack ? 0 : null,
    bottom: bottom,
    title: Text(title),
  );
}

AppBar baseAppbar(
    {String title = "",
    List<Widget>? action,
    BuildContext? context,
    PreferredSizeWidget? bottom,
    Color? backgroundColor}) {
  return AppBar(
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarIconBrightness: Get.theme.brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light,
    ),
    // 這顆返回鍵出現在每一個用 baseAppbar 的子頁面上，沒有 tooltip 時螢幕閱讀器
    // 只會唸「按鈕」。用 Builder 取得 AppBar 底下的 context：baseAppbar 只是一個
    // 回傳 AppBar 的函式，沒有自己的 BuildContext，而它的 context 具名參數所有
    // 呼叫端都沒有傳。backButtonTooltip 由 GlobalMaterialLocalizations 提供。
    leading: Builder(
      builder: (context) => IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        splashColor: Colors.transparent,
        splashRadius: 18,
        icon: Icon(
          Icons.arrow_back_ios_new,
          size: 18,
          color: Get.theme.colorScheme.onSurface,
        ),
        onPressed: () {
          Get.back();
        },
      ),
    ),
    actions: action,
    centerTitle: false,
    elevation: 0,
    bottom: bottom,
    title: Text(title),
  );
}
