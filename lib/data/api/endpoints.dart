/// 服务端地址常量。
///
/// `API_ORIGIN` 可在编译期覆盖（`--dart-define` / `dart run -D`），用于把客户端
/// 指向本地服务端。
class ServiceEndpoints {
  const ServiceEndpoints._();

  static const String apiOrigin = String.fromEnvironment(
    'API_ORIGIN',
    defaultValue: 'https://api.lightnovel.life',
  );
  static const String loginPath = '/api/user/login';
  static const String registerPath = '/api/user/register';
  static const String sendRegisterEmailPath = '/api/user/send_register_email';
  static const String sendResetEmailPath = '/api/user/send_reset_email';
  static const String resetPasswordPath = '/api/user/reset_password';
  static const String refreshTokenPath = '/api/user/refresh_token';
  static const String signalRHub = '$apiOrigin/hub/api';
}

/// 书架结构版本号。
const String shelfStructVersion = '20220211';
