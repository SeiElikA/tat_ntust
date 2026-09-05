import 'dart:convert';

import 'package:flutter_app/src/model/moodle_webapi/moodle_core_course_get_contents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Contents.mimetype', () {
    test('回應帶 mimetype 時解析出來', () {
      final c = Contents.fromJson({
        'type': 'file',
        'filename': 'week1.pdf',
        'filepath': '/',
        'filesize': 1234,
        'fileurl':
            'https://moodle.ntust.edu.tw/webservice/pluginfile.php/1/week1.pdf',
        'mimetype': 'application/pdf',
        'timemodified': 1700000000,
      });

      expect(c.filename, 'week1.pdf');
      expect(c.mimetype, 'application/pdf');
    });

    test('欄位缺席或為 null 都退回空字串（舊站台、舊快取）', () {
      expect(Contents.fromJson({'filename': 'a.pdf'}).mimetype, '');
      expect(
          Contents.fromJson({'filename': 'a.pdf', 'mimetype': null}).mimetype,
          '');
    });

    test('toJson / fromJson 往返保留 mimetype，寫進快取再讀回來不會變成空字串', () {
      final original = Contents(filename: 'a.pdf', mimetype: 'application/pdf');
      final restored =
          Contents.fromJson(json.decode(json.encode(original.toJson())));

      expect(restored.mimetype, 'application/pdf');
    });

    test('整段 section → module → contents 都解得出來', () {
      final section = MoodleCoreCourseGetContents.fromJson({
        'id': 1,
        'name': '第一週',
        'visible': 1,
        'summary': '',
        'summaryformat': 1,
        'modules': [
          {
            'id': 10,
            'name': '講義',
            'modname': 'resource',
            'modicon':
                'https://moodle.ntust.edu.tw/theme/image.php/boost/core/1/f/pdf',
            'contents': [
              {'filename': 'week1.pdf', 'mimetype': 'application/pdf'},
            ],
          },
        ],
      });

      final module = section.modules.single;
      expect(module.modname, 'resource');
      expect(module.modicon, endsWith('/f/pdf'));
      expect(module.contents.single.mimetype, 'application/pdf');
    });
  });
}
