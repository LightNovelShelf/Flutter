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

enum ReaderPageTurnAnimation { none, slide }

enum ReaderBackgroundMode { auto, paper, custom }

/// 阅读页单独的亮暗，默认跟随全局主题。
enum ReaderThemeSetting { followApp, light, dark }

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

/// 小说与漫画各自保存一份通用阅读器设置。
@immutable
class ReaderPreferences {
  const ReaderPreferences({
    this.backgroundMode = ReaderBackgroundMode.auto,
    this.backgroundColorValue = '#F7F1E3',
    this.dualPageEnabled = false,
    this.dualPageOffsetEnabled = false,
    this.immersiveEnabled = false,
    this.pageTurnAnimation = ReaderPageTurnAnimation.none,
    this.statusPillsEnabled = true,
    this.theme = ReaderThemeSetting.followApp,
    this.volumeKeyPagingEnabled = false,
    this.viewMode = ReaderViewMode.paged,
  });

  final ReaderBackgroundMode backgroundMode;
  final String backgroundColorValue;
  final bool dualPageEnabled;
  final bool dualPageOffsetEnabled;
  final bool immersiveEnabled;
  final ReaderPageTurnAnimation pageTurnAnimation;
  final bool statusPillsEnabled;
  final ReaderThemeSetting theme;
  final bool volumeKeyPagingEnabled;
  final ReaderViewMode viewMode;

  ReaderPreferences copyWith({
    ReaderBackgroundMode? backgroundMode,
    String? backgroundColorValue,
    bool? dualPageEnabled,
    bool? dualPageOffsetEnabled,
    bool? immersiveEnabled,
    ReaderPageTurnAnimation? pageTurnAnimation,
    bool? statusPillsEnabled,
    ReaderThemeSetting? theme,
    bool? volumeKeyPagingEnabled,
    ReaderViewMode? viewMode,
  }) => ReaderPreferences(
    backgroundMode: backgroundMode ?? this.backgroundMode,
    backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
    dualPageEnabled: dualPageEnabled ?? this.dualPageEnabled,
    dualPageOffsetEnabled: dualPageOffsetEnabled ?? this.dualPageOffsetEnabled,
    immersiveEnabled: immersiveEnabled ?? this.immersiveEnabled,
    pageTurnAnimation: pageTurnAnimation ?? this.pageTurnAnimation,
    statusPillsEnabled: statusPillsEnabled ?? this.statusPillsEnabled,
    theme: theme ?? this.theme,
    volumeKeyPagingEnabled:
        volumeKeyPagingEnabled ?? this.volumeKeyPagingEnabled,
    viewMode: viewMode ?? this.viewMode,
  );

  static final RegExp _hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

  static ReaderPreferences decode(Object? raw) {
    final values = raw is Map<String, dynamic>
        ? raw
        : const <String, dynamic>{};
    final color = values['backgroundColorValue'];
    return ReaderPreferences(
      backgroundMode: _enumFromName(
        ReaderBackgroundMode.values,
        values['backgroundMode'],
        ReaderBackgroundMode.auto,
      ),
      backgroundColorValue: color is String && _hexPattern.hasMatch(color)
          ? color.toUpperCase()
          : '#F7F1E3',
      dualPageEnabled: _bool(values['dualPageEnabled'], false),
      dualPageOffsetEnabled: _bool(values['dualPageOffsetEnabled'], false),
      immersiveEnabled: _bool(values['immersiveEnabled'], false),
      pageTurnAnimation: _enumFromName(
        ReaderPageTurnAnimation.values,
        values['pageTurnAnimation'],
        ReaderPageTurnAnimation.none,
      ),
      statusPillsEnabled: _bool(values['statusPillsEnabled'], true),
      theme: _enumFromName(
        ReaderThemeSetting.values,
        values['theme'],
        ReaderThemeSetting.followApp,
      ),
      volumeKeyPagingEnabled: _bool(values['volumeKeyPagingEnabled'], false),
      viewMode: _enumFromName(
        ReaderViewMode.values,
        values['viewMode'],
        ReaderViewMode.paged,
      ),
    );
  }

  Map<String, Object?> encode() => <String, Object?>{
    'backgroundMode': backgroundMode.name,
    'backgroundColorValue': backgroundColorValue,
    'dualPageEnabled': dualPageEnabled,
    'dualPageOffsetEnabled': dualPageOffsetEnabled,
    'immersiveEnabled': immersiveEnabled,
    'pageTurnAnimation': pageTurnAnimation.name,
    'statusPillsEnabled': statusPillsEnabled,
    'theme': theme.name,
    'volumeKeyPagingEnabled': volumeKeyPagingEnabled,
    'viewMode': viewMode.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ReaderPreferences &&
      other.backgroundMode == backgroundMode &&
      other.backgroundColorValue == backgroundColorValue &&
      other.dualPageEnabled == dualPageEnabled &&
      other.dualPageOffsetEnabled == dualPageOffsetEnabled &&
      other.immersiveEnabled == immersiveEnabled &&
      other.pageTurnAnimation == pageTurnAnimation &&
      other.statusPillsEnabled == statusPillsEnabled &&
      other.theme == theme &&
      other.volumeKeyPagingEnabled == volumeKeyPagingEnabled &&
      other.viewMode == viewMode;

  @override
  int get hashCode => Object.hash(
    backgroundMode,
    backgroundColorValue,
    dualPageEnabled,
    dualPageOffsetEnabled,
    immersiveEnabled,
    pageTurnAnimation,
    statusPillsEnabled,
    theme,
    volumeKeyPagingEnabled,
    viewMode,
  );
}

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
    this.imageSaveToOwnFolder = false,
    this.language = LanguageSetting.system,
    this.oledBlack = false,
    this.novelReader = const ReaderPreferences(),
    this.comicReader = const ReaderPreferences(),
    this.readerFirstLineIndent = true,

    this.readerJustify = false,
    this.readerLineHeight = 1.5,
    this.readerLineSpace = 4,
    this.comicPagedDirection = ComicPagedDirection.ltr,
    this.readerPrerenderAdjacent = true,
    this.readerSidePadding = 30,

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
  final bool imageSaveToOwnFolder;
  final LanguageSetting language;
  final bool oledBlack;
  final ReaderPreferences novelReader;
  final ReaderPreferences comicReader;
  final bool readerFirstLineIndent;

  final bool readerJustify;
  final double readerLineHeight;
  final double readerLineSpace;
  final ComicPagedDirection comicPagedDirection;
  final bool readerPrerenderAdjacent;
  final double readerSidePadding;

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
    bool? imageSaveToOwnFolder,
    LanguageSetting? language,
    bool? oledBlack,
    ReaderPreferences? novelReader,
    ReaderPreferences? comicReader,
    bool? readerFirstLineIndent,

    bool? readerJustify,
    double? readerLineHeight,
    double? readerLineSpace,
    ComicPagedDirection? comicPagedDirection,
    bool? readerPrerenderAdjacent,
    double? readerSidePadding,

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
    imageSaveToOwnFolder: imageSaveToOwnFolder ?? this.imageSaveToOwnFolder,
    language: language ?? this.language,
    oledBlack: oledBlack ?? this.oledBlack,
    novelReader: novelReader ?? this.novelReader,
    comicReader: comicReader ?? this.comicReader,
    readerFirstLineIndent: readerFirstLineIndent ?? this.readerFirstLineIndent,

    readerJustify: readerJustify ?? this.readerJustify,
    readerLineHeight: readerLineHeight ?? this.readerLineHeight,
    readerLineSpace: readerLineSpace ?? this.readerLineSpace,
    comicPagedDirection: comicPagedDirection ?? this.comicPagedDirection,
    readerPrerenderAdjacent:
        readerPrerenderAdjacent ?? this.readerPrerenderAdjacent,
    readerSidePadding: readerSidePadding ?? this.readerSidePadding,

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
      imageSaveToOwnFolder: _bool(raw['imageSaveToOwnFolder'], false),
      language: _languageWire[raw['language']] ?? LanguageSetting.system,
      oledBlack: _bool(raw['oledBlack'], false),
      novelReader: ReaderPreferences.decode(raw['novelReader']),
      comicReader: ReaderPreferences.decode(raw['comicReader']),
      readerFirstLineIndent: _bool(raw['readerFirstLineIndent'], true),

      readerJustify: _bool(raw['readerJustify'], false),
      readerLineHeight: _clampDouble(raw['readerLineHeight'], 1, 2.5, 1.5),
      readerLineSpace: _clampDouble(raw['readerLineSpace'], 0, 16, 4),
      comicPagedDirection: _enumFromName(
        ComicPagedDirection.values,
        raw['comicPagedDirection'],
        ComicPagedDirection.ltr,
      ),
      readerPrerenderAdjacent: _bool(raw['readerPrerenderAdjacent'], true),
      readerSidePadding: _clampDouble(raw['readerSidePadding'], 12, 64, 30),

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
    'imageSaveToOwnFolder': imageSaveToOwnFolder,
    'language': language.wire,
    'oledBlack': oledBlack,
    'novelReader': novelReader.encode(),
    'comicReader': comicReader.encode(),
    'readerFirstLineIndent': readerFirstLineIndent,

    'readerJustify': readerJustify,
    'readerLineHeight': readerLineHeight,
    'readerLineSpace': readerLineSpace,
    'comicPagedDirection': comicPagedDirection.name,
    'readerPrerenderAdjacent': readerPrerenderAdjacent,
    'readerSidePadding': readerSidePadding,

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
      other.imageSaveToOwnFolder == imageSaveToOwnFolder &&
      other.language == language &&
      other.oledBlack == oledBlack &&
      other.novelReader == novelReader &&
      other.comicReader == comicReader &&
      other.readerFirstLineIndent == readerFirstLineIndent &&
      other.readerJustify == readerJustify &&
      other.readerLineHeight == readerLineHeight &&
      other.readerLineSpace == readerLineSpace &&
      other.comicPagedDirection == comicPagedDirection &&
      other.readerPrerenderAdjacent == readerPrerenderAdjacent &&
      other.readerSidePadding == readerSidePadding &&
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
    imageSaveToOwnFolder,
    language,
    oledBlack,
    novelReader,
    comicReader,
    readerFirstLineIndent,

    readerJustify,
    readerLineHeight,
    readerLineSpace,
    comicPagedDirection,
    readerPrerenderAdjacent,
    readerSidePadding,

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
