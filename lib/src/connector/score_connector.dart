import 'dart:async';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/score/score_json.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide CookieManager;
import 'package:html/dom.dart';
import 'package:html/parser.dart';

class ScoreConnector {
  static const host = "https://stuinfosys.ntust.edu.tw";
  static const _scoreUrl = "$host/StuScoreQueryServ/StuScoreQuery/DisplayAll";

  static String clearString(String v) {
    return v.replaceAll("\n", "").trim(); //trim去除兩旁空格
  }

  static Future<ScoreRankJson?> getScoreRank() async {
    List<Element> items = [];
    ScoreRankJson info = ScoreRankJson();

    try {
      Completer<String> completer = Completer();
      final webView = HeadlessInAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_scoreUrl)),
          onLoadStop: (controller, url) async {
            final html = await controller.getHtml();
            completer.complete(html);
          }
      );
      await webView.run();

      final result = await completer.future;

      final tagNode = parse(result);
      final nodes = tagNode.getElementsByClassName("box-content alerts");
      //排名
      try {
        items = nodes[0]
            .getElementsByTagName("tbody")[0]
            .getElementsByTagName("tr");
        for (final node in items) {
          var i = node.getElementsByTagName("td");
          SemesterJson semester = SemesterJson(
            year: clearString(i[0].text).substring(0, 3),
            semester: clearString(i[0].text).substring(3),
          );
          RankJson rank = RankJson(
            classRank: clearString(i[1].text),
            departmentRank: clearString(i[2].text),
            averageScore: clearString(i[3].text),
            classRankYears: clearString(i[4].text),
            departmentRankYears: clearString(i[5].text),
            averageYears: clearString(i[6].text),
          );
          info.addRankBySemester(semester, rank);
        }
      } catch (e) {
        Log.d(e);
      }

      //成績
      if (nodes.length >= 2) {
        items = nodes[1]
            .getElementsByTagName("tbody")[0]
            .getElementsByTagName("tr");
      }

      for (final node in items) {
        var i = node.getElementsByTagName("td");
        SemesterJson semester = SemesterJson(
          year: clearString(i[1].text).substring(0, 3),
          semester: clearString(i[1].text).substring(3),
        );
        String score = clearString(i[5].text);
        if (["成績未到", "Grades not yet"].contains(score)) {
          score = "-";
        }
        ScoreItemJson item = ScoreItemJson(
          courseId: clearString(i[2].text),
          name: clearString(i[3].text),
          credit: clearString(i[4].text),
          score: score,
          remark: clearString(i[6].text),
          generalDimension: clearString(i[7].text),
        );
        info.addScoreBySemester(semester, item);
      }
      return info;
    } catch (e, stack) {
      Log.eWithStack(e.toString(), stack);
      return null;
    }
  }
}