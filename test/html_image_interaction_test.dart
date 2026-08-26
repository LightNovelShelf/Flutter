import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:lightnovel/shared/widgets/blurhash_image.dart';
import 'package:lightnovel/shared/widgets/book_image.dart';
import 'package:lightnovel/shared/widgets/image_preview.dart';
import 'package:lightnovel/shared/widgets/html/reader_content_style.dart';
import 'package:lightnovel/shared/widgets/reader_html_block.dart';
import 'package:photo_view/photo_view.dart';

const _hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
const _markup =
    '<a href="https://example.com"><img '
    'src="https://img.example/post.webp?size=40x60'
    '&amp;placeholder=$_hash"></a>';

const _style = ReaderContentStyle(
  fontSize: 16,
  lineHeight: 1.5,
  lineSpace: 4,
  firstLineIndent: false,
  justify: false,
);

Future<int Function()> _pumpBlock(
  WidgetTester tester, {
  String markup = _markup,
}) async {
  debugBlurHashPixelDecoder = (_, {required width, required height}) =>
      Uint8List.fromList(List<int>.filled(width * height * 4, 255));
  addTearDown(() => debugBlurHashPixelDecoder = null);
  var openedLinks = 0;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          child: ReaderHtmlBlock(
            markup: markup,
            style: _style,
            onTapUrl: (_) async {
              openedLinks++;
              return true;
            },
            borderIllustrations: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return () => openedLinks;
}

String _previewUrl(WidgetTester tester) {
  final provider = tester
      .widget<PhotoView>(find.byType(PhotoView))
      .imageProvider;
  return (provider! as CachedNetworkImageProvider).url;
}

const _plainImage =
    '<img src="https://img.example/post.webp?size=40x60'
    '&amp;placeholder=$_hash">';

void main() {
  testWidgets('阅读器正文图片预留尺寸并使用 BlurHash，长按预览，短按仍走链接', (tester) async {
    final openedLinks = await _pumpBlock(tester);

    final image = find.byType(BookImage);
    expect(image, findsOneWidget);
    expect(tester.getSize(image), const Size(40, 60));
    expect(tester.widget<BookImage>(image).blurHash, _hash);

    await tester.tap(image);
    await tester.pump();
    expect(openedLinks(), 1);
    expect(find.byKey(imagePreviewTransformKey), findsNothing);

    await tester.longPress(image);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(imagePreviewTransformKey), findsOneWidget);
    expect(openedLinks(), 1);
  });

  testWidgets('预览请求的地址与显示的一致，命中同一份缓存', (tester) async {
    await _pumpBlock(tester);

    final displayed = tester.widget<BookImage>(find.byType(BookImage));
    // 显示高度 60、DPR 3 落在 256 档。
    expect(displayed.url, contains('height=256'));
    expect(displayed.requestSizedVariant, isFalse);

    await tester.longPress(find.byType(BookImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_previewUrl(tester), displayed.url);
  });

  testWidgets('裸图片成块，段落内图片保持行内布局', (tester) async {
    await _pumpBlock(tester, markup: _plainImage);
    expect(find.byType(InlineCustomWidget), findsNothing);

    await _pumpBlock(tester, markup: '<p>$_plainImage</p>');
    expect(find.byType(InlineCustomWidget), findsOneWidget);

    await _pumpBlock(tester, markup: '<p>前$_plainImage后</p>');
    expect(find.byType(InlineCustomWidget), findsOneWidget);
    final paragraph = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('前') &&
          widget.text.toPlainText().contains('后'),
    );
    expect(paragraph, findsOneWidget);
    expect(tester.getSize(paragraph).height, lessThanOrEqualTo(70));
  });
}
