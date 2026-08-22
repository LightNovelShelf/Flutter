import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/providers.dart';
import 'widgets/auth_form_scaffold.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.initialEmail});

  /// 重置密码完成后回跳时带回的邮箱，用于预填。
  final String? initialEmail;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final String email = _email.text.trim();
    final String password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入邮箱和密码。');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider).signIn(email, password);
      if (!mounted) return;
      context.go('/discover');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiError ? error.message : '登录失败，请重试。';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      appBarTitle: '登录',
      title: '欢迎回来',
      description: '登录后即可同步书架、历史记录和阅读进度。',
      children: <Widget>[
        AuthTextField(
          controller: _email,
          hintText: '邮箱',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.username],
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 13),
        AuthPasswordField(
          controller: _password,
          hintText: '密码',
          focusNode: _passwordFocus,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.password],
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 13),
        AuthFooterLink(
          label: '忘记密码？',
          alignment: Alignment.centerRight,
          onPressed: () => context.push('/reset-password'),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 13),
          AuthFormError(message: _error),
        ],
        const SizedBox(height: 13),
        AuthSubmitButton(
          label: '登录',
          submittingLabel: '正在登录…',
          isSubmitting: _isSubmitting,
          onPressed: _submit,
        ),
        const SizedBox(height: 13),
        AuthFooterLink(
          label: '初次使用轻书架？创建账号',
          onPressed: () => context.push('/register'),
        ),
      ],
    );
  }
}
