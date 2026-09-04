import '../decode.dart';

const String signMakeupItemKey = 'sign_makeup';
const String comicQuotaItemKey = 'comic_quota_50';

class ShopItem {
  const ShopItem({
    required this.key,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.imagePlaceholder,
    required this.price,
    required this.owned,
    required this.monthlyLimit,
    required this.monthlyPurchased,
  });

  final String key;
  final String name;
  final String description;
  final String imageUrl;
  final String? imagePlaceholder;
  final int price;
  final int owned;
  final int? monthlyLimit;
  final int monthlyPurchased;

  int? get remaining => monthlyLimit == null
      ? null
      : (monthlyLimit! - monthlyPurchased).clamp(0, monthlyLimit!);
  bool get canPurchase => monthlyLimit == null || remaining! > 0;

  static ShopItem decode(Object? value) {
    final record = asRecord(value, '商城道具');
    final image = decodeCover(record['Image']);
    return ShopItem(
      key: asString(record['Key']),
      name: asString(record['Name']),
      description: asStringOrEmpty(record['Description']),
      imageUrl: image.url,
      imagePlaceholder: image.placeholder,
      price: asCount(record['Price']),
      owned: asCount(record['Owned']),
      monthlyLimit: asNullableInt(record['MonthlyLimit']),
      monthlyPurchased: asCount(record['MonthlyPurchased']),
    );
  }
}

class ShopCatalog {
  const ShopCatalog({required this.coin, required this.items});

  final int coin;
  final List<ShopItem> items;

  static ShopCatalog decode(Object? value) {
    final record = asRecord(value, '商城响应');
    return ShopCatalog(
      coin: asCount(record['Coin']),
      items: asArray(record['Items'], '商城道具').map(ShopItem.decode).toList(),
    );
  }
}

class OwnedShopItem {
  const OwnedShopItem({
    required this.key,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.imagePlaceholder,
    required this.quantity,
  });

  final String key;
  final String name;
  final String description;
  final String imageUrl;
  final String? imagePlaceholder;
  final int quantity;

  static OwnedShopItem decode(Object? value) {
    final record = asRecord(value, '持有道具');
    final image = decodeCover(record['Image']);
    return OwnedShopItem(
      key: asString(record['Key']),
      name: asString(record['Name']),
      description: asStringOrEmpty(record['Description']),
      imageUrl: image.url,
      imagePlaceholder: image.placeholder,
      quantity: asCount(record['Quantity']),
    );
  }
}

class OwnedShopItems {
  const OwnedShopItems({required this.items});

  final List<OwnedShopItem> items;

  static OwnedShopItems decode(Object? value) {
    final record = asRecord(value, '持有道具响应');
    return OwnedShopItems(
      items: asArray(
        record['Items'],
        '持有道具',
      ).map(OwnedShopItem.decode).toList(),
    );
  }
}

class ShopPurchaseResult {
  const ShopPurchaseResult({
    required this.key,
    required this.owned,
    required this.coin,
    required this.cost,
    required this.monthlyPurchased,
  });

  final String key;
  final int owned;
  final int coin;
  final int cost;
  final int monthlyPurchased;

  static ShopPurchaseResult decode(Object? value) {
    final record = asRecord(value, '购买响应');
    return ShopPurchaseResult(
      key: asString(record['Key']),
      owned: asCount(record['Owned']),
      coin: asCount(record['Coin']),
      cost: asCount(record['Cost']),
      monthlyPurchased: asCount(record['MonthlyPurchased']),
    );
  }
}

class ComicQuotaUseResult {
  const ComicQuotaUseResult({
    required this.key,
    required this.granted,
    required this.quota,
    required this.owned,
  });

  final String key;
  final int granted;
  final int quota;
  final int owned;

  static ComicQuotaUseResult decode(Object? value) {
    final record = asRecord(value, '漫画额度卡使用响应');
    return ComicQuotaUseResult(
      key: asString(record['Key']),
      granted: asCount(record['Granted']),
      quota: asCount(record['Quota']),
      owned: asCount(record['Owned']),
    );
  }
}

class SignInCalendarDay {
  const SignInCalendarDay({
    required this.date,
    required this.streak,
    required this.reward,
  });

  final String date;
  final int streak;
  final int reward;

  int? get day {
    if (date.length < 10) return null;
    return int.tryParse(date.substring(8, 10));
  }

  static SignInCalendarDay decode(Object? value) {
    final record = asRecord(value, '签到日历记录');
    return SignInCalendarDay(
      date: asString(record['SignDate']),
      streak: asCount(record['Streak']),
      reward: asCount(record['Reward']),
    );
  }
}

class SignInCalendar {
  const SignInCalendar({
    required this.year,
    required this.month,
    required this.days,
  });

  final int year;
  final int month;
  final List<SignInCalendarDay> days;

  static SignInCalendar decode(Object? value) {
    final record = asRecord(value, '签到日历响应');
    return SignInCalendar(
      year: asInt(record['Year']),
      month: asInt(record['Month']),
      days: asArray(
        record['Days'],
        '签到日历记录',
      ).map(SignInCalendarDay.decode).toList(),
    );
  }
}

class SignMakeupResult {
  const SignMakeupResult({
    required this.date,
    required this.streak,
    required this.reward,
    required this.coinReward,
    required this.owned,
  });

  final String date;
  final int streak;
  final int reward;
  final int coinReward;
  final int owned;

  static SignMakeupResult decode(Object? value) {
    final record = asRecord(value, '补签响应');
    return SignMakeupResult(
      date: asString(record['Date']),
      streak: asCount(record['Streak']),
      reward: asCount(record['Reward']),
      coinReward: asCount(record['CoinReward']),
      owned: asCount(record['Owned']),
    );
  }
}
