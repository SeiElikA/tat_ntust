import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/service/error_dialog_parameter.dart';

/// 使用者對錯誤對話框的選擇。
enum RetryDecision { retry, giveUp }

/// 一次進度框顯示的憑證。
///
/// 之所以需要「憑證」而不是一個全域的關閉函式：[TaskUiDelegate.hideProgress]
/// 底下是 `BotToast.cleanAll()`，任何一次關閉都會把畫面上每一個 overlay 收掉。
/// 課程頁的三個分頁是並行載入的，先結束的那一個會讓另外兩個的遮罩提早消失，
/// 使用者以為載完了。`run()` 的 try/finally 要能「只關掉自己開的那一個」，
/// 就必須有東西可以指——就是這個 handle。
abstract class ProgressHandle {
  /// 只關掉這一個進度框。可以重複呼叫，第二次以後是 no-op。
  void dismiss();
}

/// 什麼都不做的 handle，給測試與 headless 環境用。
class NoopProgressHandle implements ProgressHandle {
  const NoopProgressHandle();

  @override
  void dismiss() {}
}

/// Task 層唯一被允許用來碰 UI 的介面。
///
/// 實作在 `lib/ui/service/get_task_ui_delegate.dart`，由 main.dart 在啟動時
/// 指派給 [TaskUiDelegate.instance]。預設是 [NoopTaskUiDelegate]，所以
/// 測試不需要註冊任何東西，非 UI 層也不必依賴 GetX 的服務定位。
abstract class TaskUiDelegate {
  static TaskUiDelegate instance = const NoopTaskUiDelegate();

  /// 顯示進度框，回傳只關掉這一個的憑證。`run()` 走這條。
  ProgressHandle beginProgress(String message);

  /// 成對 API：不回傳 handle，配對只能靠呼叫端手寫的 [hideProgress]。
  /// 新程式碼一律用 [beginProgress]。
  void showProgress(String message);

  /// [showProgress] 的另一半。
  ///
  /// 因為沒有 handle 可以指，實作只能把「[showProgress] 開出來、還沒關掉的」
  /// 進度框全部關掉：呼叫端手寫的配對會漏，一次關一個會讓漏掉的遮罩永遠留在
  /// 畫面上（理由寫在 `lib/ui/other/my_progress_dialog.dart`）。
  /// 它碰不到 [beginProgress] 交出去的那些 handle。
  void hideProgress();

  Future<RetryDecision> confirmRetry(ErrorDialogParameter parameter);

  void toast(String message);

  /// 請使用者從幾個選項裡挑一個。key 是顯示的字，value 是要回傳的值。
  ///
  /// 取消或沒有實作時回 null，呼叫端自己決定 fallback。行事曆下載途中要問
  /// 學期就是走這條。
  Future<String?> chooseOne(String title, Map<String, String> options);

  /// 請使用者手動挑一個學期。取消時回 null。
  ///
  /// [allowNull] 為 false 時，使用者沒有選就回「現在這個學期」而不是 null
  /// ——那是既有行為，呼叫端在那條路徑上沒有 null 的處理。
  ///
  /// 這個對話框是課表在三個學期來源全都拿不到資料、或存到的學期字串壞掉時
  /// 的最後手段。走這個介面而不是直接 import widget：controller -> ui 是
  /// 上行邊。
  Future<SemesterJson?> chooseSemester({bool allowNull = false});

  /// 帶使用者去登入設定。
  ///
  /// 站台明確拒絕憑證（帳號或密碼錯）時的出口。
  Future<void> openLoginScreen();
}

/// 測試與 headless 環境用的空實作。
class NoopTaskUiDelegate implements TaskUiDelegate {
  const NoopTaskUiDelegate();

  @override
  ProgressHandle beginProgress(String message) => const NoopProgressHandle();

  @override
  void showProgress(String message) {}

  @override
  void hideProgress() {}

  @override
  Future<RetryDecision> confirmRetry(ErrorDialogParameter parameter) async =>
      RetryDecision.giveUp;

  @override
  Future<String?> chooseOne(String title, Map<String, String> options) async =>
      null;

  @override
  Future<SemesterJson?> chooseSemester({bool allowNull = false}) async => null;

  @override
  Future<void> openLoginScreen() async {}

  @override
  void toast(String message) {}
}
