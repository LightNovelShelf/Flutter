import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/api_error.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/data/repositories/profile_repository.dart';
import 'package:lightnovel/data/repositories/user_summary.dart';
import 'package:lightnovel/shared/widgets/user_card_sheet.dart';

const int _userId = 66660;

class _AnonymousProfile extends ProfileController {
  @override
  Future<UserProfile?> build() async => null;
}

void main() {
  testWidgets('用户资料加载失败时不显示私信按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(_AnonymousProfile.new),
          userSummaryProvider(_userId).overrideWith(
            (ref) => Future<PublicUserSummary>.error(
              const ApiError('用户不存在', ApiErrorCategory.server),
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showUserCardSheet(
                  context,
                  userId: _userId,
                  userName: '测试用户',
                ),
                child: const Text('打开名片'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开名片'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '私信'), findsNothing);
  });
}
