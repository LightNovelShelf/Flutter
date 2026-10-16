import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/platform/reader_volume_keys.dart';
import '../data/api/api_client.dart';
import '../data/api/models.dart';
import '../data/providers.dart';
import '../data/session/auth_controller.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/register_verify_screen.dart';
import '../features/auth/reset_password_new_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/reset_password_verify_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/community/community_compose_screen.dart';
import '../features/community/community_home_screen.dart';
import '../features/discover/announcement_center_screen.dart';
import '../features/discover/book_list_screen.dart';
import '../features/discover/comic_list_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/discover/novel_series_books_screen.dart';
import '../features/discover/ranking_screen.dart';
import '../features/history/history_screen.dart';
import '../features/reader/comic_reader_screen.dart';
import '../features/reader/novel_reader_screen.dart';
import '../features/reader/reader_open_position.dart';
import '../features/reader/widgets/reader_theme.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shelf/shelf_screen.dart';
import 'home_shell.dart';
import 'list_detail.dart';
import 'pane_routes.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 让 go_router 跟随认证状态刷新。只有 redirect 真正判断的两个状态位翻转才通知，
/// 否则 refreshing/signingIn 这类中间态会让 go_router 重解析路由、重跑栈上所有 builder。
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen<(bool, bool)>(
      authSnapshotProvider.select(
        (snapshot) => (
          snapshot.status == AuthenticationStatus.authenticated,
          snapshot.status == AuthenticationStatus.signedOut,
        ),
      ),
      (_, _) => notifyListeners(),
    );
  }
}

const Set<String> _authRoutes = <String>{
  '/sign-in',
  '/sign-in/credentials',
  '/register',
  '/register/verify',
  '/reset-password',
  '/reset-password/verify',
  '/reset-password/new-password',
};

/// 能放进右栏的页面整页打开时也用 [buildPanePage] 构建。嵌套路由的父页按自己那一段地址解析。
Widget _panePage(BuildContext _, GoRouterState state) =>
    buildPanePage(state.uri.replace(path: state.matchedLocation))!;

final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final runtime = ref.watch(appRuntimeProvider);
  final refresh = _AuthRefreshListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: runtime.hasStoredSession ? '/discover' : '/sign-in',
    refreshListenable: refresh,
    observers: <NavigatorObserver>[readerVolumeKeyRouteObserver],
    redirect: (context, state) {
      final status = ref.read(authSnapshotProvider).status;
      final location = state.matchedLocation;
      final isAuthRoute = _authRoutes.contains(location);
      if (status == AuthenticationStatus.signedOut && !isAuthRoute) {
        return '/sign-in';
      }
      if (status == AuthenticationStatus.authenticated && isAuthRoute) {
        return '/discover';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(path: '/', redirect: (_, _) => '/discover'),
      GoRoute(path: '/sign-in', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: '/sign-in/credentials',
        builder: (_, state) =>
            SignInScreen(initialEmail: state.uri.queryParameters['email']),
      ),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/register/verify',
        builder: (_, _) => const RegisterVerifyScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password/verify',
        builder: (_, _) => const ResetPasswordVerifyScreen(),
      ),
      GoRoute(
        path: '/reset-password/new-password',
        builder: (_, _) => const ResetPasswordNewScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        // 每个 branch 独立成层，切 tab 时 NavigationBar 指示器动画与刚露出的页面互不牵连。
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/discover',
                builder: (_, _) => const RepaintBoundary(
                  child: ListDetailHost(child: DiscoverScreen()),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/shelf',
                builder: (_, _) => const RepaintBoundary(
                  child: ListDetailHost(child: ShelfScreen()),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/history',
                builder: (_, _) => const RepaintBoundary(
                  child: ListDetailHost(child: HistoryScreen()),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/community',
                builder: (_, _) => const RepaintBoundary(
                  child: ListDetailHost(
                    initialLocation: '/community/rankings',
                    child: CommunityHomeScreen(),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/search',
                builder: (_, _) => const RepaintBoundary(
                  child: ListDetailHost(child: SearchScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/shelf/folder',
        builder: (_, state) => ListDetailHost(
          child: ShelfScreen(
            parents: state.uri.queryParametersAll['parent'] ?? const <String>[],
          ),
        ),
      ),
      GoRoute(
        path: '/books',
        builder: (_, _) => const ListDetailHost(child: BookListScreen()),
      ),
      GoRoute(
        path: '/books/series',
        builder: (_, state) => ListDetailHost(
          child: NovelSeriesBooksScreen(
            seriesName: state.uri.queryParameters['name'] ?? '',
            initialOrder:
                bookListOrderFromWire(state.uri.queryParameters['order']) ??
                BookListOrder.latest,
          ),
        ),
      ),
      GoRoute(
        path: '/comics',
        builder: (_, _) => const ListDetailHost(child: ComicListScreen()),
      ),
      GoRoute(
        path: '/ranking',
        builder: (_, _) => const ListDetailHost(child: RankingScreen()),
      ),
      GoRoute(
        path: '/announcements',
        builder: (_, _) => const ListDetailHost(
          placeholder: PanePlaceholder.announcement,
          primaryFraction: 0.4,
          child: AnnouncementCenterScreen(),
        ),
      ),
      GoRoute(path: '/announcement/:id', builder: _panePage),
      GoRoute(
        path: '/book/:id',
        builder: _panePage,
        routes: <RouteBase>[GoRoute(path: 'comments', builder: _panePage)],
      ),
      GoRoute(
        path: '/reader/:bookId/:sortNum',
        builder: (_, state) {
          final bookId =
              int.tryParse(state.pathParameters['bookId'] ?? '') ?? 0;
          final sortNum =
              int.tryParse(state.pathParameters['sortNum'] ?? '') ?? 1;
          final position = switch (state.uri.queryParameters['position']) {
            'start' => ReaderOpenPosition.start,
            'end' => ReaderOpenPosition.end,
            _ => ReaderOpenPosition.saved,
          };
          final type = state.uri.queryParameters['type'] == 'Comic'
              ? BookType.comic
              : BookType.novel;
          final Widget screen = type == BookType.comic
              ? ComicReaderScreen(bookId: bookId, sortNum: sortNum)
              : NovelReaderScreen(
                  bookId: bookId,
                  sortNum: sortNum,
                  openPosition: position,
                );
          return ReaderThemeScope(type: type, child: screen);
        },
      ),
      GoRoute(path: '/community/thread/:id', builder: _panePage),
      GoRoute(
        path: '/community/compose',
        // 带 threadId 即编辑已有帖子
        builder: (_, state) => CommunityComposeScreen(
          threadId: int.tryParse(state.uri.queryParameters['threadId'] ?? ''),
          boardKey: state.uri.queryParameters['boardKey'],
          subCategoryKey: state.uri.queryParameters['subCategoryKey'],
        ),
      ),
      GoRoute(path: '/community/mine', builder: _panePage),
      GoRoute(path: '/community/notifications', builder: _panePage),
      GoRoute(path: '/community/rankings', builder: _panePage),
      GoRoute(path: '/messages', builder: _panePage),
      GoRoute(path: '/messages/:peerId', builder: _panePage),
      GoRoute(path: '/shop', builder: _panePage),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const ListDetailHost(
          placeholder: PanePlaceholder.settings,
          primaryFraction: 0.4,
          child: SettingsScreen(),
        ),
        routes: <RouteBase>[
          for (final path in const <String>[
            'profile',
            'avatar',
            'appearance',
            'content',
            'reader/novel',
            'reader/comic',
            'cache',
            'about',
          ])
            GoRoute(path: path, builder: _panePage),
        ],
      ),
    ],
  );
});
