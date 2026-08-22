import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../shared/format.dart';
import '../../shared/widgets/book_image.dart';
import '../../shared/widgets/state_views.dart';
import 'book_providers.dart';

/// 分卷/版本选择：同一系列会有不同上传者的多个版本。
class BookVersionsScreen extends ConsumerWidget {
  const BookVersionsScreen({super.key, required this.seriesTitle});

  final String seriesTitle;

  void _open(BuildContext context, ComicSeriesVolume volume) {
    context.push(
      Uri(
        path: '/book/${volume.id}',
        queryParameters: <String, String>{
          'type': 'Comic',
          'seriesTitle': seriesTitle,
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(comicSeriesProvider(seriesTitle));
    return Scaffold(
      appBar: AppBar(title: const Text('其它版本')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorStateView(
          message: error is ApiError ? error.message : '无法加载版本列表。',
          onRetry: () => ref.invalidate(comicSeriesProvider(seriesTitle)),
        ),
        data: (series) {
          if (series.volumes.isEmpty) {
            return const EmptyStateView(
              icon: Icons.library_books_outlined,
              title: '没有其它版本',
              description: '这个系列目前只有一个版本。',
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: series.volumes.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${series.title} · ${series.volumes.length}个版本',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return _VolumeRow(
                volume: series.volumes[index - 1],
                onTap: () => _open(context, series.volumes[index - 1]),
              );
            },
          );
        },
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.volume, required this.onTap});

  final ComicSeriesVolume volume;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 48,
                height: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: volume.coverUrl.isEmpty
                      ? ColoredBox(
                          color: colors.surfaceContainer,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 20,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      : BookImage(
                          url: volume.coverUrl,
                          displayHeight: 72,
                          blurHash: volume.coverPlaceholder,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      volume.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${volume.uploaderName.isEmpty ? '未知上传者' : volume.uploaderName}'
                      ' · ${volume.chapters.length}章',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '更新于 ${formatRelativeTime(volume.lastUpdatedAt)}',
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
