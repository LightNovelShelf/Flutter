import 'api_client.dart';
import 'models.dart';

extension ApiClientShop on ApiClient {
  Future<ShopCatalog> getShop() =>
      invoke('GetShop', <String, Object?>{}, ShopCatalog.decode);

  Future<OwnedShopItems> getMyItems() =>
      invoke('GetMyItems', <String, Object?>{}, OwnedShopItems.decode);

  Future<ShopPurchaseResult> buyShopItem({
    required String key,
    int quantity = 1,
  }) => invoke('BuyShopItem', <String, Object?>{
    'Key': key,
    'Quantity': quantity,
  }, ShopPurchaseResult.decode);

  Future<ComicQuotaUseResult> useComicQuotaCard() => invoke(
    'UseComicQuotaCard',
    <String, Object?>{},
    ComicQuotaUseResult.decode,
  );

  Future<SignMakeupResult> useSignMakeupCard({required String date}) => invoke(
    'UseSignMakeupCard',
    <String, Object?>{'Date': date},
    SignMakeupResult.decode,
  );
}
