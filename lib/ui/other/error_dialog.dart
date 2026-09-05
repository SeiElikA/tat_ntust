//  error_dialog.dart
//  用於顯示錯誤視窗
//  Created by morris13579 on 2020/02/12.
//  Copyright © 2020 morris13579 All rights reserved.
//

import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/service/error_dialog_parameter.dart';
import 'package:get/get.dart';

export 'package:flutter_app/src/service/error_dialog_parameter.dart';

class ErrorDialog {
  ErrorDialogParameter parameter;

  ErrorDialog(this.parameter);

  Future<bool> show() async {
    // 預設值在這裡補，而不是在 ErrorDialogParameter 的建構子，
    // 這樣參數類別才不需要 R.current 與 Get。
    final title = parameter.title ?? R.current.alertError;
    final btnOkText = parameter.btnOkText ?? R.current.restart;
    final btnCancelText = parameter.btnCancelText ?? R.current.cancel;
    final animType = parameter.animType ?? AnimType.bottomSlide;
    final dialogType = parameter.dialogType ?? DialogType.error;
    final btnOkOnPress = parameter.offOkBtn
        ? null
        : (parameter.btnOkOnPress ??
            () => Get.back<bool>(result: parameter.okResult));
    final btnCancelOnPress = parameter.offCancelBtn
        ? null
        : (parameter.btnCancelOnPress ??
            () => Get.back<bool>(result: parameter.cancelResult));

    DismissType? dismissType;
    var dialog = AwesomeDialog(
        context: Get.key.currentState!.context,
        dialogType: dialogType,
        animType: animType,
        title: title,
        desc: parameter.desc,
        btnOkText: btnOkText,
        btnCancelText: btnCancelText,
        useRootNavigator: false,
        dismissOnTouchOutside: false,
        autoDismiss: false,
        btnCancelOnPress: btnCancelOnPress,
        btnOkOnPress: btnOkOnPress,
        onDismissCallback: (DismissType type) {
          dismissType = type;
        });
    await dialog.show();
    switch (dismissType) {
      case DismissType.btnOk:
        return parameter.okResult;
      case DismissType.btnCancel:
        return parameter.cancelResult;
      default:
        return parameter.cancelResult;
    }
  }
}
