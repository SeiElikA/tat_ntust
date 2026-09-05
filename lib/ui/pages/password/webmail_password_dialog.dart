import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/ui/pages/password/password_field.dart';
import 'package:flutter_app/src/store/model.dart';
import 'package:get/get.dart';

class WebMailPasswordDialog extends StatefulWidget {
  const WebMailPasswordDialog({super.key});

  @override
  State<StatefulWidget> createState() => _WebMailPasswordDialogState();
}

class _WebMailPasswordDialogState extends State<WebMailPasswordDialog> {
  final TextEditingController _originPasswordController =
      TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool passwordShow = false;
  final FocusNode _originPasswordFocus = FocusNode();
  String _originPasswordErrorMessage = "";

  @override
  void dispose() {
    // TextEditingController 會一路持有使用者剛剛輸入的 WebMail 明文密碼，
    // 對話框關掉之後若不 dispose，它會跟著 State 一起留在記憶體裡；
    // FocusNode 沒 dispose 也會留在 focus tree 上並持續發通知。
    _originPasswordController.dispose();
    _originPasswordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Center(
        child: Text(
          R.current.pleaseEnterWebMailPassword,
          textAlign: TextAlign.center,
        ),
      ),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20))),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PasswordField(
              controller: _originPasswordController,
              focusNode: _originPasswordFocus,
              obscured: !passwordShow,
              onToggleObscured: () =>
                  setState(() => passwordShow = !passwordShow),
              hintText: R.current.password,
              validator: (value) => _validatorOriginPassword(value!),
              errorMessage: _originPasswordErrorMessage,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(R.current.cancel),
          onPressed: () => Get.back<bool>(result: false),
        ),
        TextButton(
          child: Text(R.current.sure),
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              Model.instance.setWebMailPassword(_originPasswordController.text);
              await Model.instance.saveUserData();
              Get.back<bool>(result: true);
            }
          },
        )
      ],
    );
  }

  String? _validatorOriginPassword(String value) {
    _originPasswordErrorMessage = "";
    if (value.isEmpty) {
      _originPasswordErrorMessage = R.current.passwordNull;
    }
    return _originPasswordErrorMessage.isEmpty
        ? null
        : _originPasswordErrorMessage;
  }
}
