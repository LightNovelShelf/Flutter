import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_error.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../shared/format.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/settings_rows.dart';
import '../../shared/widgets/user_avatar.dart';
import 'point_log_sheet.dart';
import 'sign_in_sheet.dart';

/// 个人资料：账号信息、成长记录、每日签到与退出登录。
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const Duration _copyFeedbackDuration = Duration(milliseconds: 1200);

  String? _copiedRowId;
  Timer? _copyTimer;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 已有缓存时重新拉取，保证经验值与签到状态最新。
      if (ref.read(profileProvider).hasValue) {
        ref.read(profileProvider.notifier).reload();
      }
    });
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  String _errorMessage(Object error, String fallback) =>
      error is ApiError ? error.message : fallback;

  Future<void> _copy(String rowId, String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _copyTimer?.cancel();
    setState(() => _copiedRowId = rowId);
    _copyTimer = Timer(_copyFeedbackDuration, () {
      if (mounted) setState(() => _copiedRowId = null);
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '要退出登录吗？',
      message: '已同步的账号数据仍会保留在服务器上。',
      confirmLabel: '退出登录',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(authControllerProvider).signOut();
    } catch (error) {
      if (!mounted) return;
      await showAppAlert(
        context: context,
        title: '无法退出登录',
        message: _errorMessage(error, '请重试。'),
      );
    } finally {
      // 退出后路由守卫可能已卸载本页，故判断 mounted。
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Widget _copyableRow({
    required String rowId,
    required String title,
    required IconData icon,
    required String value,
    String? maskedValue,
  }) {
    final copied = _copiedRowId == rowId;
    final isEmpty = value.trim().isEmpty;
    return SettingsValueRow(
      title: title,
      description: isEmpty ? null : (copied ? '已复制' : '轻触复制'),
      icon: icon,
      value: isEmpty ? '暂无' : (copied ? '已复制' : (maskedValue ?? value)),
      enabled: !isEmpty,
      onTap: isEmpty ? null : () => _copy(rowId, value),
    );
  }

  List<Widget> _sections(UserProfile profile) {
    final growth = profile.growth;
    return <Widget>[
      SettingsSection(
        title: '个人信息',
        children: <Widget>[
          SettingsRow(
            title: '头像',
            description: '更换个人头像',
            icon: Icons.account_circle_outlined,
            onTap: () => context.push('/settings/avatar'),
            trailing: UserAvatar(
              url: profile.avatarUrl,
              name: profile.userName,
              size: 42,
              fallbackIcon: Icons.person,
            ),
          ),
          _copyableRow(
            rowId: 'uid',
            title: 'UID',
            icon: Icons.tag,
            value: '${profile.id}',
          ),
          _copyableRow(
            rowId: 'userName',
            title: '用户名',
            icon: Icons.alternate_email,
            value: profile.userName,
          ),
          _copyableRow(
            rowId: 'email',
            title: '邮箱',
            icon: Icons.mail_outline,
            value: profile.email,
          ),
          _copyableRow(
            rowId: 'inviteCode',
            title: '邀请码',
            icon: Icons.confirmation_number_outlined,
            value: profile.inviteCode,
            // 邀请码只做遮罩展示，复制到剪贴板的仍是原文。
            maskedValue: '•' * profile.inviteCode.length,
          ),
          SettingsValueRow(
            title: '用户组',
            icon: Icons.groups_outlined,
            value: profile.groupName.trim().isEmpty ? '暂无' : profile.groupName,
          ),
          SettingsValueRow(
            title: '注册时间',
            icon: Icons.event_outlined,
            value: formatMediumDate(profile.registeredAt),
          ),
        ],
      ),
      SettingsSection(
        title: '成长记录',
        children: <Widget>[
          SettingsValueRow(
            title: '等级',
            icon: Icons.military_tech_outlined,
            value: '${growth.level} 级',
          ),
          SettingsNavigationRow(
            title: '经验值',
            icon: Icons.show_chart,
            value: formatCount(growth.experience),
            onTap: () =>
                showPointLogSheet(context, kind: PointLogKind.experience),
          ),
          SettingsRow(
            title: '金币',
            icon: Icons.paid_outlined,
            onTap: () => showPointLogSheet(context, kind: PointLogKind.coin),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton(
                  onPressed: () => context.push('/shop'),
                  child: const Text('商城'),
                ),
                Text(
                  formatCount(growth.coin),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          SettingsValueRow(
            title: '漫画额度',
            description: '今日剩余 ${formatCount(growth.comicQuotaToday)} 点',
            icon: Icons.auto_stories_outlined,
            value: '永久 ${formatCount(growth.comicQuota)} 点',
          ),
          SettingsNavigationRow(
            title: '每日签到',
            description: growth.signedToday
                ? '连续 ${growth.signInStreak} 天 · 今日已签到'
                : '连续 ${growth.signInStreak} 天 · 签到可获得经验值',
            icon: Icons.event_available_outlined,
            value: growth.signedToday ? '已完成' : '签到',
            onTap: () async {
              await showSignInSheet(context);
              if (mounted) ref.read(profileProvider.notifier).reload();
            },
          ),
        ],
      ),
      SettingsSection(
        title: '账号',
        children: <Widget>[
          SettingsRow(
            title: _signingOut ? '正在退出…' : '退出登录',
            description: '从此设备移除当前账号的登录状态',
            icon: Icons.logout,
            enabled: !_signingOut,
            onTap: _signOut,
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.value;
    final loading = profileAsync.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('个人资料')),
      body: SettingsList(
        children: profile == null
            ? <Widget>[
                SettingsSection(
                  title: '个人资料',
                  children: <Widget>[
                    SettingsNavigationRow(
                      title: loading ? '正在加载个人资料…' : '无法加载个人资料',
                      description: loading ? '正在获取轻书架账号信息' : '请重试。',
                      icon: loading
                          ? Icons.account_circle_outlined
                          : Icons.error_outline,
                      enabled: !loading,
                      onTap: () => ref.read(profileProvider.notifier).reload(),
                    ),
                  ],
                ),
              ]
            : _sections(profile),
      ),
    );
  }
}
