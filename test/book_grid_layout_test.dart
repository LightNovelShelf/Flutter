import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/shared/layout/book_grid_layout.dart';
import 'package:lightnovel/shared/widgets/book_cover_grid_item.dart';

void main() {
  testWidgets('骨架块按计算高度布局时不会溢出', (tester) async {
    final layout = BookGridLayout.of(412);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: layout.tileWidth,
              height: layout.skeletonTileHeight,
              child: const BookGridSkeletonTile(),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
