import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/network/api_error.dart';
import 'api/api_client.dart';
import 'app_runtime.dart';
import 'repositories/reader_font_repository.dart';
import 'session/auth_controller.dart';
import 'settings/app_settings.dart';

/// 全局重试策略，由 `main` 挂到 `ProviderScope` 上。
///
/// Riverpod 默认对任意 Exception 退避重试十次（累计约 38 秒）。
/// 一般重试三次就够了，不然要等好久...
Duration? apiRetry(int retryCount, Object error) {
  if (isCancellation(error)) return null;
  if (error is! ApiError || error.category != ApiErrorCategory.network) {
    return null;
  }
  return ProviderContainer.defaultRetry(retryCount, error, maxRetries: 3);
}

/// 由 `main` 在 `ProviderScope` 中覆盖。
final Provider<AppRuntime> appRuntimeProvider = Provider<AppRuntime>(
  (ref) => throw UnimplementedError('appRuntimeProvider 必须在启动时覆盖。'),
);

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>(
  (ref) => ref.watch(appRuntimeProvider).api,
);

final ChangeNotifierProvider<AuthController> authControllerProvider =
    ChangeNotifierProvider<AuthController>(
      (ref) => ref.watch(appRuntimeProvider).auth,
    );

final ChangeNotifierProvider<SettingsController> settingsControllerProvider =
    ChangeNotifierProvider<SettingsController>(
      (ref) => ref.watch(appRuntimeProvider).settings,
    );

final Provider<AppSettings> appSettingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(settingsControllerProvider).settings,
);

final Provider<AuthenticationSnapshot> authSnapshotProvider =
    Provider<AuthenticationSnapshot>(
      (ref) => ref.watch(authControllerProvider).snapshot,
    );

final Provider<ReaderFontRepository> readerFontRepositoryProvider =
    Provider<ReaderFontRepository>((ref) => const ReaderFontRepository());
