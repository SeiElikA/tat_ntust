/// NTUST Moodle 課名的純函式。
class MoodleCourseNameUtils {
  MoodleCourseNameUtils._();

  /// NTUST 課名前綴 `115.1【AT1001301】`；容忍沒有「.」與前後空白。
  static final RegExp _coursePrefix =
      RegExp(r'^\s*\d{3}\.?[0-9A-Za-z]\s*【[^】]*】\s*');

  /// 去掉前綴；去完是空字串就退回原字串（trim 過），不比對到就原樣回傳。
  static String stripCoursePrefix(String name) {
    final trimmed = name.trim();
    final stripped = trimmed.replaceFirst(_coursePrefix, '').trim();
    return stripped.isEmpty ? trimmed : stripped;
  }
}
