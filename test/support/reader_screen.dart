import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阅读器当前屏的构成，供正文视图与整屏两处用例共用。

/// 当前屏从左到右每一栏上摆着什么：
/// `'2-0'` 是第 2 章第 0 栏的正文，`'…'` 是加载栏，`''` 是留白。
///
/// `PageView` 会预建左右邻屏，落在视口外的一律不算。
List<String> readerScreenSlots(WidgetTester tester, {int columns = 1}) {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final slots = List<String>.filled(columns, '');
  int? bandOf(Rect box) {
    final band = (box.center.dx / (width / columns)).floor();
    return band < 0 || band >= columns ? null : band;
  }

  bool visible(RenderObject? box) =>
      box is RenderBox &&
      box.hasSize &&
      box.localToGlobal(Offset.zero).dx < width &&
      box.localToGlobal(Offset.zero).dx + box.size.width > 0;

  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'reader-page-',
                ),
          )
          .evaluate()) {
    final box = element.renderObject;
    if (!visible(box)) continue;
    box as RenderBox;
    final band = bandOf(box.localToGlobal(Offset.zero) & box.size);
    if (band == null) continue;
    final parts = (element.widget.key! as ValueKey<String>).value.split('-');
    slots[band] = '${parts[2]}-${parts[3]}';
  }
  for (final element in find.byType(CircularProgressIndicator).evaluate()) {
    final box = element.renderObject;
    if (!visible(box)) continue;
    box as RenderBox;
    final band = bandOf(box.localToGlobal(Offset.zero) & box.size);
    if (band == null) continue;
    slots[band] = '…';
  }
  return slots;
}
