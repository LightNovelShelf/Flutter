import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../providers.dart';

/// QQ / QQ 群 / 自定义网址三种头像来源。
enum AvatarSource { url, qq, qqGroup }

class AvatarSourceValue {
  const AvatarSourceValue(this.source, this.value);

  final AvatarSource source;
  final String value;
}

const String _qqAvatarUrl = 'https://q.qlogo.cn/headimg_dl?spec=100&dst_uin=';
final RegExp _qqGroupAvatarPattern =
    RegExp(r'^https://p\.qlogo\.cn/gh/([0-9]+)/\1/100$');
final RegExp _qqNumberPattern = RegExp(r'^[1-9]\d{4,}$');
final RegExp _httpsImageUrlPattern = RegExp(
  r'^https:\/\/[\w-]+(?:\.[\w-]+)+(?:[\w\-.,@?^=%&:/~+#]*[\w\-@?^=%&/~+#])?$',
  caseSensitive: false,
);

AvatarSourceValue parseAvatarSource(String url) {
  if (url.startsWith(_qqAvatarUrl)) {
    return AvatarSourceValue(AvatarSource.qq, url.substring(_qqAvatarUrl.length));
  }
  final groupMatch = _qqGroupAvatarPattern.firstMatch(url);
  if (groupMatch != null) {
    return AvatarSourceValue(AvatarSource.qqGroup, groupMatch.group(1)!);
  }
  return AvatarSourceValue(AvatarSource.url, url);
}

String resolveAvatarUrl(AvatarSource source, String value) {
  final trimmed = value.trim();
  switch (source) {
    case AvatarSource.qq:
      if (!_qqNumberPattern.hasMatch(trimmed)) {
        throw ArgumentError('请输入有效的 QQ 号码。');
      }
      return '$_qqAvatarUrl$trimmed';
    case AvatarSource.qqGroup:
      if (!_qqNumberPattern.hasMatch(trimmed)) {
        throw ArgumentError('请输入有效的 QQ 群号码。');
      }
      return 'https://p.qlogo.cn/gh/$trimmed/$trimmed/100';
    case AvatarSource.url:
      if (!_httpsImageUrlPattern.hasMatch(trimmed)) {
        throw ArgumentError('图片网址必须使用 HTTPS。');
      }
      return trimmed;
  }
}

/// 当前账号资料；未登录时保持 `null`。
class ProfileController extends AsyncNotifier<UserProfile?> {
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  Future<UserProfile?> build() async {
    final snapshot = ref.watch(authSnapshotProvider);
    if (!snapshot.isAuthenticated) return null;
    return _api.getMyProfile();
  }

  Future<void> reload() async {
    state = const AsyncValue<UserProfile?>.loading();
    state = await AsyncValue.guard(() async {
      if (!ref.read(authControllerProvider).snapshot.isAuthenticated) return null;
      return _api.getMyProfile();
    });
  }

  Future<DailyCheckInResult> checkIn() async {
    final result = await _api.checkIn();
    await reload();
    return result;
  }

  Future<void> setAvatar(String url) async {
    await _api.setAvatar(url);
    await reload();
  }
}

final AsyncNotifierProvider<ProfileController, UserProfile?> profileProvider =
    AsyncNotifierProvider<ProfileController, UserProfile?>(ProfileController.new);
