import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'api/api_client.dart';
import 'app_runtime.dart';
import 'session/auth_controller.dart';
import 'settings/app_settings.dart';

/// 由 `main` 在 `ProviderScope` 中覆盖。
final Provider<AppRuntime> appRuntimeProvider = Provider<AppRuntime>(
  (ref) => throw UnimplementedError('appRuntimeProvider 必须在启动时覆盖。'),
);

final Provider<ApiClient> apiClientProvider =
    Provider<ApiClient>((ref) => ref.watch(appRuntimeProvider).api);

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
