import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_exception.dart';
import '../../services/app_state.dart';
import '../../services/dev_flags.dart';
import '../../services/push_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';
import '../personas/persona_workshop_page.dart';
import 'account_security_page.dart';
import 'edit_profile_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TextEditingController? _baseCtrl;
  String? _health;
  int _versionTaps = 0;

  static const _versionLabel = 'v0.1.0';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppStateScope.of(context);
    _baseCtrl ??= TextEditingController(text: s.baseUrl);
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    final u = s.user;
    final showDev = DevFlags.showDevTools;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (u != null) ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfilePage()),
                );
                if (mounted) setState(() {});
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    UserAvatar(
                      emoji: u.avatarEmoji,
                      colorHex: u.avatarColor,
                      imageUrl: s.absoluteAvatarUrl(u.avatarUrl),
                      radius: 32,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.nickname,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            u.email,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          if (u.bio.trim().isNotEmpty)
                            Text(
                              u.bio,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          Text(
                            u.profileCompleted ? '编辑资料' : '完善资料',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('我的角色'),
              subtitle: const Text('创作中心 · 审核状态'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PersonaWorkshopPage(),
                  ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('账号安全'),
              subtitle: const Text('改密码、换绑邮箱、注销'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountSecurityPage(),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
            if (showDev)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('用户 ID'),
                subtitle: Text(u.id),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: u.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制 user_id')),
                    );
                  },
                ),
              ),
            const Divider(height: 28),
            if (!kIsWeb && PushService.supported)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('主动关怀推送'),
                subtitle: Text(
                  Platform.isIOS
                      ? 'iOS 系统通知提醒（极光推送；默认关）'
                      : 'Android 系统通知栏提醒（极光推送；默认关）',
                ),
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
            if (!kIsWeb && PushService.supported && s.pushReminders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('发送测试推送'),
                subtitle: const Text('确认通知栏能否收到'),
                trailing: const Icon(Icons.notifications_active_outlined),
                onTap: () async {
                  try {
                    await s.api().testPush(userId: s.userId);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已发送，请看通知栏')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(apiErrorMessage(e))),
                    );
                  }
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动朗读回复'),
              subtitle: const Text('播一句出一句字，不先把全文打在气泡里'),
              value: s.autoTts,
              onChanged: (v) async {
                await s.setAutoTts(v);
                setState(() {});
              },
            ),
          ],
          if (showDev) ...[
            Text(
              '开发选项',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseCtrl!,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                helperMaxLines: 4,
                helperText:
                    '云端默认: http://124.221.29.21:8501\n'
                    '本机调试: http://127.0.0.1:8000 / 模拟器 http://10.0.2.2:8000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                await s.setBaseUrl(_baseCtrl!.text.trim());
                await _ping();
              },
              child: const Text('保存并检测'),
            ),
            if (_health != null) ...[
              const SizedBox(height: 8),
              Text(_health!),
            ],
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('SSE 流式回复'),
              subtitle: Text(
                kIsWeb
                    ? 'Web 也可开；失败会自动回退 JSON'
                    : '打字机效果；失败自动回退 JSON（推荐开启）',
              ),
              value: s.useStream,
              onChanged: (v) async {
                await s.setUseStream(v);
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: () async {
              await s.logout();
            },
            child: const Text('退出登录'),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _onVersionTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                showDev
                    ? '$_versionLabel · 开发模式${kDebugMode ? '（Debug）' : '（已解锁）'}'
                    : '$_versionLabel · AI 虚拟角色',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
