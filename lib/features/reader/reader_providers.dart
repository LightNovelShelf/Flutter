import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../data/api/api_client.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/settings/app_settings.dart';

String? readerConvertParam(ConvertType type) =>
    type == ConvertType.none ? null : type.name;

/// 章节目录：阅读器与目录弹层共用一份数据。
final FutureProviderFamily<BookDetail, int> readerBookDetailProvider =
    FutureProvider.family<BookDetail, int>(
      (ref, bookId) => ref.watch(apiClientProvider).getBookInfo(bookId),
      isAutoDispose: true,
    );
