import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_state.dart';
import '../../services/dev_flags.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';
import 'register_page.dart';
import 'reset_password_page.dart';

/// 对齐 Soulora 登录示意：柔紫氛围背景 + 毛玻璃卡 + 衬线品牌 + 渐变登录按钮
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _titleColor = AppColors.textPrimary;
  static const _labelColor = AppColors.textSecondary;
  static const _hintColor = AppColors.textMuted;
  static const _linkColor = AppColors.textSecondary;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _base = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _showServer = false;
  String? _connHint;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppStateScope.of(context);
    if (_base.text.isEmpty) _base.text = s.baseUrl;
  }

  Future<void> _pingApi() async {
    final base = _base.text.trim();
    if (base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 API 地址')),
      );
      return;
    }
    final s = AppStateScope.of(context);
    setState(() => _connHint = '检测中…');
    try {
      await s.setBaseUrl(base);
      final h = await s.api().health();
      if (!mounted) return;
      setState(() => _connHint = '已连接 · ${h['model_profile'] ?? 'ok'}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _connHint = '未连接：${apiErrorMessage(e)}');
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _base.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入邮箱和密码')),
      );
      return;
    }
    final s = AppStateScope.of(context);
    setState(() => _busy = true);
    try {
      final base = _base.text.trim().isNotEmpty ? _base.text.trim() : s.baseUrl;
      await s.setBaseUrl(base);
      final session = await s.api().login(email: email, password: password);
      await s.applySession(session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return frostInputDecoration(hintText: hint, suffixIcon: suffixIcon);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 示意同款柔紫室内氛围底图
          Image.asset(
            'assets/images/login_bg.png',
            fit: BoxFit.cover,
            width: size.width,
            height: size.height,
            errorBuilder: (_, __, ___) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE8DFF8),
                    Color(0xFFD4C4F0),
                    Color(0xFFF0D6E8),
                    Color(0xFFC9B8E8),
                  ],
                ),
              ),
            ),
          ),
          // 轻微提亮，让毛玻璃更透
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
            ),
          ),
          // 示意中的光弧
          Center(
            child: IgnorePointer(
              child: CustomPaint(
                size: Size(size.width * 0.92, size.height * 0.55),
                painter: _GlowArcPainter(),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _FrostedLoginCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 6),
                        const Center(
                          child: SouloraMark(size: 64),
                        ),
                        const SizedBox(height: 12),
                        // 品牌：衬线 + 上方小光弧
                        SizedBox(
                          height: 56,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                top: 2,
                                child: CustomPaint(
                                  size: const Size(72, 22),
                                  painter: _BrandSparkPainter(),
                                ),
                              ),
                              Text(
                                'Soulora',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w600,
                                  color: _titleColor,
                                  letterSpacing: 0.4,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                height: 1,
                                thickness: 0.8,
                                color: _labelColor.withValues(alpha: 0.28),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                AppBrand.tagline,
                                style: TextStyle(
                                  color: _labelColor.withValues(alpha: 0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                height: 1,
                                thickness: 0.8,
                                color: _labelColor.withValues(alpha: 0.28),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        if (_showServer || DevFlags.showDevTools) ...[
                          const Text(
                            '服务器',
                            style: TextStyle(
                              color: _labelColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _base,
                            style: const TextStyle(
                              color: _titleColor,
                              fontSize: 14,
                            ),
                            decoration: _fieldDecoration(
                              hint: 'API 地址',
                              suffixIcon: IconButton(
                                tooltip: '检测连接',
                                onPressed: _busy ? null : _pingApi,
                                icon: const Icon(
                                  Icons.wifi_find_outlined,
                                  color: _hintColor,
                                ),
                              ),
                            ),
                          ),
                          if (_connHint != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _connHint!,
                              style: TextStyle(
                                fontSize: 12,
                                color: _connHint!.startsWith('已连接')
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                        const Text(
                          '邮箱',
                          style: TextStyle(
                            color: _labelColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          style: const TextStyle(
                            color: _titleColor,
                            fontSize: 15,
                          ),
                          decoration: _fieldDecoration(hint: '请输入邮箱地址'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '密码',
                          style: TextStyle(
                            color: _labelColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _login(),
                          style: const TextStyle(
                            color: _titleColor,
                            fontSize: 15,
                          ),
                          decoration: _fieldDecoration(
                            hint: '请输入密码',
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: _hintColor,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        FrostButton(
                          onPressed: _busy ? null : _login,
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppColors.textPrimary,
                                  ),
                                )
                              : const Text('登录'),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: _linkColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const ResetPasswordPage(),
                                        ),
                                      );
                                    },
                              child: const Text(
                                '忘记密码',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 12,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              color: _linkColor.withValues(alpha: 0.35),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: _linkColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const RegisterPage(),
                                        ),
                                      );
                                    },
                              child: const Text(
                                '注册',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () =>
                              setState(() => _showServer = !_showServer),
                          style: TextButton.styleFrom(
                            foregroundColor: _hintColor,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            _showServer ? '收起服务器设置' : '服务器设置',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedLoginCard extends StatelessWidget {
  const _FrostedLoginCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: AppColors.glassSoft,
            border: Border.all(
              color: AppColors.strokeStrong,
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 36,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 卡片背后的大光弧（示意同款）
class _GlowArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final radius = size.width * 0.42;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = SweepGradient(
        startAngle: -1.2,
        endAngle: 1.8,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.55),
          const Color(0xFFE8DEFF).withValues(alpha: 0.9),
          Colors.white.withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.05,
      2.1,
      false,
      paint,
    );

    // 弧上高光点
    final spark = Offset(
      center.dx + radius * 0.72,
      center.dy - radius * 0.55,
    );
    canvas.drawCircle(
      spark,
      3.2,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Soulora 标题上方的小流星弧
class _BrandSparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.48,
        size.height * 0.05,
        size.width * 0.88,
        size.height * 0.55,
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = Colors.white.withValues(alpha: 0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.48),
      2.4,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
