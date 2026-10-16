import 'dart:io';

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';

import '../../settings/about_settings_screen.dart';

const String _turnstileSiteKey = '0x4AAAAAAADgWLX3ngufVh5F';

/// 发送邮箱验证码前的 Cloudflare 人机验证，令牌一次性有效，每次发送后需调用 [AuthTurnstileState.reset]。
class AuthTurnstile extends StatefulWidget {
  const AuthTurnstile({
    super.key,
    required this.action,
    required this.onTokenChanged,
  });

  /// 与后端校验的用途一致，如 register、reset_password。
  final String action;

  /// 令牌可用时传入令牌，过期、出错或重置时传入 null。
  final ValueChanged<String?> onTokenChanged;

  /// 插件依赖的 WebView 不支持 Linux。
  static bool get isSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  @override
  State<AuthTurnstile> createState() => AuthTurnstileState();
}

class AuthTurnstileState extends State<AuthTurnstile> {
  int _generation = 0;
  String? _error;

  /// 重建 WebView 重新发起验证，旧令牌随之作废。
  void reset() {
    widget.onTokenChanged(null);
    if (!mounted) return;
    setState(() {
      _generation += 1;
      _error = null;
    });
  }

  void _fail(String message) {
    widget.onTokenChanged(null);
    if (!mounted) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextStyle hintStyle = TextStyle(
      color: colors.onSurfaceVariant,
      fontSize: 14,
      height: 20 / 14,
    );

    if (!AuthTurnstile.isSupported) {
      return Text('当前平台无法完成人机验证，请前往网页操作。', style: hintStyle);
    }

    final String? error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: CloudflareTurnstile(
            key: ValueKey<int>(_generation),
            siteKey: _turnstileSiteKey,
            action: widget.action,
            // 移动端要求 baseUrl 属于站点密钥登记的域名。
            baseUrl: officialWebsiteUrl,
            options: TurnstileOptions(
              language: 'zh-cn',
              theme: Theme.of(context).brightness == Brightness.dark
                  ? TurnstileTheme.dark
                  : TurnstileTheme.light,
            ),
            onTokenReceived: (String token) {
              if (_error != null) setState(() => _error = null);
              widget.onTokenChanged(token);
            },
            onTokenExpired: () => widget.onTokenChanged(null),
            onError: (TurnstileException _) => _fail('人机验证失败。'),
            onTimeout: () => _fail('人机验证加载超时。'),
          ),
        ),
        if (error != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(error, style: hintStyle.copyWith(color: colors.error)),
              TextButton(onPressed: reset, child: const Text('重试')),
            ],
          ),
      ],
    );
  }
}
