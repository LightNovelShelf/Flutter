import 'package:flutter/material.dart';

import '../../../data/api/api_client.dart';

/// 小说列表的排序切换：平铺、按系列、系列内书籍三处共用同一组选项。
class NovelOrderSelector extends StatelessWidget {
  const NovelOrderSelector({
    super.key,
    required this.order,
    required this.onChanged,
  });

  final BookListOrder order;
  final ValueChanged<BookListOrder> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<BookListOrder>(
    segments: const <ButtonSegment<BookListOrder>>[
      ButtonSegment<BookListOrder>(
        value: BookListOrder.latest,
        label: Text('最新更新'),
      ),
      ButtonSegment<BookListOrder>(
        value: BookListOrder.newest,
        label: Text('最新上架'),
      ),
      ButtonSegment<BookListOrder>(
        value: BookListOrder.view,
        label: Text('最多阅读'),
      ),
    ],
    selected: <BookListOrder>{order},
    showSelectedIcon: false,
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}
