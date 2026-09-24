import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services/app_state.dart';
import 'membership_benefits_page.dart';

/// 旧「星尘充值」入口：已并入 VIP 订阅（开通送星尘）。
class RechargePage extends StatefulWidget {
  const RechargePage({super.key});

  @override
  State<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends State<RechargePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final m = AppStateScope.of(context).user?.membership ?? const Membership();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MembershipBenefitsPage(membership: m),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
