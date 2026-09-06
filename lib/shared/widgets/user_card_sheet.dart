import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/user_summary.dart';
import '../format.dart';
import 'skeleton.dart';
import 'user_avatar.dart';

/// 名片里的动作。导航放到调用方的 context 上执行，弹窗关闭动画不会打断路由。
enum _UserCardAction { directMessage }

/// 通用用户名片：任何头像点开都是这一份。
/// [userName] 与 [avatarUrl] 是列表里已有的数据，用来在资料回来之前先把名字和头像画出来。
Future<void> showUserCardSheet(
  BuildContext context, {
  required int userId,
  String userName = '',
  String avatarUrl = '',
}) async {
  if (userId <= 0) return;
  final action = await showModalBottomSheet<_UserCardAction>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _UserCardSheet(
      userId: userId,
      userName: userName,
      avatarUrl: avatarUrl,
    ),
  );
  if (action == _UserCardAction.directMessage && context.mounted) {
    context.push('/messages/$userId');
  }
}

class _UserCardSheet extends ConsumerWidget {
  const _UserCardSheet({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
  });

  final int userId;
  final String userName;
  final String avatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final async = ref.watch(userSummaryProvider(userId));
    final summary = async.value;
    final name = summary?.userName.trim().isNotEmpty ?? false
        ? summary!.userName
        : displayUserName(userName, deleted: false);
    final myId = ref.watch(
      profileProvider.select((profile) => profile.value?.id ?? 0),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                UserAvatar(
                  url: summary?.avatarUrl ?? avatarUrl,
                  name: name,
                  size: 56,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (summary != null) ...<Widget>[
                            const SizedBox(width: 8),
                            _LevelPill(level: summary.level),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary?.roleName.trim().isNotEmpty ?? false
                            ? summary!.roleName
                            : 'UID $userId',
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (userId != myId && !async.hasError) ...<Widget>[
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        Navigator.pop(context, _UserCardAction.directMessage),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: const Text('私信'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            if (summary != null)
              _Stats(summary: summary)
            else if (async.hasError)
              _LoadError(
                message: describeApiError(
                  async.error!,
                  fallback: '无法加载用户资料。',
                  normalize: true,
                ),
                onRetry: () => ref.invalidate(userSummaryProvider(userId)),
              )
            else
              const _StatsSkeleton(),
            if (summary != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                '加入于 ${formatMediumDate(summary.registeredAt?.toLocal())}',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.primary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Lv$level',
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.summary});

  final PublicUserSummary summary;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      _StatCell(label: '书籍', value: summary.bookCount),
      _StatCell(label: '主题', value: summary.threadCount),
      _StatCell(label: '社区回复', value: summary.replyCount),
      _StatCell(label: '评论', value: summary.commentCount),
    ],
  );
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            formatCompactCount(value),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) => const Row(
    children: <Widget>[
      Expanded(child: Center(child: SkeletonBox(height: 18, width: 44))),
      Expanded(child: Center(child: SkeletonBox(height: 18, width: 44))),
      Expanded(child: Center(child: SkeletonBox(height: 18, width: 44))),
      Expanded(child: Center(child: SkeletonBox(height: 18, width: 44))),
    ],
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
