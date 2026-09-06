import 'package:flutter/material.dart';

import '../format.dart';

class UserNameText extends StatelessWidget {
  const UserNameText({
    super.key,
    required this.name,
    required this.deleted,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String name;
  final bool deleted;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final visibleName = displayUserName(name, deleted: deleted);
    final showDeletedStatus = deleted && name.trim().isNotEmpty;
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: visibleName),
          if (showDeletedStatus)
            TextSpan(
              text: '（已注销）',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
      style: style,
    );
  }
}
