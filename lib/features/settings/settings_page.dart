import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../services/dev_flags.dart';
import '../../services/keep_alive_service.dart';
import '../../services/push_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';
import '../../widgets/user_avatar.dart';
import '../personas/persona_workshop_page.dart';
import 'account_security_page.dart';
import 'edit_profile_page.dart';
import '../wallet/membership_benefits_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  TextEditingController? _baseCtrl;
  String? _health;
  int _versionTaps = 0;
  bool _batteryWhitelisted = true;

  static const _versionLabel = 'v0.1.0';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBatteryWhitelist();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统省电设置页返回后回填白名单状态
    if (state == AppLifecycleState.resumed) _refreshBatteryWhitelist();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppStateScope.of(context);
    _baseCtrl ??= TextEditingController(text: s.baseUrl);
  }

  Future<void> _refreshBatteryWhitelist() async {
    if (!KeepAliveService.supported) return;
    final ok = await KeepAliveService.instance.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() => _batteryWhitelisted = ok);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _baseCtrl?.dispose();
    super.dispose();
  }

  Future<void> _ping() async {
    final s = AppStateScope.of(context);
    try {
      final h = await s.api().health();
      setState(() => _health = '已连接 · ${h['model_profile'] ?? 'ok'}');
    } catch (e) {
      setState(() => _health = '未连接：${apiErrorMessage(e)}');
    }
  }

  Future<void> _onVersionTap() async {
    if (kDebugMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debug 包已显示开发选项')),
      );
      return;
    }
    _versionTaps += 1;
    if (_versionTaps < 7) {
      if (_versionTaps >= 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              DevFlags.unlocked
                  ? '再点 ${7 - _versionTaps} 次关闭开发选项'
                  : '再点 ${7 - _versionTaps} 次打开开发选项',
            ),
          ),
        );
      }
      return;
    }
    _versionTaps = 0;
    final on = await DevFlags.toggleUnlocked();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(on ? '已打开开发选项' : '已关闭开发选项')),
    );
  }

  String _membershipSubtitle(Membership m) {
    if (!m.isMember) {
      return m.expired ? '会员已到期，权益已回到体验档' : '体验 / 心动 / 挚爱权益对比';
    }
    final on = m.expiresOn;
    if (on == null) return '永久有效 · 点开看权益';
    final mm = on.month.toString().padLeft(2, '0');
    final dd = on.day.toString().padLeft(2, '0');
    return '有效期至 ${on.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    final u = s.user;
    final showDev = DevFlags.showDevTools;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            if (u != null) ...[
              _ProfileHeader(
                nickname: u.nickname,
                email: u.email,
                bio: u.bio,
                completed: u.profileCompleted,
                avatar: UserAvatar(
                  emoji: u.avatarEmoji,
                  colorHex: u.avatarColor,
                  imageUrl: s.absoluteAvatarUrl(u.avatarUrl),
                  radius: 42,
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EditProfilePage()),
                  );
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 22),
              _MembershipBanner(
                title: u.membership.isMember ? u.membership.label : '会员权益',
                subtitle: _membershipSubtitle(u.membership),
                member: u.membership.isMember,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MembershipBenefitsPage(
                        membership: u.membership,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _ShortcutCard(
                    icon: Icons.auto_awesome_rounded,
                    title: '我的角色',
                    subtitle: '创作与审核',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PersonaWorkshopPage(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  _ShortcutCard(
                    icon: Icons.lock_outline_rounded,
                    title: '账号安全',
                    subtitle: '密码与邮箱',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccountSecurityPage(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const _SectionLabel('陪伴'),
              _SettingsGroup(
                children: [
                  if (!kIsWeb && PushService.supported) ...[
                    _MeSwitch(
                      title: '主动关怀推送',
                      subtitle: Platform.isIOS
                          ? '她想你的时候，系统会轻轻提醒你'
                          : '她想你的时候，通知栏会轻轻提醒你',
                      value: s.pushReminders,
                      onChanged: (v) async {
                        await s.setPushReminders(v);
                        if (!mounted) return;
                        setState(() {});
                        if (v && !PushService.instance.serverEnabled) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('服务端尚未启用推送，请稍后再试'),
                            ),
                          );
                        } else if (v &&
                            PushService.instance.registrationId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('正在注册推送，请稍候…'),
                            ),
                          );
                        }
                      },
                    ),
                    if (s.pushReminders)
                      _MeRow(
                        title: '发送测试推送',
                        subtitle: Platform.isIOS ? '先回到桌面再点' : '确认通知栏能否收到',
                        onTap: () async {
                          try {
                            final res = await s.api().testPush(userId: s.userId);
                            if (!context.mounted) return;
                            final msgId = '${res['msg_id'] ?? ''}'.trim();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Platform.isIOS
                                      ? '已提交${msgId.isNotEmpty ? '（$msgId）' : ''}。请切到桌面查看'
                                      : '已发送，请看通知栏',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(apiErrorMessage(e))),
                            );
                          }
                        },
                      ),
                  ],
                  if (KeepAliveService.supported) ...[
                    _MeSwitch(
                      title: '后台保持在线',
                      subtitle: '通知栏常驻一条，退到后台也能实时收消息',
                      value: s.keepAliveBackground,
                      onChanged: (v) async {
                        await s.setKeepAliveBackground(v);
                        if (!mounted) return;
                        setState(() {});
                        if (v) await _refreshBatteryWhitelist();
                      },
                    ),
                    if (s.keepAliveBackground && !_batteryWhitelisted)
                      _MeRow(
                        title: '关闭省电限制',
                        subtitle: '未加白名单时系统仍可能冻结后台连接',
                        onTap: () async {
                          await KeepAliveService.instance
                              .requestIgnoreBatteryOptimizations();
                          await _refreshBatteryWhitelist();
                        },
                      ),
                  ],
                  _MeSwitch(
                    title: '仅声音模式',
                    subtitle: '关掉自动朗读，想听的时候再点',
                    value: u.nightMode,
                    onChanged: (v) async {
                      final token = s.accessToken;
                      if (token == null || token.isEmpty) return;
                      try {
                        final user = await s.api().updatePreferences(
                              accessToken: token,
                              nightMode: v,
                            );
                        if (v && s.autoTts) {
                          await s.setAutoTts(false);
                        }
                        await s.applyUser(user);
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(v ? '已开启仅声音模式' : '已关闭仅声音模式'),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(apiErrorMessage(e))),
                        );
                      }
                    },
                  ),
                  _MeSwitch(
                    title: '晚间问候',
                    subtitle: '傍晚她可能先来找你说说话',
                    value: u.eveningGreetingEnabled,
                    onChanged: (v) async {
                      final token = s.accessToken;
                      if (token == null || token.isEmpty) return;
                      try {
                        final user = await s.api().updatePreferences(
                              accessToken: token,
                              eveningGreetingEnabled: v,
                            );
                        await s.applyUser(user);
                        if (!mounted) return;
                        setState(() {});
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(apiErrorMessage(e))),
                        );
                      }
                    },
                  ),
                  _MeSwitch(
                    title: '自动朗读回复',
                    subtitle: u.nightMode
                        ? '仅声音模式下已关闭自动朗读'
                        : '开着时，每句文字和语音一起出来，并自动往下读',
                    value: s.autoTts && !u.nightMode,
                    onChanged: u.nightMode
                        ? null
                        : (v) async {
                            await s.setAutoTts(v);
                            setState(() {});
                          },
                  ),
                ],
              ),
            ],
            if (showDev) ...[
              const SizedBox(height: 26),
              const _SectionLabel('开发'),
              FrostSurface(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (u != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '用户 ID',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    u.id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.copy_rounded,
                                color: AppColors.textSecondary,
                                size: 18,
                              ),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: u.id));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制 user_id')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _baseCtrl!,
                      decoration: frostInputDecoration(
                        labelText: 'API Base URL',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FrostButton(
                      onPressed: () async {
                        await s.setBaseUrl(_baseCtrl!.text.trim());
                        await _ping();
                      },
                      child: const Text('保存并检测'),
                    ),
                    if (_health != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _health!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    _MeSwitch(
                      title: 'SSE 流式回复',
                      subtitle: kIsWeb
                          ? 'Web 也可开；失败会自动回退 JSON'
                          : '打字机效果；失败自动回退 JSON',
                      value: s.useStream,
                      onChanged: (v) async {
                        await s.setUseStream(v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            Center(
              child: TextButton(
                onPressed: () async {
                  await s.logout();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: AppColors.strokeSoft),
                  ),
                ),
                child: const Text(
                  '退出登录',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _onVersionTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  showDev
                      ? '$_versionLabel · ${AppBrand.name} 开发模式${kDebugMode ? '（Debug）' : '（已解锁）'}'
                      : '$_versionLabel · ${AppBrand.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.nickname,
    required this.email,
    required this.bio,
    required this.completed,
    required this.avatar,
    required this.onTap,
  });

  final String nickname;
  final String email;
  final String bio;
  final bool completed;
  final Widget avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = bio.trim().isNotEmpty ? bio.trim() : email;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.strokeStrong, width: 1.4),
            ),
            child: avatar,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          nickname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        if (line.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            line,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.glassSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.strokeSoft),
            ),
            child: Text(
              completed ? '编辑资料' : '完善资料',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MembershipBanner extends StatelessWidget {
  const _MembershipBanner({
    required this.title,
    required this.subtitle,
    required this.member,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool member;
  final VoidCallback onTap;

  static const _peach = Color(0xFFE8B4A0);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: member
                  ? const [Color(0xFF3A2E2C), Color(0xFF242228)]
                  : const [Color(0xFF2A2830), Color(0xFF1C1C22)],
            ),
            border: Border.all(
              color: member ? const Color(0x66E8B4A0) : AppColors.strokeSoft,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _peach.withValues(alpha: member ? 0.22 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: _peach,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  '权益',
                  style: TextStyle(
                    color: _peach,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _peach,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FrostSurface(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Column(
                children: [
                  Icon(icon, size: 22, color: AppColors.textPrimary),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
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
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final items = children.where((w) => w is! SizedBox).toList();
    return FrostSurface(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.strokeSoft,
              ),
            items[i],
          ],
        ],
      ),
    );
  }
}

class _MeSwitch extends StatelessWidget {
  const _MeSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: onChanged == null
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accentCyan.withValues(alpha: 0.55),
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.glassSoft,
          ),
        ],
      ),
    );
  }
}

class _MeRow extends StatelessWidget {
  const _MeRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
