/// 私聊输入区快捷句 / 表情（轻量，无第三方表情包）
class ChatQuickReplies {
  ChatQuickReplies._();

  static const emojis = <String>[
    '😊',
    '😆',
    '🥺',
    '😌',
    '🥰',
    '😳',
    '🤔',
    '😴',
    '🫡',
    '✨',
    '🌙',
    '☕',
    '📚',
    '🎵',
    '🌧️',
    '🔥',
  ];

  /// 空会话 / 仅开场白时的「开场」推荐
  static List<String> openers({required String personaName}) {
    return companionOpeners(personaName: personaName);
  }

  /// 语音陪伴 · 男客向开场
  static List<String> companionOpeners({required String personaName}) {
    final name = personaName.trim();
    return [
      '在吗',
      '今天有点累',
      '想听你说说话',
      '还没睡吧',
      if (name.isNotEmpty) '嗨，$name',
    ];
  }

  /// 聊起来之后的接话快捷句
  static List<String> followUps() => companionFollowUps();

  /// 语音陪伴 · 接话快捷句
  static List<String> companionFollowUps() => const [
        '嗯',
        '继续说',
        '你呢',
        '哈哈',
        '陪我说会儿话',
        '我有点想你了',
      ];

  /// 聊天输入区上方展示（合并 bond 阶段句）
  static List<String> companionTips({
    required bool greetingOnly,
    required String personaName,
    List<String> bondExtras = const [],
  }) {
    final base = greetingOnly
        ? companionOpeners(personaName: personaName)
        : [...companionFollowUps(), ...bondExtras];
    final seen = <String>{};
    final out = <String>[];
    for (final raw in base) {
      final t = raw.trim();
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      out.add(t);
      if (out.length >= 6) break;
    }
    return out;
  }
}
