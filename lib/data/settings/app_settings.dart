import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/platform/stores.dart';

const String settingsStorageKey = 'lightnovel.settings.v1';

enum ThemeSetting { system, light, dark }

enum LanguageSetting { system, zhCN, zhTW }

enum HomeRankType { daily, weekly, monthly }

enum SeriesSearchMode { system, original, display }

enum ConvertType { none, t2s, s2t }

enum ReaderViewMode { paged, scroll }

enum ReaderBackgroundMode { auto, paper, custom }

enum ComicPagedDirection { ltr, rtl }

enum CleanChapterTitleScope { continueReading, readerTitle }

T _enumFromName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

const Map<String, LanguageSetting> _languageWire = <String, LanguageSetting>{
  'system': LanguageSetting.system,
  'zh-CN': LanguageSetting.zhCN,
  'zh-TW': LanguageSetting.zhTW,
};

extension LanguageSettingWire on LanguageSetting {
  String get wire => switch (this) {
    LanguageSetting.system => 'system',
    LanguageSetting.zhCN => 'zh-CN',
    LanguageSetting.zhTW => 'zh-TW',
  };
}

double _clampDouble(Object? raw, double min, double max, double fallback) {
  if (raw is! num || !raw.isFinite) return fallback;
  return raw.toDouble().clamp(min, max);
}

int _clampInt(Object? raw, int min, int max, int fallback) {
  if (raw is! num || !raw.isFinite) return fallback;
  return raw.round().clamp(min, max);
}

bool _bool(Object? raw, bool fallback) => raw is bool ? raw : fallback;

/// 持久化的应用设置。
@immutable
class AppSettings {
  const AppSettings({
    this.bookDetailCacheEnabled = true,
    this.cleanChapterTitleScopes = const <CleanChapterTitleScope>{
      CleanChapterTitleScope.continueReading,
      CleanChapterTitleScope.readerTitle,
    },
    this.coverColorExtraction = false,
    this.fontCacheEnabled = true,
    this.fontCacheLimit = 30,
    this.fontSize = 18,
    this.homeRankType = HomeRankType.weekly,
    this.ignoreAI = false,
    this.ignoreJapanese = false,
    this.language = LanguageSetting.system,
    this.oledBlack = false,
    this.readerBackgroundMode = ReaderBackgroundMode.auto,
    this.readerBackgroundColorValue = '#F7F1E3',
    this.readerFirstLineIndent = true,
    this.readerJustify = false,
    this.readerLineHeight = 1.6,
    this.readerParagraphSpacing = 0,
    this.comicPagedDirection = ComicPagedDirection.ltr,
    this.readerPrerenderAdjacent = true,
    this.readerSidePadding = 30,
    this.readerVolumeKeyPagingEnabled = false,
    this.readerViewMode = ReaderViewMode.paged,
    this.seedColorValue = '#B71C1C',
    this.seriesSearchMode = SeriesSearchMode.system,
    this.theme = ThemeSetting.system,
    this.useSystemColor = true,
    this.convertType = ConvertType.none,
    this.autoCheckUpdate = true,
  });

  final bool bookDetailCacheEnabled;
  final Set<CleanChapterTitleScope> cleanChapterTitleScopes;
  final bool coverColorExtraction;
  final bool fontCacheEnabled;
  final int fontCacheLimit;
  final double fontSize;
  final HomeRankType homeRankType;
  final bool ignoreAI;
  final bool ignoreJapanese;
  final LanguageSetting language;
  final bool oledBlack;
  final ReaderBackgroundMode readerBackgroundMode;
  final String readerBackgroundColorValue;
  final bool readerFirstLineIndent;
  final bool readerJustify;
  final double readerLineHeight;
  final double readerParagraphSpacing;
  final ComicPagedDirection comicPagedDirection;
  final bool readerPrerenderAdjacent;
  final double readerSidePadding;
  final bool readerVolumeKeyPagingEnabled;
  final ReaderViewMode readerViewMode;
  final String seedColorValue;
  final SeriesSearchMode seriesSearchMode;
  final ThemeSetting theme;
  final bool useSystemColor;
  final ConvertType convertType;
  final bool autoCheckUpdate;

  AppSettings copyWith({
    bool? bookDetailCacheEnabled,
    Set<CleanChapterTitleScope>? cleanChapterTitleScopes,
    bool? coverColorExtraction,
    bool? fontCacheEnabled,
    int? fontCacheLimit,
    double? fontSize,
    HomeRankType? homeRankType,
    bool? ignoreAI,
    bool? ignoreJapanese,
    LanguageSetting? language,
    bool? oledBlack,
    ReaderBackgroundMode? readerBackgroundMode,
    String? readerBackgroundColorValue,
    bool? readerFirstLineIndent,
    bool? readerJustify,
    double? readerLineHeight,
    double? readerParagraphSpacing,
    ComicPagedDirection? comicPagedDirection,
    bool? readerPrerenderAdjacent,
    double? readerSidePadding,
    bool? readerVolumeKeyPagingEnabled,
    ReaderViewMode? readerViewMode,
    String? seedColorValue,
    SeriesSearchMode? seriesSearchMode,
    ThemeSetting? theme,
    bool? useSystemColor,
    ConvertType? convertType,
    bool? autoCheckUpdate,
  }) => AppSettings(
    bookDetailCacheEnabled:
        bookDetailCacheEnabled ?? this.bookDetailCacheEnabled,
    cleanChapterTitleScopes:
        cleanChapterTitleScopes ?? this.cleanChapterTitleScopes,
    coverColorExtraction: coverColorExtraction ?? this.coverColorExtraction,
    fontCacheEnabled: fontCacheEnabled ?? this.fontCacheEnabled,
    fontCacheLimit: fontCacheLimit ?? this.fontCacheLimit,
    fontSize: fontSize ?? this.fontSize,
    homeRankType: homeRankType ?? this.homeRankType,
    ignoreAI: ignoreAI ?? this.ignoreAI,
    ignoreJapanese: ignoreJapanese ?? this.ignoreJapanese,
    language: language ?? this.language,
    oledBlack: oledBlack ?? this.oledBlack,
    readerBackgroundMode: readerBackgroundMode ?? this.readerBackgroundMode,
    readerBackgroundColorValue:
        readerBackgroundColorValue ?? this.readerBackgroundColorValue,
    readerFirstLineIndent: readerFirstLineIndent ?? this.readerFirstLineIndent,
    readerJustify: readerJustify ?? this.readerJustify,
    readerLineHeight: readerLineHeight ?? this.readerLineHeight,
    readerParagraphSpacing:
        readerParagraphSpacing ?? this.readerParagraphSpacing,
    comicPagedDirection: comicPagedDirection ?? this.comicPagedDirection,
    readerPrerenderAdjacent:
        readerPrerenderAdjacent ?? this.readerPrerenderAdjacent,
    readerSidePadding: readerSidePadding ?? this.readerSidePadding,
    readerVolumeKeyPagingEnabled:
        readerVolumeKeyPagingEnabled ?? this.readerVolumeKeyPagingEnabled,
    readerViewMode: readerViewMode ?? this.readerViewMode,
    seedColorValue: seedColorValue ?? this.seedColorValue,
    seriesSearchMode: seriesSearchMode ?? this.seriesSearchMode,
    theme: theme ?? this.theme,
    useSystemColor: useSystemColor ?? this.useSystemColor,
    convertType: convertType ?? this.convertType,
    autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
  );

  static final RegExp _hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

  static String _hexColor(Object? raw, String fallback) =>
      raw is String && _hexPattern.hasMatch(raw) ? raw.toUpperCase() : fallback;

  /// 解码时同时执行钳制与校验，写入路径也走此方法。
  static AppSettings decode(Map<String, dynamic> raw) {
    final scopes = raw['cleanChapterTitleScopes'];
    return AppSettings(
      bookDetailCacheEnabled: _bool(raw['bookDetailCacheEnabled'], true),
      cleanChapterTitleScopes: scopes is List
          ? <CleanChapterTitleScope>{
              for (final value in scopes)
                if (value == 'continueReading')
                  CleanChapterTitleScope.continueReading
                else if (value == 'readerTitle')
                  CleanChapterTitleScope.readerTitle,
            }
          : const <CleanChapterTitleScope>{
              CleanChapterTitleScope.continueReading,
              CleanChapterTitleScope.readerTitle,
            },
      coverColorExtraction: _bool(raw['coverColorExtraction'], false),
      fontCacheEnabled: _bool(raw['fontCacheEnabled'], true),
      fontCacheLimit: _clampInt(raw['fontCacheLimit'], 10, 60, 30),
      fontSize: _clampDouble(raw['fontSize'], 12, 32, 18),
      homeRankType: _enumFromName(
        HomeRankType.values,
        raw['homeRankType'],
        HomeRankType.weekly,
      ),
      ignoreAI: _bool(raw['ignoreAI'], false),
      ignoreJapanese: _bool(raw['ignoreJapanese'], false),
      language: _languageWire[raw['language']] ?? LanguageSetting.system,
      oledBlack: _bool(raw['oledBlack'], false),
      readerBackgroundMode: _enumFromName(
        ReaderBackgroundMode.values,
        raw['readerBackgroundMode'],
        ReaderBackgroundMode.auto,
      ),
      readerBackgroundColorValue: _hexColor(
        raw['readerBackgroundColorValue'],
        '#F7F1E3',
      ),
      readerFirstLineIndent: _bool(raw['readerFirstLineIndent'], true),
      readerJustify: _bool(raw['readerJustify'], false),
      readerLineHeight: _clampDouble(raw['readerLineHeight'], 1, 2.5, 1.6),
      readerParagraphSpacing: _clampDouble(
        raw['readerParagraphSpacing'],
        0,
        16,
        0,
      ),
      comicPagedDirection: _enumFromName(
        ComicPagedDirection.values,
        raw['comicPagedDirection'],
        ComicPagedDirection.ltr,
      ),
      readerPrerenderAdjacent: _bool(raw['readerPrerenderAdjacent'], true),
      readerSidePadding: _clampDouble(raw['readerSidePadding'], 12, 64, 30),
      readerVolumeKeyPagingEnabled: _bool(
        raw['readerVolumeKeyPagingEnabled'],
        false,
      ),
      readerViewMode: _enumFromName(
        ReaderViewMode.values,
        raw['readerViewMode'],
        ReaderViewMode.paged,
      ),
      seedColorValue: _hexColor(raw['seedColorValue'], '#B71C1C'),
      seriesSearchMode: _enumFromName(
        SeriesSearchMode.values,
        raw['seriesSearchMode'],
        SeriesSearchMode.system,
      ),
      theme: _enumFromName(
        ThemeSetting.values,
        raw['theme'],
        ThemeSetting.system,
      ),
      useSystemColor: _bool(raw['useSystemColor'], true),
      convertType: _enumFromName(
        ConvertType.values,
        raw['convertType'],
        ConvertType.none,
      ),
      autoCheckUpdate: _bool(raw['autoCheckUpdate'], true),
    );
  }

  Map<String, Object?> encode() => <String, Object?>{
    'bookDetailCacheEnabled': bookDetailCacheEnabled,
    'cleanChapterTitleScopes': cleanChapterTitleScopes
        .map((scope) => scope.name)
        .toList(),
    'coverColorExtraction': coverColorExtraction,
    'fontCacheEnabled': fontCacheEnabled,
    'fontCacheLimit': fontCacheLimit,
    'fontSize': fontSize,
    'homeRankType': homeRankType.name,
    'ignoreAI': ignoreAI,
    'ignoreJapanese': ignoreJapanese,
    'language': language.wire,
    'oledBlack': oledBlack,
    'readerBackgroundMode': readerBackgroundMode.name,
    'readerBackgroundColorValue': readerBackgroundColorValue,
    'readerFirstLineIndent': readerFirstLineIndent,
    'readerJustify': readerJustify,
    'readerLineHeight': readerLineHeight,
    'readerParagraphSpacing': readerParagraphSpacing,
    'comicPagedDirection': comicPagedDirection.name,
    'readerPrerenderAdjacent': readerPrerenderAdjacent,
    'readerSidePadding': readerSidePadding,
    'readerVolumeKeyPagingEnabled': readerVolumeKeyPagingEnabled,
    'readerViewMode': readerViewMode.name,
    'seedColorValue': seedColorValue,
    'seriesSearchMode': seriesSearchMode.name,
    'theme': theme.name,
    'useSystemColor': useSystemColor,
    'convertType': convertType.name,
    'autoCheckUpdate': autoCheckUpdate,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.bookDetailCacheEnabled == bookDetailCacheEnabled &&
      setEquals(other.cleanChapterTitleScopes, cleanChapterTitleScopes) &&
      other.coverColorExtraction == coverColorExtraction &&
      other.fontCacheEnabled == fontCacheEnabled &&
      other.fontCacheLimit == fontCacheLimit &&
      other.fontSize == fontSize &&
      other.homeRankType == homeRankType &&
      other.ignoreAI == ignoreAI &&
      other.ignoreJapanese == ignoreJapanese &&
      other.language == language &&
      other.oledBlack == oledBlack &&
      other.readerBackgroundMode == readerBackgroundMode &&
      other.readerBackgroundColorValue == readerBackgroundColorValue &&
      other.readerFirstLineIndent == readerFirstLineIndent &&
      other.readerJustify == readerJustify &&
      other.readerLineHeight == readerLineHeight &&
      other.readerParagraphSpacing == readerParagraphSpacing &&
      other.comicPagedDirection == comicPagedDirection &&
      other.readerPrerenderAdjacent == readerPrerenderAdjacent &&
      other.readerSidePadding == readerSidePadding &&
      other.readerVolumeKeyPagingEnabled == readerVolumeKeyPagingEnabled &&
      other.readerViewMode == readerViewMode &&
      other.seedColorValue == seedColorValue &&
      other.seriesSearchMode == seriesSearchMode &&
      other.theme == theme &&
      other.useSystemColor == useSystemColor &&
      other.convertType == convertType &&
      other.autoCheckUpdate == autoCheckUpdate;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    bookDetailCacheEnabled,
    Object.hashAllUnordered(cleanChapterTitleScopes),
    coverColorExtraction,
    fontCacheEnabled,
    fontCacheLimit,
    fontSize,
    homeRankType,
    ignoreAI,
    ignoreJapanese,
    language,
    oledBlack,
    readerBackgroundMode,
    readerBackgroundColorValue,
    readerFirstLineIndent,
    readerJustify,
    readerLineHeight,
    readerParagraphSpacing,
    comicPagedDirection,
    readerPrerenderAdjacent,
    readerSidePadding,
    readerVolumeKeyPagingEnabled,
    readerViewMode,
    seedColorValue,
    seriesSearchMode,
    theme,
    useSystemColor,
    convertType,
    autoCheckUpdate,
  ]);
}

/// 设置存取：整体以一个 JSON blob 持久化，写入串行化。
class SettingsController extends ChangeNotifier {
  SettingsController(this._store, this._settings);

  final KeyValueStore _store;
  AppSettings _settings;
  Future<void> _write = Future<void>.value();

  AppSettings get settings => _settings;

  static Future<SettingsController> load(KeyValueStore store) async {
    final raw = await store.read(settingsStorageKey);
    if (raw == null || raw.isEmpty) {
      return SettingsController(store, const AppSettings());
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SettingsController(store, AppSettings.decode(decoded));
      }
    } catch (_) {
      // 损坏的配置直接忽略，保留默认值。
    }
    return SettingsController(store, const AppSettings());
  }

  void update(AppSettings Function(AppSettings settings) mutate) {
    final next = AppSettings.decode(
      mutate(_settings).encode().cast<String, dynamic>(),
    );
    // 滑块之类会反复写同一个值，相等就别惊动 MaterialApp 与所有设置订阅者。
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    _write = _write.then(
      (_) => _store.write(settingsStorageKey, jsonEncode(next.encode())),
      onError: (_) =>
          _store.write(settingsStorageKey, jsonEncode(next.encode())),
    );
  }

  void toggleCleanChapterTitleScope(CleanChapterTitleScope scope) {
    update((settings) {
      final scopes = Set<CleanChapterTitleScope>.of(
        settings.cleanChapterTitleScopes,
      );
      if (!scopes.remove(scope)) scopes.add(scope);
      return settings.copyWith(cleanChapterTitleScopes: scopes);
    });
  }
}
