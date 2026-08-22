import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/settings_rows.dart';

const String officialWebsiteUrl = 'https://www.lightnovel.app';

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

  Future<void> _openWebsite() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(officialWebsiteUrl),
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
              onTap: _openWebsite,
            ),
          ],
        ),
      ],
    ),
  );
}
