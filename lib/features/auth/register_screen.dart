import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_error.dart';
import '../../data/providers.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../settings/about_settings_screen.dart';
import 'auth_flow_session.dart';
import 'widgets/auth_form_scaffold.dart';
import 'widgets/auth_turnstile.dart';

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

  final GlobalKey<AuthTurnstileState> _turnstile =
      GlobalKey<AuthTurnstileState>();

  String? _error;
  String? _turnstileToken;
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
    final String? token = _turnstileToken;
    if (token == null) {
      setState(() => _error = '请先完成人机验证。');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final String email = _email.text.trim();
    try {
      await ref.read(authControllerProvider).sendRegisterCode(email, token);
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
    } finally {
      _turnstile.currentState?.reset();
    }
  }

  Future<void> _openWebRegister() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse('$officialWebsiteUrl/register'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      await showAppAlert(context: context, title: '无法打开链接', message: '请稍后重试。');
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
        const SizedBox(height: 14),
        AuthTurnstile(
          key: _turnstile,
          action: 'register',
          onTokenChanged: (String? token) {
            if (mounted) setState(() => _turnstileToken = token);
          },
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
          onPressed: _turnstileToken == null ? null : _submit,
        ),
        const SizedBox(height: 14),
        AuthFooterLink(
          label: '已有账号？登录',
          onPressed: () => context.pushReplacement('/sign-in/credentials'),
        ),
        const SizedBox(height: 4),
        AuthFooterLink(label: '前往网页注册', onPressed: _openWebRegister),
      ],
    );
  }
}
