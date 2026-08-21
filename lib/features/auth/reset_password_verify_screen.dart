import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/providers.dart';
import 'auth_flow_session.dart';
import 'widgets/auth_form_scaffold.dart';
import 'widgets/verification_code_field.dart';

class ResetPasswordVerifyScreen extends ConsumerStatefulWidget {
  const ResetPasswordVerifyScreen({super.key});

  @override
  ConsumerState<ResetPasswordVerifyScreen> createState() =>
      _ResetPasswordVerifyScreenState();
}

class _ResetPasswordVerifyScreenState
    extends ConsumerState<ResetPasswordVerifyScreen> {
  static const int _cooldownSeconds = 60;

  final TextEditingController _code = TextEditingController();

  PasswordResetDraft? _draft;
  Timer? _ticker;
  int _cooldown = _cooldownSeconds;
  bool _isSending = false;
  bool _showInvalid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = AuthFlowSession.instance.passwordReset;
    if (_draft == null) {
      // 草稿只在内存中，进程重启或深链直达时退回流程起点。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/reset-password');
      });
      return;
    }
    _code.addListener(_handleCodeChanged);
    _startCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.removeListener(_handleCodeChanged);
    _code.dispose();
    super.dispose();
  }

  void _handleCodeChanged() {
    if (!_showInvalid) return;
    setState(() => _showInvalid = false);
  }

  /// initState 也会调用，因此不能 setState，重建由调用方负责。
  void _startCooldown() {
    _ticker?.cancel();
    _cooldown = _cooldownSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    final PasswordResetDraft? draft = _draft;
    if (draft == null || _isSending || _cooldown > 0) return;

    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider).sendResetCode(draft.email);
      if (!mounted) return;
      setState(_startCooldown);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiError ? error.message : '无法发送验证码，请重试。',
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// 只做本地校验并写回草稿，没有网络请求。
  void _submit() {
    final PasswordResetDraft? draft = _draft;
    if (draft == null) return;

    final String code = _code.text.trim();
    if (code.length != VerificationCodeField.length) {
      setState(() {
        _error = '请输入 4 位验证码。';
        _showInvalid = true;
      });
      return;
    }

    AuthFlowSession.instance.setPasswordReset(draft.withCode(code));
    context.push('/reset-password/new-password');
  }

  @override
  Widget build(BuildContext context) {
    final PasswordResetDraft? draft = _draft;
    if (draft == null) return const SizedBox.shrink();

    return AuthFormScaffold(
      appBarTitle: '找回',
      title: '查看邮箱',
      description: '请输入发送至 ${draft.email} 的 4 位验证码。',
      children: <Widget>[
        VerificationCodeField(
          controller: _code,
          isInvalid: _showInvalid,
          isSending: _isSending,
          cooldownSeconds: _cooldown,
          onResend: _resend,
          onSubmitted: _submit,
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 18),
          AuthFormError(message: _error),
        ],
        const SizedBox(height: 18),
        AuthSubmitButton(
          label: '继续',
          submittingLabel: '继续',
          isSubmitting: false,
          onPressed: _submit,
        ),
      ],
    );
  }
}
