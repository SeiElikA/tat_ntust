import 'dart:async';

import 'package:card_swiper/card_swiper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/announcement/announcement_json.dart';
import 'package:flutter_app/src/util/remote_config_utils.dart';
import 'package:flutter_app/ui/components/page/base_page.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AnnouncementPage extends StatefulWidget {
  final List<AnnouncementInfoJson> info;
  final int countDown;

  const AnnouncementPage({
    super.key,
    required this.info,
    required this.countDown,
  });

  @override
  State<StatefulWidget> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  late SwiperController controller;
  Timer? _countDownTimer;
  int index = 0;
  late int count;

  @override
  void initState() {
    controller = SwiperController();
    count = widget.countDown;
    // Timer 必須存成欄位並在 dispose 取消，回呼裡也要先檢查 mounted：對已
    // unmount 的 State setState 會拋例外，例外若在 timer.cancel() 之前逸出，
    // Timer 就永遠不會自我取消，每秒丟一次直到 process 結束。結束條件用 <= 0，
    // 避免 remote config 設成 0 或負數時永不結束。
    _countDownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        count--;
      });
      if (count <= 0) {
        timer.cancel();
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    _countDownTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
        title: widget.info[index].title,
        action: [
          btnConfirm()
        ],
        child: SizedBox(
          height: Get.height,
          width: Get.width,
          child: Swiper(
            loop: false,
            itemCount: widget.info.length,
            controller: controller,
            pagination: SwiperPagination(
              builder: DotSwiperPaginationBuilder(
                size: 8,
                activeSize: widget.info.length == 1 ? 0 : 12,
                space: 12,
                color: Colors.grey,
                activeColor: Get.iconColor,
              ),
            ),
            onIndexChanged: (i) {
              setState(() {
                index = i;
              });
            },
            itemBuilder: (context, index) {
              return Container(
                padding: const EdgeInsets.only(bottom: 35),
                child: Markdown(
                  selectable: true,
                  shrinkWrap: true,
                  data: widget.info[index].content,
                  styleSheet: MarkdownStyleSheet.fromTheme(Get.theme.copyWith(
                      textTheme: Get.textTheme.copyWith(
                          bodyMedium: Get.textTheme.bodyMedium
                              ?.copyWith(height: 1.2)))),
                  onTapLink: (String text, String? href, String title) {
                    if (href != null) {
                      launchUrlString(href);
                    }
                  },
                ),
              );
            },
          ),
        ));
  }

  Widget btnConfirm() {
    return TextButton(
      onPressed: count > 0
          ? null
          : () {
        Get.back<bool>(result: true);
        RemoteConfigUtils.setAnnouncementRead();
      },
      child:
      Text(count > 0 ? "${R.current.wait} $count" : R.current.sure),
    );
  }
}
