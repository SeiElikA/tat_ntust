import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/core/connector_parameter.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/service/interactive_login_gateway.dart';
import 'package:flutter_app/src/model/moodle_token_entity.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_enrol_get_users.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_gradereport_get_grade_items.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_mod_forum_get_forum_discussions.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_profile_entity.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_setting_entity.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_app/src/util/html_utils.dart';

enum MoodleWebApiConnectorStatus { loginSuccess, loginFail }

/// Moodle 在 HTTP 200 底下回報的失敗。
///
/// Moodle 的 REST server 幾乎不用 HTTP 狀態碼表達錯誤：token 失效、function
/// 沒對這個 service 開放、參數不合法，一律是 200 加一包
/// `{"exception":..,"errorcode":..,"message":..}`；部分成功則是 `warnings[]`。
/// 而 `core/dio_connector.dart` 的 `validateStatus` 又放行到 500，所以這種
/// 回應連例外都不會拋，不主動判讀就會變成「無聲失敗」。
///
/// 這個例外是九條讀取路徑唯一的錯誤形狀：errorcode / exception / message
/// 都帶得出來，invalidtoken 的重登入直接掛在 [isInvalidToken] 上。
///
/// 刻意只保留這幾個具名欄位，不留整包 body：site_info 之類的回應帶 userid、
/// fullname 與 userprivateaccesskey，整包進 log 就是把它們寫進 logcat。
class MoodleApiException implements Exception {
  MoodleApiException({
    required this.wsFunction,
    this.errorcode,
    this.exception,
    this.message,
    this.debugInfo,
    this.siteFunctionVersion,
    this.skippedBeforeRequest = false,
  });

  /// 失敗的那一個 wsfunction 名稱。
  final String wsFunction;

  /// Moodle 的錯誤代碼，例如 `invalidtoken`、`accessexception`。
  /// 部分失敗（warnings[]）時是第一筆 warning 的 `warningcode`。
  final String? errorcode;

  /// Moodle 的例外類別名稱，例如 `moodle_exception`、`webservice_access_exception`。
  final String? exception;
  final String? message;

  /// 只有站台開了 debug 才會有；正式站通常是 null。
  final String? debugInfo;

  /// 站台回報的這個 function 的版本（site_info 的 `functions[].version`）。
  ///
  /// [MoodleProfileEntity.wsVersion] 的用途就在這裡：Moodle 會在新版加參數
  /// （例如 `core_enrol_get_users_courses` 的 `returnusercount` 是 3.7 才有），
  /// 舊站台收到會直接回 `invalidparameter`。把站台實際的版本一起記下來，
  /// log 才有辦法分辨「參數打錯」與「站台太舊」。
  final String? siteFunctionVersion;

  /// 這次是本地在送出前就擋下來的（[MoodleWebApiConnector.wsFunctionBlocked]），
  /// 不是伺服器回的。
  final bool skippedBeforeRequest;

  /// token 已經失效，重新登入才有救。
  ///
  /// 只認 `invalidtoken`：`accessexception` 是「這個 service 沒有這個
  /// function」，重登入不會變好，拿它去觸發重登入只會變成無限迴圈。
  bool get isInvalidToken => errorcode == 'invalidtoken';

  @override
  String toString() {
    final buffer = StringBuffer('MoodleApiException($wsFunction');
    if (skippedBeforeRequest) buffer.write(', skipped-before-request');
    if (errorcode != null) buffer.write(', errorcode: $errorcode');
    if (exception != null) buffer.write(', exception: $exception');
    if (message != null) buffer.write(', message: $message');
    if (debugInfo != null) buffer.write(', debuginfo: $debugInfo');
    if (siteFunctionVersion != null) {
      buffer.write(', siteFunctionVersion: $siteFunctionVersion');
    }
    buffer.write(')');
    return buffer.toString();
  }
}

class MoodleWebApiConnector {
  static const String host = "https://moodle2.ntust.edu.tw";
  static const String _webAPIUrl = "$host/webservice/rest/server.php";

  /// 站台資訊與可用 function 清單的來源。
  static const String siteInfoFunction = "core_webservice_get_site_info";

  /// 這個帳號的全部課程（含歷史學期）的來源。
  static const String enrolledCoursesFunction = "core_enrol_get_users_courses";

  /// 課程成績的來源。
  ///
  /// 不是 `gradereport_user_get_grades_table`：那一個回的是渲染好的 HTML
  /// 表格，欄位增減會讓呼叫端的 DOM 走訪靜靜地壞掉。這一個回結構化欄位。
  /// 站台實測（moodle2.ntust.edu.tw）site_info 的 functions[] 有列出它。
  static const String gradeItemsFunction = "gradereport_user_get_grade_items";

  /// 一次登入嘗試的 launch 網址與它所使用的 passport。
  ///
  /// passport 必須跟著回傳：Moodle 的 signature 是 `md5(wwwroot + passport)`
  /// （`admin/tool/mobile/launch.php`，純字串相接、沒有分隔符），驗證它才能
  /// 確定拿到的 token 真的來自我們剛才發出的那次請求。
  ///
  /// 亂數刻意比官方 App 強：官方是 `Math.random() * 1000`，這裡是 0 到 999999
  /// 的密碼學亂數。不要為了對齊官方而縮小值域或換成非密碼學亂數。
  static ({String url, String passport}) buildLoginLaunch() {
    final passport = Random.secure().nextInt(1000000).toString();
    return (
      url: "$host/admin/tool/mobile/launch.php"
          "?service=moodle_mobile_app&passport=$passport"
          "&urlscheme=moodlemobile&lang=zh_tw",
      passport: passport,
    );
  }

  /// 驗證 launch.php 回傳的 signature。
  ///
  /// 伺服器算的是 `md5($CFG->wwwroot . $passport)`。官方 App 在比對失敗時
  /// 會把 https 與 http 對調再算一次，因為使用者輸入的網址未必與站台設定的
  /// wwwroot 同一個 scheme；這裡照做。
  static bool verifyLoginSignature(String signature, String passport) {
    for (final base in [host, host.replaceFirst('https://', 'http://')]) {
      final expected = md5.convert(utf8.encode('$base$passport')).toString();
      if (expected == signature) return true;
    }
    return false;
  }

  static String? _wsToken;

  /// process 內的 token 快取。持久化由 [MoodleSessionStore] 負責，
  /// 登出時兩邊都必須清，由 SessionCleaner 統一處理。
  static String? get wsToken => _wsToken;

  /// 換 token 就等於換身分，所有跟著這個 token 來的快取都要作廢。
  ///
  /// 清除掛在 setter 上而不是各個呼叫端，是因為會改 token 的地方有三處
  /// （[login]、[restoreToken]、SessionCleaner），漏掉任何一個就是跨帳號
  /// 洩漏：[userId] 會拿去查別人的成績，[siteInfo] 會用別人的 function
  /// 清單去擋這個帳號的請求。SessionCleaner 另外還會再清一次 userId，
  /// 那是它的職責，重複清沒有壞處。
  static set wsToken(String? value) {
    if (_wsToken != value) {
      userId = null;
      siteInfo = null;
      _usersCoursesCache = null;
    }
    _wsToken = value;
  }

  /// 最近一次 site_info 的解析結果，也就是這個 token 的可用 function 清單。
  ///
  /// 由 [isMoodleTokenAvailable]、[_ensureUserId] 與 [getProfile] 順手填上——
  /// 這三個本來就會打 site_info，不會多一次網路往返。connector 自己留一份而
  /// 不是反向去 `Get.find<MainController>()` 拿 `MainController.profile`：
  /// connector 不該依賴 controller 層，而且這些方法全是 static，沒有可以
  /// 注入的地方。
  ///
  /// 換 token 時由 [wsToken] 的 setter 清掉。
  static MoodleProfileEntity? siteInfo;

  /// 呼叫端觀察 API 失敗的出口。
  ///
  /// 九個讀取路徑對外一律是「失敗回 null」（十幾個呼叫端都靠這個契約），
  /// 所以錯誤細節走這條旁路送出去：AuthSession 在啟動時裝一個
  /// `onApiError = (e) { if (e.isInvalidToken) ... }` 就能接上重新登入。
  ///
  /// 這裡刻意不在 connector 內部自動重登入：[login] 會 `Get.to` 一個
  /// WebView 頁面，背景任務失敗時憑空彈出登入畫面比失敗本身更糟。
  static void Function(MoodleApiException error)? onApiError;

  /// tokenpluginfile.php 這條路徑在這個站台通不通。null 代表還沒探測出結果。
  ///
  /// 舊路徑 `webservice/pluginfile.php?token=<wsToken>` 會把長效憑證放進
  /// 圖片的 src、WebView 的歷史紀錄與任何轉址的 Referer。官方 App 優先走
  /// `tokenpluginfile.php/<userprivateaccesskey>/…`，那把鑰匙是 site_info 的
  /// `userprivateaccesskey`（不是 wsToken），只能拿檔案、不能呼叫 web service。
  ///
  /// 但站台可以停用 tokenpluginfile.php，硬切過去會讓所有附件都打不開，
  /// 所以跟官方 App 一樣在執行期實際探測一次並記住結果。這是站台層級的性質，
  /// 換 token 不會改變，所以刻意不掛在 [wsToken] 的 setter 上一起清。
  static bool? tokenPluginFileWorks;

  static Future<void>? _tokenPluginFileProbing;

  /// 進行中的探測。測試用來等它結束——正式流程不需要 await，
  /// [fileUrlWithToken] 是同步的，探測完成之前一律先給舊路徑。
  static Future<void>? get tokenPluginFileProbe => _tokenPluginFileProbing;

  /// 探測的實作。抽成可替換的欄位，測試才不必真的連網路。
  static Future<bool> Function(String url) tokenPluginFileProber =
      _headTokenPluginFile;

  /// 把探測狀態清回「還沒探測」。測試用。
  static void resetTokenPluginFileProbe() {
    tokenPluginFileWorks = null;
    _tokenPluginFileProbing = null;
  }

  /// `<前綴>[/webservice]/pluginfile.php` 這一段。
  static final RegExp _pluginFileSegment =
      RegExp(r'(/webservice)?/pluginfile\.php');

  /// 把 pluginfile 網址改寫成 tokenpluginfile 網址。不能改寫時回 null。
  ///
  /// 規則跟官方 App 的 `CoreUrl.fixPluginfileURL` 一樣，就是把路徑裡的
  /// `[/webservice]/pluginfile.php` 換成 `/tokenpluginfile.php/<accessKey>`，
  /// query 原封不動帶著走（`forcedownload=1` 之類必須留著）。
  static String? tokenPluginFileUrl(String fileUrl) {
    final accessKey = siteInfo?.userprivateaccesskey ?? "";
    if (accessKey.isEmpty) return null;

    // 只動 '?' 前面那一段。query 裡也可能出現 pluginfile.php（有些模組會把
    // 來源網址整條塞進參數），那不是我們要換掉的東西。
    final queryAt = fileUrl.indexOf('?');
    final path = queryAt < 0 ? fileUrl : fileUrl.substring(0, queryAt);
    final query = queryAt < 0 ? "" : fileUrl.substring(queryAt);
    // 已經帶著 token 的網址不改寫：tokenpluginfile 不吃 wsToken，改寫只會
    // 生出一個兩種憑證都在的怪網址，token 照樣外流。
    if (query.contains("token=")) return null;

    final match = _pluginFileSegment.firstMatch(path);
    if (match == null) return null;
    return "${path.substring(0, match.start)}"
        "/tokenpluginfile.php/$accessKey"
        "${path.substring(match.end)}$query";
  }

  /// 探測 tokenpluginfile 到底能不能用。
  ///
  /// 只讀回應標頭、不下載內容（`getHeadersByGet` 用 stream 的 responseType），
  /// 是這個專案裡最接近官方 App 那一次 HEAD 的做法：附件可能是幾十 MB 的 PDF，
  /// 為了探測整包抓下來不划算。非 200 會拋，交給呼叫端當成「不支援」。
  static Future<bool> _headTokenPluginFile(String url) async {
    await DioConnector.instance.getHeadersByGet(ConnectorParameter(url));
    return true;
  }

  static Future<void> _probeTokenPluginFile(String probeUrl) {
    final running = _tokenPluginFileProbing;
    if (running != null) return running;
    return _tokenPluginFileProbing = () async {
      try {
        tokenPluginFileWorks = await tokenPluginFileProber(probeUrl);
      } catch (e) {
        // 探測失敗（站台停用、斷網、逾時）一律當成不支援。走舊路徑最多是
        // 多帶一次 token，切過去卻打不開則是每一個附件都開不了；這個 process
        // 之後不再重試，重開 App 才會重探。
        tokenPluginFileWorks = false;
        Log.e("tokenpluginfile probe failed: $e");
      }
    }();
  }

  /// 產生可以直接取用的 Moodle 檔案網址。
  ///
  /// host 不是自家的就原樣回傳，不附任何憑證。fileurl 是伺服器回傳的內容，
  /// 一旦哪天多一個會帶外部網址的模組，長效的 wsToken 就會被主動送到
  /// 對方伺服器的 access log。官方 Moodle App 也有做同樣的檢查。這個檢查
  /// 擋在兩條路徑的前面，所以對 tokenpluginfile 一樣有效。
  ///
  /// 站台支援 tokenpluginfile 時走那條（憑證在路徑上、而且是只能取檔案的
  /// accessKey）；accessKey 為空、還沒探測完、或探測失敗，一律安全地退回
  /// 舊的 `?token=`。
  static String fileUrlWithToken(String fileUrl) {
    final token = wsToken;
    if (token == null) return fileUrl;
    final uri = Uri.tryParse(fileUrl);
    if (uri == null || uri.host != Uri.parse(host).host) {
      Log.e("refuse to attach token to a foreign host: ${uri?.host}");
      return fileUrl;
    }

    final tokenUrl = tokenPluginFileUrl(fileUrl);
    if (tokenUrl != null) {
      if (tokenPluginFileWorks == true) return tokenUrl;
      // 還沒探測過就順手拿這個真實網址探一次（官方 App 也是拿正在改寫的那個
      // 網址去 HEAD）。這一次呼叫仍然回舊路徑：探測是非同步的，而這個方法
      // 會在 build() 裡被呼叫，等不了。
      if (tokenPluginFileWorks == null) {
        unawaited(_probeTokenPluginFile(tokenUrl));
      }
    }
    return Connector.uriAddQuery(fileUrl, {"token": token});
  }

  /// 從本機還原先前存下的 token。由 main.dart 在啟動時呼叫。
  ///
  /// 這個入口的存在是為了讓 store 層不必反向 import connector。
  ///
  /// **還原回來的 token 是 assumed 而不是 verified**：它只代表磁碟上存過
  /// 一顆，伺服器端可能早就讓它失效了。帶著它發的第一個請求收到
  /// invalidtoken 時，`onApiError` 會把它清掉並重登。
  static void restoreToken(MoodleTokenEntity token) {
    wsToken = token.token;
  }

  /// Moodle 的使用者 id，從 core_webservice_get_site_info 取得。
  ///
  /// 啟動時的 isMoodleTokenAvailable 就會拿到同一份回應，順手記下來，
  /// getCourseUrl 與 getScore 才不必各自再打一次 site_info。
  ///
  /// 這是 process 級的 static，**換帳號時必須清掉**，否則就是又一個
  /// 跨帳號洩漏。清除由 [wsToken] 的 setter 與 SessionCleaner 一起把關。
  static String? userId;

  /// 「HTTP 200 但其實是錯誤」的唯一判讀點。回傳 null 代表這包回應是正常的。
  ///
  /// 集中在這裡，才不會每加一個 getter 就要重抄一次同樣的檢查。判斷條件
  /// 跟著 Moodle 的 `webservice/lib.php`：失敗一定帶 `exception`，
  /// 通常也帶 `errorcode`。
  ///
  /// [treatWarningsAsError] 預設 false。`warnings[]` 在讀取路徑上是常態
  /// （例如某些單元沒有權限看就會附一筆），把它當成失敗會讓原本能用的頁面
  /// 整頁消失；只有寫入路徑（[toggleSetting]）才需要「有 warning 就算沒寫成功」。
  static MoodleApiException? moodleErrorOf(
    dynamic data, {
    required String wsFunction,
    bool treatWarningsAsError = false,
  }) {
    // 不是 Map 就不是 Moodle 的錯誤包。captive portal 回的 HTML、正常的
    // List 回應都走這裡；它們是不是合法留給呼叫端自己的轉型去判斷。
    if (data is! Map) return null;

    if (data.containsKey("errorcode") || data.containsKey("exception")) {
      return MoodleApiException(
        wsFunction: wsFunction,
        errorcode: data["errorcode"]?.toString(),
        exception: data["exception"]?.toString(),
        message: data["message"]?.toString(),
        debugInfo: data["debuginfo"]?.toString(),
        siteFunctionVersion: siteInfo?.wsVersion(wsFunction),
      );
    }

    if (treatWarningsAsError) {
      final warnings = data["warnings"];
      if (warnings is List && warnings.isNotEmpty) {
        final first = warnings.first;
        return MoodleApiException(
          wsFunction: wsFunction,
          errorcode: first is Map ? first["warningcode"]?.toString() : null,
          message:
              first is Map ? first["message"]?.toString() : first.toString(),
          siteFunctionVersion: siteInfo?.wsVersion(wsFunction),
        );
      }
    }

    return null;
  }

  /// 這次呼叫要不要在送出前就放棄。回傳 null 代表可以送。
  ///
  /// site_info 的 `functions[]` 就是站台回報給這個 token 的可用清單。不在
  /// 清單裡的 function，Moodle 一定回 `accessexception`，所以這裡的跳過與
  /// 「送出去必定失敗」等價，只是省下一次網路往返，而且用同一個 errorcode
  /// 讓呼叫端不必分辨是誰擋的。
  ///
  /// **[siteInfo] 還沒載入時一律放行**（fail-open）。App 剛啟動、或 getProfile
  /// 自己失敗時清單就是空的，把「還不知道」當成「站台沒開放」會讓整個功能
  /// 無聲消失，那比多打一次註定失敗的請求嚴重得多。同理，清單解析出來是空的
  /// （站台沒送 functions）也一律放行。
  static MoodleApiException? wsFunctionBlocked(String wsFunction) {
    // site_info 是清單本身的來源，擋掉它等於再也拿不到清單，是死結。
    if (wsFunction == siteInfoFunction) return null;

    final profile = siteInfo;
    if (profile == null || !profile.knowsWsFunctions) return null;
    if (profile.wsAvailable(wsFunction)) return null;

    return MoodleApiException(
      wsFunction: wsFunction,
      errorcode: "accessexception",
      message: "站台未對這個 token 開放 $wsFunction"
          "（site_info 的 functions[] 沒有列出），已在送出前跳過",
      skippedBeforeRequest: true,
    );
  }

  /// 送出一次 web service 呼叫。
  ///
  /// 所有 wsfunction 都經過這裡，於是「送出前檢查可用性」與「200 但其實是
  /// 錯誤」各只有一份實作，要加 invalidtoken 重試也只有這一個掛點。
  /// 失敗一律拋 [MoodleApiException]，由各 getter 決定要記什麼、回什麼。
  static Future<dynamic> _callWs(
    String wsFunction,
    Map<String, dynamic> data, {
    bool treatWarningsAsError = false,
  }) async {
    final blocked = wsFunctionBlocked(wsFunction);
    if (blocked != null) throw blocked;

    final parameter = ConnectorParameter(_webAPIUrl);
    parameter.data = {
      "moodlewsrestformat": "json",
      "wsfunction": wsFunction,
      "wstoken": wsToken,
      ...data,
    };
    final result = await Connector.getJsonByPost(parameter);
    final error = moodleErrorOf(
      result,
      wsFunction: wsFunction,
      treatWarningsAsError: treatWarningsAsError,
    );
    if (error != null) throw error;
    return result;
  }

  /// 九個 catch 共用的收尾：記 log，並把伺服器說的錯誤送給 [onApiError]。
  ///
  /// [MoodleApiException] 用 [Log.e] 而不是 [Log.eWithStack]：stack 是我們
  /// 自己 throw 的位置，沒有任何診斷價值，而 eWithStack 會一路送進
  /// Crashlytics——token 過期、站台維護這種每個人都會遇到的伺服器回應
  /// 不該被當成當機回報。真正的例外（轉型失敗、斷網）才用 eWithStack。
  static void _reportFailure(String wsFunction, Object e, StackTrace stack) {
    if (e is MoodleApiException) {
      Log.e(e.toString());
      onApiError?.call(e);
      return;
    }
    Log.eWithStack("$wsFunction: $e", stack);
  }

  /// 把 site_info 的回應存成 [siteInfo]。解析失敗只是這次快取不到。
  ///
  /// 這裡吞掉例外是刻意的：呼叫端（例如 [isMoodleTokenAvailable]）判斷的是
  /// 「token 還能不能用」，不該因為多做的這一步而變成 false。
  static void _cacheSiteInfo(dynamic data) {
    if (data is! Map) return;
    try {
      siteInfo = MoodleProfileEntity.fromJson(Map<String, dynamic>.from(data));
    } catch (e, stack) {
      Log.eWithStack("cache site info: $e", stack);
    }
  }

  /// 取得 userId，需要時才打 site_info。
  ///
  /// 失敗時回 null 或拋 [MoodleApiException]（例如 token 失效），兩者都由
  /// 呼叫端的 try/catch 處理。
  static Future<String?> _ensureUserId() async {
    final cached = userId;
    if (cached != null) return cached;
    final result = await _callWs(siteInfoFunction, const {});
    if (result is! Map || result["userid"] == null) {
      // 不要無聲失敗：這裡回 null 之後 getCourseUrl 與 getScore 也會跟著
      // 回 null，錯誤原因就整條線消失了。
      _reportFailure(
        siteInfoFunction,
        MoodleApiException(
          wsFunction: siteInfoFunction,
          message: 'site_info 回應裡沒有 userid',
        ),
        StackTrace.current,
      );
      return null;
    }
    _cacheSiteInfo(result);
    return userId = result["userid"].toString();
  }

  static Future<MoodleWebApiConnectorStatus> login(
      String account, String password) async {
    try {
      final tokenData = await InteractiveLoginGateway.instance
          .signInMoodle(account: account, password: password);
      if (tokenData == null) {
        return MoodleWebApiConnectorStatus.loginFail;
      }

      wsToken = tokenData.token;

      await Model.instance.setMoodleToken(tokenData);

      return MoodleWebApiConnectorStatus.loginSuccess;
    } catch (e, stack) {
      Log.eWithStack(e, stack);
    }

    return MoodleWebApiConnectorStatus.loginFail;
  }

  /// 檢查本機的 wsToken 在伺服器端是否仍然有效。
  ///
  /// 這個方法在 App 啟動路徑上（MainController.onInit），任何例外逸出都會讓
  /// 主畫面永遠停在載入中，所以這裡一律吞掉例外回 false，由呼叫端決定
  /// 要不要重新登入。斷網、逾時、captive portal 回傳 HTML 都走這條。
  static Future<bool> isMoodleTokenAvailable() async {
    if (wsToken == null) {
      return false;
    }

    try {
      // errorcode（token 失效、站台維護）由 _callWs 統一攔下來變成例外，
      // 這裡不必再檢查一次。不要印 result：site_info 帶 userid、fullname
      // 與 userprivateaccesskey。
      final result = await _callWs(siteInfoFunction, const {});
      // 不要硬轉型：captive portal 會回 200 加一段 HTML，轉型會拋 TypeError。
      if (result is! Map) return false;
      // 順手把 userid 與 function 清單記下來。這是啟動時本來就會打的一次
      // site_info，之後的成績頁、課程對照與可用性檢查都不必再各打一次。
      if (result["userid"] != null) userId = result["userid"].toString();
      _cacheSiteInfo(result);
      return true;
    } catch (e, stack) {
      _reportFailure(siteInfoFunction, e, stack);
      return false;
    }
  }

  /// 課程的 Moodle 內部 id。缺席時回 null，**不要**用
  /// `course["id"].toString()`——那會產生字面上的字串 "null"，被上層當成
  /// 有效的 findId 快取起來，之後每一次載入都拿這個假 id 去問伺服器。
  static String? _courseKeyOf(Map course) {
    final id = course["id"];
    if (id == null) return null;
    return id.toString();
  }

  /// [_getUsersCourses] 的短期記憶。
  ///
  /// 課號對照、某學期的課號清單、目前學期三者會在同一次課表更新裡接連呼叫，
  /// 沒有這個 memo 就是同一份 50 門課的回應抓三次。登出時由 SessionCleaner
  /// 連同 wsToken 一起清掉（見 wsToken 的 setter）。
  static List<dynamic>? _usersCoursesCache;

  /// 清掉課程清單的短期記憶。
  ///
  /// wsToken 的 setter 只在「值真的改變」時清，所以已經是 null 的情況
  /// （測試之間、重複登出）不會觸發。登出與測試重設都要明確呼叫這個。
  static void clearCoursesCache() => _usersCoursesCache = null;

  /// 一次拿回這個帳號的全部課程（含已結束的歷史學期）。
  ///
  /// 課號對照、某學期的課號清單、目前學期三件事共用這一次往返：實測這個
  /// function 一次回 50 門課，每一門都帶 `idnumber`、`startdate`、`enddate`。
  ///
  /// 拿不到 userid 時回 null（[_ensureUserId] 已經記過 log）；其他失敗照常拋。
  static Future<List<dynamic>?> _getUsersCourses({bool refresh = false}) async {
    if (!refresh && _usersCoursesCache != null) return _usersCoursesCache;
    final uid = await _ensureUserId();
    if (uid == null) return null;

    final result = await _callWs(enrolledCoursesFunction, {
      "moodlewssettingfilter": "true",
      "moodlewssettingfileurl": "true",
      "userid": uid,
      // Moodle 3.7 起支援。官方文件說在選課人數多的課程上，算這個統計
      // 可能多花好幾秒，而這裡完全用不到它。官方 App 也一律送 false。
      "returnusercount": "0",
    });
    return _usersCoursesCache = result as List;
  }

  /// idnumber 的前綴長度：`<學年3碼><學期1碼>`（例如 1141、114H）。
  /// 實測 50 門課的 idnumber 長度都是 13、全部非空。
  static const int semesterPrefixLength = 4;

  /// 去掉學年學期前綴之後的課號。長度不夠時回 null。
  static String? _courseIdOf(String idnumber) =>
      idnumber.length > semesterPrefixLength
          ? idnumber.substring(semesterPrefixLength)
          : null;

  /// 在課程清單裡找出 [courseId] 對應的 Moodle 內部課程 id。找不到回 null。
  ///
  /// **以 idnumber 為準**：那才是放課號的欄位（[courseIdsOfSemester] 用的也是
  /// 它）。拿 fullname 比對，只要別門課的課名裡剛好含有這個課號就會配到錯的
  /// 課、開出別人的成績與名單，所以它只留作 fallback——實測 50 門課的
  /// idnumber 全部非空，但 Moodle 規格上 idnumber 是選填。
  static String? matchCourseId(List<dynamic> courses, String courseId) {
    if (courseId.isEmpty) return null;
    for (final course in courses) {
      if (course is! Map) continue;
      final idnumber = course["idnumber"];
      if (idnumber is! String || idnumber.isEmpty) continue;
      if (idnumber == courseId || _courseIdOf(idnumber) == courseId) {
        final id = _courseKeyOf(course);
        if (id != null) return id;
      }
    }
    for (final course in courses) {
      if (course is! Map) continue;
      final fullname = course["fullname"];
      if (fullname is String && fullname.contains(courseId)) {
        final id = _courseKeyOf(course);
        if (id != null) return id;
      }
    }
    return null;
  }

  static Future<String?> getCourseUrl(String courseId) async {
    try {
      final courses = await _getUsersCourses();
      if (courses == null) return null;
      return matchCourseId(courses, courseId);
    } catch (e, stack) {
      // 這裡不能吞掉錯誤：使用者只會看到「不支援這門課」，log 裡查不到原因。
      _reportFailure(enrolledCoursesFunction, e, stack);
      return null;
    }
  }

  /// 取得課程目錄。
  ///
  /// [modName] 有值時只回傳該種模組（Moodle 的 `options[modname]`）。
  /// `core_course_get_contents` 會把整門課的所有單元、所有檔案與其中繼資料
  /// 一次送回來，是這套 API 裡最重的呼叫；只要找特定模組時務必收窄範圍。
  /// 官方 App 的做法相同，甚至會直接送 `cmid` 只取一個模組。
  static Future<List<MoodleCoreCourseGetContents>?> getCourseDirectory(
      String courseId,
      {String? modName}) async {
    const wsFunction = "core_course_get_contents";
    try {
      final result = await _callWs(wsFunction, {
        "moodlewssettingfilter": "true",
        "moodlewssettingfileurl": "true",
        "courseid": courseId,
        if (modName != null) ...{
          "options[0][name]": "modname",
          "options[0][value]": modName,
        },
      });
      List<MoodleCoreCourseGetContents> v = (result as List)
          .map((e) => MoodleCoreCourseGetContents.fromJson(e))
          .toList();
      for (var i in v) {
        for (var j in i.modules) {
          j.name = HtmlUtils.clean(j.name);
        }
      }
      return v;
    } catch (e, stack) {
      _reportFailure(wsFunction, e, stack);
      return null;
    }
  }

  static Future<MoodleModForumGetForumDiscussions?> getCourseAnnouncement(
      String id) async {
    const wsFunction = "mod_forum_get_forum_discussions";
    try {
      // 只要討論區：為了一個 forum 的 instance id 去抓整門課的內容太重，
      // 而且「課程目錄」分頁同一次瀏覽還會再抓一次同樣的內容。
      List<MoodleCoreCourseGetContents>? v =
          await getCourseDirectory(id, modName: "forum");
      if (v == null) {
        throw Exception("List<MoodleCoreCourseGetContents> is null");
      }
      String? forumId;
      for (var i in v) {
        if (i.name.contains("一般")) {
          for (var j in i.modules) {
            // 公告後來改名成「課程公佈欄」，兩種名稱都要認。
            if (j.name.contains("公告") || j.name.contains("課程公佈欄")) {
              forumId = j.instance.toString();
              break;
            }
          }
        }
        if (forumId != null) {
          break;
        }
      }
      if (forumId == null) {
        throw Exception("forumId is null");
      }

      final result = await _callWs(wsFunction, {
        "moodlewssettingfilter": "true",
        "moodlewssettingfileurl": "true",
        "forumid": forumId,
        "page": 0,
        "perpage": 100,
        "sortorder": 1,
        "groupid": 0,
      });
      return MoodleModForumGetForumDiscussions.fromJson(
          result as Map<String, dynamic>);
    } catch (e, stack) {
      _reportFailure(wsFunction, e, stack);
      return null;
    }
  }

  /// Moodle 內建的「這門課的老師」角色 shortname。
  ///
  /// Moodle 的 archetype 裡 editingteacher 是授課老師、teacher 是不能編輯的
  /// 老師／助教。manager、coursecreator 是站台層級的管理角色，不是這門課的
  /// 老師，刻意不列進來——這份名單的用途是找同學，寧可多顯示一個人，
  /// 也不要把真的同學藏起來。
  static const Set<String> teacherRoleShortNames = {
    'editingteacher',
    'teacher',
  };

  /// 這個人要不要留在「修課同學」名單裡。
  ///
  /// 以 roles 判斷，不要退回比對名字裡有沒有「老師」：那會藏掉名字裡剛好
  /// 有這兩個字的同學，也留下名字裡沒有的老師。
  ///
  /// **roles 為空時回 true（顯示）**。roles 拿不拿得到取決於權限，實測學生
  /// token 拿得到但規格沒有保證；拿不到時若反過來全部藏起來，名單會變成空的
  /// 而上層對空名單是直接報錯。保守的方向是多顯示，不是全部消失。
  static bool isCourseMember(MoodleCoreEnrolGetUsers user) {
    if (user.roles.isEmpty) return true;
    return !user.roles
        .any((role) => teacherRoleShortNames.contains(role.shortname));
  }

  static Future<List<MoodleCoreEnrolGetUsers>?> getMember(String id) async {
    const wsFunction = "core_enrol_get_enrolled_users";
    List<MoodleCoreEnrolGetUsers> userinfo = [];
    try {
      final result = await _callWs(wsFunction, {
        "moodlewssettingfilter": "true",
        "moodlewssettingfileurl": "true",
        "courseid": id,
        "options[0][name]": "limitfrom",
        "options[0][value]": "0",
        "options[1][name]": "limitnumber",
        "options[1][value]": "0",
        "options[2][name]": "sortby",
        "options[2][value]": "siteorder",
      });
      for (var i in (result as List)) {
        var user = MoodleCoreEnrolGetUsers.fromJson(i as Map<String, dynamic>);
        if (isCourseMember(user)) userinfo.add(user);
      }
      return userinfo;
    } catch (e, stack) {
      _reportFailure(wsFunction, e, stack);
      return null;
    }
  }

  /// 從 Moodle 取得某學期的課號清單。失敗回 null。
  ///
  /// 這裡刻意不回空清單代表失敗：空清單會被上游當成「這學期真的沒有課」，
  /// 組出一張零課程的課表並覆蓋掉磁碟上原本正確的快取。所以「抓取失敗」
  /// 一律是 null，空清單只代表這學期真的一門 Moodle 課都沒有，兩者不能混。
  ///
  /// 資料來源是 `core_enrol_get_users_courses` 加本機過濾，歷史學期才撈得到。
  /// 不要換成 timeline classification 端點：它只回 `inprogress`，過去的學期
  /// 根本不在回應裡，結果會是把當前學期的課號當成歷史學期的課表回傳。
  static Future<List<String>?> getCourseIds(SemesterJson semester) async {
    try {
      final courses = await _getUsersCourses();
      if (courses == null) return null;
      return courseIdsOfSemester(courses, semester);
    } catch (e, stack) {
      _reportFailure(enrolledCoursesFunction, e, stack);
      return null;
    }
  }

  /// 從全部課程裡挑出屬於 [semester] 的課號（去掉學年學期前綴）。
  ///
  /// 官方 Moodle App 也是這樣做的：它只有在 classification 是 customfield
  /// 時才會去打 timeline 那個端點。
  static List<String> courseIdsOfSemester(
      List<dynamic> courses, SemesterJson semester) {
    final prefix = "${semester.year}${semester.semester}";
    // 前綴長度不對就代表這個 SemesterJson 根本不是 <學年3碼><學期1碼>，
    // 硬比會把整份清單都配上去。回空清單，交給上游當成沒有課。
    if (prefix.length != semesterPrefixLength) return [];

    final ids = <String>[];
    for (final course in courses) {
      if (course is! Map) continue;
      final idnumber = course["idnumber"];
      if (idnumber is! String || !idnumber.startsWith(prefix)) continue;
      final courseId = _courseIdOf(idnumber);
      if (courseId != null && courseId.isNotEmpty) ids.add(courseId);
    }
    return ids;
  }

  /// 沒有 token 就先登入一次。
  ///
  /// **它與這個檔案自己的政策矛盾。** [onApiError] 的說明寫著「刻意不在
  /// connector 內部自動重登入：login 會開一個 WebView 頁面，背景任務失敗時
  /// 憑空彈出登入畫面比失敗本身更糟」——而這裡做的正是那件事。
  ///
  /// 集中成一處是為了讓那個矛盾只有一個位置可以修。真正的解法是讓呼叫端用
  /// `AuthSession.tryEnsure` 決定要不要登入，但那會改變「什麼時候會彈出
  /// 登入畫面」，需要實機驗證。
  static Future<void> _ensureToken() async {
    if (wsToken != null) return;
    await login(Model.instance.getAccount(), Model.instance.getPassword());
  }

  static Future<SemesterJson?> getCurrentSemester() async {
    await _ensureToken();
    try {
      final courses = await _getUsersCourses();
      if (courses == null) return null;
      return currentSemesterOf(courses);
    } catch (e, stack) {
      _reportFailure(enrolledCoursesFunction, e, stack);
      return null;
    }
  }

  /// 從全部課程推出「目前學期」。推不出來回 null。
  ///
  /// 清單裡含歷史學期，所以自己判斷：先照 Moodle 對 inprogress 的定義
  /// （startdate 已到，且 enddate 是 0 或還沒到）挑出進行中的課，取其中最新
  /// 的學期；學期之間的空檔可能一門進行中的課都沒有，那就退回清單裡最新的
  /// 那個學期，而不是回 null。
  static SemesterJson? currentSemesterOf(List<dynamic> courses,
      {DateTime? now}) {
    // Moodle 的 startdate / enddate 是 Unix 秒。
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    String? inProgress;
    String? latest;

    for (final course in courses) {
      if (course is! Map) continue;
      final idnumber = course["idnumber"];
      if (idnumber is! String || idnumber.length <= semesterPrefixLength) {
        continue;
      }
      final prefix = idnumber.substring(0, semesterPrefixLength);
      if (_isLaterSemester(latest, prefix)) latest = prefix;

      final start = _asUnixSeconds(course["startdate"]);
      final end = _asUnixSeconds(course["enddate"]);
      // 沒有 startdate 就不當成「還沒開始」；enddate 是 0 是 Moodle 表示
      // 「沒有結束日」的方式。
      final started = start == null || start <= at;
      final ended = end != null && end != 0 && end <= at;
      if (started && !ended && _isLaterSemester(inProgress, prefix)) {
        inProgress = prefix;
      }
    }

    final picked = inProgress ?? latest;
    if (picked == null) return null;
    return SemesterJson(
      year: picked.substring(0, semesterPrefixLength - 1),
      semester: picked.substring(semesterPrefixLength - 1),
    );
  }

  /// `<學年><學期>` 前綴誰比較新。
  ///
  /// 直接比字串：學年固定 3 碼且補零（"099" < "100"），學期是 1、2、H，
  /// 而 '1' < '2' < 'H' 剛好就是上學期、下學期、暑期的先後。
  static bool _isLaterSemester(String? current, String candidate) =>
      current == null || candidate.compareTo(current) > 0;

  static int? _asUnixSeconds(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse("$value");
  }

  /// 一門課的成績項目。抓不到回 null（呼叫端會顯示錯誤頁）。
  ///
  /// 帶 `userid` 呼叫，所以 `usergrades` 只會有自己那一筆，這裡直接把它剝出來
  /// 給快取與畫面用。`moodlewssettingfileurl` 要留著：回饋欄位裡的 `<img>`
  /// 需要 Moodle 幫忙把 pluginfile 換成可以帶 token 取用的網址。
  static Future<MoodleUserGradesEntity?> getScore(String id) async {
    try {
      final uid = await _ensureUserId();
      if (uid == null) return null;

      final result = await _callWs(gradeItemsFunction, {
        "moodlewssettingfilter": "true",
        "moodlewssettingfileurl": "true",
        "courseid": id,
        "userid": uid,
      });
      final grades = userGradesOf(result);
      if (grades == null) {
        // 不要無聲成功。usergrades 是空的代表這門課對這個 token 沒有成績可看
        // （課號對錯人、或站台沒開放），回一個 gradeItems 為空的物件會讓畫面
        // 顯示一片空白的「成功」，而且那個空物件還會被寫進快取。
        _reportFailure(
          gradeItemsFunction,
          MoodleApiException(
            wsFunction: gradeItemsFunction,
            message: '回應裡沒有 usergrades',
          ),
          StackTrace.current,
        );
        return null;
      }
      return grades;
    } catch (e, stack) {
      _reportFailure(gradeItemsFunction, e, stack);
      return null;
    }
  }

  /// 從 `gradereport_user_get_grade_items` 的回應剝出第一筆 usergrades。
  ///
  /// 形狀不對就回 null，而不是讓 `result["usergrades"][0]` 拋 TypeError 之後
  /// 被 catch 吞成「抓不到」。
  ///
  /// 與 moodleErrorOf / matchCourseId / currentSemesterOf 一樣是公開的純函式：
  /// 九個 getter 走 static 的 Connector.getJsonByPost，沒有注入假回應的地方，
  /// 所以「怎麼判讀」一律抽成公開純函式單獨測。
  static MoodleUserGradesEntity? userGradesOf(dynamic result) {
    if (result is! Map) return null;
    final entity =
        MoodleGradeItemsEntity.fromJson(Map<String, dynamic>.from(result));
    if (entity.userGrades.isEmpty) return null;
    return entity.userGrades.first;
  }

  static Future<MoodleProfileEntity?> getProfile() async {
    try {
      // 這個 fromJson 之前一定要先判錯：MoodleProfileEntity 每個欄位都有
      // JsonKey.defaultValue，把 {"errorcode": "invalidtoken", ...} 丟進去
      // 不會拋，會得到一個欄位全空、看起來完全合法的物件——呼叫端當成
      // 「成功」，而這份空 profile 還會被存進 siteInfo 變成「站台什麼
      // function 都沒開」。攔截點在 _callWs（moodleErrorOf）。
      final result = await _callWs(siteInfoFunction, const {});
      final profile =
          MoodleProfileEntity.fromJson(result as Map<String, dynamic>);
      siteInfo = profile;
      return profile;
    } catch (e, stack) {
      _reportFailure(siteInfoFunction, e, stack);
      return null;
    }
  }

  static Future<MoodleSettingEntity?> getSettings() async {
    const wsFunction = "core_message_get_user_notification_preferences";
    await _ensureToken();
    try {
      final result = await _callWs(wsFunction, const {});
      return MoodleSettingEntity.fromJson(result as Map<String, dynamic>);
    } catch (e, stack) {
      _reportFailure(wsFunction, e, stack);
      return null;
    }
  }

  /// 切換 Moodle 通知設定。成功回 true。
  ///
  /// 一定要把成敗回報給呼叫端：Moodle 對 core_user_update_user_preferences
  /// 的失敗是回 HTTP 200 帶 exception 或 errorcode、部分失敗回 warnings[]，
  /// 連例外都不會拋，忽略它就是使用者看到開關切過去了、伺服器沒有改。
  ///
  /// 這裡是唯一送 `treatWarningsAsError: true` 的呼叫：寫入只要有一筆
  /// warning 就代表偏好設定沒有真的存進去，讀取路徑則不然。
  static Future<bool> toggleSetting(String key, List<String> values) async {
    const wsFunction = "core_user_update_user_preferences";
    await _ensureToken();
    try {
      await _callWs(
        wsFunction,
        {
          "preferences[0][type]": "${key}_enabled",
          "preferences[0][value]": values.join(","),
          "moodlewssettingfilter": true,
          "moodlewssettingfileurl": true,
        },
        treatWarningsAsError: true,
      );
      return true;
    } catch (e, stack) {
      _reportFailure(wsFunction, e, stack);
      return false;
    }
  }
}
