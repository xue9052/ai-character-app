import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../services/app_state.dart';

class RebindEmailPage extends StatefulWidget {
  const RebindEmailPage({super.key});

  @override
  State<RebindEmailPage> createState() => _RebindEmailPageState();
}

class _RebindEmailPageState extends State<RebindEmailPage> {
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
        const SnackBar(content: Text('请先填写新邮箱')),
      );
      return;
    }
    final s = AppStateScope.of(context);
    final token = s.accessToken;
    if (token == null) return;
    setState(() => _sending = true);
    try {
      final data = await s.api().sendEmailCode(
            email: email,
            purpose: 'rebind_email',
            accessToken: token,
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
                ? '验证码已发送到新邮箱'
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
    final token = s.accessToken;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final session = await s.api().rebindEmail(
            accessToken: token,
            newEmail: _email.text.trim(),
            code: _code.text.trim(),
            password: _password.text,
          );
      await s.applySession(session);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邮箱已更换')),
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
    final current = AppStateScope.of(context).user?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('换绑邮箱')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (current.isNotEmpty)
            Text(
              '当前邮箱：$current',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '新邮箱',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: (_sending || _cooldown > 0) ? null : _sendCode,
                child: Text(
                  _cooldown > 0
                      ? '${_cooldown}s'
                      : (_sending ? '发送中' : '获取验证码'),
                ),
              ),
            ],
          ),
          if (_devHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _devHint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '当前密码（确认身份）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '提交中…' : '确认换绑'),
          ),
        ],
      ),
    );
  }
}