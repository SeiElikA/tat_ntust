import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';

/// 密碼輸入欄位，附眼睛切換與底下的錯誤訊息列。
/// `CheckPasswordDialog` 與 `WebMailPasswordDialog` 共用這一份。
///
/// **共用的只有外觀與可及性，不含 validator。** 一個在比對既有的秘密，一個在
/// 儲存新的秘密，合起來會讓「驗證」與「寫入」共用同一段邏輯，所以 [validator]
/// 由呼叫端傳入。
class PasswordField extends StatelessWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.obscured,
    required this.onToggleObscured,
    required this.hintText,
    required this.validator,
    required this.errorMessage,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// true 代表目前是遮住的。
  final bool obscured;
  final VoidCallback onToggleObscured;

  final String hintText;
  final String? Function(String?) validator;

  /// 顯示在欄位下方的錯誤訊息。空字串代表不顯示。
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 2,
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  cursorColor: Colors.blue[800],
                  textInputAction: TextInputAction.done,
                  focusNode: focusNode,
                  onEditingComplete: focusNode.unfocus,
                  obscureText: obscured,
                  validator: validator,
                  decoration: InputDecoration(
                    hintText: hintText,
                    // 錯誤訊息自己畫在下面，這裡把內建的那條壓成零高度，
                    // 否則對話框會在輸入錯誤時跳一下。
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                ),
              ),
              IconButton(
                // 純圖示按鈕沒有 tooltip 時，螢幕閱讀器只唸得出「按鈕」，也唸不
                // 出密碼目前是顯示還是隱藏。tooltip 會轉成 semantics label，文案
                // 要跟著狀態走：現在藏著就唸「顯示密碼」（按下去會發生的事）。
                tooltip:
                    obscured ? R.current.showPassword : R.current.hidePassword,
                icon: Icon(
                    obscured ? EvaIcons.eyeOffOutline : EvaIcons.eyeOutline),
                onPressed: onToggleObscured,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (errorMessage.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}
