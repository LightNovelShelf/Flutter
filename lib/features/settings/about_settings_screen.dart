import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/settings_rows.dart';

const String officialWebsiteUrl = 'https://www.lightnovel.app';
const String officialGroupUrl = 'https://t.me/+J5xdTWVGOJMyOWRl';
const String sponsorUrl = 'https://www.ifdian.net/a/wuyu8512';
const String githubUrl = 'https://github.com/LightNovelShelf/Flutter';

class AboutSettingsScreen extends StatefulWidget {
  const AboutSettingsScreen({super.key});

  @override
  State<AboutSettingsScreen> createState() => _AboutSettingsScreenState();
}

class _AboutSettingsScreenState extends State<AboutSettingsScreen> {
  String _version = '版本未知';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    final version = info.version.trim();
    final build = info.buildNumber.trim();
    setState(() {
      _version = version.isEmpty
          ? '版本未知'
          : (build.isEmpty ? version : '$version ($build)');
    });
  }

  Future<void> _openExternalUrl(String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      await showAppAlert(context: context, title: '无法打开链接', message: '请稍后重试。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: SettingsList(
      children: <Widget>[
        SettingsSection(
          title: '本应用',
          children: <Widget>[
            SettingsValueRow(
              title: '版本',
              icon: Icons.sell_outlined,
              value: _version,
            ),
            SettingsNavigationRow(
              title: '轻书架',
              description: 'www.lightnovel.app',
              icon: Icons.public,
              onTap: () => _openExternalUrl(officialWebsiteUrl),
            ),
            SettingsNavigationRow(
              title: '官方群组',
              description: 'Telegram',
              icon: Icons.forum_outlined,
              onTap: () => _openExternalUrl(officialGroupUrl),
            ),
            SettingsNavigationRow(
              title: '赞助本站',
              description: 'ifdian.net/a/wuyu8512',
              icon: Icons.favorite_border,
              onTap: () => _openExternalUrl(sponsorUrl),
            ),
            SettingsNavigationRow(
              title: 'GitHub',
              description: 'github.com/LightNovelShelf/Flutter',
              icon: Icons.code,
              onTap: () => _openExternalUrl(githubUrl),
            ),
          ],
        ),
      ],
    ),
  );
}
