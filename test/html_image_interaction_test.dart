import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  paragraphSpacing: 4,
  color: Colors.black,
  firstLineIndent: false,
  justify: false,
);

Future<int Function()> _pumpBlock(
  WidgetTester tester,
  ImagePreviewTrigger trigger,
) async {
  debugBlurHashPixelDecoder = (_, {required width, required height}) =>
      Uint8List.fromList(List<int>.filled(width * height * 4, 255));
  addTearDown(() => debugBlurHashPixelDecoder = null);
  var openedLinks = 0;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          child: ReaderHtmlBlock(
            markup: _markup,
            style: _style,
            onTapUrl: (_) async {
              openedLinks++;
              return true;
            },
            borderIllustrations: false,
            imagePreviewTrigger: trigger,
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

void main() {
  testWidgets('阅读器正文图片预留尺寸并使用 BlurHash，长按预览，短按仍走链接', (tester) async {
    final openedLinks = await _pumpBlock(tester, ImagePreviewTrigger.longPress);

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

  testWidgets('社区正文图片短按预览，外层链接不跳转', (tester) async {
    final openedLinks = await _pumpBlock(tester, ImagePreviewTrigger.tap);

    final image = find.byType(BookImage);
    await tester.tap(image);
    // 先出一帧把预览路由推进去，再推进过渡动画。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(imagePreviewTransformKey), findsOneWidget);
    expect(openedLinks(), 0);
  });

  testWidgets('预览请求的地址与显示的一致，命中同一份缓存', (tester) async {
    await _pumpBlock(tester, ImagePreviewTrigger.tap);

    final displayed = tester.widget<BookImage>(find.byType(BookImage));
    // 显示高度 60、DPR 3 落在 256 档。
    expect(displayed.url, contains('height=256'));
    expect(displayed.requestSizedVariant, isFalse);

    await tester.tap(find.byType(BookImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_previewUrl(tester), displayed.url);
  });
}
