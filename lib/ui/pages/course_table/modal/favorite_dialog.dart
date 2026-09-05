import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

class FavoriteDialog extends StatelessWidget {
  const FavoriteDialog({super.key, required this.value, required this.onPressed, required this.onDelete});

  final List<CourseTableJson> value;
  final Function(int) onPressed;
  final Function(int) onDelete;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        width: double.minPositive,
        child: ListView.builder(
          itemCount: value.length,
          shrinkWrap: true, //使清單最小化
          itemBuilder: (BuildContext context, int index) {
            return SizedBox(
              height: 50,
              child: TextButton(
                onPressed: () => onPressed(index),
                onLongPress: () => showDeleteDialog(index),
                // 不放 studentName：現存的 querycourse 路徑一律寫死空字串，加上
                // 去會讓新存的課表多一個空格、舊的又有名字，同一份清單兩種樣子。
                child: Text(sprintf("%s %s-%s", [
                  value[index].studentId,
                  value[index].courseSemester.year,
                  value[index].courseSemester.semester
                ]), style: TextStyle(color: Get.theme.colorScheme.onSurface),),
              ),
            );
          },
        ),
      ),
    );
  }

  void showDeleteDialog(int index) {
    Get.dialog(
      AlertDialog.adaptive(
        title: Text(R.current.delete),
        actions: [
          TextButton(onPressed: Get.back, child: Text(R.current.cancel)),
          TextButton(onPressed: () {
            onDelete(index);
          }, child: Text(R.current.sure)),
        ],
      )
    );
  }
}
