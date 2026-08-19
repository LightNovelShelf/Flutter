import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../features/book/book_comments_screen.dart';
import '../features/book/book_detail_screen.dart';
import '../features/book/book_versions_screen.dart';
import '../features/community/community_compose_screen.dart';
import '../features/community/community_home_screen.dart';
import '../features/community/community_mine_screen.dart';
import '../features/community/community_notifications_screen.dart';
import '../features/community/community_rankings_screen.dart';
import '../features/community/community_thread_screen.dart';
import '../features/discover/announcement_center_screen.dart';
import '../features/discover/announcement_detail_screen.dart';
import '../features/discover/book_list_screen.dart';
import '../features/discover/comic_list_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/discover/ranking_screen.dart';
import '../features/history/history_screen.dart';
import '../features/reader/comic_reader_screen.dart';
import '../features/reader/novel_reader_screen.dart';
import '../features/reader/reader_open_position.dart';
import '../features/search/search_screen.dart';
import '../features/settings/about_settings_screen.dart';
import '../features/settings/appearance_settings_screen.dart';
import '../features/settings/avatar_settings_screen.dart';
import '../features/settings/cache_settings_screen.dart';
import '../features/settings/content_settings_screen.dart';
import '../features/settings/profile_screen.dart';
import '../features/settings/reader_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shelf/shelf_screen.dart';
import 'home_shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 让 go_router 跟随认证状态刷新。
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this._ref) {
    _ref.listen<AuthenticationSnapshot>(
      authSnapshotProvider,
      (_, _) => notifyListeners(),
    );
  }

  final Ref _ref;
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

final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final runtime = ref.watch(appRuntimeProvider);
  final refresh = _AuthRefreshListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: runtime.hasStoredSession ? '/discover' : '/sign-in',
    refreshListenable: refresh,
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
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/discover', builder: (_, _) => const DiscoverScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/shelf', builder: (_, _) => const ShelfScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/community',
                builder: (_, _) => const CommunityHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/shelf/folder',
        builder: (_, state) => ShelfScreen(
          parents: state.uri.queryParametersAll['parent'] ?? const <String>[],
        ),
      ),
      GoRoute(path: '/books', builder: (_, _) => const BookListScreen()),
      GoRoute(path: '/comics', builder: (_, _) => const ComicListScreen()),
      GoRoute(path: '/ranking', builder: (_, _) => const RankingScreen()),
      GoRoute(
        path: '/announcements',
        builder: (_, _) => const AnnouncementCenterScreen(),
      ),
      GoRoute(
        path: '/announcement/:id',
        builder: (_, state) => AnnouncementDetailScreen(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/book/:id',
        builder: (_, state) => BookDetailScreen(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          type: state.uri.queryParameters['type'] == 'Comic'
              ? BookType.comic
              : state.uri.queryParameters['type'] == 'Novel'
                  ? BookType.novel
                  : null,
          seriesTitle: state.uri.queryParameters['seriesTitle'],
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'comments',
            builder: (_, state) => BookCommentsScreen(
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
              title: state.uri.queryParameters['title'] ?? '评论',
              targetType: state.uri.queryParameters['target'] == 'Series'
                  ? CommentTargetType.series
                  : CommentTargetType.book,
              seriesTitle: state.uri.queryParameters['seriesTitle'],
            ),
          ),
          GoRoute(
            path: 'versions',
            builder: (_, state) => BookVersionsScreen(
              seriesTitle: state.uri.queryParameters['seriesTitle'] ?? '',
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/reader/:bookId/:sortNum',
        builder: (_, state) {
          final bookId = int.tryParse(state.pathParameters['bookId'] ?? '') ?? 0;
          final sortNum = int.tryParse(state.pathParameters['sortNum'] ?? '') ?? 1;
          final position = switch (state.uri.queryParameters['position']) {
            'start' => ReaderOpenPosition.start,
            'end' => ReaderOpenPosition.end,
            _ => ReaderOpenPosition.saved,
          };
          if (state.uri.queryParameters['type'] == 'Comic') {
            return ComicReaderScreen(bookId: bookId, sortNum: sortNum);
          }
          return NovelReaderScreen(
            bookId: bookId,
            sortNum: sortNum,
            openPosition: position,
          );
        },
      ),
      GoRoute(
        path: '/community/thread/:id',
        builder: (_, state) => CommunityThreadScreen(
          threadId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          parentReplyId:
              int.tryParse(state.uri.queryParameters['parentReplyId'] ?? ''),
          replyId: int.tryParse(state.uri.queryParameters['replyId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/community/compose',
        builder: (_, state) => CommunityComposeScreen(
          boardKey: state.uri.queryParameters['boardKey'],
          subCategoryKey: state.uri.queryParameters['subCategoryKey'],
        ),
      ),
      GoRoute(
        path: '/community/mine',
        builder: (_, _) => const MyCommunityScreen(),
      ),
      GoRoute(
        path: '/community/notifications',
        builder: (_, _) => const CommunityNotificationsScreen(),
      ),
      GoRoute(
        path: '/community/rankings',
        builder: (_, _) => const CommunityRankingsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(path: 'profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(path: 'avatar', builder: (_, _) => const AvatarSettingsScreen()),
          GoRoute(
            path: 'appearance',
            builder: (_, _) => const AppearanceSettingsScreen(),
          ),
          GoRoute(
            path: 'content',
            builder: (_, _) => const ContentSettingsScreen(),
          ),
          GoRoute(path: 'reader', builder: (_, _) => const ReaderSettingsScreen()),
          GoRoute(path: 'cache', builder: (_, _) => const CacheSettingsScreen()),
          GoRoute(path: 'about', builder: (_, _) => const AboutSettingsScreen()),
        ],
      ),
    ],
  );
});
