import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/providers.dart';
import 'auth_flow_session.dart';
import 'widgets/auth_form_scaffold.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final TextEditingController _email = TextEditingController();

  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// 不做本地校验，邮箱格式交给发送验证码时报错。
  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final String email = _email.text.trim();
    try {
      await ref.read(authControllerProvider).sendResetCode(email);
      if (!mounted) return;
      AuthFlowSession.instance.setPasswordReset(
        PasswordResetDraft(email: email, code: ''),
      );
      setState(() => _isSubmitting = false);
      context.push('/reset-password/verify');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiError ? error.message : '无法发送验证码，请重试。';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      appBarTitle: '找回',
      title: '重置密码',
      description: '输入账号邮箱，我们会向你发送一个 4 位验证码。',
      children: <Widget>[
        AuthTextField(
          controller: _email,
          hintText: '邮箱',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          autofillHints: const <String>[AutofillHints.email],
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 14),
          AuthFormError(message: _error),
        ],
        const SizedBox(height: 14),
        AuthSubmitButton(
          label: '发送验证码',
          submittingLabel: '正在发送验证码…',
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
        const SizedBox(height: 14),
        AuthFooterLink(
          label: '返回登录',
          onPressed: () => context.pushReplacement('/sign-in/credentials'),
        ),
      ],
    );
  }
}
