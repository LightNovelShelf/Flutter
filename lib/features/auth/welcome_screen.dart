import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/app_system_ui.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import 'widgets/auth_cover_mosaic.dart';

/// 拼贴封面来源，取最新书单前 6 本。失败时降级为骨架，不报错。
final FutureProvider<List<BookListItem>> welcomeCoversProvider =
    FutureProvider<List<BookListItem>>((ref) async {
      final BookListPage page = await ref
          .watch(apiClientProvider)
          .getLatestBookList(size: 12);
      return page.items.take(6).toList(growable: false);
    });

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color background = theme.scaffoldBackgroundColor;
    final Size screen = MediaQuery.sizeOf(context);
    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    final double mosaicHeight = (screen.height * 0.76).clamp(470.0, 670.0);

    // 不在栈顶或系统要求减少动效时冻结跑马灯，避免后台空转。
    final bool isActive =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        !MediaQuery.disableAnimationsOf(context);

    final List<BookListItem> books = ref
        .watch(welcomeCoversProvider)
        .maybeWhen(
          data: (List<BookListItem> value) => value,
          orElse: () => const <BookListItem>[],
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUi.defaultOverlayStyle(theme.brightness),
      child: Scaffold(
        body: Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: mosaicHeight,
              child: AuthCoverMosaic(books: books, isActive: isActive),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        background.withValues(alpha: 0.01),
                        background.withValues(alpha: 0.08),
                        background.withValues(alpha: 0.58),
                        background,
                        background,
                      ],
                      stops: const <double>[0, 0.43, 0.59, 0.72, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 22,
                  right: 22,
                  bottom: math.max(22, safeBottom + 12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      '轻书架',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 350),
                      child: Text(
                        '每个故事，\n都是一个世界。',
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          height: 39 / 34,
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(
                        '寻找下一段故事，珍藏每一次旅程。',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 16,
                          height: 23 / 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _StartReadingButton(
                      onPressed: () => context.push('/sign-in/credentials'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartReadingButton extends StatelessWidget {
  const _StartReadingButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(28);

    return Material(
      color: colors.primary,
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '开始阅读',
                style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward_rounded,
                size: 21,
                color: colors.onPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
