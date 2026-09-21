import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/models.dart';

/// 书架筛选：全部显示 / 只看小说 / 只看漫画。三个标签等宽，菜单里的勾才对得齐。
enum ShelfFilter {
  all('全部显示', Icons.apps_outlined),
  novel('只看小说', Icons.menu_book_outlined),
  comic('只看漫画', Icons.photo_library_outlined);

  const ShelfFilter(this.label, this.icon);

  final String label;
  final IconData icon;

  /// 要留下的书籍类型；`null` 表示不筛选。
  ShelfItemType? get bookType => switch (this) {
    ShelfFilter.all => null,
    ShelfFilter.novel => ShelfItemType.novel,
    ShelfFilter.comic => ShelfItemType.comic,
  };
}

/// 筛选跨层级共享：进出文件夹、来回切页面都保持同一个选择。
class ShelfFilterController extends Notifier<ShelfFilter> {
  @override
  ShelfFilter build() => ShelfFilter.all;

  void select(ShelfFilter filter) => state = filter;
}

final NotifierProvider<ShelfFilterController, ShelfFilter> shelfFilterProvider =
    NotifierProvider<ShelfFilterController, ShelfFilter>(
      ShelfFilterController.new,
    );
