import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/config/app_colors.dart';
import 'package:flutter_app/src/controller/calendar/calendar_controller.dart';
import 'package:flutter_app/src/util/language_utils.dart';
import 'package:flutter_app/src/util/ui_utils.dart';
import 'package:flutter_app/ui/components/custom_appbar.dart';
import 'package:flutter_app/ui/components/page/loading_page.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';

/*
firstDay是日曆的第一天。用戶將無法在訪問前幾天訪問。
lastDay是日曆的最後可用日期。幾天后用戶將無法訪問。
focusedDay是當前的目標日期。使用此屬性來確定當前應顯示的月份。
 */
final kNow = DateTime.now();
final kFirstDay = DateTime(kNow.year, kNow.month - 12, kNow.day);
final kLastDay = DateTime(kNow.year, kNow.month + 12, kNow.day);

class CalendarPage extends GetView<CalendarController> {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(CalendarController());
    return Obx(() {
      return Scaffold(
        appBar: mainAppbar(title: R.current.calendar, action: [
          IconButton(
            icon: const Icon(CupertinoIcons.refresh),
            splashRadius: 18,
            iconSize: 24,
            onPressed: () async {
              await controller.addEvent(forceUpdate: true);
            },
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
                  border: Border.all(color: Get.theme.colorScheme.primary, width: 1.5),
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
                markerSize: 6
              ),
            ),
            const SizedBox(height: 12.0),
            Expanded(child: _buildEventList()),
          ],
        ),
      );
    });
  }

  Widget _buildEventList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
