import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/components/page/loading_page.dart';
import 'package:get/get.dart';

/// 把 [Result] 三態畫成畫面。
///
/// 樣板：controller 持一個 `Rxn<Result<T>>`（null 代表還在載入），頁面只負責
/// 把它畫出來，`build()` 不觸發任何請求。
///
/// [Stale] 會在內容上方多一條橫幅：「抓到新資料」與「沒抓到但讀得回快取」必須
/// 在畫面上分得開，否則使用者不知道自己看的是舊資料。
class ResultView<T> extends StatelessWidget {
  const ResultView({
    super.key,
    required this.state,
    required this.builder,
    required this.errorBuilder,
    this.onRetry,
  });

  /// null 代表還在載入。
  final Rx<Result<T>?> state;

  final Widget Function(T data) builder;

  /// 失敗時要畫什麼。由呼叫端注入而不是在這裡直接用 `ErrorPage`：
  /// `error_page.dart` import `route_utils.dart`，而後者 import 所有頁面，直接用
  /// 會把這個檔案拉進 lib/ui 那個大環裡。「錯誤長什麼樣」是頁面的事，這裡只負責
  /// 狀態對映。
  final Widget Function(String message) errorBuilder;

  /// 失敗畫面上的重試入口。null 就不顯示。
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final result = state.value;
      if (result == null) {
        return const LoadingPage(isLoading: true, isShowBackground: false);
      }
      return switch (result) {
        Ok<T>(:final data) => builder(data),
        Stale<T>(:final data, :final reason) => Column(
            children: [
              _StaleBanner(message: reason.message, onRetry: onRetry),
              Expanded(child: builder(data)),
            ],
          ),
        Failed<T>(:final reason) => errorBuilder(reason.message),
      };
    });
  }
}

/// 「你看到的是舊資料」的橫幅。
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.message, this.onRetry});

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.history, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(R.current.refresh),
              ),
          ],
        ),
      ),
    );
  }
}
