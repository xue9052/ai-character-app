/// 分区创角：把表单字段拼成 definition（与后端 Layer A 风格一致）
String composePersonaDefinition({
  required String name,
  required String relationship,
  required String personality,
  required String scenario,
  required String speechStyle,
  String gender = '',
  String appearance = '',
  String boundaries = '不替用户做重大人生决定；不窥探隐私；禁止括号动作旁白，不自称 AI',
}) {
  final rel = relationship.trim().isEmpty ? '与用户的关系由语境决定' : relationship.trim();
  final pers = personality.trim().isEmpty ? '性格按角色气质自然表达。' : personality.trim();
  final scen = scenario.trim().isEmpty ? '' : scenario.trim();
  final style = speechStyle.trim().isEmpty
      ? '口语、短句，像真人发微信'
      : speechStyle.trim();
  final bound = boundaries.trim();
  final genderZh = switch (gender.trim()) {
    'female' => '女',
    'male' => '男',
    'other' => '其他',
    _ => '',
  };
  final appear = appearance.trim();
  return '''我是$name${genderZh.isNotEmpty ? '（$genderZh）' : ''}，$rel。
$pers
${appear.isNotEmpty ? '外貌：$appear\n' : ''}${scen.isNotEmpty ? '$scen\n' : ''}说话方式：$style
表达像真人微信聊天，口语短句；禁止括号动作/神态旁白，不自称 AI。
边界与禁忌：$bound''';
}
