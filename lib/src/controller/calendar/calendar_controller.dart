import 'package:flutter_app/debug/log/log.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/src/repository/calendar_repository.dart';
import 'package:get/get.dart';
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:table_calendar/table_calendar.dart';

class CalendarController extends GetxController {
  RxList<String> selectedEvents = <String>[].obs;
  RxMap<DateTime, List<String>> events = <DateTime, List<String>>{}.obs;
  Rx<CalendarFormat> calendarFormat = Rx(CalendarFormat.month);
  Rx<RangeSelectionMode> rangeSelectionMode = Rx(RangeSelectionMode.toggledOff);
  Rx<DateTime> focusedDay = DateTime.now().obs;
  Rx<DateTime> selectedDay = DateTime.now().obs;
  Rx<DateTime?> rangeStart = Rx(null);
  Rx<DateTime?> rangeEnd = Rx(null);

  @override
  Future<void> onInit() async {
    super.onInit();
    await addEvent();
  }

  Future<void> addEvent({bool forceUpdate = false}) async {
    events.clear();
    // 檔案已經在磁碟上就直接回 Ok，不需要網路。
    final result =
        await CalendarRepository.instance.getCalendarFile(forceUpdate: forceUpdate);
    final savePath = result.dataOrNull;
    if (savePath != null) {
      final icsLines = await File(savePath).readAsLines();
      final iCalendar = ICalendar.fromLines(icsLines);
      for (var i in iCalendar.data) {
        if (!i.containsKey("dtstart") || !i.containsKey("summary")) {
          continue;
        }

        // 單筆解析失敗只跳過該筆：例外會從 GetX 不 await 的 onInit 逸出，
        // 讓畫面停在被截斷的半份行事曆，使用者沒有任何線索。
        try {
          IcsDateTime timeStart = i["dtstart"];
          DateTime dt = DateTime.parse(timeStart.dt);
          var time = DateTime.utc(dt.year, dt.month, dt.day);
          String event = i["summary"];
          for (var raw in event.split("  ")) {
            // 剝掉開頭的「數字加標點」編號前綴。不可以換成固定長度切割：
            // 編號可能是兩位數（「10.開學」），短 token 也會 RangeError。
            final item = raw
                .replaceAll(" ", "")
                .replaceFirst(RegExp(r'^\d+[.、,:]?'), '');
            if (item.isEmpty) continue;
            events.putIfAbsent(time, () => []).add(item);
          }
        } catch (e, stack) {
          Log.eWithStack(e.toString(), stack);
          continue;
        }
      }
      var today = DateTime.now().toUtc();
      today = today.add(const Duration(hours: 8)); //to TW time

      selectedDay.value = today;
      selectedEvents.value = events[today] ?? [];

      _selectEvent();
    }
  }

  void onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(this.focusedDay.value, focusedDay)) {
      this.selectedDay.value = selectedDay;
      this.focusedDay.value = focusedDay;
      rangeStart.value = null;
      rangeEnd.value = null;
      rangeSelectionMode.value = RangeSelectionMode.toggledOff;
      selectedEvents.value = events[focusedDay] ?? [];
      HapticFeedback.lightImpact();
    }
  }

  void onFormatChanged(CalendarFormat format) {
    if (calendarFormat.value != format) {
      calendarFormat.value = format;
    }
  }

  void onPageChanged(DateTime focusedDay) {
    this.focusedDay.value = focusedDay;
    _getEvent(focusedDay);
  }

  Future<void> _getEvent(DateTime time) async {
    selectedDay.value = time;
    _selectEvent();
  }

  void _selectEvent() {
    for (DateTime time in events.keys) {
      if (selectedDay.value.year == time.year &&
          selectedDay.value.month == time.month &&
          selectedDay.value.day == time.day) {
        selectedEvents.value = events[time] ?? [];
        return;
      }
    }
    // 找不到就要清空，否則換月後清單會繼續顯示上一天的事件，掛在錯誤的
    // 日期底下。
    selectedEvents.clear();
  }
}
