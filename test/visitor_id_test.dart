import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/core/platform/stores.dart';
import 'package:lightnovel/data/session/auth_controller.dart';
import 'package:lightnovel/data/session/visitor_id.dart';

class _FakeCredentialStore implements CredentialStore {
  _FakeCredentialStore([Map<String, String>? initial])
    : values = <String, String>{...?initial};

  final Map<String, String> values;
  bool failReads = false;
  int reads = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    await Future<void>.delayed(Duration.zero);
    if (failReads) throw StateError('钥匙串不可用');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('首次生成后写入存储，重建实例仍读回同一个值', () async {
    final store = _FakeCredentialStore();

    final first = await VisitorId(credentials: store).value();
    expect(
      first,
      matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')),
    );
    expect(store.values[AuthCredentialKeys.visitorId], first);

    final second = await VisitorId(credentials: store).value();
    expect(second, first);
  });

  test('并发取值只生成一个标识', () async {
    final store = _FakeCredentialStore();
    final visitor = VisitorId(credentials: store);

    final results = await Future.wait(<Future<String>>[
      visitor.value(),
      visitor.value(),
      visitor.value(),
    ]);

    expect(results.toSet(), hasLength(1));
    expect(store.reads, 1);
  });

  test('读失败时不覆盖已有标识', () async {
    final store = _FakeCredentialStore(<String, String>{
      AuthCredentialKeys.visitorId: 'kept-id',
    })..failReads = true;

    final fallback = await VisitorId(credentials: store).value();
    expect(fallback, isNot('kept-id'));
    expect(store.values[AuthCredentialKeys.visitorId], 'kept-id');
  });
}
