import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../shared/format.dart';
import '../../shared/widgets/comments/comment_compose_sheet.dart';
import '../../shared/widgets/comments/comment_thread_list.dart';
import '../../shared/widgets/image_preview.dart';
import '../announcement/announcement_providers.dart';
import '../book/book_providers.dart';

/// 正文作为评论列表的头部，整页只有一个滚动容器。
class AnnouncementDetailScreen extends ConsumerWidget {
  const AnnouncementDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(announcementDetailProvider(id));
    final item = detail.value;
    final target = CommentTarget(type: CommentTargetType.announcement, id: id);

    final Widget header;
    if (item != null) {
      header = _ArticleCard(item: item);
    } else if (detail.isLoading) {
      header = const _ArticleSkeleton();
    } else {
      header = _ArticleError(
        message: describeApiError(detail.error!),
        // id 非法时重试无效。
        onRetry: id <= 0
            ? null
            : () => ref.invalidate(announcementDetailProvider(id)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('公告'),
        actions: <Widget>[
          if (item != null)
            IconButton(
              tooltip: '写评论',
              icon: const Icon(Icons.edit_outlined),
              // 弹窗提交成功后自行刷新评论列表。
              onPressed: () =>
                  showCommentComposeSheet(context, target: target),
            ),
        ],
      ),
      body: CommentThreadList(
        target: target,
        header: header,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 48),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.item});

  final AnnouncementItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ArticleShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectableText(
            item.title,
            style: TextStyle(
              fontSize: 21,
              height: 28 / 21,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatShortDate(item.createdAt)} · 站点公告',
            style: TextStyle(
              fontSize: 12,
              height: 16 / 12,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 0.5, color: colors.outlineVariant),
          const SizedBox(height: 12),
          HtmlWidget(
            item.contentHtml,
            textStyle: TextStyle(
              fontSize: 16,
              height: 25.6 / 16,
              color: colors.onSurface,
            ),
            onTapImage: (metadata) => previewHtmlImage(context, metadata),
          ),
        ],
      ),
    );
  }
}

class _ArticleSkeleton extends StatelessWidget {
  const _ArticleSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget bar(double height, double widthFactor, double radius) =>
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        );

    return _ArticleShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          bar(24, 0.68, 7),
          const SizedBox(height: 12),
          bar(12, 0.36, 6),
          const SizedBox(height: 16),
          bar(14, 1, 6),
          const SizedBox(height: 10),
          bar(14, 1, 6),
          const SizedBox(height: 10),
          bar(14, 0.72, 6),
          const SizedBox(height: 10),
          bar(14, 1, 6),
        ],
      ),
    );
  }
}

class _ArticleError extends StatelessWidget {
  const _ArticleError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ArticleShell(
      child: Column(
        children: <Widget>[
          Icon(Icons.error_outline, size: 32, color: colors.error),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 20 / 14, color: colors.error),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArticleShell extends StatelessWidget {
  const _ArticleShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}
