import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/blurhash_image.dart';
import 'package:lightnovel/shared/widgets/book_image.dart';
import 'package:lightnovel/shared/widgets/image_preview.dart';
import 'package:lightnovel/features/reader/reader_content_style.dart';
import 'package:lightnovel/features/reader/widgets/reader_html_block.dart';

void main() {
  testWidgets('富文本图片预留尺寸并使用 BlurHash，短按不触发链接、长按预览', (tester) async {
    const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    debugBlurHashPixelDecoder = (_, {required width, required height}) =>
        Uint8List.fromList(List<int>.filled(width * height * 4, 255));
    addTearDown(() => debugBlurHashPixelDecoder = null);
    var openedLinks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: ReaderHtmlBlock(
              markup:
                  '<a href="https://example.com"><img '
                  'src="https://img.example/post.webp?size=40x60'
                  '&amp;placeholder=$hash"></a>',
              style: const ReaderContentStyle(
                fontSize: 16,
                lineHeight: 1.5,
                paragraphSpacing: 4,
                color: Colors.black,
                firstLineIndent: false,
                justify: false,
              ),
              onTapUrl: (_) async {
                openedLinks++;
                return true;
              },
              borderIllustrations: false,
              consumeImageTap: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = find.byType(BookImage);
    expect(image, findsOneWidget);
    expect(tester.getSize(image), const Size(40, 60));
    expect(tester.widget<BookImage>(image).blurHash, hash);

    await tester.tap(image);
    await tester.pump();
    expect(openedLinks, 0);
    expect(find.byKey(imagePreviewTransformKey), findsNothing);

    await tester.longPress(image);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(imagePreviewTransformKey), findsOneWidget);
    expect(openedLinks, 0);
  });
}
