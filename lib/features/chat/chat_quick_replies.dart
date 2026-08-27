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
    final name = personaName.trim();
    return [
      '你好呀',
      '在吗～',
      '今天过得怎么样？',
      '想和你聊聊天',
      if (name.isNotEmpty) '嗨，$name',
    ];
  }

  /// 聊起来之后的接话快捷句
  static List<String> followUps() => const [
        '然后呢？',
        '真的吗',
        '我也这么想',
        '再说细一点？',
        '哈哈',
        '嗯嗯',
      ];
}
