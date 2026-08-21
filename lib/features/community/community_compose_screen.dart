import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/community_models.dart';
import '../../data/providers.dart';
import 'community_providers.dart';
import 'widgets/community_primitives.dart';

/// 正文里允许保留的标签，其余字符转义。
const List<String> _allowedTags = <String>[
  'strong',
  'em',
  'blockquote',
  'ul',
  'ol',
  'li',
];

final RegExp _allowedTagPattern = RegExp(
  '</?(${_allowedTags.join('|')})>',
  caseSensitive: false,
);
final RegExp _blockLevelStart = RegExp(
  r'^<(blockquote|ul|ol)>',
  caseSensitive: false,
);
final RegExp _blankLine = RegExp(r'\n[ \t]*\n');
final RegExp _blockOpenOnOwnLine = RegExp(
  r'(?<!\n)\n[ \t]*(<(?:blockquote|ul|ol)>)',
  caseSensitive: false,
);
final RegExp _blockCloseOnOwnLine = RegExp(
  r'(</(?:blockquote|ul|ol)>)[ \t]*\n(?!\n)',
  caseSensitive: false,
);

/// 正文用纯文本编辑，发布时按空行切段生成 HTML。
String buildCommunityContentHtml(String text) {
  final escaped = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  var restored = escaped;
  for (final String tag in _allowedTags) {
    restored = restored
        .replaceAll('&lt;$tag&gt;', '<$tag>')
        .replaceAll('&lt;/$tag&gt;', '</$tag>');
  }
  // 块级标签必须独立成段，被 <p> 包住是非法嵌套。
  final normalized = restored
      .replaceAllMapped(_blockOpenOnOwnLine, (match) => '\n\n${match[1]}')
      .replaceAllMapped(_blockCloseOnOwnLine, (match) => '${match[1]}\n\n');
  final buffer = StringBuffer();
  for (final String block in normalized.split(_blankLine)) {
    final trimmed = block.trim();
    if (trimmed.isEmpty) continue;
    if (_blockLevelStart.hasMatch(trimmed)) {
      buffer.write(trimmed.replaceAll('\n', ''));
      continue;
    }
    buffer.write('<p>${trimmed.replaceAll('\n', '<br />')}</p>');
  }
  return buffer.toString();
}

/// 字数校验只看正文文字，标记不计入。
String communityPlainText(String text) =>
    text.replaceAll(_allowedTagPattern, '');

class CommunityComposeScreen extends ConsumerStatefulWidget {
  const CommunityComposeScreen({super.key, this.boardKey, this.subCategoryKey});

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
      final accepted = await ref.read(communityPostNoticeProvider).isAccepted();
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _preparing = false;
        _noticeAccepted = accepted;
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
        _error = describeCommunityError(error, fallback: '无法准备编辑器。');
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
          '• 请勿求书，也不要请求他人上传或发送书籍。\n'
          '• 不要在站点社区反馈软件问题。',
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
      final detail = await ref
          .read(apiClientProvider)
          .createCommunityThread(
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
        _error = describeCommunityError(error, fallback: '无法发布讨论。');
      });
    }
  }

  /// 把选中文字包进标签，无选区时作用于当前行。
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

  void _wrapList(String tag) {
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
    final lines = selected.isEmpty
        ? const <String>['']
        : selected.split('\n').where((line) => line.trim().isNotEmpty).toList();
    final items = (lines.isEmpty ? const <String>[''] : lines)
        .map((line) => '<li>${line.trim()}</li>')
        .join('\n');
    final replacement = '<$tag>\n$items\n</$tag>';
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
        title: const Text('发布帖子'),
        actions: <Widget>[
          IconButton(
            onPressed: _canPublish ? _publish : null,
            tooltip: '发布',
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
                    title: _boards.isEmpty ? '无法准备编辑器' : '无法发布',
                    description: _error!,
                    isError: true,
                    onRetry: _boards.isEmpty ? _prepare : null,
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
                  onBold: () => _wrapSelection('<strong>', '</strong>'),
                  onItalic: () => _wrapSelection('<em>', '</em>'),
                  onQuote: () =>
                      _wrapSelection('<blockquote>', '</blockquote>'),
                  onBulletList: () => _wrapList('ul'),
                  onNumberList: () => _wrapList('ol'),
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
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onBulletList,
    required this.onNumberList,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onBulletList;
  final VoidCallback onNumberList;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
                _ToolbarButton(
                  icon: Icons.format_bold,
                  tooltip: '加粗',
                  onPressed: enabled ? onBold : null,
                ),
                _ToolbarButton(
                  icon: Icons.format_italic,
                  tooltip: '斜体',
                  onPressed: enabled ? onItalic : null,
                ),
                _ToolbarButton(
                  icon: Icons.format_quote,
                  tooltip: '引用',
                  onPressed: enabled ? onQuote : null,
                ),
                _ToolbarButton(
                  icon: Icons.format_list_bulleted,
                  tooltip: '无序列表',
                  onPressed: enabled ? onBulletList : null,
                ),
                _ToolbarButton(
                  icon: Icons.format_list_numbered,
                  tooltip: '有序列表',
                  onPressed: enabled ? onNumberList : null,
                ),
              ],
            ),
          ),
          Divider(height: 0.5, thickness: 0.5, color: colors.outlineVariant),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: TextField(
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
                hintText: '写下帖子内容…',
              ),
            ),
          ),
        ],
      ),
    );
  }
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
