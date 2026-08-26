import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../shared/format.dart';
import '../../shared/paging/identity_child_delegate.dart';
import '../../shared/paging/scroll_prefetch.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/comments/reply_compose_sheet.dart';
import '../../shared/widgets/comments/thread_reply_row.dart';
import 'community_thread_providers.dart';
import 'community_thread_rows.dart';
import 'community_thread_state.dart';
import 'widgets/community_feed_card.dart';
import 'widgets/community_primitives.dart';
import 'widgets/community_reply_row.dart';
import 'widgets/community_thread_footer.dart';
import 'widgets/community_thread_header.dart';

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

  /// 只有深链要定位的那一行需要 GlobalKey：GlobalKey 进程级注册、阻断 element 复用，
  /// 行索引一变就整棵子树 deactivate 再 activate。
  GlobalKey? _targetRowKey;

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
      _targetRowKey = GlobalKey();
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

  /// 等首屏加载完成再定位，否则回复树为空，翻页找不到锚点。
  Future<void> _bootstrapFocus(int replyId) async {
    await ref.read(_provider.notifier).initialLoad;
    if (!mounted) return;
    await _focusReply(replyId, widget.parentReplyId);
  }

  /// 深链定位：翻页直到找到目标回复，高亮 1200ms 后滚动过去。
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
    await _scrollToReply();
  }

  /// 目标行就是 `widget.replyId` 那一行，它独占 [_targetRowKey]。
  Future<void> _scrollToReply() async {
    for (int attempt = 0; attempt < 6; attempt += 1) {
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 100 : 200),
      );
      if (!mounted) return;
      final target = _targetRowKey?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.2,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
        return;
      }
      // 目标行尚未构建，先滚到底部撑开列表再重试。
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    }
  }

  Future<void> _openComposer({CommunityThreadReply? target}) async {
    if (!ref.read(_provider).canReply) return;
    final replyToId = target?.id;
    final replyToName = target == null
        ? null
        : displayUserName(target.authorName, deleted: target.authorIsDeleted);
    final posted = await showReplyComposeSheet(
      context,
      hintText: replyToName == null ? '回复讨论' : '回复 $replyToName',
      maxHeight: 220,
      onSubmit: (content) => ref
          .read(communityThreadProvider(widget.threadId).notifier)
          .postReply(content: content, replyToId: replyToId),
      describeError: _describeReplyError,
    );
    if (posted && mounted) await ref.read(_provider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    // 互动失败是一次性提示，用 noticeTag 区分文案相同的重复失败。
    ref.listen<CommunityThreadState>(_provider, (previous, next) {
      final notice = next.notice;
      if (notice == null || next.noticeTag == (previous?.noticeTag ?? 0)) {
        return;
      }
      showAppSnackBar(context, notice);
    });

    final state = ref.watch(_provider);
    final detail = state.thread;
    final rows = state.rows;
    final controller = ref.read(_provider.notifier);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        // 整页一个 SelectionArea：逐行包会给每条回复各装一套手势识别与选区注册。
        child: SelectionArea(
          child: CustomScrollView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              const SliverAppBar(title: Text('')),
              if (detail != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  sliver: SliverToBoxAdapter(
                    child: CommunityThreadHeader(
                      detail: detail,
                      controller: controller,
                      threadActionBusy: state.threadActionBusy,
                      canReply: state.canReply,
                      error: state.error,
                      onReply: _openComposerFromHeader,
                    ),
                  ),
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
                  sliver: SliverList(
                    delegate: IdentityChildDelegate<CommunityThreadRow>(
                      items: rows,
                      revision: (
                        state.replyActionId,
                        state.canReply,
                        _highlightedReplyId,
                      ),
                      itemBuilder: (context, row, index) =>
                          _buildRow(state, row),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 42),
                sliver: SliverToBoxAdapter(
                  child: CommunityThreadFooter(
                    detail: detail,
                    controller: controller,
                    loadingMore: state.loadingMore,
                    loadMoreError: state.loadMoreError,
                  ),
                ),
              ),
            ],
          ),
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

  /// 头部的回复回调走方法撕取，闭包每次 build 都是新对象，头部就永远比不相等。
  Future<void> _openComposerFromHeader() => _openComposer();

  Future<void> _deleteReply(int replyId) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '删除回复',
      message: '此操作无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await ref.read(_provider.notifier).deleteReply(replyId);
  }

  Widget _buildRow(CommunityThreadState state, CommunityThreadRow row) {
    final busy = state.replyActionId != null;

    if (row.kind == CommunityThreadRowKind.more) {
      final loading = state.replyActionId == 'children:${row.parent.id}';
      return ThreadReplyGroup(
        key: ValueKey<String>('more:${row.parent.id}'),
        isChild: true,
        closesGroup: row.closesGroup,
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
    final isChild = row.kind == CommunityThreadRowKind.child;
    final GlobalKey? targetKey = _targetRowKey;
    return ThreadReplyGroup(
      key: targetKey != null && reply.id == widget.replyId
          ? targetKey
          : ValueKey<int>(reply.id),
      isChild: isChild,
      closesGroup: row.closesGroup,
      child: CommunityReplyRow(
        reply: reply,
        isChild: isChild,
        highlighted: _highlightedReplyId == reply.id,
        canReply: state.canReply,
        busy: busy,
        onLike: () => ref.read(_provider.notifier).toggleReplyLike(reply),
        onReply: () => _openComposer(target: reply),
        onDelete: () => _deleteReply(reply.id),
      ),
    );
  }
}

String _describeReplyError(Object error) => describeApiError(
  error,
  fallback: '无法发布回复。',
  auth: '请重新登录后发布回复。',
  network: '离线时无法发布回复。',
);
