import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../services/app_state.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _sending = false;
  int _cooldown = 0;
  String? _devHint;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _tickCooldown() {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted || _cooldown <= 0) return false;
      setState(() => _cooldown -= 1);
      return _cooldown > 0;
    });
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写邮箱')),
      );
      return;
    }
    final s = AppStateScope.of(context);
    setState(() => _sending = true);
    try {
      final data = await s.api().sendEmailCode(
        email: email,
        purpose: 'reset_password',
      );
      final dev = data['dev_code']?.toString();
      setState(() {
        _cooldown = (data['retry_after'] as num?)?.toInt() ??
            (data['cooldown'] as num?)?.toInt() ??
            60;
        _devHint = (dev != null && dev.isNotEmpty) ? '开发模式验证码：$dev' : null;
      });
      _tickCooldown();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['smtp_configured'] == true
                ? '验证码已发送，请查收邮件（含垃圾箱）'
                : '验证码已生成（服务器未配 SMTP，见下方开发提示）',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.retryAfter != null && e.retryAfter! > 0) {
        setState(() => _cooldown = e.retryAfter!);
        _tickCooldown();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    final s = AppStateScope.of(context);
    setState(() => _busy = true);
    try {
      final session = await s.api().resetPassword(
        email: _email.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      await s.applySession(session);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已重置，已自动登录')),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
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
      appBar: AppBar(title: const Text('重置密码')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: (_sending || _cooldown > 0) ? null : _sendCode,
                child: Text(_cooldown > 0 ? '${_cooldown}s' : '获取验证码'),
              ),
            ],
          ),
          if (_devHint != null) ...[
            const SizedBox(height: 8),
            Text(_devHint!, style: TextStyle(color: Colors.orange.shade200)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '新密码（至少 8 位）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '提交中…' : '重置并登录'),
          ),
        ],
      ),
    );
  }
}
