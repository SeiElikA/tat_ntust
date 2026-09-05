import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/ui/pages/course_table/modal/manual_semester_dialog.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_app/ui/other/error_dialog.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/ui/other/my_progress_dialog.dart';
import 'package:get/get.dart';

/// [TaskUiDelegate] 的正式實作，由 main.dart 在啟動時指派。
///
/// [beginProgress] 是 `run()` 走的路：每一次顯示都拿得到自己的 handle，關掉時
/// 不會動到別人的遮罩。[showProgress] / [hideProgress] 是手寫配對的舊路。
class GetTaskUiDelegate implements TaskUiDelegate {
  const GetTaskUiDelegate();

  @override
  ProgressHandle beginProgress(String message) =>
      _BotToastProgressHandle(MyProgressDialog.beginProgressDialog(message));

  @override
  void showProgress(String message) => MyProgressDialog.progressDialog(message);

  @override
  void hideProgress() => MyProgressDialog.hideProgressDialog();

  @override
  Future<RetryDecision> confirmRetry(ErrorDialogParameter parameter) async {
    // 站台明確拒絕憑證時，把「確定」換成通往登入設定的出口。「登入頁在哪」
    // 是 UI 這一層的責任。
    if (parameter.offerLoginScreen) {
      parameter.btnOkText = R.current.setting;
      parameter.okResult = false;
      parameter.btnOkOnPress = () {
        // 改完帳密回來之後把對話框關掉並回報 retry——使用者剛剛才修正了
        // 讓它失敗的原因，直接重試才是他預期的。
        RouteUtils.toLoginScreen().then((_) => Get.back<bool>(result: true));
      };
    }
    return await ErrorDialog(parameter).show()
        ? RetryDecision.retry
        : RetryDecision.giveUp;
  }

  @override
  void toast(String message) => MyToast.show(message);

  @override
  Future<String?> chooseOne(String title, Map<String, String> options) =>
      selectOneDialog(title, options);

  @override
  Future<SemesterJson?> chooseSemester({bool allowNull = false}) =>
      manualSemesterDialog(allowSelectNull: allowNull);

  @override
  Future<void> openLoginScreen() => RouteUtils.toLoginScreen();
}

/// 從幾個選項裡挑一個的對話框；repository 只認得 [TaskUiDelegate.chooseOne]。
///
/// `barrierDismissible: false` 是刻意的：點外面關掉會讓下載流程拿到 null，
/// 而呼叫端的 fallback 是「用第一個選項」，使用者會拿到不是自己選的學期。
Future<String?> selectOneDialog(String title, Map<String, String> options) =>
    Get.dialog<String>(
      AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.entries
              .map((e) => TextButton(
                    onPressed: () => Get.back<String>(result: e.value),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        e.key,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Get.theme.colorScheme.onSurface),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
      barrierDismissible: false,
    );

/// 包住 BotToast 的 CancelFunc，只關掉自己那一個進度框。
class _BotToastProgressHandle implements ProgressHandle {
  _BotToastProgressHandle(this._cancel);

  /// 型別刻意寫成 `void Function()` 而不是 bot_toast 的 `CancelFunc`，
  /// 這樣這一層不必把 bot_toast 的型別帶進 import。
  final void Function() _cancel;

  bool _dismissed = false;

  @override
  void dismiss() {
    // BotToast 重複移除同一個 key 本來就是 no-op；這個旗標把「dismiss 可以
    // 重複呼叫」變成保證，呼叫端多關一次不必自己記有沒有關過。
    if (_dismissed) return;
    _dismissed = true;
    _cancel();
  }
}
