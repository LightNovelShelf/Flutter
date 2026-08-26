import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/widgets/blurhash_image.dart';
import 'package:lightnovel/shared/widgets/book_image.dart';

/// 封面从 BlurHash 占位过渡到真实封面的结构约束。
///
/// 占位层是缓存网络图的同级下层，真图淡入期间保持不透明，否则两层同时淡出会露出背景。
void main() {
  const String hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
  const String url = 'https://img.example/cover.webp?placeholder=abc&t=sig';

  setUp(() {
    BookImage.clearRevealCache();
    debugBlurHashPixelDecoder = (_, {required width, required height}) =>
        Uint8List.fromList(List<int>.filled(width * height * 4, 255));
  });
  tearDown(() => debugBlurHashPixelDecoder = null);

  test('Native Assets 查表解码 RGBA 像素', () {
    debugBlurHashPixelDecoder = null;
    final pixels = decodeBlurHash(hash, width: 16, height: 24);
    expect(pixels, hasLength(16 * 24 * 4));
    expect(pixels.sublist(0, 4), <int>[135, 164, 177, 255]);
  });

  Future<void> pumpCover(WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: BookImage(
              url: url,
              displayHeight: 180,
              blurHash: hash,
              filterQuality: FilterQuality.high,
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

    // Stack 子节点顺序决定层序，占位层须排在网络图之前。
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

  testWidgets('真图已解码在内存里：重新挂载不再闪一次 BlurHash', (WidgetTester tester) async {
    await pumpCover(tester);
    final String cacheKey = tester
        .widget<CachedNetworkImage>(networkImageLayer())
        .cacheKey!;
    expect(blurHashLayer(), findsOneWidget);

    // 先卸掉这棵树并清空缓存：首次挂载已经把同一个 provider 登记成 pending，
    // 不清掉的话 putIfAbsent 会直接返回那条永远不会完成的记录。
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // 造一条解码成功的缓存记录。provider 的相等只看 (cacheKey, scale, maxWidth,
    // maxHeight)，所以这里的 url 随便给也能命中同一个键。
    // `createTestImage` 要真异步才会完成，fake-async 里 await 会永久挂住。
    final ui.Image decoded = (await tester.runAsync(
      () => createTestImage(width: 4, height: 6),
    ))!;
    final CachedNetworkImageProvider provider = CachedNetworkImageProvider(
      url,
      cacheKey: cacheKey,
    );
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(ImageInfo(image: decoded)),
      ),
    );
    addTearDown(PaintingBinding.instance.imageCache.clear);
    expect(
      PaintingBinding.instance.imageCache.statusForKey(provider).keepAlive,
      isTrue,
    );

    // 翻页就是把整棵子树卸掉重挂，这里重新挂一次制造同样的效果。
    await pumpCover(tester);

    expect(blurHashLayer(), findsNothing);
    expect(networkImageLayer(), findsOneWidget);
  });

  testWidgets('真图缓存被驱逐后恢复占位层', (WidgetTester tester) async {
    await pumpCover(tester);
    final element = tester.element(networkImageLayer());
    final image = tester.widget<CachedNetworkImage>(networkImageLayer());

    image.imageBuilder!(element, const AssetImage('unused'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 251));
    expect(blurHashLayer(), findsNothing);

    image.placeholder!(element, image.imageUrl);
    await tester.pump();
    await tester.pump();

    expect(blurHashLayer(), findsOneWidget);
  });

  testWidgets('网络图单层淡入，按尺寸档请求图床并使用高质量采样', (WidgetTester tester) async {
    await pumpCover(tester);

    final CachedNetworkImage image = tester.widget<CachedNetworkImage>(
      networkImageLayer(),
    );
    expect(image.fadeOutDuration, Duration.zero);
    expect(image.fadeInDuration, const Duration(milliseconds: 200));
    // 180dp × dpr 3 = 540px，就近取档落到 512。
    expect(image.imageUrl, contains('height=512'));
    // 字节已由服务端缩放，客户端不限制解码尺寸。
    expect(image.memCacheWidth, isNull);
    expect(image.memCacheHeight, isNull);
    final Widget rendered = image.imageBuilder!(
      tester.element(networkImageLayer()),
      const AssetImage('unused'),
    );
    expect(rendered, isA<Image>());
    expect((rendered as Image).filterQuality, FilterQuality.high);
  });

  testWidgets('外站图片关闭尺寸参数时保持原地址', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: BookImage(
              url: url,
              displayHeight: 180,
              requestSizedVariant: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<CachedNetworkImage>(networkImageLayer());
    expect(image.imageUrl, url);
  });

  testWidgets('没有 BlurHash 时回落到卡片底色加图标', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: BookImage(url: url, displayHeight: 180),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('漫画整页用法：占位层铺满盒子，按图片比例解码，无图标兜底', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 300,
            child: BookImage(
              url: url,
              displayHeight: 300,
              blurHash: hash,
              fit: BoxFit.contain,
              aspectRatio: 1200 / 800,
              fadeInDuration: const Duration(milliseconds: 80),
              fallbackIcon: null,
              errorBuilder: (context, retry) => const Text('重试'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final Image placeholder = tester.widget<Image>(blurHashLayer());
    // 占位层用 fill 而非 contain：16 宽解码的高度取整后宽高比有 1/16 台阶，
    // contain 的留白会让它比真图窄几个像素。
    expect(placeholder.fit, BoxFit.fill);
    expect(placeholder.gaplessPlayback, isTrue);
    final BlurHashImage provider = placeholder.image as BlurHashImage;
    expect(provider.decodingWidth, BookImage.blurHashWidth);
    expect(provider.decodingHeight, (BookImage.blurHashWidth * 1.5).round());

    final CachedNetworkImage image = tester.widget<CachedNetworkImage>(
      networkImageLayer(),
    );
    expect(image.fit, BoxFit.contain);
    expect(image.fadeInDuration, const Duration(milliseconds: 80));
    expect(image.fadeOutDuration, Duration.zero);
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
  });

  testWidgets('长条页比例不再被截断', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 2400,
            child: BookImage(
              url: url,
              displayHeight: 2400,
              blurHash: hash,
              fit: BoxFit.contain,
              aspectRatio: 2400 / 200,
              fallbackIcon: null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final BlurHashImage provider =
        tester.widget<Image>(blurHashLayer()).image as BlurHashImage;
    expect(provider.decodingHeight, BookImage.blurHashWidth * 12);
  });

  testWidgets('封面地址去掉 placeholder 和 t 参数后作为缓存键', (WidgetTester tester) async {
    expect(BookImage.cacheKeyFor(url), 'https://img.example/cover.webp');
  });

  testWidgets('同一张图带不同签名参数命中同一个缓存键', (WidgetTester tester) async {
    expect(
      BookImage.cacheKeyFor('https://img.example/cover.webp?t=other'),
      BookImage.cacheKeyFor(url),
    );
  });

  testWidgets('保留其它查询参数', (WidgetTester tester) async {
    expect(
      BookImage.cacheKeyFor('https://img.example/cover.webp?w=200&t=sig'),
      'https://img.example/cover.webp?w=200',
    );
  });

  testWidgets('同一张图同一显示高度，缓存键与展示无关 —— 详情页三处才能复用一次请求', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 3.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              // 详情页模糊底图。
              SizedBox(
                width: 400,
                height: 280,
                child: BookImage(
                  url: url,
                  displayHeight: 150,
                  fadeInDuration: Duration(milliseconds: 80),
                ),
              ),
              // 详情页主封面。
              SizedBox(
                width: 100,
                height: 150,
                child: BookImage(
                  url: url,
                  displayHeight: 150,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final List<CachedNetworkImage> images = tester
        .widgetList<CachedNetworkImage>(networkImageLayer())
        .toList();
    expect(images, hasLength(2));
    // 显示高度同档即同一次请求，与布局尺寸、fit、淡入时长无关。
    expect(images[0].imageUrl, images[1].imageUrl);
    expect(images[0].cacheKey, images[1].cacheKey);
    expect(images[0].imageUrl, contains('height=512'));
  });
}
