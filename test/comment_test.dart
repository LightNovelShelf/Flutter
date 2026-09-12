import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/network/api_error.dart';
import 'package:lightnovel/data/api/models.dart';

Map<String, Object?> _commentPage() => <String, Object?>{
  'Page': 1,
  'TotalPages': 1,
  'Users': <String, Object?>{
    for (final id in [1, 2, 3])
      '$id': <String, Object?>{'Id': id, 'UserName': 'user$id', 'Avatar': ''},
  },
  'Commentaries': <String, Object?>{
    '100': <String, Object?>{
      'UserId': 1,
      'Content': 'root comment',
      'CreatedAt': '2026-09-12T08:00:00Z',
      'CanEdit': false,
    },
    '101': <String, Object?>{
      'UserId': 2,
      'Content': 'first reply',
      'CreatedAt': '2026-09-12T08:01:00Z',
      'CanEdit': false,
      'ReplyId': null,
    },
    '102': <String, Object?>{
      'UserId': 3,
      'Content': 'remaining reply',
      'CreatedAt': '2026-09-12T08:02:00Z',
      'CanEdit': true,
      'ReplyId': 101,
    },
  },
  'Data': <Object?>[
    <String, Object?>{
      'Id': 100,
      'Reply': <int>[101, 102],
    },
  ],
};

void main() {
  test('deleted reply target preserves the root and remaining reply', () {
    final response = _commentPage();
    (response['Commentaries']! as Map<String, Object?>).remove('101');
    final root = (response['Data']! as List<Object?>).single!;
    (root as Map<String, Object?>)['Reply'] = <int>[102];

    final page = CommentPage.decode(response);

    expect(page.items.single.id, 100);
    expect(page.items.single.content, 'root comment');
    final reply = page.items.single.replies.single;
    expect(reply.id, 102);
    expect(reply.user.id, 3);
    expect(reply.content, 'remaining reply');
    expect(reply.canEdit, isTrue);
    expect(reply.replyToUser, isNull);
  });

  test('intact reply target resolves its author', () {
    final page = CommentPage.decode(_commentPage());

    expect(page.items.single.replies.map((reply) => reply.id), [101, 102]);
    final reply = page.items.single.replies.last;
    expect(reply.content, 'remaining reply');
    expect(reply.replyToUser?.id, 2);
    expect(reply.replyToUser?.userName, 'user2');
  });

  for (final replyToId in <int?>[null, 0]) {
    test('ReplyId $replyToId means no reply target', () {
      final response = _commentPage();
      final commentaries = response['Commentaries']! as Map<String, Object?>;
      (commentaries['102']! as Map<String, Object?>)['ReplyId'] = replyToId;
      commentaries['0'] = commentaries['101'];

      final page = CommentPage.decode(response);

      expect(page.items.single.replies.last.replyToUser, isNull);
    });
  }

  for (final commentId in ['100', '101']) {
    test('missing actual comment $commentId still fails decoding', () {
      final response = _commentPage();
      (response['Commentaries']! as Map<String, Object?>).remove(commentId);

      expect(() => CommentPage.decode(response), throwsA(isA<ApiError>()));
    });

    test('malformed actual comment $commentId still fails decoding', () {
      final response = _commentPage();
      (response['Commentaries']! as Map<String, Object?>)[commentId] =
          'invalid';

      expect(() => CommentPage.decode(response), throwsA(isA<ApiError>()));
    });
  }
}
