import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/providers.dart';
import 'auth_flow_session.dart';
import 'widgets/auth_form_scaffold.dart';

class ResetPasswordNewScreen extends ConsumerStatefulWidget {
  const ResetPasswordNewScreen({super.key});

  @override
  ConsumerState<ResetPasswordNewScreen> createState() =>
      _ResetPasswordNewScreenState();
}

class _ResetPasswordNewScreenState
    extends ConsumerState<ResetPasswordNewScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirmation = TextEditingController();
  final FocusNode _passwordConfirmationFocus = FocusNode();

  PasswordResetDraft? _draft;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final PasswordResetDraft? draft = AuthFlowSession.instance.passwordReset;
    // 没有验证码说明用户没走完前两步，退回流程起点。
    if (draft == null || draft.code.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/reset-password');
      });
      return;
    }
    _draft = draft;
  }

  @override
  void dispose() {
    _password.dispose();
    _passwordConfirmation.dispose();
    _passwordConfirmationFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final PasswordResetDraft? draft = _draft;
    if (draft == null || _isSubmitting) return;

    if (_password.text.length < 8) {
      setState(() => _error = '密码至少需要 8 个字符。');
      return;
    }
    if (_password.text != _passwordConfirmation.text) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider).resetPassword(
            email: draft.email,
            password: _password.text,
            passwordConfirmation: _passwordConfirmation.text,
            code: draft.code,
          );
      AuthFlowSession.instance.clearPasswordReset();
      if (!mounted) return;
      // 带回邮箱，登录页直接预填。
      context.go(
        '/sign-in/credentials?email=${Uri.encodeQueryComponent(draft.email)}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiError ? error.message : '无法重置密码，请重试。';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_draft == null) return const SizedBox.shrink();

    return AuthFormScaffold(
      appBarTitle: '找回',
      title: '设置新密码',
      description: '请设置一个至少包含 8 个字符的新密码。',
      children: <Widget>[
        AuthPasswordField(
          controller: _password,
          hintText: '新密码',
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.newPassword],
          onSubmitted: (_) => _passwordConfirmationFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        AuthPasswordField(
          controller: _passwordConfirmation,
          hintText: '确认新密码',
          focusNode: _passwordConfirmationFocus,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.newPassword],
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 14),
          AuthFormError(message: _error),
        ],
        const SizedBox(height: 14),
        AuthSubmitButton(
          label: '重置密码',
          submittingLabel: '正在重置密码…',
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
