import 'package:flutter/material.dart';
import 'package:flutter_app/src/config/app_styles.dart';
import 'package:google_fonts/google_fonts.dart';

/// 兩套主題共用的字體設定。
///
/// 用 google_fonts 在執行期抓 Noto Sans TC，不內建字體檔（省 APK 體積）。
/// 選 Noto Sans TC 是因為它是唯一字形完整、不會缺字的選項：M PLUS
/// Rounded 1c 風格較近但是日文字體，繁中獨有的字會掉回系統字體，
/// 同一行混兩種字型。
///
/// 抓不到字體時 google_fonts 會回退到系統字體，離線首啟照常可用，只是字型不同。
class AppThemes {
  static ThemeData lightTheme(ColorScheme? lightDynamic) =>
      _withFont(ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          dialogTheme: AppStyles.dialogTheme(),
          iconTheme: AppStyles.iconTheme(),
          colorScheme: ColorScheme.fromSeed(
            seedColor: lightDynamic?.primary ?? Colors.blue,
            brightness: Brightness.light,
          )));

  static ThemeData darkTheme(ColorScheme? darkDynamic) =>
      _withFont(ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          dialogTheme: AppStyles.dialogTheme(),
          iconTheme: AppStyles.iconTheme(),
          colorScheme: ColorScheme.fromSeed(
            seedColor: darkDynamic?.primary ?? Colors.blue,
            brightness: Brightness.dark,
          )));

  /// 套字體。
  ///
  /// 以 `base.textTheme` 當基底，亮暗兩套主題各自的文字顏色與 Material 3
  /// 字級才會保留下來，只換字型。
  static ThemeData _withFont(ThemeData base) => base.copyWith(
        textTheme: GoogleFonts.notoSansTcTextTheme(base.textTheme),
        primaryTextTheme:
            GoogleFonts.notoSansTcTextTheme(base.primaryTextTheme),
      );
}
