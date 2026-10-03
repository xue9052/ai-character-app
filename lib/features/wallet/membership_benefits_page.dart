import 'dart:io' show Platform;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:uuid/uuid.dart';

import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';

/// VIP 订阅页：三档会员 · 开通送星尘 · 不做单独星尘充值。
/// 价格 / 赠送星尘 / 权益文案全部来自服务端配置。
class MembershipBenefitsPage extends StatefulWidget {
  const MembershipBenefitsPage({super.key, required this.membership});

  final Membership membership;

  @override
  State<MembershipBenefitsPage> createState() => _MembershipBenefitsPageState();
}

class _MembershipBenefitsPageState extends State<MembershipBenefitsPage> {
  static const _peach = Color(0xFFE8B4A0);
  static const _peachDeep = Color(0xFFD4A08C);
  static const _cardDark = Color(0xFF2A2A30);
  static const _tableBg = Color(0xFF222228);

  bool _loading = true;
  String? _error;
  VipCatalogDto? _catalog;
  int _selected = 0;
  int? _stardust;
  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final Map<String, ProductDetails> _storeProducts = {};
  bool _purchasing = false;
  int _loadGeneration = 0;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  VipSubscriptionDto? get _plan {
    final list = _catalog?.subscriptions ?? const <VipSubscriptionDto>[];
    if (list.isEmpty) return null;
    final i = _selected.clamp(0, list.length - 1);
    return list[i];
  }

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = _store.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error) {
        if (mounted) _showPurchaseMessage('Apple 购买状态读取失败：$error');
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  void _showPurchaseMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchasing = true);
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _showPurchaseMessage(purchase.error?.message ?? 'Apple 购买失败');
      } else if (purchase.status == PurchaseStatus.canceled) {
        _showPurchaseMessage('已取消购买');
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          final jws = purchase.verificationData.serverVerificationData;
          if (!jws.contains('.')) {
            throw StateError('StoreKit 未返回交易 JWS，请确认运行的是 StoreKit 2');
          }
          final s = AppStateScope.of(context);
          await s.api().verifyApplePurchase(jws);
          await s.refreshSessionFromServer();
          await _load();
          _showPurchaseMessage('购买已验证，会员和星尘已到账');
          if (purchase.pendingCompletePurchase) {
            await _store.completePurchase(purchase);
          }
        } catch (e) {
          // 不 complete：StoreKit 下次启动会再次投递未完成交易。
          _showPurchaseMessage('购买已完成，但验证暂未成功：$e');
        }
      }
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _load() async {
    final s = AppStateScope.of(context);
    final generation = ++_loadGeneration;
    final showInitialLoading = _catalog == null;
    setState(() {
      _loading = showInitialLoading;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        s.api().getVipCatalog(),
        s.api().getWallet(userId: s.userId).then<Object?>((v) => v).catchError(
              (_) => null,
            ),
      ]);
      final catalog = results[0] as VipCatalogDto;
      final wallet = results[1] as WalletDto?;
      if (!kIsWeb && Platform.isIOS && catalog.purchaseEnabled) {
        final ids = catalog.subscriptions
            .map((item) => item.appleProductId)
            .where((id) => id.isNotEmpty)
            .toSet();
        if (ids.isNotEmpty && await _store.isAvailable()) {
          final products = await _store.queryProductDetails(ids);
          if (generation != _loadGeneration) return;
          _storeProducts
            ..clear()
            ..addEntries(products.productDetails.map((p) => MapEntry(p.id, p)));
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      var selected = 0;
      // 默认选中「热门」或中间档
      for (var i = 0; i < catalog.subscriptions.length; i++) {
        if (catalog.subscriptions[i].badge.contains('热门')) {
          selected = i;
          break;
        }
      }
      if (selected == 0 && catalog.subscriptions.length >= 2) {
        selected = 1;
      }
      setState(() {
        _catalog = catalog;
        _selected = selected;
        _stardust = wallet?.stardust;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  String _fmtPrice(double v) {
    if (v <= 0) return '¥0';
    if (v == v.roundToDouble()) return '¥${v.toInt()}';
    return '¥${v.toStringAsFixed(1)}';
  }

  String _planPrice(VipSubscriptionDto? plan) {
    if (plan == null) return '';
    final storePrice = _storeProducts[plan.appleProductId]?.price;
    return storePrice ?? _fmtPrice(plan.priceCny);
  }

  bool get _applePurchaseAvailable =>
      !kIsWeb && Platform.isIOS && _catalog?.purchaseEnabled == true;

  Future<void> _onPay() async {
    final plan = _plan;
    if (plan == null) return;
    if (_applePurchaseAvailable) {
      final s = AppStateScope.of(context);
      final productId = plan.appleProductId.trim();
      if (productId.isEmpty) {
        _showPurchaseMessage('后台尚未配置该套餐的 Apple 商品 ID');
        return;
      }
      setState(() => _purchasing = true);
      try {
        if (!await _store.isAvailable()) throw StateError('App Store 当前不可用');
        final response = await _store.queryProductDetails({productId});
        if (response.error != null || response.productDetails.isEmpty) {
          throw StateError(
              response.error?.message ?? 'App Store 未找到商品 $productId');
        }
        _storeProducts[productId] = response.productDetails.first;
        final accountToken = const Uuid().v5(
          Namespace.url.value,
          'ai-character-app:${s.userId}',
        );
        final launched = await _store.buyNonConsumable(
          purchaseParam: Sk2PurchaseParam(
            productDetails: response.productDetails.first,
            applicationUserName: accountToken,
          ),
        );
        if (!launched) throw StateError('Apple 没有启动购买流程');
      } catch (e) {
        if (mounted) setState(() => _purchasing = false);
        _showPurchaseMessage('无法开始购买：$e');
      }
      return;
    }
    final hint = (_catalog?.contactHint ?? '').trim().isNotEmpty
        ? _catalog!.contactHint
        : '当前内测期由客服后台开通 VIP。';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgDarkElevated,
        title: Text(
          !kIsWeb && Platform.isIOS ? 'Apple 内购暂不可用' : '暂未开放支付',
        ),
        content: Text(
          !kIsWeb && Platform.isIOS
              ? '当前后台未启用 Apple 内购。请确认服务器已开启内购并配置 App Store ID、商品 ID 和证书。'
              : _isAndroid
                  ? 'Android 端暂不支持在线开通。\n'
                      '已选「${plan.title}」（${_planPrice(plan)}），'
                      '开通后赠送 ${plan.stardustGift} 星尘。\n$hint'
                  : '已选「${plan.title}」（${_planPrice(plan)}），'
                      '开通后赠送 ${plan.stardustGift} 星尘。\n$hint',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    final u = s.user;
    final m = widget.membership;
    final name =
        (u?.nickname.trim().isNotEmpty == true) ? u!.nickname.trim() : '我';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('我的会员'),
        backgroundColor: Colors.transparent,
        centerTitle: true,
      ),
      body: _loading && _catalog == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _catalog == null
              ? _buildError()
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        color: _peach,
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          children: [
                            _buildUserRow(s, u, name, m),
                            const SizedBox(height: 18),
                            _buildPlanRow(),
                            const SizedBox(height: 18),
                            _buildBenefitsTable(),
                            if ((_catalog?.contactHint ?? '').isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                _catalog!.contactHint,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _buildPayBar(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Text('加载失败：$_error', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: FilledButton(onPressed: _load, child: const Text('重试')),
        ),
      ],
    );
  }

  Widget _buildUserRow(
    AppState s,
    AuthUser? u,
    String name,
    Membership m,
  ) {
    return Row(
      children: [
        UserAvatar(
          emoji: u?.avatarEmoji ?? '🙂',
          colorHex: u?.avatarColor ?? '#7B6CF6',
          imageUrl: s.absoluteAvatarUrl(u?.avatarUrl),
          radius: 22,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: m.isMember
                          ? _peach.withValues(alpha: 0.9)
                          : AppColors.glassSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      m.isMember ? 'VIP' : '体验',
                      style: TextStyle(
                        color: m.isMember
                            ? const Color(0xFF2A1F1C)
                            : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (_stardust != null) ...[
                const SizedBox(height: 2),
                Text(
                  '星尘 $_stardust',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanRow() {
    final plans = _catalog?.subscriptions ?? const <VipSubscriptionDto>[];
    if (plans.isEmpty) {
      return const Text(
        '暂无 VIP 套餐',
        style: TextStyle(color: AppColors.textMuted),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < plans.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _buildPlanCard(i, plans[i])),
        ],
      ],
    );
  }

  Widget _buildPlanCard(int index, VipSubscriptionDto plan) {
    final selected = _selected == index;
    final fg = selected ? const Color(0xFF2A1F1C) : AppColors.textPrimary;
    final muted = selected
        ? const Color(0xFF2A1F1C).withValues(alpha: 0.55)
        : AppColors.textMuted;

    return GestureDetector(
      onTap: () => setState(() => _selected = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        decoration: BoxDecoration(
          color: selected ? _peach : _cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _peachDeep : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  _planPrice(plan),
                  style: TextStyle(
                    color: fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                if (plan.originalPriceCny > plan.priceCny)
                  Text(
                    _fmtPrice(plan.originalPriceCny),
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: muted,
                    ),
                  )
                else
                  Text(
                    '${plan.days} 天',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                const SizedBox(height: 8),
                Text(
                  '送 ${plan.stardustGift} 星尘',
                  style: TextStyle(
                    color: fg,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (plan.badge.isNotEmpty)
              Positioned(
                top: -8,
                left: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE85D5D),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    plan.badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitsTable() {
    final rows = _catalog?.benefitRows ?? const <VipBenefitRowDto>[];
    final plan = _plan;
    final memberTier = plan?.tier ?? 'plus';
    final freeTier = _catalog?.defaultTier ?? 'free';
    final memberLabel = switch (memberTier) {
      'pro' => '挚爱',
      'plus' => '心动',
      _ => '会员',
    };

    return Container(
      decoration: BoxDecoration(
        color: _tableBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                const Expanded(
                  flex: 5,
                  child: Text(
                    '权益',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    memberLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _peach,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 3,
                  child: Text(
                    '体验',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          // 开通赠送星尘：单独一行，跟选中套餐走
          if (plan != null) ...[
            _benefitLine(
              label: '开通赠送星尘',
              member: '${plan.stardustGift}',
              free: '—',
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
          ],
          for (var i = 0; i < rows.length; i++) ...[
            _benefitLine(
              label: rows[i].label,
              member: rows[i].valueFor(memberTier),
              free: rows[i].valueFor(freeTier),
            ),
            if (i < rows.length - 1)
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
          ],
        ],
      ),
    );
  }

  Widget _benefitLine({
    required String label,
    required String member,
    required String free,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.25,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              member,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              free,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayBar() {
    final plan = _plan;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: plan == null || _purchasing ? null : _onPay,
                style: FilledButton.styleFrom(
                  backgroundColor: _peach,
                  foregroundColor: const Color(0xFF2A1F1C),
                  disabledBackgroundColor: _peach.withValues(alpha: 0.4),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(
                  plan == null
                      ? '立即开通'
                      : '立即开通 ${_planPrice(plan)} · 送 ${plan.stardustGift} 星尘',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _applePurchaseAvailable
                  ? '开通即表示同意会员服务约定 · 由 Apple 安全处理付款'
                  : '开通即表示同意会员服务约定 · 当前由客服开通',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
