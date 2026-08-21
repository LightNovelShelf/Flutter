import 'package:flutter/material.dart';

import '../../format.dart';
import '../user_avatar.dart';

/// 回复用左侧竖线 + 缩进表达层级，不做无限嵌套。
class CommentThreadRow extends StatelessWidget {
  const CommentThreadRow({
    super.key,
    required this.userName,
    required this.avatarUrl,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    required this.isReply,
    required this.isLastReply,
    this.replyToUserName,
    this.onReply,
    this.onDelete,
  });

  final String userName;
  final String avatarUrl;
  final String content;
  final DateTime createdAt;
  final bool canEdit;
  final bool isReply;
  final bool isLastReply;
  final String? replyToUserName;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final avatarSize = isReply ? 24.0 : 40.0;

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        UserAvatar(url: avatarUrl, name: userName, size: avatarSize),
        SizedBox(width: isReply ? 8 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: userName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if (replyToUserName != null)
                      TextSpan(
                        text: ' 回复了 $replyToUserName',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                  ],
                ),
                style: TextStyle(
                  fontSize: isReply ? 12 : 14,
                  height: isReply ? 1.34 : 1.36,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                content,
                style: text.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.36,
                  color: colors.onSurface,
                ),
              ),
              SizedBox(
                height: 32,
                child: Row(
                  children: <Widget>[
                    Text(
                      formatRelativeTime(createdAt),
                      style: TextStyle(
                        fontSize: isReply ? 10 : 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (onReply != null)
                      _CommentAction(
                        icon: Icons.reply_outlined,
                        tooltip: '回复',
                        size: isReply ? 16 : 18,
                        color: colors.onSurfaceVariant,
                        onPressed: onReply,
                      ),
                    if (canEdit && onDelete != null)
                      _CommentAction(
                        icon: Icons.delete_outline,
                        tooltip: '删除',
                        size: isReply ? 16 : 18,
                        color: colors.error,
                        onPressed: onDelete,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!isReply) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: body,
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(72, 2, 16, isLastReply ? 8 : 6),
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2,
            ),
          ),
        ),
        child: body,
      ),
    );
  }
}

class _CommentAction extends StatelessWidget {
  const _CommentAction({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: size, color: color),
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    splashRadius: 18,
  );
}
