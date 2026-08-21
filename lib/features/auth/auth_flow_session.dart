import 'package:flutter/foundation.dart';

/// 注册流程草稿，跨填写资料与验证码两个页面。
@immutable
class RegistrationDraft {
  const RegistrationDraft({
    required this.userName,
    required this.email,
    required this.password,
    required this.passwordConfirmation,
    required this.inviteCode,
  });

  final String userName;
  final String email;
  final String password;
  final String passwordConfirmation;
  final String inviteCode;
}

/// 找回密码草稿：验证码在第二步写入，第三步消费。
@immutable
class PasswordResetDraft {
  const PasswordResetDraft({required this.email, required this.code});

  final String email;
  final String code;

  PasswordResetDraft withCode(String code) =>
      PasswordResetDraft(email: email, code: code);
}

/// 认证流程的内存草稿，存有明文密码，不持久化。
/// 进程重启后草稿丢失，页面由 guard 退回流程起点。
class AuthFlowSession {
  AuthFlowSession._();

  static final AuthFlowSession instance = AuthFlowSession._();

  RegistrationDraft? _registration;
  PasswordResetDraft? _passwordReset;

  RegistrationDraft? get registration => _registration;

  PasswordResetDraft? get passwordReset => _passwordReset;

  void setRegistration(RegistrationDraft draft) => _registration = draft;

  void clearRegistration() => _registration = null;

  void setPasswordReset(PasswordResetDraft draft) => _passwordReset = draft;

  void clearPasswordReset() => _passwordReset = null;
}
