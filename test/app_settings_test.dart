import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/settings/app_settings.dart';

void main() {
  test('两端对齐设置默认关闭，并可复制与持久化', () {
    expect(
      AppSettings.decode(const <String, dynamic>{}).readerJustify,
      isFalse,
    );

    final enabled = const AppSettings().copyWith(readerJustify: true);
    expect(enabled.readerJustify, isTrue);
    expect(enabled.encode()['readerJustify'], isTrue);
    expect(AppSettings.decode(enabled.encode()).readerJustify, isTrue);

    expect(
      AppSettings.decode(const <String, dynamic>{'readerJustify': 'true'})
          .readerJustify,
      isFalse,
    );
  });

  test('首行缩进默认开启，并可关闭与持久化', () {
    expect(
      AppSettings.decode(const <String, dynamic>{}).readerFirstLineIndent,
      isTrue,
    );

    final disabled = const AppSettings().copyWith(readerFirstLineIndent: false);
    expect(disabled.readerFirstLineIndent, isFalse);
    expect(disabled.encode()['readerFirstLineIndent'], isFalse);
    expect(
      AppSettings.decode(disabled.encode()).readerFirstLineIndent,
      isFalse,
    );
    expect(
      const AppSettings().encode(),
      isNot(contains('readerImagePreviewOpenOnLongPress')),
    );
  });

  test('默认 HTML 和小说阅读行高均为 1.5', () {
    expect(const AppSettings().readerLineHeight, 1.5);
    expect(AppSettings.decode(const <String, dynamic>{}).readerLineHeight, 1.5);
  });

  test('小说行距默认 4，并钳制后持久化', () {
    expect(AppSettings.decode(const <String, dynamic>{}).readerLineSpace, 4);
    final spaced = const AppSettings().copyWith(readerLineSpace: 4);
    expect(spaced.encode()['readerLineSpace'], 4);
    expect(AppSettings.decode(spaced.encode()).readerLineSpace, 4);
    expect(
      AppSettings.decode(const <String, dynamic>{'readerLineSpace': 99})
          .readerLineSpace,
      16,
    );
  });

  test('小说和漫画通用阅读设置独立持久化', () {
    final settings = const AppSettings().copyWith(
      novelReader: const ReaderPreferences(
        viewMode: ReaderViewMode.scroll,
        theme: ReaderThemeSetting.dark,
      ),
      comicReader: const ReaderPreferences(
        dualPageEnabled: true,
        dualPageOffsetEnabled: true,
        statusPillsEnabled: false,
      ),
    );

    final restored = AppSettings.decode(settings.encode());
    expect(restored.novelReader.viewMode, ReaderViewMode.scroll);
    expect(restored.novelReader.theme, ReaderThemeSetting.dark);
    expect(restored.novelReader.dualPageEnabled, isFalse);
    expect(restored.comicReader.viewMode, ReaderViewMode.paged);
    expect(restored.comicReader.dualPageEnabled, isTrue);
    expect(restored.comicReader.dualPageOffsetEnabled, isTrue);
    expect(restored.comicReader.statusPillsEnabled, isFalse);
  });

  test('小说和漫画分别保存翻页动画', () {
    final settings = const AppSettings().copyWith(
      novelReader: const ReaderPreferences(
        pageTurnAnimation: ReaderPageTurnAnimation.slide,
      ),
      comicReader: const ReaderPreferences(
        pageTurnAnimation: ReaderPageTurnAnimation.none,
      ),
    );

    final restored = AppSettings.decode(settings.encode());
    expect(
      restored.novelReader.pageTurnAnimation,
      ReaderPageTurnAnimation.slide,
    );
    expect(
      restored.comicReader.pageTurnAnimation,
      ReaderPageTurnAnimation.none,
    );
    expect(
      ReaderPreferences.decode(const <String, dynamic>{
        'pageTurnAnimation': 'fade',
      }).pageTurnAnimation,
      ReaderPageTurnAnimation.none,
    );
  });

  test('阅读背景只接受 #RRGGBB', () {
    final restored = AppSettings.decode(const <String, dynamic>{
      'novelReader': <String, dynamic>{
        'backgroundMode': 'day',
        'backgroundColorValue': 'green',
      },
    });

    expect(restored.novelReader, const ReaderPreferences());
    expect(restored.comicReader, const ReaderPreferences());
  });
}
