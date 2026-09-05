import 'dart:math';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:get/get.dart';

import 'custom_progress_dialog.dart';

const double kitSize = 20;
final kits = <Widget>[
  SpinKitRotatingCircle(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitChasingDots(size: kitSize + 5, color: Get.theme.colorScheme.primary),
  SpinKitPulse(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitDoubleBounce(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitThreeBounce(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitThreeInOut(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitCircle(size: kitSize + 5, color: Get.theme.colorScheme.primary),
  SpinKitFadingFour(size: kitSize + 5, color: Get.theme.colorScheme.primary),
  SpinKitRing(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitDualRing(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitSpinningLines(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitFadingGrid(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitSquareCircle(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitSpinningCircle(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitFadingCircle(size: kitSize + 5, color: Get.theme.colorScheme.primary),
  SpinKitHourGlass(size: kitSize, color: Get.theme.colorScheme.primary),
  SpinKitPouringHourGlass(
      size: kitSize + 10, color: Get.theme.colorScheme.primary),
  SpinKitRipple(size: kitSize, color: Get.theme.colorScheme.primary),
];

class MyProgressDialog {
  /// 由 [progressDialog]（沒有 handle 的舊 API）開出、還沒被關掉的進度框。
  ///
  /// 用這份清單而不是 `BotToast.cleanAll()`：cleanAll 會清掉畫面上每一個 BotToast
  /// overlay，包含別人開的。有了它，[hideProgressDialog] 只關這個類別自己開出來的
  /// 進度框，也關不到 [beginProgressDialog] 交給呼叫端保管的那些。
  ///
  /// 這裡仍然是「一次全部關掉」而不是配對關一個：舊的成對 API 是手寫配對的，
  /// 一丟例外就會跳過 hide。進度框是 allowClick=false、duration=null 的全螢幕
  /// 遮罩，漏掉一個就是一塊吃掉所有觸控、返回鍵也關不掉的畫面，只能靠「下一次
  /// hide 會全部關掉」收拾。成對 API 的呼叫端全部改走 [beginProgressDialog]
  /// 之後，這份清單才能刪。
  static final List<CancelFunc> _unownedDialogs = [];

  /// 舊的成對 API：與 [hideProgressDialog] 配對。新程式碼一律用 [beginProgressDialog]。
  static void progressDialog(String? message) {
    _unownedDialogs.add(_show(message));
  }

  /// 顯示進度框，回傳「只關掉這一個」的函式，由呼叫端自己保管。
  ///
  /// 回傳的是 BotToast 的 [CancelFunc]，內部以 UniqueKey 移除單一 overlay，
  /// 不會動到其他人的進度框；重複呼叫是 no-op。
  static CancelFunc beginProgressDialog(String? message) => _show(message);

  static CancelFunc _show(String? message) => BotToast.showCustomLoading(
        toastBuilder: (cancel) => dialog(message),
      );

  static Widget dialog(String? message) {
    final int number = Random().nextInt(kits.length);
    return CustomProgressDialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 60,
              width: 100,
              child: kits[number],
            ),
            Visibility(
              visible: message != null,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  "$message",
                  style: TextStyle(color: Get.theme.colorScheme.onSurface),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 關掉 [progressDialog] 開出來、還沒關掉的進度框。理由見 [_unownedDialogs]。
  static void hideProgressDialog() {
    // 先清空清單再逐一取消：CancelFunc 會同步跑 onClose 之類的回呼，那裡面若又
    // 繞回這個方法，看到的必須是已清空的清單，否則同一個框會被取消兩次，或清單
    // 在走訪中途被改動。
    final pending = List<CancelFunc>.of(_unownedDialogs);
    _unownedDialogs.clear();
    for (final cancel in pending) {
      cancel();
    }
  }
}
