import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'features/chat/chat_list_page.dart';
import 'features/personas/persona_list_page.dart';
import 'features/settings/settings_page.dart';
import 'services/app_lifecycle_bridge.dart';
import 'services/app_state.dart';
import 'services/group_ws_manager.dart';
import 'theme/app_theme.dart';
import 'theme/app_widgets.dart';

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  int _index = 0; // 默认首页（角色）

  /// 后台超过这个时长，回前台时重连一次，避免 socket 已被系统静默掐断
  static const _staleAfter = Duration(seconds: 30);

  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = AppStateScope.of(context);
      unawaited(s.syncKeepAlive());
      unawaited(s.syncPush());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final s = AppStateScope.of(context);
    // 进后台时释放未使用的图片内存，降低被系统杀进程概率
    if (state == AppLifecycleState.paused) {
      final cache = PaintingBinding.instance.imageCache;
      cache.clearLiveImages();
      cache.maximumSizeBytes = 48 << 20; // 48MB
      _backgroundedAt = DateTime.now();
      if (s.keepAliveWanted) {
        // 常驻服务保住进程，长连接继续收消息
        unawaited(s.syncKeepAlive());
      } else {
        GroupWsManager.instance.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
      final away = _backgroundedAt;
      _backgroundedAt = null;
      if (s.keepAliveWanted) {
        final stale = away == null ||
            DateTime.now().difference(away) > _staleAfter;
        unawaited(
          stale
              ? GroupWsManager.instance.reconnect()
              : GroupWsManager.instance.syncGroups(),
        );
      } else {
        unawaited(GroupWsManager.instance.resume());
      }
      unawaited(s.syncKeepAlive());
    }
  }

  Future<void> _onRootBackInvoked() async {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    await AppLifecycleBridge.moveToBackground();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const PersonaListPage(),
      ChatListPage(isActive: _index == 1),
      const SettingsPage(),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onRootBackInvoked();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: FrostNavBar(
          index: _index,
          onChanged: (i) => setState(() => _index = i),
          items: const [
            FrostNavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: '首页',
            ),
            FrostNavItem(
              icon: Icons.forum_outlined,
              selectedIcon: Icons.forum_rounded,
              label: '聊天',
            ),
            FrostNavItem(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
