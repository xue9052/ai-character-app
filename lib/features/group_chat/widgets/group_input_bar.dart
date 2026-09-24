import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/models.dart';
import '../../../theme/app_theme.dart';
import 'group_gift_panel.dart';

/// 群聊输入条：左侧「+」展开；礼物面板内嵌在输入区上方（对齐私聊）。
class GroupInputBar extends StatefulWidget {
  const GroupInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.enabled = true,
    this.sending = false,
    this.hint = '说点什么…',
    this.onAtTap,
    this.onImageTap,
    this.giftMembers = const [],
    this.baseUrl = '',
    this.userId = '',
    this.onSendGift,
    this.giftOpen = false,
    this.giftPreselectedIds = const {},
    this.onGiftOpenChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final bool enabled;
  final bool sending;
  final String hint;
  final VoidCallback? onAtTap;
  final VoidCallback? onImageTap;
  final List<GroupMemberDto> giftMembers;
  final String baseUrl;
  final String userId;
  final Future<void> Function(GiftDto gift, List<String> personaIds)? onSendGift;
  final bool giftOpen;
  final Set<String> giftPreselectedIds;
  final ValueChanged<bool>? onGiftOpenChanged;

  @override
  State<GroupInputBar> createState() => _GroupInputBarState();
}

class _GroupInputBarState extends State<GroupInputBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _plusCtrl;
  late final Animation<double> _plusReveal;
  late final Animation<double> _plusTurn;
  bool _plusOpen = false;

  @override
  void initState() {
    super.initState();
    _plusCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    final curve = CurvedAnimation(
      parent: _plusCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _plusReveal = curve;
    _plusTurn = Tween<double>(begin: 0, end: 0.125).animate(curve);
  }

  @override
  void dispose() {
    _plusCtrl.dispose();
    super.dispose();
  }

  Future<void> _setPlusOpen(bool open) async {
    if (open == _plusOpen) return;
    widget.focusNode.unfocus();
    if (open) {
      setState(() => _plusOpen = true);
      await _plusCtrl.forward();
    } else {
      await _plusCtrl.reverse();
      if (mounted) setState(() => _plusOpen = false);
    }
  }

  Future<void> _onAction(VoidCallback? action, {bool openGift = false}) async {
    await _setPlusOpen(false);
    if (!mounted) return;
    if (openGift) {
      widget.onGiftOpenChanged?.call(true);
      return;
    }
    action?.call();
  }

  bool get _hasGift =>
      widget.onSendGift != null && widget.giftMembers.isNotEmpty;

  bool get _hasPlusActions =>
      widget.onImageTap != null || widget.onAtTap != null || _hasGift;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasPlusActions)
              SizeTransition(
                sizeFactor: _plusReveal,
                child: FadeTransition(
                  opacity: _plusReveal,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.glassSoft,
                            border: Border.all(
                              color: AppColors.strokeStrong,
                              width: 1.2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 26, 10, 22),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                if (widget.onImageTap != null)
                                  _PlusAction(
                                    icon: Icons.image_outlined,
                                    label: '图片',
                                    onTap: widget.enabled
                                        ? () => unawaited(
                                              _onAction(widget.onImageTap),
                                            )
                                        : null,
                                  ),
                                if (widget.onAtTap != null)
                                  _PlusAction(
                                    icon: Icons.alternate_email_rounded,
                                    label: '@',
                                    onTap: widget.enabled
                                        ? () => unawaited(
                                              _onAction(widget.onAtTap),
                                            )
                                        : null,
                                  ),
                                if (_hasGift)
                                  _PlusAction(
                                    icon: Icons.card_giftcard_rounded,
                                    label: '礼物',
                                    onTap: widget.enabled
                                        ? () => unawaited(
                                              _onAction(null, openGift: true),
                                            )
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.giftOpen && _hasGift)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GroupGiftPanel(
                  key: ValueKey(widget.giftPreselectedIds.join(',')),
                  members: widget.giftMembers,
                  baseUrl: widget.baseUrl,
                  userId: widget.userId,
                  preselectedIds: widget.giftPreselectedIds,
                  enabled: widget.enabled,
                  onSend: (gift, ids) async {
                    await widget.onSendGift!(gift, ids);
                    widget.onGiftOpenChanged?.call(false);
                  },
                  onClose: () => widget.onGiftOpenChanged?.call(false),
                ),
              ),
            _inputPill(),
          ],
        ),
      ),
    );
  }

  Widget _inputPill() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.glassSoft,
              borderRadius: BorderRadius.circular(AppColors.radiusPill),
              border: Border.all(
                color: AppColors.strokeStrong,
                width: 1.2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_hasPlusActions) _plusButton(),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onTap: () {
                        if (_plusOpen) unawaited(_setPlusOpen(false));
                        if (widget.giftOpen) {
                          widget.onGiftOpenChanged?.call(false);
                        }
                      },
                      onSubmitted: (_) {
                        if (widget.enabled && !widget.sending) {
                          widget.onSubmit();
                        }
                      },
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.35,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 11,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: (widget.enabled && !widget.sending)
                        ? widget.onSubmit
                        : null,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: widget.sending ? 0.16 : 0.34,
                          ),
                        ),
                        child: Center(
                          child: widget.sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white.withValues(alpha: 0.95),
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _plusButton() {
    return GestureDetector(
      onTap: widget.enabled
          ? () {
              HapticFeedback.selectionClick();
              if (widget.giftOpen) {
                widget.onGiftOpenChanged?.call(false);
              }
              unawaited(_setPlusOpen(!_plusOpen));
            }
          : null,
      child: SizedBox(
        width: 44,
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _plusOpen
                ? Colors.white.withValues(alpha: 0.32)
                : Colors.transparent,
          ),
          child: RotationTransition(
            turns: _plusTurn,
            child: Icon(
              _plusOpen ? Icons.close_rounded : Icons.add_rounded,
              color: Colors.white.withValues(
                alpha: widget.enabled ? 0.92 : 0.35,
              ),
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlusAction extends StatelessWidget {
  const _PlusAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14),
                  border: Border.all(color: AppColors.strokeSoft),
                ),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
