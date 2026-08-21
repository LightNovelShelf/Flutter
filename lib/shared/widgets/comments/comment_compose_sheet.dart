import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/providers.dart';
import '../../../features/book/book_providers.dart';

/// 底部发表弹窗；成功后刷新对应列表并返回 true。
///
/// 这里刻意不走 `showDraggableSheet`：输入框要跟着键盘顶起来（viewInsets 内边距 +
/// 内容高度自适应），而 `DraggableScrollableSheet` 固定占屏幕的某个比例，键盘弹起时
/// 会把输入框压在软键盘底下。
Future<bool> showCommentComposeSheet(
  BuildContext context, {
  required CommentTarget target,
  int? parentId,
  int? replyId,
  String? replyToUserName,
}) async {
  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    builder: (_) => _CommentComposeSheet(
      target: target,
      parentId: parentId,
      replyId: replyId,
      replyToUserName: replyToUserName,
    ),
  );
  return posted ?? false;
}

class _CommentComposeSheet extends ConsumerStatefulWidget {
  const _CommentComposeSheet({
    required this.target,
    this.parentId,
    this.replyId,
    this.replyToUserName,
  });

  final CommentTarget target;
  final int? parentId;
  final int? replyId;
  final String? replyToUserName;

  @override
  ConsumerState<_CommentComposeSheet> createState() =>
      _CommentComposeSheetState();
}

class _CommentComposeSheetState extends ConsumerState<_CommentComposeSheet> {
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
    final api = ref.read(apiClientProvider);
    final target = widget.target;
    try {
      if (widget.parentId != null) {
        await api.replyComment(
          type: target.type,
          id: target.id,
          content: content,
          seriesTitle: target.seriesTitle,
          parentId: widget.parentId,
          replyId: widget.replyId,
        );
      } else {
        await api.postComment(
          type: target.type,
          id: target.id,
          content: content,
          seriesTitle: target.seriesTitle,
        );
      }
      await ref.read(commentThreadProvider(target).notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = describeCommentError(error, fallback: '无法发表评论。');
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
              constraints: const BoxConstraints(minHeight: 104, maxHeight: 148),
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 4000,
                maxLines: null,
                expands: false,
                textAlignVertical: TextAlignVertical.top,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: colors.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: widget.replyToUserName == null
                      ? '写评论'
                      : '回复 ${widget.replyToUserName}',
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
                label: Text(_submitting ? '正在发布…' : '发布'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
