import 'package:flutter/material.dart';

import '../../format.dart';
import '../user_avatar.dart';

/// 主楼与子级回复的图标尺寸，子级小一号。
double threadRowIconSize(bool isChild) => isChild ? 16.0 : 18.0;

/// 社区回复与评论共用的一行。
/// 主楼头像 40、正文缩进 56；子级头像 24、正文顶格。
/// 点赞/回复/删除各页不同，由 [actions] 传入，时间戳固定占左侧。
class ThreadReplyRow extends StatelessWidget {
  const ThreadReplyRow({
    super.key,
    required this.userName,
    required this.avatarUrl,
    required this.content,
    required this.publishedAt,
    required this.isChild,
    this.replyToUserName,
    this.badge,
    this.highlighted = false,
    this.actions = const <Widget>[],
  });

  final String userName;
  final String avatarUrl;
  final String content;
  final DateTime? publishedAt;
  final bool isChild;
  final String? replyToUserName;
  final Widget? badge;
  final bool highlighted;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final replyToName = replyToUserName?.trim() ?? '';
    final double indent = isChild ? 0 : 56;

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (isChild)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              UserAvatar(url: avatarUrl, name: userName, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: userName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (replyToName.isNotEmpty)
                        TextSpan(
                          text: ' 回复了 $replyToName',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    color: colors.onSurface,
                  ),
                ),
              ),
              ?badge,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              UserAvatar(url: avatarUrl, name: userName, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 19 / 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        if (badge != null) ...<Widget>[
                          const SizedBox(width: 8),
                          badge!,
                        ],
                      ],
                    ),
                    if (replyToName.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        '回复 $replyToName',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(left: indent),
          child: SelectionArea(
            child: Text(
              content.trim(),
              style: TextStyle(
                fontSize: 14,
                height: 19 / 14,
                color: colors.onSurface,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: indent),
          child: SizedBox(
            height: 32,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    formatRelativeTimeFine(publishedAt),
                    style: TextStyle(
                      fontSize: isChild ? 10 : 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: highlighted ? colors.primaryContainer : Colors.transparent,
        border: highlighted
            ? Border(left: BorderSide(color: colors.primary, width: 3))
            : null,
        borderRadius: BorderRadius.circular(highlighted ? 12 : 0),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: highlighted ? 6 : 0,
        vertical: isChild ? 2 : 8,
      ),
      child: body,
    );
  }
}

/// 回复分组容器：主楼之间用发丝线分隔，子级挂在左竖线上缩进 56。
/// [closesGroup] 标记一个主楼及其子级的最后一行。
class ThreadReplyGroup extends StatelessWidget {
  const ThreadReplyGroup({
    super.key,
    required this.isChild,
    required this.closesGroup,
    required this.child,
  });

  final bool isChild;
  final bool closesGroup;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final BorderSide bottom = closesGroup
        ? BorderSide(color: colors.outlineVariant, width: 0.5)
        : BorderSide.none;
    if (!isChild) {
      return Container(
        padding: EdgeInsets.only(top: 8, bottom: closesGroup ? 8 : 0),
        decoration: BoxDecoration(border: Border(bottom: bottom)),
        child: child,
      );
    }
    return Container(
      margin: const EdgeInsets.only(left: 56),
      padding: EdgeInsets.only(left: 12, top: 6, bottom: closesGroup ? 8 : 0),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.outlineVariant, width: 2),
          bottom: bottom,
        ),
      ),
      child: child,
    );
  }
}

/// 回复行右侧的图标按钮，尺寸固定 32×32 以对齐时间戳基线。
class ThreadRowIconButton extends StatelessWidget {
  const ThreadRowIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.iconSize,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final double iconSize;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 32,
    child: IconButton(
      icon: Icon(icon, color: color),
      iconSize: iconSize,
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
    ),
  );
}
