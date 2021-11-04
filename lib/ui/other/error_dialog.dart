//  error_dialog.dart
//  北科課程助手
//  用於顯示錯誤視窗
//  Created by morris13579 on 2020/02/12.
//  Copyright © 2020 morris13579 All rights reserved.
//

import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_app/src/R.dart';
import 'package:get/get.dart';

class ErrorDialogParameter {
  BuildContext? context;
  late String? title;
  String desc;
  late String? btnOkText;
  late String? btnCancelText;
  late DialogType? dialogType;
  late AnimType? animType;
  late Function? btnOkOnPress;
  late Function? btnCancelOnPress;
  bool offOkBtn;
  bool offCancelBtn;
  bool okResult;
  bool cancelResult;

  ErrorDialogParameter(
      {this.context,
      required this.desc,
      this.title,
      this.btnOkText,
      this.btnCancelText,
      this.animType,
      this.dialogType,
      this.btnCancelOnPress,
      this.btnOkOnPress,
      this.okResult: true,
      this.cancelResult: false,
      this.offOkBtn: false,
      this.offCancelBtn: false}) {
    title = title ?? R.current.alertError;
    btnOkText = btnOkText ?? R.current.restart;
    btnCancelText = btnCancelText ?? R.current.cancel;
    animType = animType ?? AnimType.BOTTOMSLIDE;
    dialogType = dialogType ?? DialogType.ERROR;
    btnCancelOnPress = btnCancelOnPress ??
        () {
          Get.back<bool>(result: cancelResult);
        };
    btnOkOnPress = btnOkOnPress ??
        () {
          Get.back<bool>(result: okResult);
        };
    if (offOkBtn) {
      btnOkOnPress = null;
    }
    if (offCancelBtn) {
      btnCancelOnPress = null;
    }
  }
}

class ErrorDialog {
  ErrorDialogParameter parameter;

  ErrorDialog(this.parameter);

  Future<bool> show() async {
    DismissType? dismissType;
    var dialog = AwesomeDialog(
        context: Get.key.currentState!.context,
        dialogType: parameter.dialogType!,
        animType: parameter.animType!,
        title: parameter.title!,
        desc: parameter.desc,
        btnOkText: parameter.btnOkText!,
        btnCancelText: parameter.btnCancelText!,
        useRootNavigator: false,
        dismissOnTouchOutside: false,
        btnCancelOnPress: parameter.btnCancelOnPress,
        btnOkOnPress: parameter.btnOkOnPress,
        onDissmissCallback: (DismissType type) {
          dismissType = type;
        });
    dialog.isDissmisedBySystem = true;
    await dialog.show();
    bool result;
    print(dismissType);
    switch (dismissType) {
      case DismissType.BTN_OK:
        result = parameter.okResult;
        break;
      case DismissType.BTN_CANCEL:
        result = parameter.cancelResult;
        break;
      default:
        result = parameter.cancelResult;
    }
    return result;
  }
}
