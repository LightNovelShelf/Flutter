import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/app/theme/app_theme.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/features/discover/announcement_center_screen.dart';

/// 维持 90 帧（11.1ms 预算）依赖的两条不变量，都是实测掉帧反推出来的。
void main() {
  group('主题实例复用', () {
    const AppSettings settings = AppSettings();

    test('同样输入必须返回同一个实例，否则 AnimatedTheme 会重建整棵树', () {
      final ThemeData first = buildAppTheme(
        brightness: Brightness.light,
        settings: settings,
      );
      final ThemeData second = buildAppTheme(
        brightness: Brightness.light,
        settings: settings,
      );

      expect(identical(first, second), isTrue);
    });

    test('只有影响取色的字段变化才重新构建', () {
      final ThemeData base = buildAppTheme(
        brightness: Brightness.light,
        settings: settings,
      );

      // 与主题无关的设置项改动不应该产生新实例。
      final ThemeData unrelated = buildAppTheme(
        brightness: Brightness.light,
        settings: settings.copyWith(bookDetailCacheEnabled: false),
      );
      expect(identical(base, unrelated), isTrue);

      // 亮暗和种子色是真正的输入，必须分开缓存。
      final ThemeData dark = buildAppTheme(
        brightness: Brightness.dark,
        settings: settings,
      );
      expect(identical(base, dark), isFalse);
      expect(dark.brightness, Brightness.dark);

      final ThemeData reseeded = buildAppTheme(
        brightness: Brightness.light,
        settings: settings.copyWith(seedColorValue: '#FF5722'),
      );
      expect(identical(base, reseeded), isFalse);
      expect(reseeded.colorScheme.primary, isNot(base.colorScheme.primary));
    });
  });

  group('公告摘要', () {
    test('去标签、还原实体、压空白', () {
      expect(
        announcementSummary('<p>你好&nbsp;&amp;&nbsp;再见</p>'),
        '你好 & 再见',
      );
    });

    test('80 个字符以内原样返回，超出才截断并加省略号', () {
      final String exact = '字' * 80;
      expect(announcementSummary('<p>$exact</p>'), exact);

      final String overflow = '字' * 81;
      final String summary = announcementSummary('<p>$overflow</p>');
      expect(summary, '${'字' * 80}…');
      expect(summary.runes.length, 81);
    });

    test('按 rune 截断，不切断代理对', () {
      // emoji 是代理对，按 UTF-16 code unit 截断会切出半个字符。
      final String overflow = '🙂' * 81;
      final String summary = announcementSummary(overflow);
      expect(summary, '${'🙂' * 80}…');
    });

    test('同一份正文重复调用返回缓存的同一个字符串', () {
      const String html = '<p>缓存命中检查</p>';
      expect(
        identical(announcementSummary(html), announcementSummary(html)),
        isTrue,
      );
    });
  });
}
