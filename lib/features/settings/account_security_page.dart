import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../services/app_state.dart';
import 'change_password_page.dart';
import 'rebind_email_page.dart';

class AccountSecurityPage extends StatelessWidget {
  const AccountSecurityPage({super.key});

  Future<void> _deleteAccount(BuildContext context) async {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('注销账号'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '将永久删除账号、聊天、记忆与自定义角色，且不可恢复。',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                decoration: const InputDecoration(
                  labelText: '输入 DELETE 确认',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认注销'),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) {
      passwordCtrl.dispose();
      confirmCtrl.dispose();
      return;
    }

    final s = AppStateScope.of(context);
    final token = s.accessToken;
    if (token == null) {
      passwordCtrl.dispose();
      confirmCtrl.dispose();
      return;
    }
    try {
      await s.api().deleteAccount(
            accessToken: token,
            password: passwordCtrl.text,
            confirm: confirmCtrl.text.trim(),
          );
      await s.logout();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号已注销')),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    } finally {
      passwordCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = AppStateScope.of(context).user?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('账号安全')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('修改密码'),
            subtitle: const Text('登录状态下验证旧密码后更换'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
              );
            },
          ),
          ListTile(
            title: const Text('换绑邮箱'),
            subtitle: Text(email.isEmpty ? '验证新邮箱后更换登录邮箱' : '当前：$email'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RebindEmailPage()),
              );
            },
          ),
          const Divider(height: 32),
          ListTile(
            title: Text(
              '注销账号',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('删除账号及全部相关数据'),
            onTap: () => _deleteAccount(context),
          ),
        ],
      ),
    );
  }
}
