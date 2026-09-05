import 'package:flutter/material.dart';
import 'package:flutter_app/src/store/key_value_store.dart';

/// 使用者偏好的單一出口。
///
/// **所有 key 名不可更動**，改名會讓已安裝的使用者升級後設定消失。
class SettingsStore {
  static SettingsStore instance = SettingsStore(SharedPrefsKeyValueStore());

  final KeyValueStore _store;

  SettingsStore(this._store);

  // ---- 主題 ----------------------------------------------------------------
  static const themeModeKey = 'isThemeMode';

  Future<int> get themeModeIndex async => await _store.readInt(themeModeKey) ?? 0;

  Future<void> setThemeModeIndex(int index) =>
      _store.writeInt(themeModeKey, index);

  ThemeMode themeModeOf(int index) => ThemeMode.values[index];

  // ---- 檔案總管 ------------------------------------------------------------
  static const showHiddenFilesKey = 'hidden';
  static const fileSortKey = 'sort';

  Future<bool> get showHiddenFiles async =>
      await _store.readBool(showHiddenFilesKey) ?? false;

  Future<void> setShowHiddenFiles(bool value) =>
      _store.writeBool(showHiddenFilesKey, value);

  Future<int> get fileSort async => await _store.readInt(fileSortKey) ?? 0;

  Future<void> setFileSort(int value) => _store.writeInt(fileSortKey, value);

  // ---- 下載路徑 ------------------------------------------------------------
  static const downloadPathKey = 'download_path';

  Future<String?> get downloadPath async => _store.readString(downloadPathKey);

  Future<void> setDownloadPath(String value) =>
      _store.writeString(downloadPathKey, value);

  // ---- 公告已讀時間 --------------------------------------------------------
  static const announcementLastReadKey = 'announcement_last_read_time';

  /// 已讀時間。格式是「UTC 加 8 小時再 toString」，讀不到時退回 2000 年。
  Future<DateTime> get announcementLastRead async {
    final raw = await _store.readString(announcementLastReadKey);
    if (raw == null) return DateTime.utc(2000);
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return DateTime.utc(2000);
    }
  }

  Future<void> markAnnouncementRead() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    return _store.writeString(announcementLastReadKey, now.toString());
  }
}
