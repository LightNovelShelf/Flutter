import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/features/settings/sign_in_sheet.dart';
import 'package:lightnovel/features/shop/shop_screen.dart';

void main() {
  test('decodes limited and unlimited shop purchase rules', () {
    final catalog = ShopCatalog.decode(<String, Object?>{
      'Coin': 120,
      'Items': <Object?>[
        <String, Object?>{
          'Key': signMakeupItemKey,
          'Name': '补签卡',
          'Description': '补签最近漏签的日期',
          'Image': '/img/shop/sign-makeup.svg',
          'Price': 30,
          'Owned': 1,
          'MonthlyLimit': 2,
          'MonthlyPurchased': 3,
        },
        <String, Object?>{
          'Key': comicQuotaItemKey,
          'Name': '漫画额度 ×50',
          'Description': '使用后获得 50 点漫画额度',
          'Image': '/img/shop/comic-quota.svg',
          'Price': 100,
          'Owned': 2,
          'MonthlyPurchased': 4,
        },
      ],
    });

    final limited = catalog.items.first;
    final unlimited = catalog.items.last;
    expect(catalog.coin, 120);
    expect(limited.key, signMakeupItemKey);
    expect(limited.remaining, 0);
    expect(limited.canPurchase, isFalse);
    expect(unlimited.key, comicQuotaItemKey);
    expect(unlimited.monthlyLimit, isNull);
    expect(unlimited.remaining, isNull);
    expect(unlimited.canPurchase, isTrue);
  });

  test('decodes inventory, purchase, makeup, and quota use responses', () {
    final inventory = OwnedShopItems.decode(<String, Object?>{
      'Items': <Object?>[
        <String, Object?>{
          'Key': signMakeupItemKey,
          'Name': '补签卡',
          'Description': '',
          'Image': '/card.svg',
          'Quantity': 2,
        },
      ],
    });
    final calendar = SignInCalendar.decode(<String, Object?>{
      'Year': 2026,
      'Month': 8,
      'Days': <Object?>[
        <String, Object?>{'SignDate': '2026-08-09', 'Streak': 3, 'Reward': 12},
      ],
    });
    final purchase = ShopPurchaseResult.decode(<String, Object?>{
      'Key': signMakeupItemKey,
      'Owned': 3,
      'Coin': 90,
      'Cost': 30,
      'MonthlyPurchased': 1,
    });
    final makeup = SignMakeupResult.decode(<String, Object?>{
      'Date': '2026-08-09',
      'Streak': 4,
      'Reward': 14,
      'CoinReward': 2,
      'Owned': 1,
    });
    final quota = ComicQuotaUseResult.decode(<String, Object?>{
      'Key': comicQuotaItemKey,
      'Granted': 50,
      'Quota': 125,
      'Owned': 1,
    });

    expect(inventory.items.single.quantity, 2);
    expect(calendar.days.single.day, 9);
    expect(purchase.coin, 90);
    expect(makeup.streak, 4);
    expect(makeup.owned, 1);
    expect(quota.key, comicQuotaItemKey);
    expect(quota.granted, 50);
    expect(quota.quota, 125);
    expect(quota.owned, 1);
  });

  test('decodes permanent and daily comic quota balances', () {
    final profile = UserProfile.decode(<String, Object?>{
      'Id': 1,
      'Growth': <String, Object?>{'ComicQuota': 125, 'ComicQuotaToday': 20},
    });

    expect(profile.growth.comicQuota, 125);
    expect(profile.growth.comicQuotaToday, 20);
  });

  test('makeup eligibility uses the inclusive 30-day UTC window', () {
    final today = DateTime.utc(2026, 8, 30);

    expect(
      canUseSignMakeupCard(
        date: DateTime.utc(2026, 7, 31),
        today: today,
        cards: 1,
        signed: false,
      ),
      isTrue,
    );
    expect(
      canUseSignMakeupCard(
        date: DateTime.utc(2026, 7, 30),
        today: today,
        cards: 1,
        signed: false,
      ),
      isFalse,
    );
    expect(
      canUseSignMakeupCard(date: today, today: today, cards: 1, signed: false),
      isFalse,
    );
    expect(
      canUseSignMakeupCard(
        date: DateTime.utc(2026, 8, 29),
        today: today,
        cards: 0,
        signed: false,
      ),
      isFalse,
    );
    expect(
      canUseSignMakeupCard(
        date: DateTime.utc(2026, 8, 29),
        today: today,
        cards: 1,
        signed: true,
      ),
      isFalse,
    );
  });

  test('formats makeup dates in UTC', () {
    expect(
      formatSignDateUtc(DateTime.parse('2026-08-01T01:00:00+08:00')),
      '2026-07-31',
    );
  });

  test('routes SVG shop images away from the raster decoder', () {
    expect(isSvgShopImage('/img/shop/sign-makeup.svg'), isTrue);
    expect(isSvgShopImage('https://cdn.example/item.SVG?height=256'), isTrue);
    expect(isSvgShopImage('https://cdn.example/item.png'), isFalse);
  });
}
