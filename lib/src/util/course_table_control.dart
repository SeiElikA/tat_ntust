import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/util/ui_utils.dart';

/// 課表用的星期名稱，索引對齊 [Day] 的順序。
///
/// 第八個是 Day.unKnown，收容查不到星期的課（見 course_time.dart）。
/// 兩個 ARB 都沒有「未知」這一類的 key，硬補一個等於多一組要維護的翻譯；
/// titleOther（其它／Other）兩個語系都有翻譯，語意也正好是「不屬於前面七天」。
/// 這是 titleOther 在 App 內唯一與「更多」無關的讀取點，換掉它之前先看這裡。
List<String> courseDayNames() => [
      R.current.Monday,
      R.current.Tuesday,
      R.current.Wednesday,
      R.current.Thursday,
      R.current.Friday,
      R.current.Saturday,
      R.current.Sunday,
      R.current.titleOther,
    ];

/// 把一門課的上課時間組成「星期_節次 」的顯示字串。
///
/// 放在這裡而不是 model 上：model 為了組在地化字串 import `R.dart` 會是
/// `tool/deps.py` 的 model -> config 上行邊。
String courseTimeString(Map<Day, String> time) {
  final names = courseDayNames();
  final buffer = StringBuffer();
  for (final day in time.keys) {
    if (time[day]!.replaceAll(RegExp('[|\n]'), "").isEmpty) continue;
    buffer.write("${names[day.index]}_${time[day]} ");
  }
  return buffer.toString();
}

class CourseTableControl {
  bool isHideSaturday = false;
  bool isHideSunday = false;
  bool isHideUnKnown = false;
  bool isHideN = false;
  bool isHideA = false;
  bool isHideB = false;
  bool isHideC = false;
  bool isHideD = false;
  CourseTableJson? courseTable;

  /// getter 而不是欄位：這個物件是 CourseController 的欄位，而 GetX 的
  /// controller 不會被 forceAppUpdate 重建，存成欄位會凍在建立時的語言。
  List<String> get dayStringList => courseDayNames();
  List<String> timeList = [
    "08:10 - 09:00",
    "09:10 - 10:00",
    "10:20 - 11:10",
    "11:20 - 12:10",
    "12:20 - 13:10",
    "13:20 - 14:10",
    "14:20 - 15:10",
    "15:30 - 16:20",
    "16:30 - 17:20",
    "17:30 - 18:20",
    "18:25 - 19:15",
    "19:20 - 20:10",
    "20:15 - 21:05",
    "21:00 - 22:00"
  ];

  /// 節次代號。與 [SectionNumber]、`CourseConnector.timeEnum` 和分享碼的
  /// `1234N56789ABCD` 逐格對位。
  ///
  /// 第 5 格是午休 `N` 而不是「5」：querycourse 的 `Node` 用的是「第幾格」，
  /// 它前端那張 `1…10 A…D` 的表跟這裡逐格對應（理由與統計見
  /// `CourseConnector.fillCourseTime`）。以前這裡照抄了 querycourse 的格號，
  /// 於是 15:30 那一列被標成「8」——對照 [timeList] 就知道它是第 7 節，而且
  /// 臺科根本沒有第 10 節。
  List<String> sectionStringList = [
    "1",
    "2",
    "3",
    "4",
    "N",
    "5",
    "6",
    "7",
    "8",
    "9",
    "A",
    "B",
    "C",
    "D"
  ];
  static int dayLength = 8;
  static int sectionLength = 14;
  late Map<String, Color> colorMap;

  void set(CourseTableJson value) {
    courseTable = value;
    isHideSaturday = !courseTable!.isDayInCourseTable(Day.saturday);
    isHideSunday = !courseTable!.isDayInCourseTable(Day.sunday);
    isHideUnKnown = !courseTable!.isDayInCourseTable(Day.unKnown);
    isHideN = !courseTable!.isSectionNumberInCourseTable(SectionNumber.t_N);
    isHideA = (!courseTable!.isSectionNumberInCourseTable(SectionNumber.t_A));
    isHideB = (!courseTable!.isSectionNumberInCourseTable(SectionNumber.t_B));
    isHideC = (!courseTable!.isSectionNumberInCourseTable(SectionNumber.t_C));
    isHideD = (!courseTable!.isSectionNumberInCourseTable(SectionNumber.t_D));
    isHideA &= (isHideB & isHideC & isHideD);
    isHideB &= (isHideC & isHideD);
    isHideC &= isHideD;
    _initColorList();
  }

  List<int> get getDayIntList {
    List<int> intList = [];
    for (int i = 0; i < dayLength; i++) {
      if (isHideSaturday && i == 5) continue;
      if (isHideSunday && i == 6) continue;
      if (isHideUnKnown && i == 7) continue;
      intList.add(i);
    }
    return intList;
  }

  CourseInfoJson? getCourseInfo(int intDay, int intNumber) {
    Day day = Day.values[intDay];
    SectionNumber number = SectionNumber.values[intNumber];
    //Log.d( day.toString()  + " " + number.toString() );
    return courseTable?.courseInfoMap[day]?[number];
  }

  Color getCourseInfoColor(int intDay, int intNumber) {
    CourseInfoJson? courseInfo = getCourseInfo(intDay, intNumber);
    for (String key in colorMap.keys) {
      if (courseInfo != null) {
        if (key == courseInfo.main.course.id) {
          return colorMap[key]!;
        }
      }
    }
    return Colors.white;
  }

  void _initColorList() {
    colorMap = {};
    List<String> courseInfoList = courseTable!.getCourseIdList();
    int colorCount = courseInfoList.length;

    final colors = UIUtils.generateHarmoniousColors(12)..shuffle();

    for (int i = 0; i < colorCount; i++) {
      colorMap[courseInfoList[i]] = colors[i % colors.length];
    }
  }

  List<int> get getSectionIntList {
    List<int> intList = [];
    for (int i = 0; i < sectionLength; i++) {
      if (isHideN && i == 4) continue;
      if (isHideA && i == 10) continue;
      if (isHideB && i == 11) continue;
      if (isHideC && i == 12) continue;
      if (isHideD && i == 13) continue;
      intList.add(i);
    }
    return intList;
  }

  String getDayString(int day) {
    return dayStringList[day];
  }

  String getTimeString(int time) {
    return timeList[time];
  }

  String getSectionString(int section) {
    return sectionStringList[section];
  }
}
