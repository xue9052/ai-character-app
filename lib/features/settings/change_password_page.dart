import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../services/app_state.dart';
import '../../theme/app_widgets.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _old = TextEditingController();
  final _next = TextEditingController();
  final _next2 = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _next.dispose();
    _next2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('新密码至少 8 位')),
      );
      return;
    }
    if (_next.text != _next2.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次新密码不一致')),
      );
      return;
    }
    final s = AppStateScope.of(context);
    final token = s.accessToken;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final session = await s.api().changePassword(
            accessToken: token,
            oldPassword: _old.text,
            newPassword: _next.text,
          );
      await s.applySession(session);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已更新')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _old,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '当前密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '新密码（至少 8 位）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next2,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '确认新密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FrostButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '提交中…' : '保存'),
          ),
        ],
      ),
    );
  }
}
