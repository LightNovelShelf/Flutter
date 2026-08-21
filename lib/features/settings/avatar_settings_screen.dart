import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../data/repositories/avatar_source.dart';
import '../../data/repositories/profile_repository.dart';
import '../../shared/widgets/user_avatar.dart';

const Map<AvatarSource, ({String label, String placeholder, String hint})>
    _sourceCopy = <AvatarSource, ({String label, String placeholder, String hint})>{
  AvatarSource.url: (
    label: 'HTTPS 图片网址',
    placeholder: 'https://example.com/avatar.jpg',
    hint: '图片网址必须使用 HTTPS。',
  ),
  AvatarSource.qq: (
    label: 'QQ 号码',
    placeholder: '输入 QQ 号码',
    hint: '你的 QQ 号码会显示在公开的头像网址中。',
  ),
  AvatarSource.qqGroup: (
    label: 'QQ 群号码',
    placeholder: '输入 QQ 群号码',
    hint: '你的 QQ 群号码会显示在公开的头像网址中。',
  ),
};

/// 头像设置页，按来源分别保存草稿并实时预览。
class AvatarSettingsScreen extends ConsumerStatefulWidget {
  const AvatarSettingsScreen({super.key});

  @override
  ConsumerState<AvatarSettingsScreen> createState() =>
      _AvatarSettingsScreenState();
}

class _AvatarSettingsScreenState extends ConsumerState<AvatarSettingsScreen> {
  final TextEditingController _controller = TextEditingController();
  final Map<AvatarSource, String> _drafts = <AvatarSource, String>{
    AvatarSource.url: '',
    AvatarSource.qq: '',
    AvatarSource.qqGroup: '',
  };

  AvatarSource _source = AvatarSource.url;
  String? _error;
  bool _saving = false;
  int? _hydratedProfileId;

  @override
  void initState() {
    super.initState();
    // 输入变化需要重建预览。
    _controller.addListener(_onInputChanged);
    final profile = ref.read(profileProvider).value;
    if (profile != null) _hydrate(profile);
  }

  @override
  void dispose() {
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  /// 用当前头像回填草稿，按账号 id 去重，避免刷新覆盖正在输入的内容。
  void _hydrate(UserProfile profile) {
    if (_hydratedProfileId == profile.id) return;
    _hydratedProfileId = profile.id;
    final parsed = parseAvatarSource(profile.avatarUrl);
    _drafts[parsed.source] = parsed.value;
    _source = parsed.source;
    _controller.text = parsed.value;
  }

  void _selectSource(AvatarSource source) {
    if (source == _source) return;
    setState(() {
      _drafts[_source] = _controller.text;
      _source = source;
      _error = null;
      _controller.text = _drafts[source] ?? '';
    });
  }

  String _previewUrl(UserProfile profile) {
    final input = _controller.text.trim();
    if (input.isEmpty) return profile.avatarUrl;
    try {
      return resolveAvatarUrl(_source, input);
    } on ArgumentError {
      // 输入未完成时不报错，继续显示现有头像。
      return profile.avatarUrl;
    }
  }

  Future<void> _save() async {
    final String url;
    try {
      url = resolveAvatarUrl(_source, _controller.text);
    } on ArgumentError catch (error) {
      setState(() => _error = error.message?.toString() ?? '请输入有效的头像来源。');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(profileProvider.notifier).setAvatar(url);
      if (!mounted) return;
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiError ? error.message : '无法更新头像，请重试。',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<UserProfile?>>(profileProvider, (_, next) {
      final profile = next.value;
      if (profile != null && _hydratedProfileId != profile.id) {
        setState(() => _hydrate(profile));
      }
    });

    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.value;

    return Scaffold(
      appBar: AppBar(title: const Text('头像')),
      body: profile == null
          ? _StatusView(
              loading: profileAsync.isLoading,
              onRetry: () => ref.read(profileProvider.notifier).reload(),
            )
          : _body(profile),
    );
  }

  Widget _body(UserProfile profile) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final copy = _sourceCopy[_source]!;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 24, 20, math.max(28, bottomInset + 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '更换头像',
            style: text.headlineMedium?.copyWith(
              fontSize: 30,
              height: 36 / 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '选择图片来源，保存前可先查看效果。',
            style: text.bodyLarge?.copyWith(
              fontSize: 16,
              height: 23 / 16,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: <Widget>[
                UserAvatar(
                  url: _previewUrl(profile),
                  name: profile.userName,
                  size: 64,
                  fallbackIcon: Icons.person,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        profile.userName.trim().isEmpty
                            ? '个人头像'
                            : profile.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '实时预览',
                        style: text.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SegmentedButton<AvatarSource>(
            segments: const <ButtonSegment<AvatarSource>>[
              ButtonSegment<AvatarSource>(
                value: AvatarSource.url,
                label: Text('图片网址'),
              ),
              ButtonSegment<AvatarSource>(
                value: AvatarSource.qq,
                label: Text('QQ 头像'),
              ),
              ButtonSegment<AvatarSource>(
                value: AvatarSource.qqGroup,
                label: Text('QQ 群头像'),
              ),
            ],
            selected: <AvatarSource>{_source},
            showSelectedIcon: false,
            onSelectionChanged:
                _saving ? null : (selection) => _selectSource(selection.first),
          ),
          const SizedBox(height: 22),
          Text(
            copy.label,
            style: text.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            enabled: !_saving,
            keyboardType: _source == AvatarSource.url
                ? TextInputType.url
                : TextInputType.number,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: copy.placeholder,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? copy.hint,
            style: text.bodySmall?.copyWith(
              fontSize: 13,
              height: 18 / 13,
              color: _error == null ? colors.onSurfaceVariant : colors.error,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (_saving) ...<Widget>[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  _saving ? '正在保存…' : '保存头像',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.loading, required this.onRetry});

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (loading) ...<Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
            ],
            Text(
              loading ? '正在加载个人资料…' : '无法加载个人资料',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant),
            ),
            if (!loading) ...<Widget>[
              const SizedBox(height: 14),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}
