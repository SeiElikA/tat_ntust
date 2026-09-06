import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/connector/moodle_webapi_connector.dart';
import 'package:flutter_app/src/controller/announcement/announcement_center_controller.dart';
import 'package:flutter_app/src/model/announcement/announcement_json.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_message_popup_notifications.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/src/service/task_ui_delegate.dart';
import 'package:flutter_app/src/util/moodle_notification_utils.dart';
import 'package:flutter_app/ui/components/card/section_card.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/inline_error_view.dart';
import 'package:flutter_app/ui/components/page/result_view.dart';
import 'package:flutter_app/ui/components/page/section_empty_state.dart';
import 'package:flutter_app/ui/components/page/web_view_opener.dart';
import 'package:flutter_app/ui/pages/announcement/notification_tile.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// 「公告與通知」：上半是 App 自己的公告（Remote Config，同啟動彈窗的內容），
/// 下半是 Moodle 站內通知。WebView 開啟器由呼叫端注入，
/// 見 docs/ARCHITECTURE.md「UI 慣例」。
///
/// 兩半疊在同一個捲動視圖裡而不是分頁：量級差太多（0–2 則對 0–50 則），而且
/// 標題在卡片外，一半載入或失敗時另一半照樣看得到。也因為每一半都只是頁面
/// 中段的一個區塊，失敗畫面一律是 `InlineErrorView`，這一頁不需要注入
/// 頁面層級的 errorBuilder。
class AnnouncementCenterPage extends StatefulWidget {
  const AnnouncementCenterPage({
    super.key,
    required this.openWebView,
    this.controller,
    this.clock = DateTime.now,
  });

  final WebViewOpener openWebView;

  /// 測試注入預先載好的狀態；注入時這一頁不會自己再發請求。
  final AnnouncementCenterController? controller;

  /// 「現在」，時間欄的基準。
  final DateTime Function() clock;

  @override
  State<StatefulWidget> createState() => _AnnouncementCenterPageState();
}

class _AnnouncementCenterPageState extends State<AnnouncementCenterPage> {
  late final AnnouncementCenterController _controller;
  late final bool _ownsController;

  /// 沒有 contexturl、就地展開內文的那幾列。
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AnnouncementCenterController();
    if (_ownsController) unawaited(_controller.loadAll());
  }

  @override
  void dispose() {
    // 注入進來的那一顆屬於呼叫端（測試），不歸這裡收。
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: baseAppbar(title: R.current.announcementCenter),
      body: RefreshIndicator(
        onRefresh: _controller.refreshAll,
        child: ListView(
          // 清單空或是錯誤畫面時也要拉得動。
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
          children: [
            SectionHeader(
              icon: Icons.campaign_outlined,
              title: R.current.appAnnouncement,
              first: true,
            ),
            ResultView<List<AnnouncementInfoJson>>(
              shrinkWrap: true,
              state: _controller.appNotices,
              onRetry: _controller.loadAppNotices,
              errorBuilder: (message) => InlineErrorView(
                message: message,
                onRetry: _controller.loadAppNotices,
              ),
              builder: _buildAppNotices,
            ),
            SectionHeader(
              icon: Icons.notifications_none,
              title: R.current.moodleNotification,
              trailing: _MarkAllReadButton(controller: _controller),
            ),
            ResultView<MoodleNotificationList>(
              shrinkWrap: true,
              state: _controller.notifications,
              onRetry: _reloadNotifications,
              errorBuilder: (message) => InlineErrorView(
                message: message,
                onRetry: _reloadNotifications,
              ),
              builder: _buildNotifications,
            ),
          ],
        ),
      ),
    );
  }

  /// 重試是使用者主動按的，所以 `background: false`：這時候才可以開登入頁。
  Future<void> _reloadNotifications() =>
      _controller.loadNotifications(background: false);

  Widget _buildAppNotices(List<AnnouncementInfoJson> list) {
    if (list.isEmpty) {
      return _empty(R.current.appAnnouncementEmpty);
    }
    final items = AnnouncementCenterController.sortForList(list);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _AppNoticeCard(
            info: items[i],
            index: i,
            unread: AnnouncementCenterController.isUnread(
                items[i], _controller.lastReadSnapshot),
          ),
        ],
      ],
    );
  }

  Widget _buildNotifications(MoodleNotificationList data) {
    if (data.notifications.isEmpty) {
      // 清單空但未讀數不是 0 ＝ 使用者在 Moodle 關掉了站內通知，
      // 跟「真的沒有通知」是兩件事。
      return _empty(MoodleNotificationUtils.looksDisabledByUser(data)
          ? R.current.notificationDisabledOnMoodle
          : R.current.notificationEmpty);
    }

    final now = widget.clock();
    final items = MoodleNotificationUtils.sortNewestFirst(data.notifications);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              indent: 60,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          _buildTile(items[i], now),
        ],
      ],
    );
  }

  Widget _buildTile(MoodleNotification n, DateTime now) {
    final url = MoodleNotificationUtils.openUrlOf(
      n,
      siteHost: MoodleWebApiConnector.siteHost,
    );
    return NotificationTile(
      key: ValueKey('notification-${n.id}'),
      notification: n,
      now: now,
      openable: url != null,
      expanded: _expanded.contains(n.id),
      openWebView: widget.openWebView,
      onTap: () => unawaited(_onTap(n, url)),
    );
  }

  Future<void> _onTap(MoodleNotification n, String? url) async {
    // 標記已讀是背景寫入，失敗只 toast：使用者的意圖是打開它，不是管理已讀狀態。
    unawaited(_controller.markRead(n));
    if (url == null) {
      setState(() {
        if (!_expanded.remove(n.id)) _expanded.add(n.id);
      });
      return;
    }
    // 不自己呼叫 autologinUrl：注入進來的開啟器（RouteUtils.toWebViewPage）
    // 已經做了，再換一次會在伺服器 6 分鐘的節流內白燒一把鑰匙。
    await widget.openWebView(n.subject, url);
  }

  /// 區塊級的空狀態：兩半都是頁面中段的一塊，整頁級的 `EmptyState` 疊兩份
  /// 會變成同一張插圖上下重複兩次。
  Widget _empty(String message) => SectionEmptyState(
        asset: "assets/image/img_message.svg",
        message: message,
      );
}

/// 「全部標為已讀」。只在有未讀而且是 `Ok`（不是 `Stale`）時出現：`Stale`
/// 幾乎一定是離線，提供一個必定失敗的寫入比不提供更糟。
class _MarkAllReadButton extends StatelessWidget {
  const _MarkAllReadButton({required this.controller});

  final AnnouncementCenterController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.markingAll.value) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      final state = controller.notifications.value;
      final unread = switch (state) {
        Ok(:final data) => data.unreadcount,
        _ => 0,
      };
      if (unread <= 0) return const SizedBox.shrink();
      return TextButton(
        onPressed: () => unawaited(_confirmAndMark(context)),
        child: Text(R.current.notificationMarkAllRead),
      );
    });
  }

  /// 伺服器預設在已讀 7 天後刪除通知，所以這是有破壞性的操作，要先問。
  ///
  /// 對話框刻意不寫數字：`core_message_mark_all_notifications_as_read` 標的是
  /// `{notifications}` 全部，而畫面上的未讀數只算 popup 那一部分，寫上去等於
  /// 少報這次寫入的範圍。
  Future<void> _confirmAndMark(BuildContext context) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog.adaptive(
        title: Text(R.current.notificationMarkAllRead),
        content: Text(R.current.notificationMarkAllReadConfirm),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: Text(R.current.cancel),
          ),
          TextButton(
            onPressed: () => Get.back<bool>(result: true),
            child: Text(R.current.sure),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (await controller.markAllRead()) {
      TaskUiDelegate.instance.toast(R.current.notificationMarkAllReadDone);
    }
  }
}

/// 一則 App 公告。內文沿用啟動彈窗的 `flutter_markdown`，同一段公告在兩個
/// 地方才會長得一樣；連結一律走外部瀏覽器（公告連的是表單與商店，不是 Moodle）。
class _AppNoticeCard extends StatelessWidget {
  const _AppNoticeCard({
    required this.info,
    required this.index,
    required this.unread,
  });

  final AnnouncementInfoJson info;
  final int index;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard([
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unread) ...[
            Semantics(
              label: R.current.notificationUnread,
              child: Container(
                key: ValueKey('notice-unread-$index'),
                margin: const EdgeInsets.only(top: 7, right: 8),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: scheme.primary, shape: BoxShape.circle),
              ),
            ),
          ],
          // 卡片標題，不是 SectionSubLabel：那是卡片內小標的字級，會比
          // 底下的 Markdown 內文還小。
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                info.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      height: 1.3,
                    ),
              ),
            ),
          ),
        ],
      ),
      // startTime 是 UTC 欄位裝著台北的牆上時間（見 RemoteConfigUtils），
      // toLocal() 會讓每一則公告的日期整整位移八小時。
      SectionField(
        R.current.announcementPublishedAt,
        DateFormat.yMd().format(info.startTime),
      ),
      const SectionDivider(),
      MarkdownBody(
        data: info.content,
        selectable: true,
        onTapLink: (text, href, title) {
          if (href != null) unawaited(launchUrlString(href));
        },
      ),
    ]);
  }
}
