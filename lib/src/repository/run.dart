import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/repository/retry.dart';
import 'package:flutter_app/src/service/connectivity_probe.dart';
import 'package:flutter_app/src/service/error_dialog_parameter.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/store/cache_store.dart';

/// 取資料的共用外殼：登入、進度框、快取回退、重試迴圈。
///
/// 相依全部透過各自的 `instance` 靜態欄位取得，與 [CacheStore]、
/// [TaskUiDelegate] 一致。**不要改用 `Get.find`**：那會讓 repository 層依賴
/// GetX 的服務定位，測試也必須先起一個容器。
Future<Result<T>> run<T>({
  /// 這次取資料需要哪些系統已登入。
  required Set<SystemId> requires,

  /// 真正去拿資料。回傳 null 代表失敗（connector 的慣例）。
  /// 要指定失敗原因就丟 [TaskFailure]。
  required Future<T?> Function() fetch,

  /// 盡力而為的登入。失敗不影響結果，只是少了一部分資料。
  Set<SystemId> optional = const {},

  /// 離線快取。null 代表不快取。
  CacheKey<T>? cache,

  /// 先讀快取，命中就完全不打網路。
  ///
  /// **只給識別子對照表用**（例如 courseId → Moodle 內部 id）。
  /// 一般的結果快取維持「只在失敗時讀」：不是 stale-while-revalidate，
  /// 畫面不會先閃一次舊資料再跳成新的。
  bool cacheFirst = false,

  /// 有值就顯示進度框，以 try/finally 收尾。
  ///
  /// 關掉的必須是 [TaskUiDelegate.beginProgress] 給的 handle，不是全域的
  /// hideProgress——後者底下是 BotToast.cleanAll()，會把並行分頁的遮罩一起
  /// 收掉。
  String? progressMessage,

  /// fetch 回 null 且沒丟 [TaskFailure] 時，錯誤訊息用這個。
  String? errorMessage,

  /// 失敗時要不要問使用者。
  RetryPolicy retry = RetryPolicy.askUser,

  /// 只出現在 log 裡，用來認出是哪一條路徑。
  String debugLabel = 'run',

  /// 背景取資料：使用者沒有要求，所以**不准有任何東西蓋在他正在看的畫面上**。
  ///
  /// 為 true 時做兩件事：
  /// - 忽略 [progressMessage]，不開進度框。
  /// - 以 `interactive: false` 呼叫 [AuthSession.ensure]，登入只做安靜的那一段，
  ///   不升級到可見的登入頁。
  ///
  /// 第二點是重點：`retry: RetryPolicy.none` 只擋掉重試／錯誤對話框，擋不掉
  /// 互動式登入——那個升級發生在 `ensure()` 裡面，而 `run()` 在看 `retry` 之前
  /// 就已經呼叫過它了。少了這個旗標，背景預載會在 SSO 過期時把登入頁蓋在
  /// 使用者正在看的畫面上。
  bool background = false,
}) async {
  final auth = AuthSession.instance;
  final ui = TaskUiDelegate.instance;
  final store = CacheStore.instance;
  final net = ConnectivityProbe.instance;

  Future<Result<T>> fallback(FailureReason reason) async {
    final cached = cache == null ? null : await store.read<T>(cache);
    Log.d(
        '$debugLabel ${cached == null ? "failed" : "stale"}: ${reason.message}');
    if (cached == null) return Failed<T>(reason);
    ui.toast(R.current.loadingCache);
    return Stale<T>(cached, reason);
  }

  if (cacheFirst && cache != null) {
    final hit = await store.read<T>(cache);
    if (hit != null) return Ok<T>(hit);
  }

  if (!await net.isOnline()) return fallback(const Offline());

  while (true) {
    // 登入失敗與取資料失敗走同一個重試迴圈：使用者按的是同一顆按鈕。
    final authFailure = await auth.ensure(requires, interactive: !background);
    if (authFailure != null) {
      final authReason = _reasonOf(authFailure);
      if (retry == RetryPolicy.none || !authReason.retryable) {
        return fallback(authReason);
      }
      if (await _confirmRetry(ui, authReason) == RetryDecision.giveUp) {
        return fallback(authReason);
      }
      await auth.invalidate(requires);
      continue;
    }
    for (final id in optional) {
      await auth.tryEnsure(id);
    }

    T? value;
    FailureReason? reason;
    // handle 開在 while 迴圈裡：按下重試會重跑一輪，每一輪都要是自己的一個。
    final progress = (progressMessage == null || background)
        ? null
        : ui.beginProgress(progressMessage);
    try {
      value = await fetch();
    } on TaskFailure catch (e) {
      reason = e.reason;
    } catch (e, stack) {
      Log.eWithStack('$debugLabel: $e', stack);
      // 途中斷線要重新分類成 Offline，否則使用者只會看到一個沒有幫助的
      // 錯誤訊息，而不是「請檢查網路」。
      reason = await net.isOnline()
          ? FetchFailed(errorMessage ?? e.toString())
          : const Offline();
    } finally {
      progress?.dismiss();
    }

    if (value != null) {
      if (cache != null) await store.write<T>(cache, value);
      return Ok<T>(value);
    }

    reason ??= FetchFailed(errorMessage);
    if (retry == RetryPolicy.none || !reason.retryable) return fallback(reason);
    if (await _confirmRetry(ui, reason) == RetryDecision.giveUp) {
      return fallback(reason);
    }
    // 重試前作廢登入狀態：「按重試會靜默重新登入」全靠這一行。
    await auth.invalidate(requires);
  }
}

/// [AuthFailure] 到 [FailureReason] 的對映。
///
/// 分成兩個型別是為了不讓 auth 層 import repository 層——auth 是
/// repository 的相依，反過來會是上行邊。
///
/// **[AuthError.message] 要帶下去**，否則站台實際回的原因（「帳號或密碼
/// 錯誤」）會被換成一句通用訊息。
FailureReason _reasonOf(AuthError error) => switch (error.failure) {
      AuthFailure.notSignedIn => const NotSignedIn(),
      AuthFailure.loginFailed => LoginFailed(error.message),
    };

/// 把 [FailureReason] 轉成對話框吃的 [ErrorDialogParameter]。
Future<RetryDecision> _confirmRetry(
    TaskUiDelegate ui, FailureReason reason) async {
  try {
    final parameter = ErrorDialogParameter(desc: reason.message);
    // 站台明確說了原因（多半是帳密錯）時，多給一個通往登入設定的出口。
    parameter.offerLoginScreen = reason is LoginFailed && reason.detail != null;
    return await ui.confirmRetry(parameter);
  } catch (e) {
    // 對話框自己出問題時當成 giveUp。
    return RetryDecision.giveUp;
  }
}
