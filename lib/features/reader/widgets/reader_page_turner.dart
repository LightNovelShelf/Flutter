import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/settings/app_settings.dart';

const Duration readerPageTurnDuration = Duration(milliseconds: 220);
const Duration readerPageCurlDuration = Duration(milliseconds: 420);

class ReaderPageTurnController {
  ReaderPageTurnController({int initialPage = 0}) : _page = initialPage;

  int _page;
  _ReaderPageTurnerState? _state;

  int get page => _page;

  bool get hasClients => _state != null;

  bool get isTurning => _state?._turning ?? false;

  void jumpToPage(int page) {
    final state = _state;
    if (state == null) {
      _page = page;
      return;
    }
    state._jump(page);
  }

  void animateToPage(int page) {
    final state = _state;
    if (state == null) {
      _page = page;
      return;
    }
    state._animateTo(page);
  }

  void dispose() => _state = null;
}

class ReaderPageTurner extends StatefulWidget {
  const ReaderPageTurner({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.animation,
    this.reverse = false,
    this.isSpread,
    this.paperColor = const Color(0xFFFFFFFF),
    this.onPageChanged,
    this.onTurnStart,
    this.onTurnEnd,
    this.onBoundary,
  });

  final ReaderPageTurnController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ReaderPageTurnAnimation animation;
  final bool reverse;
  final bool Function(int index)? isSpread;
  final Color paperColor;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onTurnStart;
  final VoidCallback? onTurnEnd;
  final ValueChanged<bool>? onBoundary;

  @override
  State<ReaderPageTurner> createState() => _ReaderPageTurnerState();
}

class _Turn {
  _Turn({
    required this.first,
    required this.corner,
    required this.book,
    required this.spine,
  });

  final int first;
  final Offset corner;
  final bool book;
  final double spine;
  double progress = 0;
  Offset point = Offset.zero;

  int get second => first + 1;

  Offset get turned => Offset(2 * spine - corner.dx, corner.dy);
}

class _ReaderPageTurnerState extends State<ReaderPageTurner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this)
    ..addListener(_tick)
    ..addStatusListener(_onMotionStatus);

  Size _size = Size.zero;
  _Turn? _turn;
  bool _turning = false;
  final Map<int, Widget> _items = <int, Widget>{};

  bool _dragging = false;
  Offset _dragStart = Offset.zero;
  Offset _dragDelta = Offset.zero;
  int _dragDirection = 0;
  int _boundary = 0;

  double _fromProgress = 0;
  double _toProgress = 0;
  Offset _fromPoint = Offset.zero;
  Offset _toPoint = Offset.zero;
  double _lift = 0;

  int get _page => widget.controller._page;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(ReaderPageTurner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      if (identical(oldWidget.controller._state, this)) {
        oldWidget.controller._state = null;
      }
      widget.controller._state = this;
    }
    _items.clear();
  }

  @override
  void dispose() {
    if (identical(widget.controller._state, this)) {
      widget.controller._state = null;
    }
    _motion.dispose();
    if (_turning) {
      final onTurnEnd = widget.onTurnEnd;
      scheduleMicrotask(() => onTurnEnd?.call());
    }
    super.dispose();
  }

  void _setPage(int page) {
    if (page == _page) return;
    widget.controller._page = page;
    widget.onPageChanged?.call(page);
  }

  void _begin() {
    if (_turning) return;
    _turning = true;
    widget.onTurnStart?.call();
  }

  void _end() {
    if (!_turning) return;
    _turning = false;
    widget.onTurnEnd?.call();
  }

  bool _isBook(int first) {
    final isSpread = widget.isSpread;
    return isSpread != null && isSpread(first) && isSpread(first + 1);
  }

  _Turn _createTurn(int first, double cornerY) {
    final book = _isBook(first);
    return _Turn(
      first: first,
      corner: Offset(_size.width, cornerY),
      book: book,
      spine: book ? _size.width / 2 : 0,
    );
  }

  void _settleTurn() {
    _motion.stop();
    _turn = null;
    _dragging = false;
    _dragDirection = 0;
    _items.clear();
    if (mounted) setState(() {});
    _end();
  }

  void _finishNow() {
    if (_turn == null && !_dragging && !_turning) return;
    _settleTurn();
  }

  void _jump(int page) {
    _finishNow();
    if (page == _page) return;
    _begin();
    _setPage(page);
    if (mounted) setState(() {});
    _end();
  }

  void _animateTo(int page) {
    final animated =
        widget.animation != ReaderPageTurnAnimation.none &&
        widget.animation != ReaderPageTurnAnimation.vertical &&
        (page - _page).abs() == 1 &&
        !_size.isEmpty;
    if (!animated) {
      _jump(page);
      return;
    }
    _finishNow();
    final forward = page > _page;
    final turn = _createTurn(forward ? _page : page, _size.height)
      ..progress = forward ? 0 : 1;
    turn.point = forward ? turn.corner : turn.turned;
    _turn = turn;
    _begin();
    _setPage(page);
    _run(forward ? 1 : 0, lift: true);
  }

  void _run(double goal, {bool lift = false}) {
    final turn = _turn!;
    _fromProgress = turn.progress;
    _toProgress = goal;
    _fromPoint = turn.point;
    _toPoint = goal >= 1 ? turn.turned : turn.corner;
    _lift = lift ? _size.height * 0.12 : 0;
    final curl = widget.animation == ReaderPageTurnAnimation.simulation;
    final base = curl ? readerPageCurlDuration : readerPageTurnDuration;
    final remaining = (goal - turn.progress).abs().clamp(0.3, 1.0);
    _motion
      ..duration = base * remaining
      ..forward(from: 0);
  }

  void _tick() {
    final turn = _turn;
    if (turn == null) return;
    final t = Curves.easeOutCubic.transform(_motion.value);
    turn.progress = ui.lerpDouble(_fromProgress, _toProgress, t)!;
    turn.point = _constrain(
      turn,
      Offset.lerp(_fromPoint, _toPoint, t)! -
          Offset(0, _lift * math.sin(math.pi * _motion.value)),
    );
    setState(() {});
  }

  void _onMotionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _settleTurn();
  }

  Offset _constrain(_Turn turn, Offset point) {
    final anchor = Offset(turn.spine, turn.corner.dy);
    final radius = turn.corner.dx - turn.spine;
    final offset = point - anchor;
    final distance = offset.distance;
    if (distance <= radius || distance == 0) return point;
    return anchor + offset * (radius / distance);
  }

  double _curlProgress(_Turn turn) {
    final span = turn.corner.dx - turn.turned.dx;
    if (span <= 0) return 0;
    return ((turn.corner.dx - turn.point.dx) / span).clamp(0.0, 1.0);
  }

  Offset _logical(Offset position) => widget.reverse
      ? Offset(_size.width - position.dx, position.dy)
      : position;

  void _onDragStart(DragStartDetails details) {
    if (widget.itemCount <= 0 || _size.isEmpty) return;
    _finishNow();
    _dragging = true;
    _dragStart = _logical(details.localPosition);
    _dragDelta = Offset.zero;
    _dragDirection = 0;
    _boundary = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final delta = details.delta;
    _dragDelta += Offset(widget.reverse ? -delta.dx : delta.dx, delta.dy);
    if (_dragDirection == 0 && _boundary == 0) {
      if (_dragDelta.dx == 0) return;
      final forward = _dragDelta.dx < 0;
      final target = _page + (forward ? 1 : -1);
      if (target < 0 || target >= widget.itemCount) {
        _boundary = forward ? 1 : -1;
        return;
      }
      _dragDirection = forward ? 1 : -1;
      _begin();
      if (widget.animation != ReaderPageTurnAnimation.none) {
        final turn = _createTurn(
          forward ? _page : target,
          _dragStart.dy < _size.height / 2 ? 0 : _size.height,
        )..progress = forward ? 0 : 1;
        turn.point = forward ? turn.corner : turn.turned;
        _turn = turn;
      }
    }
    final turn = _turn;
    if (turn == null) return;
    final forward = _dragDirection > 0;
    final width = _size.width;
    if (widget.animation == ReaderPageTurnAnimation.simulation) {
      turn.point = _constrain(
        turn,
        (forward ? turn.corner : turn.turned) + _dragDelta,
      );
      turn.progress = _curlProgress(turn);
    } else {
      turn.progress = forward
          ? (-_dragDelta.dx / width).clamp(0.0, 1.0)
          : (1 - _dragDelta.dx / width).clamp(0.0, 1.0);
    }
    setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity =
        (widget.reverse ? -1 : 1) * details.velocity.pixelsPerSecond.dx;
    final width = _size.width;
    if (_boundary != 0) {
      final next = _boundary > 0;
      _boundary = 0;
      if (_dragDelta.dx.abs() > width * 0.12 || velocity.abs() > 400) {
        widget.onBoundary?.call(next);
      }
      return;
    }
    if (_dragDirection == 0) return;
    final forward = _dragDirection > 0;
    final moved = forward ? -_dragDelta.dx : _dragDelta.dx;
    final towards = forward ? -velocity : velocity;
    final threshold = widget.animation == ReaderPageTurnAnimation.none
        ? 24.0
        : width * 0.2;
    final commit = (moved > threshold && towards > -300) || towards > 500;
    final turn = _turn;
    if (turn == null) {
      if (commit) _setPage(_page + (forward ? 1 : -1));
      _settleTurn();
      return;
    }
    if (commit) {
      _setPage(forward ? turn.second : turn.first);
      _run(forward ? 1 : 0);
    } else {
      _run(forward ? 0 : 1);
    }
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _onDragEnd(DragEndDetails());
  }

  Widget _item(int index) => _items.putIfAbsent(index, () {
    final child = Builder(
      builder: (context) => widget.itemBuilder(context, index),
    );
    final stacked =
        widget.animation == ReaderPageTurnAnimation.cover ||
        widget.animation == ReaderPageTurnAnimation.simulation;
    return RepaintBoundary(
      child: stacked
          ? ColoredBox(color: widget.paperColor, child: child)
          : child,
    );
  });

  Matrix4 get _mirror => Matrix4.identity()
    ..setEntry(0, 0, -1)
    ..setEntry(0, 3, _size.width);

  Matrix4 _physicalMatrix(Matrix4 matrix) =>
      widget.reverse ? _mirror.multiplied(matrix).multiplied(_mirror) : matrix;

  Path _physicalPath(Path path) =>
      widget.reverse ? path.transform(_mirror.storage) : path;

  Offset _physicalPoint(Offset point) =>
      widget.reverse ? Offset(_size.width - point.dx, point.dy) : point;

  Widget _layer(Object key, int index, {Matrix4? transform, Path? clip}) =>
      _TurnLayer(
        key: ValueKey<Object>(key),
        transform: transform == null ? null : _physicalMatrix(transform),
        clip: clip == null ? null : _physicalPath(clip),
        child: _item(index),
      );

  Widget _shade(
    Object key,
    Path path, {
    Offset? from,
    Offset? to,
    required List<Color> colors,
    double blur = 0,
  }) => CustomPaint(
    key: ValueKey<Object>(key),
    painter: _ShadePainter(
      path: _physicalPath(path),
      from: from == null ? null : _physicalPoint(from),
      to: to == null ? null : _physicalPoint(to),
      colors: colors,
      blur: blur,
    ),
  );

  Matrix4 _translate(double dx) => Matrix4.translationValues(dx, 0, 0);

  List<Widget> _layers() {
    final turn = _turn;
    if (widget.itemCount <= 0) return const <Widget>[];
    if (turn == null || turn.second >= widget.itemCount) {
      final page = math.min(math.max(_page, 0), widget.itemCount - 1);
      return <Widget>[_layer(('page', page), page)];
    }
    final width = _size.width;
    final progress = turn.progress;
    final first = turn.first;
    final second = turn.second;
    switch (widget.animation) {
      case ReaderPageTurnAnimation.slide:
        return <Widget>[
          _layer(
            ('page', first),
            first,
            transform: _translate(-progress * width),
          ),
          _layer(
            ('page', second),
            second,
            transform: _translate((1 - progress) * width),
          ),
        ];
      case ReaderPageTurnAnimation.cover:
        final edge = width - progress * width;
        return <Widget>[
          _layer(('page', second), second),
          _layer(
            ('page', first),
            first,
            transform: _translate(-progress * width),
          ),
          _shade(
            'cover-shadow',
            Path()..addRect(Rect.fromLTWH(edge, 0, 24, _size.height)),
            from: Offset(edge, 0),
            to: Offset(edge + 24, 0),
            colors: const <Color>[Color(0x47000000), Color(0x00000000)],
          ),
        ];
      case ReaderPageTurnAnimation.simulation:
        return _curlLayers(turn);
      case ReaderPageTurnAnimation.vertical:
      case ReaderPageTurnAnimation.none:
        return <Widget>[_layer(('page', _page), _page)];
    }
  }

  List<Widget> _curlLayers(_Turn turn) {
    final first = turn.first;
    final second = turn.second;
    final page = Offset.zero & _size;
    final fold = turn.corner - turn.point;
    if (fold.distance < 0.5) {
      return <Widget>[
        _layer(('page', second), second),
        _layer(('page', first), first),
      ];
    }
    final normal = fold / fold.distance;
    final origin = (turn.corner + turn.point) / 2;
    final sheet = turn.book
        ? Rect.fromLTRB(turn.spine, 0, _size.width, _size.height)
        : page;
    final beyond = _clipHalfPlane(
      <Offset>[
        sheet.topLeft,
        sheet.topRight,
        sheet.bottomRight,
        sheet.bottomLeft,
      ],
      origin,
      normal,
    );
    if (beyond.length < 3) {
      return <Widget>[
        _layer(('page', second), second),
        _layer(('page', first), first),
      ];
    }
    final flap = <Offset>[
      for (final point in beyond) _reflect(point, origin, normal),
    ];
    final beyondPath = _polygon(beyond);
    final flapPath = _polygon(flap);
    final remaining = Path.combine(
      PathOperation.difference,
      Path()..addRect(page),
      beyondPath,
    );
    final reflection = _reflection(origin, normal);
    final back = turn.book
        ? reflection.multiplied(
            Matrix4.identity()
              ..setEntry(0, 0, -1)
              ..setEntry(0, 3, 2 * turn.spine),
          )
        : reflection;
    return <Widget>[
      _layer(('page', second), second),
      _shade(
        'curl-under',
        beyondPath,
        from: origin,
        to: origin + normal * 40,
        colors: const <Color>[Color(0x55000000), Color(0x00000000)],
      ),
      _layer(('page', first), first, clip: remaining),
      _shade(
        'curl-cast',
        flapPath,
        colors: const <Color>[Color(0x40000000)],
        blur: 8,
      ),
      _layer(
        ('flap', turn.book ? second : first),
        turn.book ? second : first,
        transform: back,
        clip: flapPath,
      ),
      if (!turn.book)
        _shade(
          'curl-paper',
          flapPath,
          colors: <Color>[widget.paperColor.withValues(alpha: 0.9)],
        ),
      _shade(
        'curl-fold',
        flapPath,
        from: origin,
        to: origin - normal * 32,
        colors: const <Color>[Color(0x33000000), Color(0x00000000)],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: ClipRect(
          child: Stack(fit: StackFit.expand, children: _layers()),
        ),
      );
    },
  );
}

class _TurnLayer extends StatelessWidget {
  const _TurnLayer({
    super.key,
    required this.transform,
    required this.clip,
    required this.child,
  });

  final Matrix4? transform;
  final Path? clip;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: _PathClipper(clip),
    clipBehavior: clip == null ? Clip.none : Clip.antiAlias,
    child: Transform(transform: transform ?? Matrix4.identity(), child: child),
  );
}

class _PathClipper extends CustomClipper<Path> {
  const _PathClipper(this.path);

  final Path? path;

  @override
  Path getClip(Size size) => path ?? (Path()..addRect(Offset.zero & size));

  @override
  bool shouldReclip(_PathClipper oldClipper) => oldClipper.path != path;
}

class _ShadePainter extends CustomPainter {
  const _ShadePainter({
    required this.path,
    required this.from,
    required this.to,
    required this.colors,
    required this.blur,
  });

  final Path path;
  final Offset? from;
  final Offset? to;
  final List<Color> colors;
  final double blur;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final from = this.from;
    final to = this.to;
    if (from != null && to != null && colors.length > 1) {
      paint.shader = ui.Gradient.linear(from, to, colors);
    } else {
      paint.color = colors.first;
    }
    if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ShadePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.blur != blur ||
      !listEquals(oldDelegate.colors, colors);
}

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

List<Offset> _clipHalfPlane(
  List<Offset> polygon,
  Offset origin,
  Offset normal,
) {
  final clipped = <Offset>[];
  for (var index = 0; index < polygon.length; index++) {
    final current = polygon[index];
    final next = polygon[(index + 1) % polygon.length];
    final currentSide = _dot(current - origin, normal);
    final nextSide = _dot(next - origin, normal);
    if (currentSide >= 0) clipped.add(current);
    if ((currentSide >= 0) != (nextSide >= 0)) {
      final t = currentSide / (currentSide - nextSide);
      clipped.add(Offset.lerp(current, next, t)!);
    }
  }
  return clipped;
}

Offset _reflect(Offset point, Offset origin, Offset normal) =>
    point - normal * (2 * _dot(point - origin, normal));

Matrix4 _reflection(Offset origin, Offset normal) {
  final nx = normal.dx;
  final ny = normal.dy;
  final shift = 2 * _dot(origin, normal);
  return Matrix4.identity()
    ..setEntry(0, 0, 1 - 2 * nx * nx)
    ..setEntry(0, 1, -2 * nx * ny)
    ..setEntry(0, 3, shift * nx)
    ..setEntry(1, 0, -2 * nx * ny)
    ..setEntry(1, 1, 1 - 2 * ny * ny)
    ..setEntry(1, 3, shift * ny);
}

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);
