import '../../core/network/api_error.dart';
import '../../core/network/request_scheduler.dart';
import 'api_client.dart';
import 'decode.dart';
import 'endpoints.dart';
import 'models.dart';

/// 账号与个人数据：公告、历史、书架、资料，以及五个走裸 HTTP 的鉴权端点
/// （SignalR 建连本身要带令牌，登录/刷新只能走 HTTP）。
extension ApiClientAccount on ApiClient {
  Future<OnlineInfo> getOnlineInfo() =>
      invoke('GetOnlineInfo', null, OnlineInfo.decode);

  Future<AnnouncementPage> getAnnouncementList({
    int page = 1,
    int size = 5,
    CancelToken? cancelToken,
  }) => invoke(
    'GetAnnouncementList',
    <String, Object?>{'Page': page, 'Size': size},
    AnnouncementPage.decode,
    cancelToken: cancelToken,
  );

  Future<AnnouncementItem> getAnnouncementDetail(int id) => invoke(
    'GetAnnouncementDetail',
    <String, Object?>{'Id': id},
    AnnouncementItem.decode,
  );

  Future<ReadHistory> getReadHistory() =>
      invoke('GetReadHistory', null, ReadHistory.decode);

  Future<void> clearReadHistory() => invoke('ClearReadHistory', null, (_) {});

  Future<UserShelf> getBookShelf() =>
      invoke('GetBookShelf', null, UserShelf.decode);

  Future<void> saveBookShelf(UserShelf shelf) =>
      invoke('SaveBookShelf', <String, Object?>{
        'data': shelf.items.map((item) => item.encode()).toList(),
        'ver': shelf.version ?? shelfStructVersion,
      }, (_) {});

  Future<UserProfile> getMyProfile() =>
      invoke('GetMyInfo', <String, Object?>{}, UserProfile.decode);

  Future<void> setAvatar(String url) =>
      invoke('SetAvatar', <String, Object?>{'Url': url}, (_) {});

  Future<DailyCheckInResult> checkIn() =>
      invoke('SignIn', <String, Object?>{}, DailyCheckInResult.decode);

  Future<SessionTokens> login({
    required String email,
    required String passwordHash,
  }) async {
    final response = await request(
      'POST',
      ServiceEndpoints.loginPath,
      body: <String, Object?>{'email': email, 'password': passwordHash},
    );
    ensureOk(response, '无法登录。');
    // 不走 envelopeOf：SessionTokens.decode 自己会查信封失败位。
    return SessionTokens.decode(decodeHttpBody(response));
  }

  Future<SessionTokens> register({
    required String userName,
    required String email,
    required String passwordHash,
    required String code,
    required String inviteCode,
  }) async {
    final response = await request(
      'POST',
      ServiceEndpoints.registerPath,
      body: <String, Object?>{
        'userName': userName,
        'email': email,
        'password': passwordHash,
        'code': code,
        'inviteCode': inviteCode,
      },
    );
    ensureOk(response, '无法创建账号。');
    return SessionTokens.decode(decodeHttpBody(response));
  }

  Future<void> sendRegisterEmail(String email) =>
      _requestEmailCode(ServiceEndpoints.sendRegisterEmailPath, email);

  Future<void> sendResetEmail(String email) =>
      _requestEmailCode(ServiceEndpoints.sendResetEmailPath, email);

  Future<void> _requestEmailCode(String path, String email) async {
    final response = await request(
      'GET',
      path,
      query: <String, String>{'email': email},
    );
    // 验证码接口的 401 只是「这次不给发」，不能当登录失效把用户踢下线。
    ensureOk(response, '无法发送验证码。', authStatuses: const <int>{});
    envelopeOf(response, '无法发送验证码。');
  }

  Future<void> resetPassword({
    required String email,
    required String newPasswordHash,
    required String code,
  }) async {
    final response = await request(
      'POST',
      ServiceEndpoints.resetPasswordPath,
      body: <String, Object?>{
        'email': email,
        'newPassword': newPasswordHash,
        'code': code,
      },
    );
    ensureOk(response, '无法重置密码。');
    envelopeOf(response, '无法重置密码。');
  }

  Future<String> refreshToken(String refreshToken) async {
    if (refreshToken.isEmpty) {
      throw const ApiError('需要登录后才能继续。', ApiErrorCategory.auth, status: 401);
    }
    final response = await request(
      'POST',
      ServiceEndpoints.refreshTokenPath,
      body: <String, Object?>{'token': refreshToken},
    );
    // 会话过期在这个端点上是 404；不归到 auth 就走不到重新登录的引导。
    ensureOk(
      response,
      '登录状态已过期，请重新登录。',
      authStatuses: const <int>{401, 404},
    );
    final envelope = asRecord(
      envelopeOf(response, '登录状态已过期，请重新登录。'),
      '刷新令牌响应',
    );
    return asString(
      envelope['Response'] ?? envelope['response'] ?? envelope['Token'],
    );
  }
}
