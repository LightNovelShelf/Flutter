import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/providers.dart';
import 'auth_flow_session.dart';
import 'widgets/auth_form_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final TextEditingController _userName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirmation = TextEditingController();
  final TextEditingController _inviteCode = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _passwordConfirmationFocus = FocusNode();
  final FocusNode _inviteCodeFocus = FocusNode();

  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _userName.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    _inviteCode.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _passwordConfirmationFocus.dispose();
    _inviteCodeFocus.dispose();
    super.dispose();
  }

  /// 邮箱不做本地校验，交给发送验证码时报错。
  String? _validate() {
    if (_userName.text.trim().isEmpty) return '请输入用户名。';
    if (_password.text.length < 8) return '密码至少需要 8 个字符。';
    if (_password.text != _passwordConfirmation.text) return '两次输入的密码不一致。';
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final String? invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final String email = _email.text.trim();
    try {
      await ref.read(authControllerProvider).sendRegisterCode(email);
      if (!mounted) return;
      AuthFlowSession.instance.setRegistration(
        RegistrationDraft(
          userName: _userName.text.trim(),
          email: email,
          password: _password.text,
          passwordConfirmation: _passwordConfirmation.text,
          inviteCode: _inviteCode.text.trim(),
        ),
      );
      setState(() => _isSubmitting = false);
      context.push('/register/verify');
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
      appBarTitle: '注册',
      title: '创建账号',
      description: '填写账号信息。我们会向你的邮箱发送一个 4 位验证码。',
      children: <Widget>[
        AuthTextField(
          controller: _userName,
          hintText: '用户名',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.newUsername],
          onSubmitted: (_) => _emailFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: _email,
          hintText: '邮箱',
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.email],
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        AuthPasswordField(
          controller: _password,
          hintText: '密码',
          focusNode: _passwordFocus,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.newPassword],
          onSubmitted: (_) => _passwordConfirmationFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        AuthPasswordField(
          controller: _passwordConfirmation,
          hintText: '确认密码',
          focusNode: _passwordConfirmationFocus,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.newPassword],
          onSubmitted: (_) => _inviteCodeFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: _inviteCode,
          hintText: '邀请码（可选）',
          focusNode: _inviteCodeFocus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 14),
          AuthFormError(message: _error),
        ],
        const SizedBox(height: 14),
        AuthSubmitButton(
          label: '继续',
          submittingLabel: '正在发送验证码…',
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
        const SizedBox(height: 14),
        AuthFooterLink(
          label: '已有账号？登录',
          onPressed: () => context.pushReplacement('/sign-in/credentials'),
        ),
      ],
    );
  }
}
