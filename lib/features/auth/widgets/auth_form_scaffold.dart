import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 认证表单页的统一外壳：顶栏 + 可滚动内容，内容列最大宽 520 居中。
class AuthFormScaffold extends StatelessWidget {
  const AuthFormScaffold({
    super.key,
    required this.appBarTitle,
    required this.title,
    required this.description,
    required this.children,
  });

  final String appBarTitle;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    // 键盘弹出时 Scaffold 会压缩正文，底部留白取安全区而不是 viewInsets。
    final double safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          top: 24,
          bottom: math.max(32, safeBottom + 20),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 32,
                      height: 36,
                      child: Center(
                        child: Icon(
                          Icons.menu_book_rounded,
                          size: 32,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        height: 38 / 32,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 390),
                      child: Text(
                        description,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 16,
                          height: 23 / 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 认证表单输入框：高 52（由装饰的内边距决定）、圆角 14、发丝边框。
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.focusNode,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      style: authFieldTextStyle(context),
      decoration: authFieldDecoration(context, hintText: hintText),
    );
  }
}

/// 带可见性切换的密码输入框，切换按钮的点击区域 48×48。
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.hintText,
    this.textInputAction,
    this.autofillHints,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscured,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onSubmitted: widget.onSubmitted,
      style: authFieldTextStyle(context),
      decoration: authFieldDecoration(context, hintText: widget.hintText).copyWith(
        // 不要让图标约束反过来决定输入框高度：48 小于 52，高度仍由内边距给出。
        suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        suffixIcon: InkResponse(
          radius: 22,
          onTap: () => setState(() => _obscured = !_obscured),
          child: Icon(
            _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            color: colors.onSurfaceVariant,
            semanticLabel: _obscured ? '显示密码' : '隐藏密码',
          ),
        ),
      ),
    );
  }
}

/// 表单主按钮：提交中转圈 + 「进行中」文案，整体降透明度。
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.submittingLabel,
    required this.isSubmitting,
    required this.onPressed,
  });

  final String label;
  final String submittingLabel;
  final bool isSubmitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color onAccent = colors.onPrimary;

    return Opacity(
      opacity: isSubmitting ? 0.56 : 1,
      child: FilledButton(
        onPressed: isSubmitting ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: onAccent,
          disabledBackgroundColor: colors.primary,
          disabledForegroundColor: onAccent,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isSubmitting) ...<Widget>[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: onAccent),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              isSubmitting ? submittingLabel : label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表单错误文案，无错误时不占位。
class AuthFormError extends StatelessWidget {
  const AuthFormError({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final String? text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 14,
          height: 20 / 14,
        ),
      ),
    );
  }
}

class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.alignment = Alignment.center,
  });

  final String label;
  final VoidCallback onPressed;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 4 位验证码输入：真正的输入框透明覆盖在 4 个格子上方，点击任意处均可聚焦。
class VerificationCodeField extends StatefulWidget {
  const VerificationCodeField({
    super.key,
    required this.controller,
    required this.isInvalid,
    required this.isSending,
    required this.cooldownSeconds,
    required this.onResend,
    this.onSubmitted,
  });

  static const int length = 4;

  final TextEditingController controller;
  final bool isInvalid;
  final bool isSending;
  final int cooldownSeconds;
  final VoidCallback onResend;
  final VoidCallback? onSubmitted;

  @override
  State<VerificationCodeField> createState() => _VerificationCodeFieldState();
}

class _VerificationCodeFieldState extends State<VerificationCodeField>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _caret = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_syncCaret);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_syncCaret);
    _focusNode.dispose();
    _caret.dispose();
    super.dispose();
  }

  void _syncCaret() {
    if (_focusNode.hasFocus) {
      if (!_caret.isAnimating) _caret.repeat();
    } else {
      _caret.stop();
      _caret.value = 0;
    }
  }

  String get _resendLabel {
    if (widget.isSending) return '正在发送…';
    if (widget.cooldownSeconds > 0) return '${widget.cooldownSeconds} 秒后重发';
    return '重新发送';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool canResend = !widget.isSending && widget.cooldownSeconds == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '验证码',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: TextButton(
                onPressed: canResend ? widget.onResend : null,
                style: TextButton.styleFrom(
                  foregroundColor: colors.primary,
                  disabledForegroundColor: colors.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(_resendLabel),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Stack(
          children: <Widget>[
            AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                widget.controller,
                _focusNode,
                _caret,
              ]),
              builder: (context, _) => _buildSlots(context),
            ),
            Positioned.fill(
              // 透明输入框覆盖在格子上层：命中测试仍然生效，负责真正的键盘输入。
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    LengthLimitingTextInputFormatter(VerificationCodeField.length),
                  ],
                  onSubmitted: (_) => widget.onSubmitted?.call(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    isCollapsed: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSlots(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String value = widget.controller.text;
    final int caretIndex = math.min(value.length, VerificationCodeField.length - 1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List<Widget>.generate(VerificationCodeField.length, (int index) {
        final bool hasChar = index < value.length;
        final bool showCaret = _focusNode.hasFocus && index == caretIndex;
        return Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: widget.isInvalid ? colors.error : colors.outlineVariant,
              width: 1,
            ),
          ),
          child: hasChar
              ? Text(
                  value[index],
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : showCaret
                  ? Opacity(
                      opacity: _caret.value < 0.5 ? 1 : 0,
                      child: Container(width: 2, height: 21, color: colors.primary),
                    )
                  : Text(
                      '•',
                      style: TextStyle(
                        color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                        fontSize: 20,
                      ),
                    ),
        );
      }),
    );
  }
}

/// 输入框共用的文字样式与装饰，保证密码框与普通框视觉一致。
TextStyle authFieldTextStyle(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 17,
    );

InputDecoration authFieldDecoration(
  BuildContext context, {
  required String hintText,
}) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: colors.outlineVariant, width: 1),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: colors.onSurfaceVariant, fontSize: 17),
    filled: true,
    fillColor: colors.surfaceContainer,
    isDense: true,
    // 高度只能由竖向内边距给：InputDecorator 按自己算出的容器高度画填充和边框，
    // 外面套 SizedBox 只占位、撑不开。17 号字行高 26，配 13 的上下内边距正好 52；
    // minHeight 兜底，字号放大时跟着长高而不是裁字。
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    constraints: const BoxConstraints(minHeight: 52),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.primary, width: 1),
    ),
  );
}
