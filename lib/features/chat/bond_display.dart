/// 语音陪伴向：Bond 阶段展示（弱化数值，男客向文案）
class BondDisplay {
  BondDisplay._();

  /// 四阶段后端 id → 三档 UI：初识 / 熟客 / 常客
  static String companionLabel({
    required String stageId,
    String? serverLabel,
  }) {
    switch (stageId) {
      case 'stranger':
        return '初识';
      case 'familiar':
        return '熟客';
      case 'close':
      case 'bonded':
        return '常客';
      default:
        final fb = (serverLabel ?? '').trim();
        return fb.isNotEmpty ? fb : '初识';
    }
  }

  /// 进度条旁短提示（不展示亲密值数字）
  static String progressHint(double progressInStage) {
    final p = progressInStage.clamp(0.0, 1.0);
    if (p >= 0.9) return '再聊几句就更熟了';
    if (p >= 0.55) return '越来越熟';
    if (p >= 0.2) return '慢慢熟悉中';
    return '刚认识';
  }

  /// 阶段升级庆祝文案
  static String stageUpTitle(String stageId) =>
      companionLabel(stageId: stageId);
}
