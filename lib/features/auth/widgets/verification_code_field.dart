import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 4 位验证码输入，透明输入框覆盖在 4 个格子上方，点击任意处聚焦。
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
              // Opacity 为 0 仍参与命中测试，实际键盘输入由该输入框接收。
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
                    LengthLimitingTextInputFormatter(
                      VerificationCodeField.length,
                    ),
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
    final int caretIndex = math.min(
      value.length,
      VerificationCodeField.length - 1,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List<Widget>.generate(VerificationCodeField.length, (
        int index,
      ) {
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
