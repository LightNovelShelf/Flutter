import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/html_content.dart';
import 'community_providers.dart';
import 'widgets/community_primitives.dart';

String _escapeRawHtml(String text) => text.replaceAll('<', '&lt;');

/// 把社区正文 Markdown 转成接口与正文渲染器使用的 HTML。
String buildCommunityContentHtml(String text) => md
    .markdownToHtml(
      _escapeRawHtml(text),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: true,
    )
    .trim();

/// 字数校验只看 Markdown 渲染后的正文文字。
String communityPlainText(String text) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: true,
  ).parse(_escapeRawHtml(text));
  return nodes.map((node) => node.textContent).join('\n');
}

class CommunityComposeScreen extends ConsumerStatefulWidget {
  const CommunityComposeScreen({
    super.key,
    this.threadId,
    this.boardKey,
    this.subCategoryKey,
  });

  /// 非空即编辑已有帖子：正文向服务端要 Markdown，保存走 UpdateCommunityThread。
  final int? threadId;
  final String? boardKey;
  final String? subCategoryKey;

  @override
  ConsumerState<CommunityComposeScreen> createState() =>
      _CommunityComposeScreenState();
}

class _CommunityComposeScreenState
    extends ConsumerState<CommunityComposeScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  List<CommunityCatalogBoard> _boards = const <CommunityCatalogBoard>[];
  String _boardKey = '';
  String _subCategoryKey = '';
  bool _preparing = true;
  bool _publishing = false;
  bool _noticeAccepted = false;
  bool _previewing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boardKey = widget.boardKey ?? '';
    _subCategoryKey = widget.subCategoryKey ?? '';
    _title.addListener(_onTextChanged);
    _body.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _title.removeListener(_onTextChanged);
    _body.removeListener(_onTextChanged);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _editing => widget.threadId != null;

  bool get _needsPrepareRetry =>
      _boards.isEmpty || (_editing && _body.text.isEmpty);

  CommunityCatalogBoard? get _selectedBoard {
    for (final CommunityCatalogBoard board in _boards) {
      if (board.key == _boardKey) return board;
    }
    return null;
  }

  bool get _canPublish {
    if (!_noticeAccepted || _publishing || _boardKey.isEmpty) return false;
    final title = _title.text.trim();
    if (title.length < 6 || title.length > 60) return false;
    if (communityPlainText(_body.text).trim().length < 20) return false;
    final board = _selectedBoard;
    if (board != null &&
        board.subCategories.isNotEmpty &&
        _subCategoryKey.isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _prepare() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      // 优先用社区首页缓存的版块目录，冷启动直接进本页时才回源。
      var catalog =
          ref.read(communityHomeCacheProvider)?.catalogBoards ??
          const <CommunityCatalogBoard>[];
      if (catalog.isEmpty) {
        final payload = await ref
            .read(apiClientProvider)
            .getCommunityHome(const CommunityListQuery(page: 1, size: 1));
        ref.read(communityHomeCacheProvider.notifier).publish(payload);
        catalog = payload.catalogBoards;
      }
      final boards = catalog
          .where((board) => board.key != communityAllBoardKey)
          .toList(growable: false);
      // 社区须知是发布前的提示，编辑已有帖子不再拦。
      final accepted =
          _editing || await ref.read(communityPostNoticeProvider).isAccepted();

      CommunityThreadEditInfo? thread;
      if (_editing) {
        // 正文要 Markdown：本页编辑器是 Markdown 的，服务端按 Web 编辑器同一套规则转
        thread = await ref.read(apiClientProvider).getCommunityThreadEditInfo(
          threadId: widget.threadId!,
          format: 'markdown',
        );
        if (!mounted) return;
        _title.text = thread.title;
        _body.text = thread.content;
      }

      if (!mounted) return;
      setState(() {
        _boards = boards;
        _preparing = false;
        _noticeAccepted = accepted;
        if (thread != null) {
          _boardKey = thread.boardKey;
          _subCategoryKey = thread.subCategoryKey;
        }
        if (_boardKey.isEmpty ||
            !boards.any((board) => board.key == _boardKey)) {
          _boardKey = boards.isEmpty ? '' : boards.first.key;
          _subCategoryKey = widget.subCategoryKey ?? '';
        }
      });
      if (!accepted && mounted) await _showNotice();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _error = describeCommunityError(
          error,
          fallback: _editing ? '无法读取帖子内容。' : '无法准备编辑器。',
        );
      });
    }
  }

  Future<void> _showNotice() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发布前请注意'),
        content: const Text(
          '社区用于友好交流，请在发布前确认：\n\n'
          '• 尊重他人，避免攻击、嘲讽或引战。\n'
          '• 请勿求书，也不要请求他人上传或发送书籍。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('我已了解'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted != true) {
      context.pop();
      return;
    }
    try {
      await ref.read(communityPostNoticeProvider).accept();
      if (!mounted) return;
      setState(() => _noticeAccepted = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '无法保存社区须知确认状态。');
    }
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      if (_editing) {
        await api.updateCommunityThread(
          threadId: widget.threadId!,
          boardKey: _boardKey,
          subCategoryKey: _subCategoryKey,
          title: _title.text.trim(),
          contentHtml: buildCommunityContentHtml(_body.text.trim()),
        );
        if (!mounted) return;
        // 交给帖子页刷新，避免回退后还显示旧正文
        context.pop(true);
        return;
      }
      final detail = await api.createCommunityThread(
        boardKey: _boardKey,
        subCategoryKey: _subCategoryKey,
        title: _title.text.trim(),
        contentHtml: buildCommunityContentHtml(_body.text.trim()),
      );
      if (!mounted) return;
      context.pushReplacement('/community/thread/${detail.item.id}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = describeCommunityError(
          error,
          fallback: _editing ? '无法保存修改。' : '无法发布讨论。',
        );
      });
    }
  }

  /// 把选中文字包进 Markdown 标记，无选区时作用于当前行。
  void _wrapSelection(String open, String close) {
    final value = _body.value;
    final text = value.text;
    var start = value.selection.isValid ? value.selection.start : text.length;
    var end = value.selection.isValid ? value.selection.end : text.length;
    if (start == end) {
      start = text.lastIndexOf('\n', start > 0 ? start - 1 : 0);
      start = start < 0 ? 0 : start + 1;
      final lineEnd = text.indexOf('\n', end);
      end = lineEnd < 0 ? text.length : lineEnd;
      if (end < start) end = start;
    }
    final selected = text.substring(start, end);
    final replacement = '$open$selected$close';
    _body.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(
        offset: start + open.length + selected.length,
      ),
    );
  }

  void _prefixLines(String Function(int index) prefixForIndex) {
    final value = _body.value;
    final text = value.text;
    var start = value.selection.isValid ? value.selection.start : text.length;
    var end = value.selection.isValid ? value.selection.end : text.length;
    start = text.lastIndexOf('\n', start > 0 ? start - 1 : 0);
    start = start < 0 ? 0 : start + 1;
    final lineEnd = text.indexOf('\n', end);
    end = lineEnd < 0 ? text.length : lineEnd;

    final lines = text.substring(start, end).split('\n');
    final replacement = <String>[
      for (var index = 0; index < lines.length; index++)
        '${prefixForIndex(index)}${lines[index]}',
    ].join('\n');
    _body.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final board = _selectedBoard;
    final titleLength = _title.text.length;
    final titleTrimmed = _title.text.trim();
    final bodyLength = communityPlainText(_body.text).trim().length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑帖子' : '发布帖子'),
        actions: <Widget>[
          IconButton(
            onPressed: _canPublish ? _publish : null,
            tooltip: _editing ? '保存' : '发布',
            icon: _publishing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: _preparing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
              children: <Widget>[
                if (_error != null) ...<Widget>[
                  CommunityStateCard(
                    // 编辑器还没准备好（版面为空、或编辑态没取到正文）才给重试
                    title: _needsPrepareRetry
                        ? '无法准备编辑器'
                        : (_editing ? '无法保存' : '无法发布'),
                    description: _error!,
                    isError: true,
                    onRetry: _needsPrepareRetry ? _prepare : null,
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  '版面',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 9),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final CommunityCatalogBoard option
                          in _boards) ...<Widget>[
                        CommunityFilterChip(
                          label: option.title,
                          icon: resolveCommunityBoardIcon(
                            option.icon,
                            option.title,
                          ),
                          selected: option.key == _boardKey,
                          onTap: () => setState(() {
                            // 分类属于具体版面，切版面后清空。
                            _boardKey = option.key;
                            _subCategoryKey = '';
                          }),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                if (board != null &&
                    board.description.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 9),
                  Text(
                    board.description.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      height: 19 / 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (board != null &&
                    board.subCategories.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 20),
                  Text(
                    '分类',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 9),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final CommunityCatalogSubCategory category
                            in board.subCategories) ...<Widget>[
                          CommunityFilterChip(
                            label: category.label,
                            selected: category.key == _subCategoryKey,
                            onTap: () =>
                                setState(() => _subCategoryKey = category.key),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  if (_subCategoryKey.isEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '请选择分类。',
                      style: TextStyle(fontSize: 12, color: colors.error),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _title,
                  maxLength: 60,
                  enabled: !_publishing,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    hintText: '清楚描述讨论主题',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        titleLength > 0 && titleTrimmed.length < 6
                            ? '标题至少需要 6 个字符。'
                            : '',
                        style: TextStyle(fontSize: 12, color: colors.error),
                      ),
                    ),
                    Text(
                      '$titleLength/60',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '帖子内容',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '$bodyLength 个字符',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                _BodyEditor(
                  controller: _body,
                  enabled: !_publishing,
                  previewing: _previewing,
                  previewHtml: _previewing
                      ? buildCommunityContentHtml(_body.text)
                      : '',
                  onTogglePreview: () =>
                      setState(() => _previewing = !_previewing),
                  onHeading: (level) => _prefixLines(
                    (_) => '${List<String>.filled(level, '#').join()} ',
                  ),
                  onBold: () => _wrapSelection('**', '**'),
                  onItalic: () => _wrapSelection('*', '*'),
                  onQuote: () => _prefixLines((_) => '> '),
                  onBulletList: () => _prefixLines((_) => '- '),
                  onNumberList: () => _prefixLines((index) => '${index + 1}. '),
                ),
                if (bodyLength > 0 && bodyLength < 20) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '帖子内容至少需要 20 个字符。',
                    style: TextStyle(fontSize: 12, color: colors.error),
                  ),
                ],
              ],
            ),
    );
  }
}

class _BodyEditor extends StatelessWidget {
  const _BodyEditor({
    required this.controller,
    required this.enabled,
    required this.previewing,
    required this.previewHtml,
    required this.onTogglePreview,
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onBulletList,
    required this.onNumberList,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool previewing;
  final String previewHtml;
  final ValueChanged<int> onHeading;
  final VoidCallback onTogglePreview;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onBulletList;
  final VoidCallback onNumberList;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final formattingEnabled = enabled && !previewing;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: <Widget>[
                _HeadingToolbarButton(
                  enabled: formattingEnabled,
                  onSelected: onHeading,
                ),
                _ToolbarButton(
                  icon: Icons.format_bold,
                  tooltip: '加粗',
                  onPressed: formattingEnabled ? onBold : null,
                ),
                _ToolbarButton(
                  icon: Icons.format_italic,
                  tooltip: '斜体',
                  onPressed: formattingEnabled ? onItalic : null,
                ),
                _ToolbarButton(
                  icon: Icons.format_quote,
                  tooltip: '引用',
                  onPressed: formattingEnabled ? onQuote : null,
                ),
                _ToolbarButton(
                  icon: Icons.format_list_bulleted,
                  tooltip: '无序列表',
                  onPressed: formattingEnabled ? onBulletList : null,
                ),
                _ToolbarButton(
                  icon: Icons.format_list_numbered,
                  tooltip: '有序列表',
                  onPressed: formattingEnabled ? onNumberList : null,
                ),
                _ToolbarButton(
                  icon: previewing
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                  tooltip: previewing ? '继续编辑' : '预览',
                  onPressed: onTogglePreview,
                ),
              ],
            ),
          ),
          Divider(height: 0.5, thickness: 0.5, color: colors.outlineVariant),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: previewing
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: previewHtml.isEmpty
                        ? Text(
                            '暂无可预览的内容。',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          )
                        : HtmlContent(html: previewHtml),
                  )
                : TextField(
                    controller: controller,
                    enabled: enabled,
                    maxLines: null,
                    minLines: 8,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 16, height: 24 / 16),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(14),
                      hintText: '支持 Markdown 格式',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeadingToolbarButton extends StatelessWidget {
  const _HeadingToolbarButton({
    required this.enabled,
    required this.onSelected,
  });

  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    enabled: enabled,
    tooltip: '标题',
    icon: const Icon(Icons.title, size: 19),
    onSelected: onSelected,
    itemBuilder: (context) => <PopupMenuEntry<int>>[
      for (var level = 1; level <= 6; level++)
        PopupMenuItem<int>(value: level, child: Text('H$level')),
    ],
  );
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    iconSize: 19,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon),
  );
}
