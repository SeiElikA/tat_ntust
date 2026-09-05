import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:get/get.dart';
import 'package:numberpicker/numberpicker.dart';

/// 手動挑年度與學期的對話框。
///
/// [allowSelectNull] 為 false 時，使用者沒有選就回「現在這個學期」而不是 null：
/// 呼叫端在那條路徑上沒有 null 的處理。
Future<SemesterJson?> manualSemesterDialog(
    {allowSelectNull = false}) async {
  DateTime dateTime = DateTime.now();
  int year = dateTime.year - 1911;
  int semester = (dateTime.month <= 7 && dateTime.month >= 1) ? 2 : 1;
  if (dateTime.month <= 7) {
    year--;
  }
  SemesterJson before =
      SemesterJson(semester: semester.toString(), year: year.toString());
  SemesterJson? select = await Get.dialog<SemesterJson>(
    StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        return AlertDialog(
          title: Text(R.current.selectSemester),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: NumberPicker(
                        value: year,
                        minValue: 100,
                        maxValue: 120,
                        onChanged: (value) => setState(() => year = value)),
                  ),
                  Expanded(
                    child: NumberPicker(
                        value: semester,
                        minValue: 1,
                        maxValue: 3,
                        onChanged: (value) =>
                            setState(() => semester = value)),
                  ),
                ],
              )
            ],
          ),
          actions: [
            TextButton(
                child: Text(R.current.sure),
                onPressed: () {
                  Get.back<SemesterJson>(
                    result: SemesterJson(
                      semester: (semester == 3) ? "H" : semester.toString(),
                      year: year.toString(),
                    ),
                  );
                })
          ],
        );
      },
    ),
    barrierDismissible: false,
  );
  if (!allowSelectNull) {
    select ??= before;
  }
  return select;
}
