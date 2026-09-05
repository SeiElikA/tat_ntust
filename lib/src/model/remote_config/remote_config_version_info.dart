import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:version/version.dart';

part 'remote_config_version_info.g.dart';

@JsonSerializable()
class RemoteConfigVersionInfo {
  @JsonKey(name: "is_focus_update")
  bool focusUpdate;

  @JsonKey(name: "last_version")
  AndroidIosVersionInfo last;

  @JsonKey(name: "focus_update_version")
  AndroidIosVersionInfo focusUpdateVersion;

  @JsonKey(name: "last_version_detail")
  String lastVersionDetail;

  @JsonKey(name: "link")
  AndroidIosVersionInfo link;

  String get url {
    return (Platform.isAndroid) ? link.android : link.ios;
  }

  String get version {
    return (Platform.isIOS) ? last.ios : last.android;
  }

  String get focusVersion {
    return (Platform.isIOS)
        ? focusUpdateVersion.ios
        : focusUpdateVersion.android;
  }

  /// 這個版本是否對 [currentVersion] 而言是強制更新。
  ///
  /// 保持純函式、由呼叫端傳入版本：在這裡取版本會造成
  /// model -> version -> util -> model 的環。
  bool isFocusUpdateFor(String currentVersion) {
    return focusUpdate
        ? Version.parse(focusVersion) >= Version.parse(currentVersion)
        : false;
  }

  RemoteConfigVersionInfo({
    required this.last,
    required this.lastVersionDetail,
    required this.focusUpdate,
    required this.link,
    required this.focusUpdateVersion,
  });

  factory RemoteConfigVersionInfo.fromJson(Map<String, dynamic> srcJson) =>
      _$RemoteConfigVersionInfoFromJson(srcJson);

  Map<String, dynamic> toJson() => _$RemoteConfigVersionInfoToJson(this);
}

@JsonSerializable()
class AndroidIosVersionInfo {
  @JsonKey(name: "android")
  String android;

  @JsonKey(name: "ios")
  String ios;

  AndroidIosVersionInfo({required this.android, required this.ios});

  factory AndroidIosVersionInfo.fromJson(Map<String, dynamic> srcJson) =>
      _$AndroidIosVersionInfoFromJson(srcJson);

  Map<String, dynamic> toJson() => _$AndroidIosVersionInfoToJson(this);
}
