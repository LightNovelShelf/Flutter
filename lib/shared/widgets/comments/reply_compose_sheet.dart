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
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                autofocus: true,
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
