import 'package:flutter/material.dart';

/// 底部发表面板，提交成功返回 true。
///
/// 不走 `showDraggableSheet`：输入框需要跟随键盘上移，而 `DraggableScrollableSheet` 固定占屏幕比例。
Future<bool> showReplyComposeSheet(
  BuildContext context, {
  required String hintText,
  required Future<void> Function(String content) onSubmit,
  required String Function(Object error) describeError,
  double maxHeight = 148,
  String submitLabel = '发布',
}) async {
  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    builder: (_) => _ReplyComposeSheet(
      hintText: hintText,
      onSubmit: onSubmit,
      describeError: describeError,
      maxHeight: maxHeight,
      submitLabel: submitLabel,
    ),
  );
  return posted ?? false;
}

class _ReplyComposeSheet extends StatefulWidget {
  const _ReplyComposeSheet({
    required this.hintText,
    required this.onSubmit,
    required this.describeError,
    required this.maxHeight,
    required this.submitLabel,
  });

  final String hintText;
  final Future<void> Function(String content) onSubmit;
  final String Function(Object error) describeError;
  final double maxHeight;
  final String submitLabel;

  @override
  State<_ReplyComposeSheet> createState() => _ReplyComposeSheetState();
}

class _ReplyComposeSheetState extends State<_ReplyComposeSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Animation<double>? _entrance;
  bool _focusScheduled = false;
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusScheduled) return;
    _focusScheduled = true;
    // 入场动画期间弹键盘，IME 动画会被取消再重来（logcat 的 onCancelled at
    // PHASE_CLIENT_APPLY_ANIMATION），看上去就是一顿。等面板落位再要焦点。
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _focusNode.requestFocus();
      return;
    }
    _entrance = animation..addStatusListener(_onEntranceStatus);
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (!status.isCompleted) return;
    _detachEntrance();
    _focusNode.requestFocus();
  }

  void _detachEntrance() {
    _entrance?.removeStatusListener(_onEntranceStatus);
    _entrance = null;
  }

  @override
  void dispose() {
    _detachEntrance();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(content);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = widget.describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSubmit = _controller.text.trim().isNotEmpty && !_submitting;
    return _KeyboardInsetPadding(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 104,
                maxHeight: widget.maxHeight,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLength: 4000,
                maxLines: null,
                expands: false,
                textAlignVertical: TextAlignVertical.top,
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: colors.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  counterText: '',
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.38,
                  color: colors.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: canSubmit ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 18),
                label: Text(_submitting ? '正在发布…' : widget.submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 只有这一层跟着键盘 inset 重建。
///
/// [child] 由外层 build 产生，重建时是同一个 widget 实例，元素树会短路掉整棵子树，
/// 键盘动画的每一帧不会再重建 TextField。
class _KeyboardInsetPadding extends StatelessWidget {
  const _KeyboardInsetPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}
