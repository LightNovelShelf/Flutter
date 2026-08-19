import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/book_cover_image.dart';

/// 封面「BlurHash → 真实封面」过渡的结构不变量。
///
/// 占位层必须是缓存网络图的同级下层，并在真图淡入期间保持不透明，避免两层
/// 同时淡出露出背景。
void main() {
  const String hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
  const String url = 'https://img.example/cover.webp?placeholder=abc&t=sig';

  Future<void> pumpCover(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: BookCoverImage(
              url: url,
              blurHash: hash,
              filterQuality: FilterQuality.high,
              memCacheWidth: 360,
              memCacheHeight: 540,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder blurHashLayer() => find.byWidgetPredicate(
    (Widget widget) => widget is Image && widget.image is BlurHashImage,
  );

  Finder networkImageLayer() => find.byType(CachedNetworkImage);

  testWidgets('占位层与网络图同时存在，且占位层在下层', (WidgetTester tester) async {
    await pumpCover(tester);

    expect(blurHashLayer(), findsOneWidget);
    expect(networkImageLayer(), findsOneWidget);

    // 层序：占位层必须排在网络图之前，才能在淡入期间一直垫底。
    final Stack stack = tester.widget<Stack>(
      find
          .ancestor(of: networkImageLayer(), matching: find.byType(Stack))
          .first,
    );
    final int placeholderIndex = stack.children.indexWhere(
      (Widget child) => child is Image && child.image is BlurHashImage,
    );
    final int imageIndex = stack.children.indexWhere(
      (Widget child) => child is CachedNetworkImage,
    );
    expect(placeholderIndex, isNonNegative);
    expect(imageIndex, greaterThan(placeholderIndex));
  });

  testWidgets('网络图单层淡入，按物理尺寸缓存并使用高质量采样', (WidgetTester tester) async {
    await pumpCover(tester);

    final CachedNetworkImage image = tester.widget<CachedNetworkImage>(
      networkImageLayer(),
    );
    expect(image.fadeOutDuration, Duration.zero);
    expect(image.fadeInDuration, const Duration(milliseconds: 200));
    expect(image.memCacheWidth, 360);
    expect(image.memCacheHeight, 540);
    final Widget rendered = image.imageBuilder!(
      tester.element(networkImageLayer()),
      const AssetImage('unused'),
    );
    expect(rendered, isA<Image>());
    expect((rendered as Image).filterQuality, FilterQuality.high);
  });

  testWidgets('没有 BlurHash 时回落到卡片底色加图标', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: BookCoverImage(url: url),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('封面地址去掉 placeholder 参数后作为缓存键', (WidgetTester tester) async {
    expect(
      BookCoverImage.cacheKeyFor(url),
      'https://img.example/cover.webp?t=sig',
    );
  });
}
