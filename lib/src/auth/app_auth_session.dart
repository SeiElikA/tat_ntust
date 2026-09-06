import 'dart:async';

import 'package:flutter_app/src/auth/auth_session.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/service/interactive_login_gateway.dart';
import 'package:flutter_app/src/enum/ntust_login_status.dart';
import 'package:flutter_app/src/connector/ntust_connector.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/store/credentials_store.dart';
import 'package:flutter_app/src/store/moodle_session_store.dart';

/// [AuthSession] 的正式實作；`ensure` 是唯一會發起登入的入口。

class AppAuthSession implements AuthSession {
  AppAuthSession();

  /// SSO 這一趟握手完成了沒有。Moodle 不需要對應欄位：wsToken 本身就是狀態。
  /// 公開是刻意的，測試要能設定「已經登入」這個前提。
  bool ssoReady = false;

  /// 帳號與密碼都非空才算：只有帳號時畫面會顯示已登入但每次登入都失敗。
  @override
  bool get isSignedIn => CredentialsStore.instance.hasCredentials;

  /// [MoodleWebApiConnector.onApiError] 的處理器，一定要在啟動時裝上：沒裝的話
  /// token 過期只會彈重試框，而重試會帶著同一顆死 token 再失敗一次。
  void onMoodleApiError(MoodleApiException error) {
    if (!error.isInvalidToken) return;
    // 九條讀取路徑可能同時失敗，清過就不要再清。
    if (MoodleWebApiConnector.wsToken == null) return;
    Log.d('[moodle] invalidtoken：作廢 token，下一次 ensure 會重登');
    // setter 會連 userId、siteInfo 與課程快取一起作廢。
    MoodleWebApiConnector.wsToken = null;
    // 磁碟上那一顆也要清，否則下次冷啟動 restoreToken 會把它撈回來。
    unawaited(MoodleSessionStore.instance.clear());
  }

  /// 讓 [requires] 的登入狀態失效，下次 [ensure] 會重登。兩個系統之間零相依，
  /// 不需要展開。
  @override
  Future<void> invalidate(Set<SystemId> requires) async {
    for (final id in requires) {
      switch (id) {
        case SystemId.ntustSso:
          // 成績系統沒有自己的旗標：它底下零網路呼叫，靠的就是這一顆。
          ssoReady = false;
        case SystemId.moodleWebApi:
          // wsToken 就是 Moodle 的登入狀態，清掉它就等於登出。
          MoodleWebApiConnector.wsToken = null;
      }
    }
  }

  /// 確保 [requires] 都已登入；登入流程的唯一實作。
  @override
  Future<AuthError?> ensure(Set<SystemId> requires,
      {bool interactive = true}) async {
    for (final id in _ordered(requires)) {
      final error = await _ensureOne(id, interactive: interactive);
      if (error != null) return error;
    }
    return null;
  }

  /// 盡力而為：失敗不回報，也不讓例外逸出。
  @override
  Future<void> tryEnsure(SystemId id) async {
    try {
      await ensure({id});
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
    }
  }

  /// 兩者之間沒有相依，順序只影響「哪一個先花時間」。SSO 排前面是因為它
  /// 種下的 cookie 會讓 Moodle 的 launch.php 靜默通過（見 main_controller）。
  List<SystemId> _ordered(Set<SystemId> ids) => [
        if (ids.contains(SystemId.ntustSso)) SystemId.ntustSso,
        if (ids.contains(SystemId.moodleWebApi)) SystemId.moodleWebApi,
      ];

  /// 同一個系統正在進行中的登入。沒有這個的話冷啟動會並行開兩個登入 WebView，
  /// 學校那邊也收到兩次登入嘗試。static 是為了跨過測試替換 instance。
  static final Map<SystemId, Future<AuthError?>> inFlight = {};

  /// [interactive] 為 false 時不開進度框、不升級到可見的登入頁。安靜那次仍登記
  /// 進 [inFlight]，不會卡住：ssoReady 沒設起來，重試迴圈下一輪會重新 ensure。
  Future<AuthError?> _ensureOne(SystemId id, {required bool interactive}) {
    final running = inFlight[id];
    if (running != null) return running;

    final future = switch (id) {
      SystemId.ntustSso => _ensureNtustSso(interactive: interactive),
      SystemId.moodleWebApi => _ensureMoodle(interactive: interactive),
    };
    inFlight[id] = future;
    return future.whenComplete(() => inFlight.remove(id));
  }

  Future<AuthError?> _ensureNtustSso({required bool interactive}) async {
    if (ssoReady) return null;
    final repo = CredentialsStore.instance;
    if (!repo.hasCredentials) {
      return const AuthError(AuthFailure.notSignedIn);
    }

    // 進度框只包住非互動的那一段。互動式登入本身就是一個畫面，
    // 在它上面再蓋一層遮罩會讓使用者按不到 Turnstile。
    final handle = interactive
        ? TaskUiDelegate.instance.beginProgress(R.current.loginNTUST)
        : null;
    Map<String, dynamic> value;
    try {
      value = await NTUSTConnector.login(repo.account, repo.password);
    } finally {
      handle?.dismiss();
    }
    if (value["status"] == NTUSTLoginStatus.success) {
      ssoReady = true;
      return null;
    }
    // 有 message 代表站台明確拒絕了憑證，開可見登入頁也是同樣結果，
    // 而且會多燒一次登入嘗試。
    final message = value["message"] as String?;
    if (message != null) {
      return AuthError(AuthFailure.loginFailed, message: message);
    }

    // 安靜模式到此為止。headless 那一段已經試過了，再往下就是把一個
    // 使用者沒有要求的登入頁蓋在他正在看的畫面上。
    if (!interactive) return const AuthError(AuthFailure.loginFailed);

    final result = await InteractiveLoginGateway.instance
        .signInNtust(account: repo.account, password: repo.password);
    if (result?.status == NTUSTLoginStatus.success) {
      ssoReady = true;
      return null;
    }
    return AuthError(AuthFailure.loginFailed, message: result?.message);
  }

  Future<AuthError?> _ensureMoodle({required bool interactive}) async {
    if (MoodleWebApiConnector.wsToken != null) return null;
    final repo = CredentialsStore.instance;
    if (!repo.hasCredentials) {
      return const AuthError(AuthFailure.notSignedIn);
    }
    // Moodle 沒有非互動的登入段（一定要開 WebView），背景預載到此為止。
    // 帶訊息：預設的「請登入」跟有憑證者看到的「重新整理」鈕對不起來。
    if (!interactive) {
      return AuthError(AuthFailure.loginFailed,
          message: R.current.moodleNotSignedIn);
    }

    final handle =
        TaskUiDelegate.instance.beginProgress(R.current.loginMoodleWebApi);
    MoodleWebApiConnectorStatus value;
    try {
      value = await MoodleWebApiConnector.login(repo.account, repo.password);
    } finally {
      handle.dismiss();
    }
    if (value == MoodleWebApiConnectorStatus.loginSuccess) return null;
    return const AuthError(AuthFailure.loginFailed);
  }
}
