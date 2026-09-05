import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/course_table/course_table_json.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:flutter_app/ui/components/input/input_field.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:sprintf/sprintf.dart';

class CourseDetailDialog extends StatelessWidget {
  const CourseDetailDialog(
      {super.key,
      required this.courseInfo,
      required this.onDetailTap,
      required this.onRemoveTap,
      required this.onMoodleTap,
      required this.time});

  final CourseInfoJson courseInfo;
  final String time;
  final Function() onDetailTap;
  final Function() onRemoveTap;
  final Function() onMoodleTap;

  @override
  Widget build(BuildContext context) {
    CourseMainJson course = courseInfo.main.course;
    String classroomName = courseInfo.main.getClassroomName();
    String teacherName = courseInfo.main.getTeacherName();

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 10.0, 10.0),
      title: Text(course.name),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GestureDetector(
            child: Text(sprintf("%s : %s", [R.current.courseId, course.id])),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: course.id));
              unawaited(Fluttertoast.showToast(msg: R.current.copy_course_id));
            },
            onLongPress: () async {
              course.id = await _showEditDialog(course.id);
              // 改過的課號要確定寫進硬碟才算完成。
              await Model.instance.saveOtherSetting();
            },
          ),
          const SizedBox(height: 4),
          Text(sprintf("%s : %s", [R.current.time, time])),
          const SizedBox(height: 4),
          Text(sprintf("%s : %s", [R.current.location, classroomName])),
          const SizedBox(height: 4),
          Text(sprintf("%s : %s", [R.current.instructor, teacherName])),
        ],
      ),
      actions: [
        (courseInfo.main.course.select)
            ? TextButton(
                onPressed: () {
                  Get.back();
                  onMoodleTap();
                },
                child: Text(R.current.courseData),
              )
            : TextButton(
                onPressed: () {
                  Get.back();
                  onRemoveTap();
                },
                child: Text(R.current.remove),
              ),
        TextButton(
          onPressed: () {
            Get.back();
            onDetailTap();
          },
          child: Text(R.current.details),
        )
      ],
    );
  }

  Future<String> _showEditDialog(String value) async {
    final String? v =
        await Get.dialog<String>(_CourseIdEditDialog(value: value));
    return v ?? value;
  }
}

/// 長按課程代碼時跳出的編輯框。
///
/// TextEditingController 由這個 State 持有並釋放。不要在 _showEditDialog() 裡
/// 直接 new 一個丟進 AlertDialog——沒有人會 dispose，每長按一次就漏一個。
///
/// 也不能改成「await Get.dialog(...) 之後再 dispose」：那個 Future 在 pop 的
/// 當下就完成，對話框還要跑一段關閉動畫，期間 InputField 仍在讀這個 controller。
class _CourseIdEditDialog extends StatefulWidget {
  const _CourseIdEditDialog({required this.value});

  final String value;

  @override
  State<_CourseIdEditDialog> createState() => _CourseIdEditDialogState();
}

class _CourseIdEditDialogState extends State<_CourseIdEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.all(16.0),
      title: const Text('Edit'),
      content: Row(
        children: <Widget>[
          Expanded(
            child: InputField(
              controller: _controller,
              hint: widget.value,
            ),
          )
        ],
      ),
      actions: <Widget>[
        TextButton(
            child: Text(R.current.cancel),
            onPressed: () {
              Get.back(result: null);
            }),
        TextButton(
            child: Text(R.current.sure),
            onPressed: () {
              Get.back<String>(result: _controller.text);
            })
      ],
    );
  }
}
