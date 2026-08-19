import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/book_cover_image.dart';

/// 封面「BlurHash → 真实封面」过渡的结构不变量。
///
/// 闪烁的成因不是动画时长，而是层级：占位层若交给 `CachedNetworkImage.placeholder`，
/// 它会随图片淡入同步淡出，中途两层都半透明就露出背景。所以这里断言占位层是网络图
/// 的**同级下层**，且没有第二段淡出。
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
            child: BookCoverImage(url: url, blurHash: hash),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder blurHashLayer() => find.byWidgetPredicate(
        (Widget widget) => widget is Image && widget.image is BlurHashImage,
      );

  testWidgets('占位层与网络图同时存在，且占位层在下层', (WidgetTester tester) async {
    await pumpCover(tester);

    expect(blurHashLayer(), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);

    // 层序：占位层必须排在网络图之前，才能在淡入期间一直垫底。
    final Stack stack = tester.widget<Stack>(
      find.ancestor(of: find.byType(CachedNetworkImage), matching: find.byType(Stack)).first,
    );
    final int placeholderIndex = stack.children.indexWhere(
      (Widget child) => child is Image && child.image is BlurHashImage,
    );
    final int imageIndex =
        stack.children.indexWhere((Widget child) => child is CachedNetworkImage);
    expect(placeholderIndex, isNonNegative);
    expect(imageIndex, greaterThan(placeholderIndex));
  });

  testWidgets('不再叠第二段淡出，占位槽保持透明', (WidgetTester tester) async {
    await pumpCover(tester);

    final CachedNetworkImage image =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    // 淡出交给外层 Stack 的遮盖，这里必须为零，否则中途露底闪一下。
    expect(image.fadeOutDuration, Duration.zero);
    expect(image.fadeInDuration, const Duration(milliseconds: 200));
  });

  testWidgets('用 BlurHashImage 而不是 BlurHash 组件（后者解码前会画蓝灰块）',
      (WidgetTester tester) async {
    await pumpCover(tester);

    expect(find.byType(BlurHash), findsNothing);
    expect(blurHashLayer(), findsOneWidget);
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

    expect(blurHashLayer(), findsNothing);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('封面地址去掉 placeholder 参数后作为缓存键', (WidgetTester tester) async {
    expect(
      BookCoverImage.cacheKeyFor(url),
      'https://img.example/cover.webp?t=sig',
    );
  });
}
