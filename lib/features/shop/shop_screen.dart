import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/network/api_error.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints.dart';
import '../../data/api/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../shared/format.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/book_image.dart';
import '../../shared/widgets/state_views.dart';
import '../settings/sign_in_sheet.dart';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  ShopCatalog? _shop;
  OwnedShopItems? _owned;
  bool _loading = true;
  String? _buyingKey;
  bool _usingComicQuota = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = ref.read(apiClientProvider);
      final shopFuture = api.getShop();
      final ownedFuture = api.getMyItems();
      final shop = await shopFuture;
      final owned = await ownedFuture;
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _owned = owned;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buy(ShopItem item) async {
    if (_buyingKey != null || _usingComicQuota) return;
    final confirmed = await showAppConfirm(
      context: context,
      title: '确认购买',
      message: '花费 ${formatCount(item.price)} 金币购买 1 个「${item.name}」？',
      confirmLabel: '购买',
    );
    if (!confirmed || !mounted) return;

    setState(() => _buyingKey = item.key);
    try {
      final result = await ref
          .read(apiClientProvider)
          .buyShopItem(key: item.key);
      await ref.read(profileProvider.notifier).reload();
      await _load(showLoading: false);
      if (!mounted) return;
      _showMessage('购买成功，现在持有 ${result.owned} 个');
    } catch (error) {
      if (mounted) _showMessage(describeApiError(error), error: true);
    } finally {
      if (mounted) setState(() => _buyingKey = null);
    }
  }

  Future<void> _useComicQuotaCard() async {
    if (_usingComicQuota || _buyingKey != null) return;
    final confirmed = await showAppConfirm(
      context: context,
      title: '使用漫画额度卡',
      message: '使用后立即获得 50 点漫画额度，永不过期。',
      confirmLabel: '使用',
    );
    if (!confirmed || !mounted) return;

    setState(() => _usingComicQuota = true);
    try {
      final result = await ref.read(apiClientProvider).useComicQuotaCard();
      await ref.read(profileProvider.notifier).reload();
      await _load(showLoading: false);
      if (!mounted) return;
      _showMessage('已发放 ${result.granted} 点漫画额度，当前余额 ${result.quota} 点');
    } catch (error) {
      if (mounted) _showMessage(describeApiError(error), error: true);
    } finally {
      if (mounted) setState(() => _usingComicQuota = false);
    }
  }

  Future<void> _openSignIn() async {
    await showSignInSheet(context);
    if (!mounted) return;
    await _load(showLoading: false);
  }

  void _showMessage(String message, {bool error = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? colors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('商城')),
    body: _buildBody(),
  );

  Widget _buildBody() {
    if (_loading && _shop == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _shop == null) {
      return ErrorStateView(message: _error!, onRetry: _load);
    }

    final shop = _shop!;
    final owned = _owned?.items ?? const <OwnedShopItem>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          _BalanceCard(coin: shop.coin),
          const SizedBox(height: 24),
          Text('商品', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (shop.items.isEmpty)
            const _EmptyItemsCard(message: '暂无在售道具')
          else
            for (
              var index = 0;
              index < shop.items.length;
              index += 1
            ) ...<Widget>[
              _ShopItemCard(
                item: shop.items[index],
                buying: _buyingKey == shop.items[index].key,
                onBuy: () => _buy(shop.items[index]),
              ),
              if (index < shop.items.length - 1) const SizedBox(height: 12),
            ],
          const SizedBox(height: 28),
          Text('我的道具', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (owned.isEmpty)
            const _EmptyItemsCard(message: '还没有任何道具')
          else
            _OwnedItemsCard(
              items: owned,
              onMakeUp: _openSignIn,
              onUseComicQuota: _useComicQuotaCard,
              usingComicQuota: _usingComicQuota,
            ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.coin});

  final int coin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: <Widget>[
            Icon(Icons.paid, color: colors.onPrimaryContainer, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '金币余额',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: colors.onPrimaryContainer),
              ),
            ),
            Text(
              formatCount(coin),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({
    required this.item,
    required this.buying,
    required this.onBuy,
  });

  final ShopItem item;
  final bool buying;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ShopImage(
              url: item.imageUrl,
              placeholder: item.imagePlaceholder,
              size: 92,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (item.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      item.description,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.paid_outlined,
                        size: 19,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatCount(item.price),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: item.canPurchase && !buying ? onBuy : null,
                        child: buying
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                item.canPurchase
                                    ? '购买'
                                    : item.monthlyLimit == 0
                                    ? '不可购买'
                                    : '本月已达上限',
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.monthlyLimit == null
                        ? '持有 ${item.owned} · 不限购'
                        : '持有 ${item.owned} · 本月还可买 ${item.remaining}/${item.monthlyLimit}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnedItemsCard extends StatelessWidget {
  const _OwnedItemsCard({
    required this.items,
    required this.onMakeUp,
    required this.onUseComicQuota,
    required this.usingComicQuota,
  });

  final List<OwnedShopItem> items;
  final VoidCallback onMakeUp;
  final VoidCallback onUseComicQuota;
  final bool usingComicQuota;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (var index = 0; index < items.length; index += 1) ...<Widget>[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              leading: _ShopImage(
                url: items[index].imageUrl,
                placeholder: items[index].imagePlaceholder,
                size: 52,
              ),
              title: Text(items[index].name),
              subtitle: items[index].description.isEmpty
                  ? null
                  : Text(items[index].description),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('x${items[index].quantity}'),
                  if (items[index].key == signMakeupItemKey) ...<Widget>[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: onMakeUp,
                      child: const Text('去补签'),
                    ),
                  ],
                  if (items[index].key == comicQuotaItemKey) ...<Widget>[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: usingComicQuota ? null : onUseComicQuota,
                      child: usingComicQuota
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('使用'),
                    ),
                  ],
                ],
              ),
            ),
            if (index < items.length - 1)
              Divider(height: 1, color: colors.outlineVariant),
          ],
        ],
      ),
    );
  }
}

bool isSvgShopImage(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  return path.toLowerCase().endsWith('.svg');
}

class _ShopImage extends StatelessWidget {
  const _ShopImage({
    required this.url,
    required this.placeholder,
    required this.size,
  });

  final String url;
  final String? placeholder;
  final double size;

  String get _resolvedUrl {
    final uri = Uri.tryParse(url);
    if (uri?.hasScheme == true) return url;
    return Uri.parse(ServiceEndpoints.apiOrigin).resolve(url).toString();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _resolvedUrl;
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: isSvgShopImage(resolvedUrl)
            ? ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SvgPicture.network(
                    resolvedUrl,
                    fit: BoxFit.contain,
                    placeholderBuilder: (_) => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            : BookImage(
                url: resolvedUrl,
                displayHeight: size,
                blurHash: placeholder,
                aspectRatio: 1,
                fallbackIcon: Icons.inventory_2_outlined,
              ),
      ),
    );
  }
}

class _EmptyItemsCard extends StatelessWidget {
  const _EmptyItemsCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}
