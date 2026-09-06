import '../decode.dart';

class OnlineInfo {
  const OnlineInfo({
    required this.onlineUserCount,
    required this.maxOnline,
    required this.dayCount,
    required this.dayRegister,
  });

  final int onlineUserCount;
  final int maxOnline;
  final int dayCount;
  final int dayRegister;

  static OnlineInfo decode(Object? value) {
    final record = asRecord(value, '在线信息');
    return OnlineInfo(
      onlineUserCount: asInt(record['OnlineUserCount']),
      maxOnline: asInt(record['MaxOnline']),
      dayCount: asInt(record['DayCount']),
      dayRegister: asInt(record['DayRegister']),
    );
  }
}

class UserGrowth {
  const UserGrowth({
    required this.experience,
    required this.coin,
    required this.comicQuota,
    required this.comicQuotaToday,
    required this.level,
    required this.growthLevel,
    required this.currentLevelExperience,
    required this.nextLevelExperience,
    required this.signInStreak,
    required this.signedToday,
  });

  final int experience;
  final int coin;
  final int comicQuota;
  final int comicQuotaToday;
  final int level;
  final int growthLevel;
  final int currentLevelExperience;
  final int? nextLevelExperience;
  final int signInStreak;
  final bool signedToday;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.userName,
    required this.avatarUrl,
    required this.email,
    required this.inviteCode,
    required this.groupName,
    required this.unreadNotificationCount,
    required this.unreadDirectMessageCount,
    required this.registeredAt,
    required this.growth,
  });

  final int id;
  final String userName;
  final String avatarUrl;
  final String email;
  final String inviteCode;
  final String groupName;
  final int unreadNotificationCount;
  final int unreadDirectMessageCount;
  final DateTime? registeredAt;
  final UserGrowth growth;

  static UserProfile decode(Object? value) {
    final record = asRecord(value, '用户资料响应');
    final role = asRecordOrEmpty(record['Role']);
    final growth = asRecordOrEmpty(record['Growth']);
    return UserProfile(
      id: asInt(record['Id']),
      userName: asStringOrEmpty(record['UserName']),
      avatarUrl: asStringOrEmpty(record['Avatar']),
      email: asStringOrEmpty(record['Email']),
      inviteCode: asStringOrEmpty(record['InviteCode']),
      groupName: asStringOrEmpty(role['Name']),
      unreadNotificationCount: asInt(record['UnreadNotificationCount'], 0),
      unreadDirectMessageCount: asInt(record['UnreadDirectMessageCount'], 0),
      registeredAt: asNullableDate(record['RegisterAt']),
      growth: UserGrowth(
        experience: asInt(growth['Exp'], 0),
        coin: asInt(growth['Coin'], 0),
        comicQuota: asInt(growth['ComicQuota'], 0),
        comicQuotaToday: asInt(growth['ComicQuotaToday'], 0),
        level: asInt(growth['Level'], 0),
        growthLevel: asInt(growth['GrowthLevel'], 0),
        currentLevelExperience: asInt(growth['CurrentLevelExp'], 0),
        nextLevelExperience: asNullableInt(growth['NextLevelExp']),
        signInStreak: asInt(growth['SignStreak'], 0),
        signedToday: asBool(growth['TodaySigned'], false),
      ),
    );
  }
}

/// 其他用户的公开资料，用户名片展示用。走裸 HTTP 端点，字段是 PascalCase。
class PublicUserSummary {
  const PublicUserSummary({
    required this.id,
    required this.userName,
    required this.avatarUrl,
    required this.roleName,
    required this.level,
    required this.registeredAt,
    required this.bookCount,
    required this.threadCount,
    required this.replyCount,
    required this.commentCount,
  });

  final int id;
  final String userName;
  final String avatarUrl;
  final String roleName;
  final int level;
  final DateTime? registeredAt;
  final int bookCount;
  final int threadCount;
  final int replyCount;
  final int commentCount;

  static PublicUserSummary decode(Object? value) {
    final record = asRecord(value, '用户名片响应');
    return PublicUserSummary(
      id: asInt(record['Id'], 0),
      userName: asStringOrEmpty(record['UserName']),
      avatarUrl: asStringOrEmpty(record['Avatar']),
      roleName: asStringOrEmpty(record['Role']),
      level: asInt(record['Level'], 0),
      registeredAt: asNullableDate(record['RegisterAt']),
      bookCount: asCount(record['BookCount']),
      threadCount: asCount(record['CommunityThreadCount']),
      replyCount: asCount(record['CommunityReplyCount']),
      commentCount: asCount(record['CommentCount']),
    );
  }
}

class DailyCheckInResult {
  const DailyCheckInResult({
    required this.reward,
    required this.streak,
    required this.experience,
    required this.level,
  });

  final int reward;
  final int streak;
  final int experience;
  final int level;

  static DailyCheckInResult decode(Object? value) {
    final record = asRecord(value, '签到响应');
    return DailyCheckInResult(
      reward: asInt(record['Reward']),
      streak: asInt(record['Streak']),
      experience: asInt(record['Exp']),
      level: asInt(record['Level']),
    );
  }
}
