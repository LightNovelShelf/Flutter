import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/features/reader/reader_engine.dart';

const String _base = 'https://api.example';

void main() {
  group('阅读器导航策略', () {
    test('文档自身那次主框架导航放行（WKWebView 会上报 baseUrl）', () {
      expect(
        isReaderDocumentNavigation(
          url: _base,
          isMainFrame: true,
          baseUrl: _base,
        ),
        isTrue,
      );
      expect(
        isReaderDocumentNavigation(
          url: '$_base/',
          isMainFrame: true,
          baseUrl: _base,
        ),
        isTrue,
      );
    });

    test('子框架与站内其它地址不算文档导航', () {
      expect(
        isReaderDocumentNavigation(
          url: '$_base/',
          isMainFrame: false,
          baseUrl: _base,
        ),
        isFalse,
      );
      expect(
        isReaderDocumentNavigation(
          url: '$_base/book/1',
          isMainFrame: true,
          baseUrl: _base,
        ),
        isFalse,
      );
    });

    test('正文外链拦掉，about:blank 与锚点放行', () {
      expect(isReaderExternalNavigation('https://example.com/a'), isTrue);
      expect(isReaderExternalNavigation('http://example.com/a'), isTrue);
      expect(isReaderExternalNavigation('about:blank'), isFalse);
      expect(isReaderExternalNavigation('#footnote-1'), isFalse);
    });
  });
}
