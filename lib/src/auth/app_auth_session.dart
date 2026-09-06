import 'dart:async';

import 'package:flutter/foundation.dart';

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

/// [AuthSession] 的正式實作。
///
/// 登入流程在這裡，而且只有這一份：`ensure` 是唯一會發起登入的入口，
/// `run()` 的 `requires` 是唯一宣告需求的方式。

class AppAuthSession implements AuthSession {
  AppAuthSession();

  /// SSO 這一趟握手完成了沒有。
  ///
  /// Moodle 那邊不需要對應的欄位：`MoodleWebApiConnector.wsToken` 本身就是
  /// 那個狀態，多一個布林只會多一種不一致。
  ///
  /// 公開是刻意的：測試要能設定「已經登入」這個前提，唯一的另一條路是真的
  /// 跑一次網路登入。
  bool ssoReady = false;

  /// 站台**明確拒絕**過的那一組帳密的指紋。
  ///
  /// 登入失敗時 [ssoReady] 仍是 false，而每一條 `run()` 都會各自再 `ensure`
  /// 一次（[inFlight] 只擋得住同時發生的），實測一次打錯密碼會送出 6 次登入，
  /// 而站台是「密碼錯誤 10 次鎖 15 分鐘」。
  ///
  /// 只在站台明確拒絕時記；網路失敗、Turnstile 逾時照常重試。刻意不由
  /// [invalidate] 清除，逃生口是改帳密或重開 App。
  @visibleForTesting
  int? rejectedCredentials;

  String? _rejectedMessage;

  /// 帳密的指紋，只用來偵測「有沒有改過帳密」，不是安全機制。
  static int credentialsFingerprint(String account, String password) =>
      Object.hash(account, password);

  @visibleForTesting
  void rejectCredentials(int fingerprint, String? message) {
    rejectedCredentials = fingerprint;
    _rejectedMessage = message;
  }

  void _clearRejection() {
    rejectedCredentials = null;
    _rejectedMessage = null;
  }

  /// 有沒有可用的憑證：帳號**與**密碼都非空。
  ///
  /// 只有帳號沒有密碼時，畫面會顯示「已登入」但任何一次登入都會失敗。
  @override
  bool get isSignedIn => CredentialsStore.instance.hasCredentials;

  /// [MoodleWebApiConnector.onApiError] 的處理器。由 `main.dart` 安裝。
  ///
  /// connector 刻意不在內部自動重登——[MoodleWebApiConnector.login] 會
  /// `Get.to` 一個 WebView 頁面，背景任務失敗時憑空彈出登入畫面比失敗本身
  /// 更糟——所以它只把錯誤從 `onApiError` 這條旁路送出來，由這裡決定怎麼做。
  ///
  /// **這個掛鉤一定要在啟動時裝上。** 沒裝的話 token 過期只會彈通用的重試
  /// 對話框，而重試會帶著同一顆死 token 再失敗一次。
  ///
  /// 這裡只做「作廢」，不做「重登」。清掉 token 之後 [SystemId.moodleWebApi]
  /// 的登入狀態就是 false，下一次 [ensure] 會走完整的登入流程。
  void onMoodleApiError(MoodleApiException error) {
    if (!error.isInvalidToken) return;
    // 九條讀取路徑可能同時失敗，清過就不要再清。
    if (MoodleWebApiConnector.wsToken == null) return;
    Log.d('[moodle] invalidtoken：作廢 token，下一次 ensure 會重登');
    // setter 會連 userId、siteInfo 與課程快取一起作廢。
    MoodleWebApiConnector.wsToken = null;
    // 磁碟上那一顆也要清。不清的話下一次冷啟動 main.dart 的 restoreToken
    // 會把同一顆死 token 撈回來，使用者要再撞一次 API 失敗才會重登。
    unawaited(MoodleSessionStore.instance.clear());
  }

  /// 讓 [requires] 的登入狀態失效，下次 [ensure] 會重登。
  ///
  /// **不需要展開相依。** 兩個系統之間零相依：`ntustSso` 與 `moodleWebApi`
  /// 是兩個獨立憑證，拿 wsToken 的過程會經過 ssoam2，但那是登入頁的 WebView
  /// 自己完成的。
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

  /// 確保 [requires] 都已登入。
  ///
  /// **這裡是登入流程的唯一實作。** 一個呼叫端可以一次宣告多個系統。
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
  ///
  /// 給「多個來源各自 try、誰掛了都不拖累別人」的情境用。
  @override
  Future<void> tryEnsure(SystemId id, {bool interactive = true}) async {
    try {
      await ensure({id}, interactive: interactive);
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

  /// 同一個系統正在進行中的登入。
  ///
  /// **沒有這個的話首次登入會跑兩次 SSO。** 冷啟動時課表與 Moodle 個人資料
  /// 並行，兩邊都會發現「還沒登入」然後各自開一個 WebView：使用者看到兩個
  /// 登入畫面接連跳出來，學校那邊收到兩次登入嘗試。
  ///
  /// static 而不是實例欄位：`AuthSession.instance` 在測試之間會被換掉，但
  /// 進行中的登入是 process 級的事實。`reset_statics` 會清掉它。
  static final Map<SystemId, Future<AuthError?>> inFlight = {};

  /// [interactive] 為 false 時：不開進度框、不升級到可見的登入頁。
  ///
  /// 安靜的那一次仍然登記進 [inFlight]，所以不會有兩次登入同時跑。代價是
  /// 緊接著來的互動式呼叫會跟著這一次的結果走。那不會卡住：`ssoReady` 沒被
  /// 設起來，`run()` 的重試迴圈下一輪會重新 ensure，那時就是互動式的了。
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

    // 已被站台拒絕過的帳密不再送出，見 [rejectedCredentials]。
    final fingerprint = credentialsFingerprint(repo.account, repo.password);
    if (rejectedCredentials == fingerprint) {
      Log.d('[sso] 這組帳密站台已明確拒絕，直接回報，不再燒登入嘗試');
      return AuthError(AuthFailure.loginFailed, message: _rejectedMessage);
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
      _clearRejection();
      return null;
    }
    // 有 message 代表站台明確拒絕，開可見登入頁也是同樣結果。記下來，
    // 後面每一條 run() 就不必再問一次。
    final message = value["message"] as String?;
    if (message != null) {
      rejectCredentials(fingerprint, message);
      return AuthError(AuthFailure.loginFailed, message: message);
    }

    // 安靜模式到此為止。headless 那一段已經試過了，再往下就是把一個
    // 使用者沒有要求的登入頁蓋在他正在看的畫面上。
    if (!interactive) return const AuthError(AuthFailure.loginFailed);

    final result = await InteractiveLoginGateway.instance
        .signInNtust(account: repo.account, password: repo.password);
    if (result?.status == NTUSTLoginStatus.success) {
      ssoReady = true;
      _clearRejection();
      return null;
    }
    // headless 那段可能是認不得頁面才升級上來的（沒有 message），真正讀到
    // 錯誤的是這一頁，同樣要記。
    if (result?.message != null) {
      rejectCredentials(fingerprint, result!.message);
    }
    return AuthError(AuthFailure.loginFailed, message: result?.message);
  }

  Future<AuthError?> _ensureMoodle({required bool interactive}) async {
    if (MoodleWebApiConnector.wsToken != null) return null;
    final repo = CredentialsStore.instance;
    if (!repo.hasCredentials) {
      return const AuthError(AuthFailure.notSignedIn);
    }

    // 共用同一份拒絕記錄：wsToken 也是走 ssoam2 換來的。只讀不寫——
    // MoodleWebApiConnectorStatus 分不出「帳密錯」與「使用者按了返回」。
    final fingerprint = credentialsFingerprint(repo.account, repo.password);
    if (rejectedCredentials == fingerprint) {
      Log.d('[moodle] 這組帳密站台已明確拒絕，不開登入頁');
      return AuthError(AuthFailure.loginFailed, message: _rejectedMessage);
    }

    // 安靜模式到此為止：Moodle 沒有 headless 路徑，拿 wsToken 唯一的方法就是
    // 開 LoginMoodlePage。少了這一行，背景預載會把登入頁蓋在課表上。
    if (!interactive) return const AuthError(AuthFailure.loginFailed);

    final handle =
        TaskUiDelegate.instance.beginProgress(R.current.loginMoodleWebApi);
    MoodleWebApiConnectorStatus value;
    try {
      value = await MoodleWebApiConnector.login(repo.account, repo.password);
    } finally {
      handle.dismiss();
    }
    if (value == MoodleWebApiConnectorStatus.loginSuccess) {
      _clearRejection();
      return null;
    }
    return const AuthError(AuthFailure.loginFailed);
  }

}
