import 'dart:async';

import 'package:clipboard/clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/core/dio_connector.dart';
import 'package:flutter_app/src/util/cloud_messaging_utils.dart';
import 'package:flutter_app/src/util/remote_config_utils.dart';
import 'package:flutter_app/ui/routes/route_utils.dart';
import 'package:flutter_app/ui/other/listview_animator.dart';
import 'package:flutter_app/src/util/my_toast.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

enum DevMenuAction {
  cloudMessageToken,
  dioLog,
  appLog,
  storeEdit,
  announcement
}

class DevPage extends StatefulWidget {
  const DevPage({super.key});

  @override
  State<StatefulWidget> createState() => _DevPageState();
}

class _DevPageState extends State<DevPage> {
  List<Map> listViewData = [
    {
      "icon": LucideIcons.keyRound,
      "title": "Cloud Messaging Token",
      "color": Colors.green,
      "onPress": DevMenuAction.cloudMessageToken
    },
    {
      "icon": LucideIcons.info,
      "title": "Dio Log",
      "color": Colors.blue,
      "onPress": DevMenuAction.dioLog
    },
    {
      "icon": LucideIcons.info,
      "title": "App Log",
      "color": Colors.yellow,
      "onPress": DevMenuAction.appLog
    },
    {
      "icon": LucideIcons.pencil,
      "title": "Store Edit",
      "color": Colors.green,
      "onPress": DevMenuAction.storeEdit
    },
    {
      "icon": LucideIcons.megaphone,
      "title": "Announcement",
      "color": Colors.deepPurple,
      "onPress": DevMenuAction.announcement
    },
  ];

  @override
  void initState() {
    super.initState();
    RemoteConfigUtils.init(focusUpdate: true);
  }

  int pressTime = 0;

  void _onListViewPress(DevMenuAction value) async {
    switch (value) {
      case DevMenuAction.cloudMessageToken:
        String? token = await CloudMessagingUtils.getToken();
        MyToast.show("${token!} copy");
        unawaited(FlutterClipboard.copy(token));
        break;
      case DevMenuAction.dioLog:
        DioConnector.instance.alice.showInspector();
        break;
      case DevMenuAction.appLog:
        unawaited(RouteUtils.toLogConsolePage());
        break;
      case DevMenuAction.storeEdit:
        unawaited(RouteUtils.toStoreEditPage());
        break;
      case DevMenuAction.announcement:
        unawaited(RouteUtils.showAnnouncement(test: true));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(R.current.developerMode),
      ),
      body: ListView.separated(
        itemCount: listViewData.length,
        itemBuilder: (context, index) {
          Widget widget;
          widget = _buildAbout(listViewData[index]);
          return InkWell(
            child: WidgetAnimator(widget),
            onTap: () {
              _onListViewPress(listViewData[index]['onPress']);
            },
          );
        },
        separatorBuilder: (context, index) {
          // 顯示格線
          return Container(
            color: Colors.black12,
            height: 1,
          );
        },
      ),
    );
  }

  Container _buildAbout(Map data) {
    return Container(
      padding: const EdgeInsets.only(
          top: 20.0, left: 20.0, right: 20.0, bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            data['icon'],
            color: data['color'],
          ),
          const SizedBox(
            width: 20.0,
          ),
          Text(
            data['title'],
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }
}
