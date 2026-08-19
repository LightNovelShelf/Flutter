import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/decode.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/repositories/shelf_repository.dart';
import 'package:lightnovel/data/settings/app_settings.dart';
import 'package:lightnovel/shared/content_filter.dart';

BookListItem _book({
  int id = 1,
  String? categoryName,
  String? categoryShortName,
}) => BookListItem(
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
  category: categoryName == null
      ? null
      : BookCategory(
          name: categoryName,
          shortName: categoryShortName ?? categoryName,
          color: '#000000',
        ),
);

void main() {
  group('封面 URL 与 BlurHash', () {
    test('校验通过的 BlurHash 才会被当作占位图', () {
      expect(normalizeBlurHash('LEHV6nWB2yk8pyo0adR*.7kCMdnj'), isNotNull);
      expect(normalizeBlurHash('短'), isNull);
      expect(normalizeBlurHash('包含非法字符<>'), isNull);
    });

    test('占位图参数里的 # 会被转义，避免后续签名参数变成 fragment', () {
      const raw = 'https://img.example/a.webp?placeholder=L#abc&t=sig';
      final normalized = normalizeCoverUrl(raw);
      expect(
        normalized,
        'https://img.example/a.webp?placeholder=L%23abc&t=sig',
      );
      expect(normalized.contains('t=sig'), isTrue);
    });

    test('从封面 URL 中提取 BlurHash', () {
      const url =
          'https://img.example/a.webp?placeholder=LEHV6nWB2yk8pyo0adR%2a.7kCMdnj&t=sig';
      expect(extractBlurHashPlaceholder(url), isNotNull);
    });
  });

  group('内容过滤', () {
    test('两个开关都关闭时原样返回', () {
      final items = <BookListItem>[_book()];
      expect(
        identical(applyContentFilter(items, const AppSettings()), items),
        isTrue,
      );
    });

    test('按日文与 AI 标签过滤，未分类内容保留', () {
      final items = <BookListItem>[
        _book(id: 1),
        _book(id: 2, categoryName: '日文原版', categoryShortName: '日原'),
        _book(id: 3, categoryName: 'AI翻译', categoryShortName: 'AI'),
        _book(id: 4),
      ];
      final filtered = applyContentFilter(
        items,
        const AppSettings(ignoreJapanese: true, ignoreAI: true),
      );
      expect(filtered.map((item) => item.id), <int>[1, 4]);
    });
  });

  group('设置持久化', () {
    test('越界值会被钳制回合法区间', () {
      final decoded = AppSettings.decode(<String, dynamic>{
        'fontSize': 999,
        'readerLineHeight': 0.1,
        'readerPreloadWindow': 9,
        'fontCacheLimit': 1,
        'seedColorValue': 'not-a-color',
      });
      expect(decoded.fontSize, 32);
      expect(decoded.readerLineHeight, 1);
      expect(decoded.readerPreloadWindow, 3);
      expect(decoded.fontCacheLimit, 10);
      expect(decoded.seedColorValue, '#B71C1C');
    });

    test('编码后再解码保持不变', () {
      const settings = AppSettings(
        fontSize: 21,
        readerLineHeight: 1.9,
        theme: ThemeSetting.dark,
        convertType: ConvertType.t2s,
      );
      final round = AppSettings.decode(
        settings.encode().cast<String, dynamic>(),
      );
      expect(round.fontSize, 21);
      expect(round.readerLineHeight, 1.9);
      expect(round.theme, ThemeSetting.dark);
      expect(round.convertType, ConvertType.t2s);
    });
  });

  group('书架草稿', () {
    ShelfDraft draftOf(List<ShelfItem> items) =>
        ShelfDraft(items: items, version: '20220211');

    test('删除文件夹后其中的书籍回到根目录', () {
      final draft = draftOf(<ShelfItem>[
        const ShelfItem.folder(
          id: 'f1',
          index: 0,
          parents: <String>[],
          updatedAt: '',
          title: '文件夹',
        ),
        const ShelfItem.book(
          id: 10,
          index: 0,
          parents: <String>['f1'],
          updatedAt: '',
        ),
      ]);
      final next = deleteShelfFolder(draft, id: 'f1', now: 'now');
      expect(next.items.length, 1);
      expect(next.items.single.bookId, 10);
      expect(next.items.single.parents, isEmpty);
    });

    test('移动书籍会写入目标路径并保持选中顺序', () {
      final draft = draftOf(<ShelfItem>[
        const ShelfItem.folder(
          id: 'f1',
          index: 0,
          parents: <String>[],
          updatedAt: '',
          title: '文件夹',
        ),
        const ShelfItem.book(
          id: 10,
          index: 1,
          parents: <String>[],
          updatedAt: '',
        ),
        const ShelfItem.book(
          id: 11,
          index: 2,
          parents: <String>[],
          updatedAt: '',
        ),
      ]);
      final next = moveShelfBooks(
        draft,
        bookIds: <int>[10, 11],
        destination: <String>['f1'],
        now: 'now',
      );
      final moved = shelfItemsAtPath(next, <String>['f1']);
      expect(moved.map((item) => item.bookId), <int>[10, 11]);
    });

    test('目标文件夹不存在时拒绝移动', () {
      final draft = draftOf(<ShelfItem>[
        const ShelfItem.book(
          id: 10,
          index: 0,
          parents: <String>[],
          updatedAt: '',
        ),
      ]);
      expect(
        () => moveShelfBooks(
          draft,
          bookIds: <int>[10],
          destination: <String>['missing'],
          now: 'now',
        ),
        throwsArgumentError,
      );
    });

    test('重排必须覆盖同层的每个条目', () {
      final draft = draftOf(<ShelfItem>[
        const ShelfItem.book(
          id: 10,
          index: 0,
          parents: <String>[],
          updatedAt: '',
        ),
        const ShelfItem.book(
          id: 11,
          index: 1,
          parents: <String>[],
          updatedAt: '',
        ),
      ]);
      expect(
        () => reorderShelfSiblings(
          draft,
          parents: const <String>[],
          orderedKeys: const <String>['BOOK:10'],
          now: 'now',
        ),
        throwsArgumentError,
      );
      final next = reorderShelfSiblings(
        draft,
        parents: const <String>[],
        orderedKeys: const <String>['BOOK:11', 'BOOK:10'],
        now: 'now',
      );
      expect(
        shelfItemsAtPath(next, const <String>[]).map((item) => item.bookId),
        <int>[11, 10],
      );
    });

    test('同名文件夹会被拒绝', () {
      final draft = draftOf(<ShelfItem>[
        const ShelfItem.folder(
          id: 'f1',
          index: 0,
          parents: <String>[],
          updatedAt: '',
          title: '重复',
        ),
      ]);
      expect(
        () => createShelfFolder(draft, id: 'f2', title: '重复', now: 'now'),
        throwsArgumentError,
      );
    });
  });

  group('书架条目编解码', () {
    test('兼容大小写字段名与数字类型枚举', () {
      final item = ShelfItem.decode(<String, dynamic>{
        'Id': 12,
        'Index': 3,
        'Parents': <String>['f1'],
        'Type': 0,
        'UpdateAt': '2026-01-01',
      });
      expect(item.isBook, isTrue);
      expect(item.bookId, 12);
      expect(item.parents, <String>['f1']);
      expect(item.encode()['type'], 'BOOK');
    });
  });
}
