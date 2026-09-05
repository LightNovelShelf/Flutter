import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/shelf_draft.dart';
import '../../data/repositories/shelf_repository.dart';

@immutable
class BookDetailBundle {
  const BookDetailBundle({required this.detail});

  final BookDetail detail;

  bool get isComic => detail.type == BookType.comic;
}

/// autoDispose：书籍数量无上限，常驻缓存会持续增长。
final FutureProviderFamily<BookDetailBundle, int> bookDetailProvider =
    FutureProvider.family<BookDetailBundle, int>(
      (ref, bookId) async => BookDetailBundle(
        detail: await ref.watch(apiClientProvider).getBookInfo(bookId),
      ),
      isAutoDispose: true,
    );

/// 只读缓存快照判定，不回源查询。
final FutureProviderFamily<bool, int> bookInShelfProvider =
    FutureProvider.family<bool, int>((ref, bookId) async {
      final snapshot = await ref.watch(shelfProvider.future);
      if (snapshot == null) return false;
      return shelfContainsBook(snapshot.items, bookId);
    }, isAutoDispose: true);

/// 书架按钮的乐观状态：`inShelf` 为 null 表示没有本地覆盖，沿用 [bookInShelfProvider]。
@immutable
class ShelfToggle {
  const ShelfToggle({this.busy = false, this.inShelf, this.error});

  final bool busy;
  final bool? inShelf;
  final String? error;
}

/// 先翻转本地状态再发请求，失败回退到服务端状态并给出提示。
class ShelfToggleController extends Notifier<ShelfToggle> {
  ShelfToggleController(this.arg);

  final int arg;

  @override
  ShelfToggle build() => const ShelfToggle();

  Future<void> toggle(bool inShelf) async {
    state = ShelfToggle(busy: true, inShelf: !inShelf);
    try {
      final result = await ref.read(shelfProvider.notifier).toggleBook(arg);
      if (!ref.mounted) return;
      state = ShelfToggle(inShelf: result);
    } catch (error) {
      if (!ref.mounted) return;
      state = ShelfToggle(
        error: describeApiError(
          error,
          fallback: '无法更新书架。',
          auth: '请重新登录后使用书架。',
          network: '离线时无法修改书架。',
        ),
      );
    }
  }
}

/// autoDispose：乐观状态仅在详情页存续期间有效。
final NotifierProviderFamily<ShelfToggleController, ShelfToggle, int>
shelfToggleProvider =
    NotifierProvider.family<ShelfToggleController, ShelfToggle, int>(
      ShelfToggleController.new,
      isAutoDispose: true,
    );
