import 'package:flutter/material.dart';
import 'package:flutter_app/src/R.dart';
import 'package:flutter_app/src/repository/result.dart';
import 'package:flutter_app/ui/components/page/loading_page.dart';
import 'package:get/get.dart';
import 'package:flutter_app/ui/other/lucide_icons.dart';

/// 把 [Result] 三態畫成畫面：controller 持 `Rxn<Result<T>>`，`build()` 不觸發
/// 請求。[Stale] 多一條橫幅，使用者才知道自己看的是舊資料。
class ResultView<T> extends StatelessWidget {
  const ResultView({
    super.key,
    required this.state,
    required this.builder,
    required this.errorBuilder,
    this.onRetry,
    this.shrinkWrap = false,
  });

  /// null 代表還在載入。
  final Rx<Result<T>?> state;

  /// 放在可捲動清單裡時要開：那種位置高度沒有上限，`Expanded` 會炸、
  /// `Positioned.fill` 也撐不開。
  final bool shrinkWrap;

  final Widget Function(T data) builder;

  /// 失敗時要畫什麼。由呼叫端注入而不是直接用 `ErrorPage`，
  /// 見 docs/ARCHITECTURE.md「UI 慣例」。
  final Widget Function(String message) errorBuilder;

  /// 失敗畫面上的重試入口。null 就不顯示。
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final result = state.value;
      if (result == null) {
        const loading = LoadingPage(isLoading: true, isShowBackground: false);
        return shrinkWrap
            ? const SizedBox(height: 120, child: loading)
            : loading;
      }
      return switch (result) {
        Ok<T>(:final data) => builder(data),
        Stale<T>(:final data, :final reason) => Column(
            mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
            children: [
              _StaleBanner(message: reason.message, onRetry: onRetry),
              if (shrinkWrap) builder(data) else Expanded(child: builder(data)),
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
            Icon(LucideIcons.history, size: 16, color: scheme.onSurfaceVariant),
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
