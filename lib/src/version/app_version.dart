import 'package:flutter_app/src/store/credentials_store.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/model/remote_config/remote_config_version_info.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_app/src/util/remote_config_utils.dart';
import 'package:flutter_app/src/version/update/app_update.dart';
import 'package:version/version.dart';

class APPVersion {
  static Future<bool> initAndCheck() async {
    try {
      await checkIFAPPUpdate();
      return await check();
    } catch (e) {
      Log.e(e);
    }
    return false;
  }

  static Future<bool> check({focusCheck = false}) async {
    RemoteConfigVersionInfo config = await RemoteConfigUtils.getVersionConfig();
    if (!config.isFocusUpdateFor(await AppUpdate.getAppVersion())) {
      if (!focusCheck) {
        if (!Model.instance.autoCheckAppUpdate) {
          Log.d("close check update because of close auto check");
          return false; //跳過檢查
        }
        if (!await Model.instance.getFirstUse(Model.appCheckUpdate)) {
          Log.d("close check update because of already check");
          return false; //跳過檢查
        }
        // 不走 AuthSession.instance.isSignedIn（判準完全相同）：這個檔案在
        // tool/deps.py 裡排在 auth 下面，往 auth 是上行邊，往 store 才是
        // 下行的。
        if (!CredentialsStore.instance.hasCredentials) {
          Log.d("close check update because of not login");
          return false; //跳過檢查
        }
      }
    }
    Model.instance.setAlreadyUse(Model.appCheckUpdate);
    Log.d("Start check update");
    bool value = await AppUpdate.checkUpdate();
    return value;
  }

  static Future<void> checkIFAPPUpdate() async {
    String version = await AppUpdate.getAppVersion();
    String preVersion = await Model.instance.getVersion();
    Log.d(" preVersion: $preVersion \n version: $version");
    // 版本戳記必須在遷移成功之後才落盤：先寫版本的話，遷移中途失敗（例外被
    // 外層 try/catch 吞掉）下次冷啟動 preVersion == version 就直接跳過，
    // 遷移永遠不會再跑，使用者停在半遷移狀態且畫面上零徵兆。
    if (preVersion != version) {
      await updateVersionCallback(preVersion);
    }
    await Model.instance.setVersion(version);
  }

  static Future<void> updateVersionCallback(String preVersion) async {
    //更新版本後執行的資料遷移
    Version version;
    try {
      version = Version.parse(preVersion);
    } catch (e) {
      version = Version.parse("0.0.0");
    }
    Model.instance.getOtherSetting().useMoodleWebApi = true;
    await Model.instance.saveSetting();
    if (version < Version.parse("1.2.6")) {
      await Model.instance.clearCourseSetting();
      await Model.instance.saveCourseSetting();
      await Model.instance.clearCourseTableList();
      await Model.instance.saveCourseTableList();
    }
  }
}
