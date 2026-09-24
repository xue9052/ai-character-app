import 'package:flutter/material.dart';

import '../../api/api_exception.dart';
import '../../services/app_state.dart';
import '../../theme/app_widgets.dart';
import 'email_code_cooldown.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> with EmailCodeCooldown {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _busy = false;
  bool _sending = false;
  String? _devHint;

  @override
  void dispose() {
    disposeEmailCodeCooldown();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
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
        purpose: 'register',
      );
      final dev = data['dev_code']?.toString();
      final wait = (data['retry_after'] as num?)?.toInt() ??
          (data['cooldown'] as num?)?.toInt() ??
          60;
      setState(() {
        _devHint = (dev != null && dev.isNotEmpty) ? '开发模式验证码：$dev' : null;
      });
      startEmailCodeCooldown(wait);
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
        startEmailCodeCooldown(e.retryAfter!);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _register() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    final p1 = _password.text;
    final p2 = _password2.text;
    if (email.isEmpty || code.isEmpty || p1.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写邮箱、验证码和密码')),
      );
      return;
    }
    if (p1.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码至少 8 位')),
      );
      return;
    }
    if (p1 != p2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次密码不一致')),
      );
      return;
    }
    final s = AppStateScope.of(context);
    setState(() => _busy = true);
    try {
      final session = await s.api().register(
        email: email,
        code: code,
        password: p1,
      );
      await s.applySession(session);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        SnackBar(
          content: Text('注册成功，昵称「${session.user.nickname}」已自动生成'),
        ),
      );
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
      appBar: AppBar(title: const Text('注册')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '邮箱验证后即可开聊。注册成功会随机分配昵称和头像，资料以后再完善。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
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
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: FrostButton(
                  expanded: false,
                  height: 56,
                  onPressed: (_sending || cooldown > 0) ? null : _sendCode,
                  child: Text(cooldown > 0 ? '${cooldown}s' : '获取验证码'),
                ),
              ),
            ],
          ),
          if (_devHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _devHint!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码（至少 8 位）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password2,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '确认密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FrostButton(
            onPressed: _busy ? null : _register,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('注册并进入'),
          ),
        ],
      ),
    );
  }
}
