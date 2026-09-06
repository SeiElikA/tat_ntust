import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_app/ui/other/input_dialog.dart';
import 'package:flutter_app/ui/other/listview_animator.dart';
import 'package:get/get.dart';
import 'package:pretty_json/pretty_json.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

class StoreEditPage extends StatefulWidget {
  const StoreEditPage({super.key});

  @override
  State<StatefulWidget> createState() => _StoreEditPageState();
}

class _StoreEditPageState extends State<StoreEditPage> {
  /// 這幾個 key 的值是憑證，不在編輯框裡回顯原文。
  static bool _isSensitive(String key) =>
      key == 'user_data' || key == 'moodle_token';

  SharedPreferences? pref;
  List<String> keyList = [];

  @override
  void initState() {
    super.initState();
  }

  Future<List<String>> initPref() async {
    pref = await SharedPreferences.getInstance();
    List<String> filter = [];
    List<String> cache = [];
    for (var i in pref!.getKeys().toList()) {
      if (!i.contains("cache_")) {
        filter.add(i);
      } else {
        cache.add(i);
      }
    }
    filter.addAll(cache);
    return filter;
  }

  @override
  void dispose() {
    Model.instance.getInstance();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Page"),
      ),
      body: FutureBuilder<List<String>>(
        future: initPref(),
        builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          } else {
            keyList = snapshot.data!;
            return ListView.separated(
              itemCount: keyList.length,
              itemBuilder: (context, index) {
                String key = keyList[index];
                String value;
                try {
                  value = prettyJson(json.decode(pref!.get(key).toString()),
                      indent: 2);
                } catch (e) {
                  value = pref!.get(key).toString();
                }
                return Container(
                  padding: const EdgeInsets.only(top: 5, left: 20, right: 20),
                  child: WidgetAnimator(
                    SizedBox(
                      height: 50,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(key),
                          ),
                          IconButton(
                              // 這兩顆按鈕在同一列、只差圖示，沒有 tooltip 時
                              // 螢幕閱讀器會連唸兩次「按鈕」，分不出哪顆是刪除。
                              tooltip: R.current.edit,
                              icon: const Icon(LucideIcons.pencil),
                              onPressed: () {
                                Get.dialog(CustomInputDialog(
                                  title: key,
                                  initText: _isSensitive(key) ? "" : value,
                                  maxLine: 20,
                                  onCancel: (String value) {},
                                  onOk: (String value) async {
                                    if (pref!.get(key).runtimeType.toString() ==
                                        'String') {
                                      await pref!.setString(key, value);
                                    }
                                    if (pref!.get(key).runtimeType.toString() ==
                                        'int') {
                                      await pref!.setInt(key, int.parse(value));
                                    }
                                  },
                                ));
                              }),
                          IconButton(
                            tooltip: R.current.delete,
                            icon: const Icon(LucideIcons.trash2),
                            onPressed: () {
                              keyList.removeAt(index);
                              pref!.remove(key);
                              setState(() {});
                            },
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (context, index) {
                // 顯示格線
                return Container(
                  color: Colors.black12,
                  height: 1,
                );
              },
            );
          }
        },
      ),
    );
  }
}
