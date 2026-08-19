import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/features/shelf/widgets/shelf_folder_tile.dart';
import 'package:lightnovel/shared/widgets/book_cover_image.dart';

BookListItem _book(int id) => BookListItem(
  id: id,
  type: BookType.novel,
  title: '书 $id',
  seriesTitle: null,
  coverUrl: '',
  coverPlaceholder: null,
  authorName: null,
  lastUpdatedAt: DateTime(2026),
  level: null,
  interiorLevel: null,
  category: null,
);

void main() {
  for (final count in <int>[1, 2]) {
    testWidgets('文件夹有 $count 本书时从左上角开始排列', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 120,
                child: ShelfFolderTile(
                  title: '文件夹',
                  covers: <BookListItem>[
                    for (var index = 0; index < count; index++)
                      _book(index + 1),
                  ],
                  childCount: count,
                ),
              ),
            ),
          ),
        ),
      );

      final tileTop = tester.getTopLeft(find.byType(ShelfFolderTile)).dy;
      final covers = find.byType(BookCoverImage);
      expect(covers, findsNWidgets(count));
      expect(tester.getTopLeft(covers.first).dy, tileTop + 10);
      if (count == 2) {
        expect(
          tester.getTopLeft(covers.at(1)).dy,
          tester.getTopLeft(covers.first).dy,
        );
      }
    });
  }
}
