import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/providers.dart';
import 'auth_flow_session.dart';
import 'widgets/auth_form_scaffold.dart';
import 'widgets/verification_code_field.dart';

class RegisterVerifyScreen extends ConsumerStatefulWidget {
  const RegisterVerifyScreen({super.key});

  @override
  ConsumerState<RegisterVerifyScreen> createState() =>
      _RegisterVerifyScreenState();
}

class _RegisterVerifyScreenState extends ConsumerState<RegisterVerifyScreen> {
  static const int _cooldownSeconds = 60;

  final TextEditingController _code = TextEditingController();

  RegistrationDraft? _draft;
  Timer? _ticker;
  int _cooldown = _cooldownSeconds;
  bool _isSending = false;
  bool _isSubmitting = false;
  bool _showInvalid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = AuthFlowSession.instance.registration;
    if (_draft == null) {
      // 草稿只存在于内存中：进程重启或深链直达时退回流程起点。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/register');
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

  /// initState 也会调用，所以这里不能 setState，重建由调用方决定。
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
    final RegistrationDraft? draft = _draft;
    if (draft == null || _isSending || _cooldown > 0) return;

    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider).sendRegisterCode(draft.email);
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

  Future<void> _submit() async {
    final RegistrationDraft? draft = _draft;
    if (draft == null || _isSubmitting) return;

    final String code = _code.text.trim();
    if (code.length != VerificationCodeField.length) {
      setState(() {
        _error = '请输入 4 位验证码。';
        _showInvalid = true;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider).register(
            userName: draft.userName,
            email: draft.email,
            password: draft.password,
            passwordConfirmation: draft.passwordConfirmation,
            code: code,
            inviteCode: draft.inviteCode,
          );
      AuthFlowSession.instance.clearRegistration();
      if (!mounted) return;
      context.go('/discover');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiError ? error.message : '无法创建账号，请重试。';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final RegistrationDraft? draft = _draft;
    if (draft == null) return const SizedBox.shrink();

    return AuthFormScaffold(
      appBarTitle: '注册',
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
          label: '创建账号',
          submittingLabel: '正在创建账号…',
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
