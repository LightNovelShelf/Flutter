import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/community_models.dart';
import '../../data/providers.dart';
import 'community_providers.dart';
import 'widgets/community_widgets.dart';

const int _replyPageSize = 5;
const int _childPageSize = 3;

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

  CommunityThreadDetail? _thread;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _viewTracked = false;
  String? _error;
  String? _loadMoreError;

  /// 帖子级动作（点赞/收藏）和回复级动作分开，免得互相禁用。
  bool _threadActionBusy = false;
  String? _replyActionId;

  int? _highlightedReplyId;
  Timer? _highlightTimer;
  int _operation = 0;

  ApiClient get _api => ref.read(apiClientProvider);

  bool get _canReply => _thread != null && !_thread!.item.locked;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.extentAfter < 480) _loadMore();
  }

  Future<void> _bootstrap() async {
    await _load();
    final replyId = widget.replyId;
    if (replyId != null && replyId > 0) {
      await _focusReply(replyId, widget.parentReplyId);
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final token = ++_operation;
    setState(() {
      _loading = !refresh;
      _refreshing = refresh;
      _error = null;
      _loadMoreError = null;
    });
    try {
      final detail = await _api.getCommunityThread(
        threadId: widget.threadId,
        replyPage: 1,
        replySize: _replyPageSize,
        trackView: !_viewTracked,
      );
      if (!mounted || token != _operation) return;
      _viewTracked = true;
      setState(() {
        _thread = detail;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted || token != _operation) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = describeCommunityError(error, fallback: '无法加载讨论。');
      });
    }
  }

  Future<void> _loadMore() async {
    final detail = _thread;
    if (detail == null ||
        _loading ||
        _refreshing ||
        _loadingMore ||
        !detail.repliesPage.hasMore) {
      return;
    }
    final token = _operation;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final size =
          detail.repliesPage.size < 1 ? _replyPageSize : detail.repliesPage.size;
      final next = await _api.getCommunityThread(
        threadId: widget.threadId,
        replyPage: detail.repliesPage.page + 1,
        replySize: size,
        trackView: false,
      );
      if (!mounted || token != _operation) return;
      setState(() {
        _loadingMore = false;
        if (next == null) return;
        _thread = _thread!.copyWith(
          repliesPage: next.repliesPage,
          replyItems: mergeCommunityById(
            _thread!.replyItems,
            next.replyItems,
            communityReplyId,
          ),
        );
      });
    } catch (error) {
      if (!mounted || token != _operation) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = describeCommunityError(error, fallback: '无法加载更多回复。');
      });
    }
  }

  Future<void> _loadChildren(CommunityThreadReply parent) async {
    if (_replyActionId != null) return;
    final actionId = 'children:${parent.id}';
    setState(() => _replyActionId = actionId);
    try {
      final size = parent.childPage.size < 1 ? _childPageSize : parent.childPage.size;
      final page = parent.childReplies.isEmpty ? 1 : parent.childPage.page + 1;
      final payload = await _api.getCommunityReplyChildren(
        threadId: widget.threadId,
        parentReplyId: parent.id,
        page: page,
        size: size,
      );
      if (!mounted) return;
      setState(() {
        _replyActionId = null;
        final detail = _thread;
        if (detail == null) return;
        _thread = detail.copyWith(
          replyItems: _updateReplies(
            detail.replyItems,
            parent.id,
            (reply) => reply.copyWith(
              childReplies: mergeCommunityById(
                reply.childReplies,
                payload.items,
                communityReplyId,
              ),
              childPage: payload.page,
            ),
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _replyActionId = null);
      _showMessage(describeCommunityError(error, fallback: '无法加载更多回复。'));
    }
  }

  Future<void> _toggleThreadLike() async {
    final detail = _thread;
    if (detail == null || detail.item.locked || _threadActionBusy) return;
    // 先乐观翻转，服务端返回后再用真实计数覆盖。
    setState(() {
      _threadActionBusy = true;
      _thread = _withCounts(
        detail.copyWith(liked: !detail.liked),
        likes: detail.item.likes + (detail.liked ? -1 : 1),
      );
    });
    try {
      final result = await _api.toggleCommunityThreadLike(detail.item.id);
      if (!mounted) return;
      setState(() {
        _threadActionBusy = false;
        _thread = _withCounts(
          _thread!.copyWith(liked: result.liked),
          likes: result.likes,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _threadActionBusy = false;
        _thread = detail;
      });
      _showMessage(describeCommunityError(error, fallback: '无法更新点赞状态。'));
    }
  }

  Future<void> _toggleThreadFavorite() async {
    final detail = _thread;
    if (detail == null || detail.item.locked || _threadActionBusy) return;
    setState(() {
      _threadActionBusy = true;
      _thread = _withCounts(
        detail.copyWith(favorited: !detail.favorited),
        favorites: detail.item.favorites + (detail.favorited ? -1 : 1),
      );
    });
    try {
      final result = await _api.toggleCommunityThreadFavorite(detail.item.id);
      if (!mounted) return;
      setState(() {
        _threadActionBusy = false;
        _thread = _withCounts(
          _thread!.copyWith(favorited: result.favorited),
          favorites: result.favorites,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _threadActionBusy = false;
        _thread = detail;
      });
      _showMessage(describeCommunityError(error, fallback: '无法更新收藏状态。'));
    }
  }

  Future<void> _toggleReplyLike(CommunityThreadReply reply) async {
    if (_replyActionId != null || !_canReply) return;
    final actionId = 'like:${reply.id}';
    setState(() {
      _replyActionId = actionId;
      _thread = _thread?.copyWith(
        replyItems: _updateReplies(
          _thread!.replyItems,
          reply.id,
          (item) => item.copyWith(
            liked: !item.liked,
            likes: item.likes + (item.liked ? -1 : 1),
          ),
        ),
      );
    });
    try {
      final result = await _api.toggleCommunityReplyLike(reply.id);
      if (!mounted) return;
      setState(() {
        _replyActionId = null;
        _thread = _thread?.copyWith(
          replyItems: _updateReplies(
            _thread!.replyItems,
            reply.id,
            (item) => item.copyWith(liked: result.liked, likes: result.likes),
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _replyActionId = null;
        _thread = _thread?.copyWith(
          replyItems: _updateReplies(
            _thread!.replyItems,
            reply.id,
            (item) => item.copyWith(liked: reply.liked, likes: reply.likes),
          ),
        );
      });
      _showMessage(describeCommunityError(error, fallback: '无法更新点赞状态。'));
    }
  }

  Future<void> _openComposer({CommunityThreadReply? target}) async {
    if (!_canReply) return;
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReplyComposerSheet(
        threadId: widget.threadId,
        replyToId: target?.id,
        replyToName: target == null
            ? null
            : _displayName(target.authorName, target.authorIsDeleted),
      ),
    );
    if (posted == true && mounted) await _load(refresh: true);
  }

  /// 深链：分页找到目标回复，高亮 1200ms 再滚过去。
  Future<void> _focusReply(int replyId, int? parentReplyId) async {
    final anchorId = parentReplyId ?? replyId;
    for (int attempt = 0; attempt < 20; attempt += 1) {
      if (!mounted || _thread == null) return;
      if (_findReply(_thread!.replyItems, anchorId) != null) break;
      if (!_thread!.repliesPage.hasMore) return;
      await _loadMore();
    }
    if (!mounted || _thread == null) return;
    if (parentReplyId != null) {
      for (int attempt = 0; attempt < 20; attempt += 1) {
        if (!mounted || _thread == null) return;
        if (_findReply(_thread!.replyItems, replyId) != null) break;
        final parent = _findReply(_thread!.replyItems, parentReplyId);
        if (parent == null || !parent.childPage.hasMore) break;
        await _loadChildren(parent);
      }
    }
    if (!mounted || _thread == null) return;
    if (_findReply(_thread!.replyItems, replyId) == null) return;
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<_ReplyRow> _buildRows() {
    final detail = _thread;
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
    final colors = Theme.of(context).colorScheme;
    final detail = _thread;
    final rows = _buildRows();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            const SliverAppBar(title: Text('')),
            if (detail != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                sliver: SliverToBoxAdapter(child: _buildHeader(detail)),
              ),
            if (detail == null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(child: _buildPlaceholder()),
              )
            else if (rows.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _loading
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
                  itemBuilder: (_, index) => _buildRow(rows[index], colors),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 42),
              sliver: SliverToBoxAdapter(child: _buildFooter(detail)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    if (_loading) {
      return const Column(
        children: <Widget>[
          CommunityFeedCardSkeleton(),
          SizedBox(height: 12),
          CommunityFeedCardSkeleton(),
        ],
      );
    }
    if (_error != null) {
      return CommunityStateCard(
        title: '无法加载讨论',
        description: _error!,
        isError: true,
        onRetry: _load,
      );
    }
    return const CommunityStateCard(
      title: '讨论不可用',
      description: '此讨论可能已被移除。',
    );
  }

  Widget _buildHeader(CommunityThreadDetail detail) {
    final colors = Theme.of(context).colorScheme;
    final item = detail.item;
    final subCategory = item.subCategoryLabel?.trim() ?? '';
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
                        CommunityAvatar(
                          url: item.authorAvatar,
                          name: _displayName(
                            item.authorName,
                            item.authorIsDeleted,
                          ),
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _displayName(
                                  item.authorName,
                                  item.authorIsDeleted,
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatCommunityTime(item.publishedAt),
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
                    SelectionArea(
                      child: HtmlWidget(
                        sanitizeCommunityHtml(detail.bodyHtml),
                        textStyle: TextStyle(
                          fontSize: 16,
                          height: 25 / 16,
                          color: colors.onSurface,
                        ),
                        onTapUrl: _openExternalUrl,
                      ),
                    ),
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
                      label: formatCommunityCount(item.likes),
                      filled: detail.liked,
                      onPressed: item.locked || _threadActionBusy
                          ? null
                          : _toggleThreadLike,
                    ),
                    _ActionButton(
                      icon: detail.favorited
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      label: formatCommunityCount(item.favorites),
                      filled: detail.favorited,
                      onPressed: item.locked || _threadActionBusy
                          ? null
                          : _toggleThreadFavorite,
                    ),
                    FilledButton.icon(
                      onPressed: _canReply ? () => _openComposer() : null,
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
        if (_error != null) ...<Widget>[
          const SizedBox(height: 14),
          CommunityStateCard(
            title: '社区操作失败',
            description: _error!,
            isError: true,
            onRetry: _load,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          '回复 · ${formatCommunityCount(detail.repliesPage.total)}',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(_ReplyRow row, ColorScheme colors) {
    final busy = _replyActionId != null;
    final BorderSide hairline = BorderSide(color: colors.outlineVariant, width: 0.5);

    if (row.kind == _ReplyRowKind.more) {
      final loading = _replyActionId == 'children:${row.parent.id}';
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
            onPressed: busy ? null : () => _loadChildren(row.parent),
            icon: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more, size: 18),
            label: Text(
              row.parent.childReplies.isEmpty ? '显示回复' : '展开更多回复',
            ),
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
      canReply: _canReply,
      busy: busy,
      onLike: () => _toggleReplyLike(reply),
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

  Widget _buildFooter(CommunityThreadDetail? detail) {
    final colors = Theme.of(context).colorScheme;
    if (detail == null) return const SizedBox.shrink();
    final children = <Widget>[];
    if (_loadingMore) {
      children.add(const CommunityFeedCardSkeleton());
    } else if (_loadMoreError != null) {
      children.add(
        CommunityStateCard(
          title: '无法加载更多',
          description: _loadMoreError!,
          isError: true,
          onRetry: _loadMore,
        ),
      );
    }
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
                          formatCommunityCount(related.replies),
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
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  static Future<bool> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 只更新计数的帖子副本（`CommunityFeedItem` 没有 copyWith）。
CommunityThreadDetail _withCounts(
  CommunityThreadDetail detail, {
  int? likes,
  int? favorites,
}) {
  final item = detail.item;
  return CommunityThreadDetail(
    item: CommunityFeedItem(
      id: item.id,
      boardKey: item.boardKey,
      boardName: item.boardName,
      subCategoryKey: item.subCategoryKey,
      subCategoryLabel: item.subCategoryLabel,
      title: item.title,
      excerpt: item.excerpt,
      authorName: item.authorName,
      authorIsDeleted: item.authorIsDeleted,
      authorAvatar: item.authorAvatar,
      publishedAt: item.publishedAt,
      replies: item.replies,
      views: item.views,
      heat: item.heat,
      likes: likes ?? item.likes,
      favorites: favorites ?? item.favorites,
      tags: item.tags,
      featured: item.featured,
      pinned: item.pinned,
      locked: item.locked,
    ),
    liked: detail.liked,
    favorited: detail.favorited,
    bodyHtml: detail.bodyHtml,
    repliesPage: detail.repliesPage,
    replyItems: detail.replyItems,
    relatedThreads: detail.relatedThreads,
  );
}

CommunityThreadReply? _findReply(List<CommunityThreadReply> items, int id) {
  for (final CommunityThreadReply reply in items) {
    if (reply.id == id) return reply;
    final child = _findReply(reply.childReplies, id);
    if (child != null) return child;
  }
  return null;
}

/// 命中 id 就替换，否则递归子回复。
List<CommunityThreadReply> _updateReplies(
  List<CommunityThreadReply> items,
  int id,
  CommunityThreadReply Function(CommunityThreadReply reply) update,
) =>
    items.map((reply) {
      if (reply.id == id) return update(reply);
      if (reply.childReplies.isEmpty) return reply;
      return reply.copyWith(
        childReplies: _updateReplies(reply.childReplies, id, update),
      );
    }).toList(growable: false);

String _displayName(String name, bool deleted) {
  final trimmed = name.trim();
  if (trimmed.isNotEmpty) return trimmed;
  return deleted ? '已注销用户' : '未知用户';
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
      await ref.read(apiClientProvider).createCommunityReply(
            threadId: widget.threadId,
            content: content,
            replyToId: widget.replyToId,
          );
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

  static String _describeReplyError(Object error) {
    if (error is ApiError) {
      return switch (error.category) {
        ApiErrorCategory.auth => '请重新登录后发布回复。',
        ApiErrorCategory.network => '离线时无法发布回复。',
        _ => error.message.trim().isEmpty ? '无法发布回复。' : error.message,
      };
    }
    return '无法发布回复。';
  }

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
