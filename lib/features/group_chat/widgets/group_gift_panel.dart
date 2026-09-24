import 'package:flutter/material.dart';

import '../../../api/models.dart';
import '../../../services/app_state.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_network_image.dart';
import '../../personas/persona_cover.dart';
import '../../wallet/membership_benefits_page.dart';

/// 群聊礼物：① 选收礼人 → ② 选礼物。
class GroupGiftPanel extends StatefulWidget {
  const GroupGiftPanel({
    super.key,
    required this.members,
    required this.baseUrl,
    required this.userId,
    required this.onSend,
    this.preselectedIds = const {},
    this.enabled = true,
    this.onClose,
  });

  final List<GroupMemberDto> members;
  final String baseUrl;
  final String userId;
  final Set<String> preselectedIds;
  final bool enabled;
  final VoidCallback? onClose;
  final Future<void> Function(GiftDto gift, List<String> personaIds) onSend;

  @override
  State<GroupGiftPanel> createState() => _GroupGiftPanelState();
}

class _GroupGiftPanelState extends State<GroupGiftPanel> {
  final _selected = <String>{};
  List<GiftDto>? _gifts;
  int? _stardust;
  bool _loading = false;
  bool _sending = false;
  bool _pickGiftStep = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.preselectedIds);
    if (_selected.isEmpty && widget.members.length == 1) {
      _selected.add(widget.members.first.personaId);
    }
    _pickGiftStep = widget.preselectedIds.isNotEmpty && _selected.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final s = AppStateScope.of(context);
      final gifts = await s.api().listGifts();
      WalletDto? wallet;
      try {
        wallet = await s.api().getWallet(userId: widget.userId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
        _stardust = wallet?.stardust;
        _loading = false;
        _loadError = gifts.isEmpty ? '暂无可用礼物' : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '礼物加载失败，请重试';
        });
      }
    }
  }

  void _toggleMember(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  String _absUrl(String url) {
    if (url.startsWith('http')) return url;
    final b = widget.baseUrl.replaceAll(RegExp(r'/$'), '');
    return '$b$url';
  }

  void _goPickGift() {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择收礼人')),
      );
      return;
    }
    if (_gifts == null && !_loading) {
      _load();
    }
    setState(() => _pickGiftStep = true);
  }

  Future<void> _pickGift(GiftDto gift) async {
    if (!widget.enabled || _sending || _selected.isEmpty) return;
    final total = gift.price * _selected.length;
    if (_stardust != null && _stardust! < total) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bgDarkElevated,
          title: const Text('星尘不足'),
          content: Text('本次需要 $total 星尘，当前余额 $_stardust。开通 VIP 可获赠星尘，去看看？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去开通 VIP'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        final s = AppStateScope.of(context);
        final m = s.user?.membership ?? const Membership();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MembershipBenefitsPage(membership: m),
          ),
        );
        if (!mounted) return;
        // 从充值页返回后刷新余额（后台可能已补发）
        try {
          final s = AppStateScope.of(context);
          final wallet = await s.api().getWallet(userId: widget.userId);
          if (mounted) setState(() => _stardust = wallet.stardust);
        } catch (_) {/* ignore */}
      }
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(gift, _selected.toList());
      if (mounted) setState(() => _sending = false);
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.glassSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.strokeStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (_pickGiftStep)
                  GestureDetector(
                    onTap: () => setState(() => _pickGiftStep = false),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _pickGiftStep
                        ? (_stardust == null
                            ? '选择礼物 · 已选 $count 人'
                            : '选择礼物 · 余额 $_stardust · 已选 $count 人')
                        : (_stardust == null
                            ? '选择收礼人'
                            : '选择收礼人 · 余额 $_stardust'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                if (_sending)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                GestureDetector(
                  onTap: widget.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_pickGiftStep) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in widget.members)
                    GestureDetector(
                      onTap:
                          widget.enabled ? () => _toggleMember(m.personaId) : null,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _selected.contains(m.personaId)
                                ? AppColors.accentPink
                                : AppColors.strokeSoft,
                            width: _selected.contains(m.personaId) ? 1.6 : 1,
                          ),
                          color: _selected.contains(m.personaId)
                              ? AppColors.accentPink.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PersonaCoverAvatar(
                                baseUrl: widget.baseUrl,
                                coverUrl: m.coverUrl,
                                fallbackColor: AppColors.bgDarkElevated,
                                fallbackLabel: m.name.isNotEmpty
                                    ? m.name.substring(0, 1)
                                    : '?',
                                radius: 12,
                              ),
                              const SizedBox(width: 6),
                              Text(m.name, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.enabled && count > 0 ? _goPickGift : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(count > 0 ? '下一步 · 选礼物' : '请先选择收礼人'),
                ),
              ),
            ] else ...[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if ((_gifts ?? []).isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loadError ?? '礼物加载失败，请稍后重试',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('重新加载'),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in _gifts!)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.enabled ? () => _pickGift(g) : null,
                        child: Container(
                          width: 72,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.accentPink.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            children: [
                              if (g.thumbUrl.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AppNetworkImage(
                                    url: _absUrl(g.thumbUrl),
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, __, ___) => const Text(
                                      '🎁',
                                      style: TextStyle(fontSize: 22),
                                    ),
                                  ),
                                )
                              else
                                const Text('🎁', style: TextStyle(fontSize: 22)),
                              const SizedBox(height: 4),
                              Text(
                                g.name,
                                style: const TextStyle(fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                count > 1
                                    ? '${g.price}×$count'
                                    : '${g.price}·+${g.bondDelta}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
