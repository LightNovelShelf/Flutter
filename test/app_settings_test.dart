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

  test('小说段间距默认 0，并钳制后持久化', () {
    expect(
      AppSettings.decode(const <String, dynamic>{}).readerParagraphSpacing,
      0,
    );
    final spaced = const AppSettings().copyWith(readerParagraphSpacing: 4);
    expect(spaced.encode()['readerParagraphSpacing'], 4);
    expect(AppSettings.decode(spaced.encode()).readerParagraphSpacing, 4);
    expect(
      AppSettings.decode(const <String, dynamic>{'readerParagraphSpacing': 99})
          .readerParagraphSpacing,
      16,
    );
  });

  test('音量键翻页默认关闭，并可开启与持久化', () {
    expect(
      AppSettings.decode(const <String, dynamic>{})
          .readerVolumeKeyPagingEnabled,
      isFalse,
    );

    final enabled = const AppSettings().copyWith(
      readerVolumeKeyPagingEnabled: true,
    );
    expect(enabled.readerVolumeKeyPagingEnabled, isTrue);
    expect(enabled, isNot(const AppSettings()));
    expect(enabled.encode()['readerVolumeKeyPagingEnabled'], isTrue);
    expect(
      AppSettings.decode(enabled.encode()).readerVolumeKeyPagingEnabled,
      isTrue,
    );
    expect(
      AppSettings.decode(
        const <String, dynamic>{'readerVolumeKeyPagingEnabled': 'true'},
      ).readerVolumeKeyPagingEnabled,
      isFalse,
    );
  });

  test('阅读背景默认跟随应用主题，自定义色只接受 #RRGGBB', () {
    final defaults = AppSettings.decode(const <String, dynamic>{});
    expect(defaults.readerBackgroundMode, ReaderBackgroundMode.auto);
    expect(defaults.readerBackgroundColorValue, '#F7F1E3');

    final custom = const AppSettings().copyWith(
      readerBackgroundMode: ReaderBackgroundMode.custom,
      readerBackgroundColorValue: '#9fed9f',
    );
    expect(custom, isNot(const AppSettings()));
    expect(custom.encode()['readerBackgroundMode'], 'custom');
    final restored = AppSettings.decode(custom.encode());
    expect(restored.readerBackgroundMode, ReaderBackgroundMode.custom);
    // 落库前统一大写，写入路径也走 decode。
    expect(restored.readerBackgroundColorValue, '#9FED9F');

    expect(
      AppSettings.decode(const <String, dynamic>{
        'readerBackgroundMode': 'day',
        'readerBackgroundColorValue': 'green',
      }),
      const AppSettings(),
    );
  });
}
