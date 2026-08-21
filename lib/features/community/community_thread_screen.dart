import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_error.dart';
import '../../data/api/community_models.dart';
import '../../shared/format.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/html/reader_content_style.dart';
import '../../shared/widgets/reader_html_block.dart';
import '../../shared/widgets/user_avatar.dart';
import '../reader/reader_html_blocks.dart';
import 'community_thread_providers.dart';
import 'widgets/community_feed_card.dart';
import 'widgets/community_primitives.dart';
import 'widgets/community_reply_row.dart';

enum _ReplyRowKind { parent, child, more }

class _ReplyRow {
  const _ReplyRow({
    required this.kind,
    required this.parent,
    this.reply,
    this.closesGroup = false,
  });

  final _ReplyRowKind kind;
  final CommunityThreadReply parent;
  final CommunityThreadReply? reply;
  final bool closesGroup;
}

class CommunityThreadScreen extends ConsumerStatefulWidget {
  const CommunityThreadScreen({
    super.key,
    required this.threadId,
    this.parentReplyId,
    this.replyId,
  });

  final int threadId;
  final int? parentReplyId;
  final int? replyId;

  @override
  ConsumerState<CommunityThreadScreen> createState() =>
      _CommunityThreadScreenState();
}

class _CommunityThreadScreenState extends ConsumerState<CommunityThreadScreen> {
  final ScrollController _controller = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  int? _highlightedReplyId;
  Timer? _highlightTimer;

  late final _provider = communityThreadProvider(widget.threadId);

  @override
  void initState() {
    super.initState();
    _controller.attachPrefetch(
      onLoadMore: () => ref.read(_provider.notifier).loadMore(),
    );
    final replyId = widget.replyId;
    if (replyId != null && replyId > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _bootstrapFocus(replyId),
      );
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 深链要等首屏落地，否则回复树还是空的，翻页找不到锚点。
  Future<void> _bootstrapFocus(int replyId) async {
    await ref.read(_provider.notifier).initialLoad;
    if (!mounted) return;
    await _focusReply(replyId, widget.parentReplyId);
  }

  /// 深链：分页找到目标回复，高亮 1200ms 再滚过去。
  Future<void> _focusReply(int replyId, int? parentReplyId) async {
    final controller = ref.read(_provider.notifier);
    final anchorId = parentReplyId ?? replyId;
    for (int attempt = 0; attempt < 20; attempt += 1) {
      if (!mounted) return;
      final state = ref.read(_provider);
      final detail = state.thread;
      if (detail == null) return;
      if (state.findReply(anchorId) != null) break;
      if (!detail.repliesPage.hasMore) return;
      await controller.loadMore();
    }
    if (parentReplyId != null) {
      for (int attempt = 0; attempt < 20; attempt += 1) {
        if (!mounted) return;
        final state = ref.read(_provider);
        if (state.thread == null) return;
        if (state.findReply(replyId) != null) break;
        final parent = state.findReply(parentReplyId);
        if (parent == null || !parent.childPage.hasMore) break;
        await controller.loadChildren(parent);
      }
    }
    if (!mounted) return;
    final state = ref.read(_provider);
    if (state.thread == null) return;
    if (state.findReply(replyId) == null) return;
    setState(() => _highlightedReplyId = replyId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlightedReplyId = null);
    });
    await _scrollToReply(replyId);
  }

  Future<void> _scrollToReply(int replyId) async {
    for (int attempt = 0; attempt < 6; attempt += 1) {
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 100 : 200),
      );
      if (!mounted) return;
      final target = _rowKeys[replyId]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.2,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
        return;
      }
      // 目标行还没懒加载出来，先滚到底部撑开列表再重试。
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    }
  }

  Future<void> _openComposer({CommunityThreadReply? target}) async {
    if (!ref.read(_provider).canReply) return;
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReplyComposerSheet(
        threadId: widget.threadId,
        replyToId: target?.id,
        replyToName: target == null
            ? null
            : displayUserName(
                target.authorName,
                deleted: target.authorIsDeleted,
              ),
      ),
    );
    if (posted == true && mounted) await ref.read(_provider.notifier).refresh();
  }

  List<_ReplyRow> _buildRows(CommunityThreadDetail? detail) {
    if (detail == null) return const <_ReplyRow>[];
    final rows = <_ReplyRow>[];
    for (final CommunityThreadReply parent in detail.replyItems) {
      final hasMore = parent.childPage.hasMore;
      final children = parent.childReplies;
      rows.add(
        _ReplyRow(
          kind: _ReplyRowKind.parent,
          parent: parent,
          reply: parent,
          closesGroup: children.isEmpty && !hasMore,
        ),
      );
      for (int index = 0; index < children.length; index += 1) {
        rows.add(
          _ReplyRow(
            kind: _ReplyRowKind.child,
            parent: parent,
            reply: children[index],
            closesGroup: index == children.length - 1 && !hasMore,
          ),
        );
      }
      if (hasMore) {
        rows.add(
          _ReplyRow(
            kind: _ReplyRowKind.more,
            parent: parent,
            closesGroup: true,
          ),
        );
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    // 互动失败是一次性提示，靠 noticeTag 区分同一句文案的第二次失败。
    ref.listen<CommunityThreadState>(_provider, (previous, next) {
      final notice = next.notice;
      if (notice == null || next.noticeTag == (previous?.noticeTag ?? 0)) return;
      showAppSnackBar(context, notice);
    });

    final colors = Theme.of(context).colorScheme;
    final state = ref.watch(_provider);
    final detail = state.thread;
    final rows = _buildRows(detail);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: ref.read(_provider.notifier).refresh,
        child: CustomScrollView(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            const SliverAppBar(title: Text('')),
            if (detail != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                sliver: SliverToBoxAdapter(child: _buildHeader(state, detail)),
              ),
            if (detail == null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(child: _buildPlaceholder(state)),
              )
            else if (rows.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: state.loading
                      ? const CommunityFeedCardSkeleton()
                      : const CommunityStateCard(
                          title: '还没有回复',
                          description: '来发布第一条回复吧。',
                          icon: Icons.mode_comment_outlined,
                        ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, index) =>
                      _buildRow(state, rows[index], colors),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 42),
              sliver: SliverToBoxAdapter(child: _buildFooter(state)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(CommunityThreadState state) {
    if (state.loading) {
      return const Column(
        children: <Widget>[
          CommunityFeedCardSkeleton(),
          SizedBox(height: 12),
          CommunityFeedCardSkeleton(),
        ],
      );
    }
    if (state.error != null) {
      return CommunityStateCard(
        title: '无法加载讨论',
        description: state.error!,
        isError: true,
        onRetry: ref.read(_provider.notifier).retry,
      );
    }
    return const CommunityStateCard(title: '讨论不可用', description: '此讨论可能已被移除。');
  }

  Widget _buildThreadBody(String html, Color color) {
    final style = ReaderContentStyle(
      fontSize: 16,
      lineHeight: 1.5,
      paragraphSpacing: 4,
      color: color,
      firstLineIndent: false,
      justify: false,
    );
    final blocks = splitContentHtmlBlocks(html);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < blocks.length; index++)
            ReaderHtmlBlock(
              markup: blocks[index],
              style: style,
              onTapUrl: _openExternalUrl,
              borderIllustrations: false,
              consumeImageTap: true,
              applyParagraphSpacing: index + 1 < blocks.length,
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(CommunityThreadState state, CommunityThreadDetail detail) {
    final colors = Theme.of(context).colorScheme;
    final controller = ref.read(_provider.notifier);
    final item = detail.item;
    final subCategory = item.subCategoryLabel?.trim() ?? '';
    final authorName = displayUserName(
      item.authorName,
      deleted: item.authorIsDeleted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CommunityCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (item.boardName.trim().isNotEmpty)
                      CommunityTagPill(label: item.boardName),
                    if (subCategory.isNotEmpty)
                      CommunityTagPill(
                        label: subCategory,
                        tone: CommunityTagTone.neutral,
                      ),
                    if (item.locked)
                      const CommunityTagPill(
                        label: '已锁定',
                        tone: CommunityTagTone.locked,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 27,
                        height: 34 / 27,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: <Widget>[
                        UserAvatar(
                          url: item.authorAvatar,
                          name: authorName,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                authorName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatRelativeTimeFine(item.publishedAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 19),
                    _buildThreadBody(detail.bodyHtml, colors.onSurface),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _ActionButton(
                      icon: detail.liked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: formatCompactCount(item.likes),
                      filled: detail.liked,
                      onPressed: item.locked || state.threadActionBusy
                          ? null
                          : controller.toggleLike,
                    ),
                    _ActionButton(
                      icon: detail.favorited
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      label: formatCompactCount(item.favorites),
                      filled: detail.favorited,
                      onPressed: item.locked || state.threadActionBusy
                          ? null
                          : controller.toggleFavorite,
                    ),
                    FilledButton.icon(
                      onPressed: state.canReply ? () => _openComposer() : null,
                      icon: const Icon(Icons.mode_comment_outlined, size: 18),
                      label: const Text('回复'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (item.locked) ...<Widget>[
          const SizedBox(height: 14),
          CommunityCard(
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '此讨论已锁定，无法再进行互动或回复。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 19 / 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (state.error != null) ...<Widget>[
          const SizedBox(height: 14),
          CommunityStateCard(
            title: '社区操作失败',
            description: state.error!,
            isError: true,
            onRetry: controller.retry,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          '回复 · ${formatCompactCount(detail.repliesPage.total)}',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    CommunityThreadState state,
    _ReplyRow row,
    ColorScheme colors,
  ) {
    final busy = state.replyActionId != null;
    final BorderSide hairline = BorderSide(
      color: colors.outlineVariant,
      width: 0.5,
    );

    if (row.kind == _ReplyRowKind.more) {
      final loading = state.replyActionId == 'children:${row.parent.id}';
      return Container(
        margin: const EdgeInsets.only(left: 56),
        padding: const EdgeInsets.only(left: 12, top: 6, bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colors.outlineVariant, width: 2),
            bottom: row.closesGroup ? hairline : BorderSide.none,
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy
                ? null
                : () => ref.read(_provider.notifier).loadChildren(row.parent),
            icon: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more, size: 18),
            label: Text(row.parent.childReplies.isEmpty ? '显示回复' : '展开更多回复'),
          ),
        ),
      );
    }

    final reply = row.reply!;
    final key = _rowKeys.putIfAbsent(reply.id, GlobalKey.new);
    final content = CommunityReplyRow(
      key: ValueKey<int>(reply.id),
      reply: reply,
      isChild: row.kind == _ReplyRowKind.child,
      highlighted: _highlightedReplyId == reply.id,
      canReply: state.canReply,
      busy: busy,
      onLike: () => ref.read(_provider.notifier).toggleReplyLike(reply),
      onReply: () => _openComposer(target: reply),
    );

    if (row.kind == _ReplyRowKind.child) {
      return Container(
        key: key,
        margin: const EdgeInsets.only(left: 56),
        padding: EdgeInsets.only(
          left: 12,
          top: 6,
          bottom: row.closesGroup ? 8 : 0,
        ),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colors.outlineVariant, width: 2),
            bottom: row.closesGroup ? hairline : BorderSide.none,
          ),
        ),
        child: content,
      );
    }

    return Container(
      key: key,
      padding: EdgeInsets.only(top: 8, bottom: row.closesGroup ? 8 : 0),
      decoration: BoxDecoration(
        border: Border(bottom: row.closesGroup ? hairline : BorderSide.none),
      ),
      child: content,
    );
  }

  Widget _buildFooter(CommunityThreadState state) {
    final colors = Theme.of(context).colorScheme;
    final detail = state.thread;
    if (detail == null) return const SizedBox.shrink();
    final controller = ref.read(_provider.notifier);
    final children = <Widget>[
      CommunityLoadMoreFooter(
        loading: state.loadingMore,
        error: state.loadMoreError,
        onRetry: controller.loadMore,
      ),
    ];
    if (!detail.repliesPage.hasMore && detail.relatedThreads.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Text(
            '相关讨论',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ),
      );
      for (final CommunityFeedItem related in detail.relatedThreads) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CommunityCard(
              radius: 18,
              padding: const EdgeInsets.all(14),
              onTap: () =>
                  context.pushReplacement('/community/thread/${related.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    related.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 20 / 15,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      if (related.boardName.trim().isNotEmpty)
                        CommunityTagPill(label: related.boardName),
                      if (related.replies > 0) ...<Widget>[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.mode_comment_outlined,
                          size: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatCompactCount(related.replies),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  static Future<bool> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
    if (filled) {
      return FilledButton.tonal(onPressed: onPressed, child: child);
    }
    return TextButton(onPressed: onPressed, child: child);
  }
}

class _ReplyComposerSheet extends ConsumerStatefulWidget {
  const _ReplyComposerSheet({
    required this.threadId,
    this.replyToId,
    this.replyToName,
  });

  final int threadId;
  final int? replyToId;
  final String? replyToName;

  @override
  ConsumerState<_ReplyComposerSheet> createState() =>
      _ReplyComposerSheetState();
}

class _ReplyComposerSheetState extends ConsumerState<_ReplyComposerSheet> {
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
      await ref
          .read(communityThreadProvider(widget.threadId).notifier)
          .postReply(content: content, replyToId: widget.replyToId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _describeReplyError(error);
      });
    }
  }

  static String _describeReplyError(Object error) => describeApiError(
    error,
    fallback: '无法发布回复。',
    auth: '请重新登录后发布回复。',
    network: '离线时无法发布回复。',
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSubmit = _controller.text.trim().isNotEmpty && !_submitting;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104, maxHeight: 220),
            child: TextField(
              controller: _controller,
              autofocus: true,
              maxLines: null,
              maxLength: 4000,
              expands: false,
              textAlignVertical: TextAlignVertical.top,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 15, height: 21 / 15),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
                hintText: widget.replyToName == null
                    ? '回复讨论'
                    : '回复 ${widget.replyToName}',
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 13,
                height: 18 / 13,
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
              label: Text(_submitting ? '正在发布' : '发布'),
            ),
          ),
        ],
      ),
    );
  }
}
