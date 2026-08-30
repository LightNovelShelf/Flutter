import 'package:flutter_test/flutter_test.dart';
import 'package:lightnovel/data/api/models.dart';
import 'package:lightnovel/features/settings/sign_in_sheet.dart';
import 'package:lightnovel/features/shop/shop_screen.dart';

void main() {
  test('decodes shop catalog and clamps remaining monthly purchases', () {
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
      ],
    });

    expect(catalog.coin, 120);
    expect(catalog.items.single.key, signMakeupItemKey);
    expect(catalog.items.single.price, 30);
    expect(catalog.items.single.owned, 1);
    expect(catalog.items.single.remaining, 0);
  });

  test('decodes inventory, calendar, purchase, and makeup responses', () {
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

    expect(inventory.items.single.quantity, 2);
    expect(calendar.days.single.day, 9);
    expect(purchase.coin, 90);
    expect(makeup.streak, 4);
    expect(makeup.owned, 1);
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
