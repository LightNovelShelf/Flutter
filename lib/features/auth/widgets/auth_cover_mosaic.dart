import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/api/models.dart';
import '../../../shared/widgets/book_cover_image.dart';

@immutable
class _TrackSpec {
  const _TrackSpec({
    required this.widthRatio,
    required this.leftRatio,
    required this.movesDown,
    required this.periodMs,
    required this.phase,
    required this.opacity,
    required this.scale,
  });

  final double widthRatio;
  final double leftRatio;
  final bool movesDown;
  final int periodMs;
  final double phase;
  final double opacity;
  final double scale;
}

const List<_TrackSpec> _trackSpecs = <_TrackSpec>[
  _TrackSpec(
    widthRatio: 0.31,
    leftRatio: -0.07,
    movesDown: true,
    periodMs: 20000,
    phase: 0.20,
    opacity: 0.90,
    scale: 0.96,
  ),
  _TrackSpec(
    widthRatio: 0.37,
    leftRatio: 0.29,
    movesDown: false,
    periodMs: 17000,
    phase: 0.55,
    opacity: 1.0,
    scale: 1.0,
  ),
  _TrackSpec(
    widthRatio: 0.31,
    leftRatio: 0.706,
    movesDown: true,
    periodMs: 23611,
    phase: 0.05,
    opacity: 0.88,
    scale: 0.94,
  ),
];

/// 轨道叠放次序（z 分别为 1 / 3 / 2），中间那条画在最上层。
const List<int> _paintOrder = <int>[0, 2, 1];

const double _trackAngle = -13 * math.pi / 180;

/// 每条轨道循环 2 本书，重复 5 组以填满可视区域。
const int _booksPerTrack = 2;
const int _repeatCount = 5;

/// 欢迎页背景：三条 −13° 倾斜的竖向封面跑马灯。
/// 没数据（加载中或失败）时整体降级成脉冲骨架，不展示错误。
class AuthCoverMosaic extends StatefulWidget {
  const AuthCoverMosaic({
    super.key,
    required this.books,
    required this.isActive,
  });

  final List<BookListItem> books;
  final bool isActive;

  @override
  State<AuthCoverMosaic> createState() => _AuthCoverMosaicState();
}

class _AuthCoverMosaicState extends State<AuthCoverMosaic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant AuthCoverMosaic oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 只有骨架可见时才让脉冲动画空转。
  void _syncPulse() {
    final bool shouldRun = widget.books.isEmpty && widget.isActive;
    if (shouldRun) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
  }

  List<BookListItem?> _slotsFor(int trackIndex) {
    final List<BookListItem> books = widget.books;
    if (books.isEmpty) {
      return List<BookListItem?>.filled(_booksPerTrack * _repeatCount, null);
    }
    final List<BookListItem?> pair = <BookListItem?>[
      for (int i = 0; i < _booksPerTrack; i += 1)
        books[(trackIndex + i * 3) % books.length],
    ];
    return <BookListItem?>[
      for (int i = 0; i < _repeatCount; i += 1) ...pair,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final double safeTop = MediaQuery.paddingOf(context).top;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        // 轨道比可视区高出 180，配合上移 100 保证旋转后仍然满幅。
        final double trackHeight = constraints.maxHeight + 180;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            for (final int index in _paintOrder)
              // 给死宽高拿到紧约束，轨道才能高过可视区而不被 Stack 夹回去。
              Positioned(
                left: _trackSpecs[index].leftRatio * width,
                top: safeTop - 100,
                width: _trackSpecs[index].widthRatio * width,
                height: trackHeight,
                child: _MarqueeTrack(
                  spec: _trackSpecs[index],
                  cardWidth: _trackSpecs[index].widthRatio * width,
                  height: trackHeight,
                  slots: _slotsFor(index),
                  isActive: widget.isActive,
                  pulse: _pulse,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MarqueeTrack extends StatefulWidget {
  const _MarqueeTrack({
    required this.spec,
    required this.cardWidth,
    required this.height,
    required this.slots,
    required this.isActive,
    required this.pulse,
  });

  final _TrackSpec spec;
  final double cardWidth;
  final double height;
  final List<BookListItem?> slots;
  final bool isActive;
  final Animation<double> pulse;

  @override
  State<_MarqueeTrack> createState() => _MarqueeTrackState();
}

class _MarqueeTrackState extends State<_MarqueeTrack>
    with TickerProviderStateMixin {
  late final AnimationController _marquee = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.spec.periodMs),
  );
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _marquee.repeat();
      _entrance.forward();
    } else {
      // 非活动状态下直接停在入场结束帧，避免看到半透明的中间态。
      _entrance.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _MarqueeTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive == oldWidget.isActive) return;
    if (widget.isActive) {
      _marquee.repeat();
      if (!_entrance.isCompleted) _entrance.forward();
    } else {
      _marquee.stop();
      _entrance.value = 1;
    }
  }

  @override
  void dispose() {
    _marquee.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double cardHeight = widget.cardWidth * 1.5;
    final double gap = math.max(8, widget.cardWidth * 0.075);
    final double loopDistance = (cardHeight + gap) * _booksPerTrack;
    final double entranceOffset = widget.spec.movesDown ? 24 : -24;

    final Widget column = OverflowBox(
      // 内容总高远超可视区，得解开纵向约束交给 ClipRect 裁。
      alignment: Alignment.topCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final BookListItem? book in widget.slots)
            Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: _CoverCard(
                book: book,
                width: widget.cardWidth,
                height: cardHeight,
                pulse: widget.pulse,
              ),
            ),
        ],
      ),
    );

    return Transform.scale(
      scale: widget.spec.scale,
      child: Transform.rotate(
        angle: _trackAngle,
        child: ClipRect(
          child: SizedBox(
            width: widget.cardWidth,
            height: widget.height,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_marquee, _entrance]),
              builder: (BuildContext context, Widget? child) {
                final double progress = (_marquee.value + widget.spec.phase) % 1.0;
                // 向下滚动时内容从 −loop 平移到 0，循环处首尾同形，肉眼无跳变。
                final double scroll = widget.spec.movesDown
                    ? (progress - 1) * loopDistance
                    : -progress * loopDistance;
                final double entered =
                    Curves.easeOutCubic.transform(_entrance.value);
                return Opacity(
                  opacity: widget.spec.opacity * entered,
                  child: Transform.translate(
                    offset: Offset(0, scroll + entranceOffset * (1 - entered)),
                    child: child,
                  ),
                );
              },
              child: column,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.book,
    required this.width,
    required this.height,
    required this.pulse,
  });

  final BookListItem? book;
  final double width;
  final double height;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final BookListItem? item = book;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: item == null
          ? AnimatedBuilder(
              animation: pulse,
              builder: (BuildContext context, _) => Opacity(
                opacity: 0.55 + 0.45 * pulse.value,
                child: ColoredBox(color: colors.surfaceContainerHighest),
              ),
            )
          : BookCoverImage(
              url: item.coverUrl,
              blurHash: item.coverPlaceholder,
            ),
    );
  }
}
