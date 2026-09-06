import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/controller/calendar/calendar_controller.dart';
import 'package:flutter_app/src/model/moodle_webapi/moodle_core_calendar_action_events.dart';
import 'package:flutter_app/src/util/language_utils.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/pages/calendar/upcoming_events_section.dart';
import 'package:flutter_app/ui/pages/web_view/inapp_web_view_page.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';

/*
kFirstDay / kLastDay 是日曆可存取範圍的上下界，超出這段的日期使用者點不到。
 */
final kNow = DateTime.now();
final kFirstDay = DateTime(kNow.year, kNow.month - 12, kNow.day);
final kLastDay = DateTime(kNow.year, kNow.month + 12, kNow.day);

class CalendarPage extends GetView<CalendarController> {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Scaffold(
        appBar: mainAppbar(title: R.current.calendar, action: [
          IconButton(
            icon: const Icon(CupertinoIcons.refresh),
            splashRadius: 18,
            iconSize: 24,
            onPressed: controller.refreshAll,
            tooltip: R.current.update,
          ),
        ]),
        body: Column(
          children: [
            TableCalendar<String>(
              locale: (LanguageUtils.getLangIndex() == LangEnum.zh)
                  ? "zh_CN"
                  : "en_US",
              availableCalendarFormats: const {
                CalendarFormat.month: 'Month',
              },
              daysOfWeekHeight: 24,
              firstDay: kFirstDay,
              lastDay: kLastDay,
              focusedDay: controller.focusedDay.value,
              selectedDayPredicate: (day) =>
                  isSameDay(controller.selectedDay.value, day),
              rangeStartDay: controller.rangeStart.value,
              rangeEndDay: controller.rangeEnd.value,
              calendarFormat: controller.calendarFormat.value,
              rangeSelectionMode: controller.rangeSelectionMode.value,
              eventLoader: (day) => controller.events[day] ?? [],
              startingDayOfWeek: StartingDayOfWeek.sunday,
              onDaySelected: controller.onDaySelected,
              onFormatChanged: controller.onFormatChanged,
              onPageChanged: controller.onPageChanged,
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: Get.textTheme.titleMedium!.copyWith(
                  color: Get.theme.colorScheme.onSurface,
                ),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  color: Get.theme.colorScheme.onSurface,
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  color: Get.theme.colorScheme.onSurface,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: Get.textTheme.bodySmall!.copyWith(
                  color: Get.theme.colorScheme.onSurfaceVariant,
                ),
                weekendStyle: Get.textTheme.bodySmall!.copyWith(
                  color: Get.theme.colorScheme.primary,
                ),
              ),
              calendarStyle: CalendarStyle(
                  defaultTextStyle: Get.textTheme.bodyMedium!.copyWith(
                    color: Get.theme.colorScheme.onSurface,
                  ),
                  weekendTextStyle: Get.textTheme.bodyMedium!.copyWith(
                    color: Get.theme.colorScheme.primary,
                  ),
                  outsideDaysVisible: false,
                  todayDecoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(
                        color: Get.theme.colorScheme.primary, width: 1.5),
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: Get.textTheme.bodyMedium!.copyWith(
                    color: Get.theme.colorScheme.primary,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Get.theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: Get.textTheme.bodyMedium!.copyWith(
                    color: Get.theme.colorScheme.onPrimary,
                  ),
                  markerDecoration: BoxDecoration(
                    color: Get.theme.colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                  markerMargin: const EdgeInsets.only(top: 4),
                  markerSize: 6),
            ),
            const SizedBox(height: 12.0),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildEventList(),
                  const SizedBox(height: 16),
                  UpcomingEventsSection(
                    state: controller.upcomingEvents,
                    onRetry: () => controller.loadUpcomingEvents(),
                    onOpen: _openEvent,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// 開一筆待辦。不能 import route_utils，見 docs/ARCHITECTURE.md「UI 慣例」。
  Future<void> _openEvent(MoodleActionEvent event) async {
    final raw = event.openUrl;
    final url = await controller.urlToOpen(event);
    await Get.to(
      () => InAppWebViewPage(
        title: event.title,
        url: WebUri(url),
        // 換成 autologin 網址時把原網址一起帶著，鑰匙被拒時才有地方退。
        fallbackUrl: url == raw ? null : WebUri(raw),
        openWithExternalWebView: true,
        loadDone: (_) {},
      ),
    );
  }

  /// 外層已經是 ListView，這裡只負責排版，不自己捲動。
  Widget _buildEventList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemBuilder: (BuildContext context, int index) {
        final event = controller.selectedEvents[index];
        BorderRadius? borderRadius =
            UIUtils.getBorderRadius(index, controller.selectedEvents.length);

        return Container(
          decoration: BoxDecoration(
              color: Get.theme.colorScheme.surfaceContainer,
              borderRadius: borderRadius),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          child: Text(
            event,
            style:
                TextStyle(color: Get.theme.colorScheme.onSurface, fontSize: 15),
          ),
        );
      },
      separatorBuilder: (BuildContext context, int index) {
        return const SizedBox(height: 2);
      },
      itemCount: controller.selectedEvents.length,
    );
  }
}
