import 'package:flutter/widgets.dart';

/// Lucide 圖示，只收錄本專案實際用到的常數，字體是自帶的
/// assets/fonts/lucide.ttf（不裝 lucide_icons_flutter，理由見 pubspec.yaml）。
///
/// 要加圖示：在 https://lucide.dev/icons/ 查名稱，碼位查
/// lucide_icons_flutter 3.1.18 的 assets/codepoints.json（就是這份 ttf 的來源）。
@staticIconProvider
class LucideIcons {
  const LucideIcons._();

  static const String _family = 'Lucide';

  /// arrow-down
  static const IconData arrowDown = IconData(0xe042, fontFamily: _family);

  /// arrow-left
  static const IconData arrowLeft = IconData(0xe048, fontFamily: _family);

  /// award
  static const IconData award = IconData(0xe04f, fontFamily: _family);

  /// bell
  static const IconData bell = IconData(0xe059, fontFamily: _family);

  /// book-open
  static const IconData bookOpen = IconData(0xe05f, fontFamily: _family);

  /// calendar
  static const IconData calendar = IconData(0xe063, fontFamily: _family);

  /// calendar-clock
  static const IconData calendarClock = IconData(0xe304, fontFamily: _family);

  /// calendar-days
  static const IconData calendarDays = IconData(0xe2b9, fontFamily: _family);

  /// camera
  static const IconData camera = IconData(0xe064, fontFamily: _family);

  /// chart-column
  static const IconData chartColumn = IconData(0xe2a3, fontFamily: _family);

  /// chevron-down
  static const IconData chevronDown = IconData(0xe06d, fontFamily: _family);

  /// chevron-left
  static const IconData chevronLeft = IconData(0xe06e, fontFamily: _family);

  /// chevron-right
  static const IconData chevronRight = IconData(0xe06f, fontFamily: _family);

  /// chevron-up
  static const IconData chevronUp = IconData(0xe070, fontFamily: _family);

  /// circle-alert
  static const IconData circleAlert = IconData(0xe077, fontFamily: _family);

  /// clipboard-check
  static const IconData clipboardCheck = IconData(0xe219, fontFamily: _family);

  /// clipboard-list
  static const IconData clipboardList = IconData(0xe086, fontFamily: _family);

  /// clock
  static const IconData clock = IconData(0xe087, fontFamily: _family);

  /// code-xml
  static const IconData codeXml = IconData(0xe206, fontFamily: _family);

  /// copy
  static const IconData copy = IconData(0xe09e, fontFamily: _family);

  /// download
  static const IconData download = IconData(0xe0b2, fontFamily: _family);

  /// ellipsis-vertical
  static const IconData ellipsisVertical =
      IconData(0xe0b7, fontFamily: _family);

  /// external-link
  static const IconData externalLink = IconData(0xe0b9, fontFamily: _family);

  /// eye
  static const IconData eye = IconData(0xe0ba, fontFamily: _family);

  /// eye-off
  static const IconData eyeOff = IconData(0xe0bb, fontFamily: _family);

  /// file-check-2
  static const IconData fileCheck2 = IconData(0xe0c2, fontFamily: _family);

  /// file-question
  static const IconData fileQuestion = IconData(0xe322, fontFamily: _family);

  /// file-text
  static const IconData fileText = IconData(0xe0cc, fontFamily: _family);

  /// folder
  static const IconData folder = IconData(0xe0d7, fontFamily: _family);

  /// graduation-cap
  static const IconData graduationCap = IconData(0xe234, fontFamily: _family);

  /// history
  static const IconData history = IconData(0xe1f5, fontFamily: _family);

  /// image-off
  static const IconData imageOff = IconData(0xe1c0, fontFamily: _family);

  /// images
  static const IconData images = IconData(0xe5c4, fontFamily: _family);

  /// info
  static const IconData info = IconData(0xe0f9, fontFamily: _family);

  /// key-round
  static const IconData keyRound = IconData(0xe4a3, fontFamily: _family);

  /// link
  static const IconData link = IconData(0xe102, fontFamily: _family);

  /// list-ordered
  static const IconData listOrdered = IconData(0xe1d1, fontFamily: _family);

  /// log-in
  static const IconData logIn = IconData(0xe10d, fontFamily: _family);

  /// log-out
  static const IconData logOut = IconData(0xe10e, fontFamily: _family);

  /// megaphone
  static const IconData megaphone = IconData(0xe235, fontFamily: _family);

  /// menu
  static const IconData menu = IconData(0xe115, fontFamily: _family);

  /// message-square
  static const IconData messageSquare = IconData(0xe117, fontFamily: _family);

  /// messages-square
  static const IconData messagesSquare = IconData(0xe40d, fontFamily: _family);

  /// minus
  static const IconData minus = IconData(0xe11c, fontFamily: _family);

  /// pencil
  static const IconData pencil = IconData(0xe1f9, fontFamily: _family);

  /// pin
  static const IconData pin = IconData(0xe259, fontFamily: _family);

  /// plus
  static const IconData plus = IconData(0xe13d, fontFamily: _family);

  /// puzzle
  static const IconData puzzle = IconData(0xe29c, fontFamily: _family);

  /// refresh-cw
  static const IconData refreshCw = IconData(0xe145, fontFamily: _family);

  /// reply
  static const IconData reply = IconData(0xe22a, fontFamily: _family);

  /// search
  static const IconData search = IconData(0xe151, fontFamily: _family);

  /// settings
  static const IconData settings = IconData(0xe154, fontFamily: _family);

  /// shield-check
  static const IconData shieldCheck = IconData(0xe1ff, fontFamily: _family);

  /// tag
  static const IconData tag = IconData(0xe17f, fontFamily: _family);

  /// timer
  static const IconData timer = IconData(0xe1e0, fontFamily: _family);

  /// trash-2
  static const IconData trash2 = IconData(0xe18e, fontFamily: _family);

  /// triangle-alert
  static const IconData triangleAlert = IconData(0xe193, fontFamily: _family);

  /// user
  static const IconData user = IconData(0xe19f, fontFamily: _family);

  /// users
  static const IconData users = IconData(0xe1a4, fontFamily: _family);

  /// vote
  static const IconData vote = IconData(0xe3ad, fontFamily: _family);

  /// x
  static const IconData x = IconData(0xe1b2, fontFamily: _family);
}
