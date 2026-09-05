//
//  connector.dart
//  北科課程助手
//
//  Created by morris13579 on 2020/02/12.
//  Copyright © 2020 morris13579 All rights reserved.
//

import 'package:dio/dio.dart';

import 'connector_parameter.dart';
import 'dio_connector.dart';

class Connector {
  /// 這四個包裝必須保留 `async`。
  ///
  /// `DioConnector.instance` 是惰性初始化的，少了 `async`，它的例外會從
  /// rejected Future 變成**同步** throw；而 `privacy_policy_page.dart` 是在
  /// `build()` 裡把回傳值當 `FutureBuilder.future` 用的，同步 throw 會直接
  /// 炸掉 build。
  static Future<dynamic> getJsonByPost(ConnectorParameter parameter) async {
    final result = await DioConnector.instance.getDataByPostResponse(parameter);
    return result.data;
  }

  static Future<String> getDataByGet(ConnectorParameter parameter) async =>
      DioConnector.instance.getDataByGet(parameter);

  static Future<Response> getDataByGetResponse(
          ConnectorParameter parameter) async =>
      DioConnector.instance.getDataByGetResponse(parameter);

  static Future<Response> getDataByPostResponse(
          ConnectorParameter parameter) async =>
      DioConnector.instance.getDataByPostResponse(parameter);

  static String uriAddQuery(String url, Map<String, dynamic> queryParameters) {
    if (!url.contains('?')) {
      url += "?";
    }
    for (var i in queryParameters.keys) {
      url += '&$i=${queryParameters[i]}';
    }
    return url;
  }
}
