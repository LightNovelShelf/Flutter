import 'package:flutter/material.dart';

import '../../data/api/models.dart';
import '../../shared/layout/book_grid_layout.dart';
import '../../shared/paging/identity_child_delegate.dart';
import '../../shared/widgets/book_cover_grid_item.dart';

/// 书架当前层中属于同一系列的小说。这里只展示已收藏的分卷。
class ShelfSeriesBooksScreen extends StatelessWidget {
  const ShelfSeriesBooksScreen({
    super.key,
    required this.seriesName,
    required this.books,
    required this.onOpen,
  });

  final String seriesName;
  final List<BookListItem> books;
  final void Function(BuildContext context, BookListItem book) onOpen;

  @override
  Widget build(BuildContext context) {
    final layout = BookGridLayout.of(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: AppBar(
        title: Text(seriesName, overflow: TextOverflow.ellipsis),
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              BookGridLayout.horizontalPadding,
              20,
              BookGridLayout.horizontalPadding,
              32,
            ),
            sliver: SliverGrid(
              gridDelegate: layout.tileGridDelegate(),
              delegate: IdentityChildDelegate<BookListItem>(
                items: books,
                revision: (layout.coverHeight,),
                itemBuilder: (_, book, _) => BookCoverGridItem.fromBook(
                  book,
                  key: ValueKey<int>(book.id),
                  coverHeight: layout.coverHeight,
                  onTap: () => onOpen(context, book),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
