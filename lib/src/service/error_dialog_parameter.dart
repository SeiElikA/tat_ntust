import 'package:awesome_dialog/awesome_dialog.dart';

/// 錯誤對話框的參數，純資料類。
///
/// 這個類別刻意不碰 `BuildContext`、不預設 `Get.back` 閉包、也不讀 `R.current`：
/// 所有預設值改由 UI 層在真正要顯示時補上（見 `lib/ui/other/error_dialog.dart`）。
/// 這樣 task 層才能不 import `lib/ui`。
///
/// 欄位保持可變，因為呼叫端是先建構再逐項覆寫。
class ErrorDialogParameter {
  String desc;
  String? title;
  String? btnOkText;
  String? btnCancelText;
  DialogType? dialogType;
  AnimType? animType;
  dynamic Function()? btnOkOnPress;
  dynamic Function()? btnCancelOnPress;
  bool offOkBtn;
  bool offCancelBtn;

  /// 除了重試之外，還要給一顆「設定」按鈕帶使用者去改帳號密碼。
  ///
  /// 只有站台明確拒絕憑證時才是 true。一般的抓取失敗重試就好，多一顆通往
  /// 登入頁的按鈕反而讓人以為是自己帳號有問題。
  bool offerLoginScreen = false;

  /// 按下確定時 `show()` 要回傳的值。預設 true，代表重試。
  bool okResult;

  /// 按下取消（或點掉對話框）時要回傳的值。預設 false，代表放棄。
  bool cancelResult;

  ErrorDialogParameter({
    required this.desc,
    this.title,
    this.btnOkText,
    this.btnCancelText,
    this.animType,
    this.dialogType,
    this.btnCancelOnPress,
    this.btnOkOnPress,
    this.okResult = true,
    this.cancelResult = false,
    this.offOkBtn = false,
    this.offCancelBtn = false,
  });
}
