/// 广场可选标签（与后端 PERSONA_TAG_PRESETS 对齐）
const kPersonaTagPresets = <String>[
  '温柔',
  '强势',
  '吐槽',
  '治愈',
  '青梅',
  '室友',
  '同事',
  '书友',
  '执事',
  '甜宠',
  '悬疑',
  '幻想',
];

const kCoverColors = <String>[
  '#5B8A72',
  '#6B7C9C',
  '#B07D62',
  '#7A6B8A',
  '#8A6D4F',
  '#4F7A8A',
  '#7B6CF6',
  '#C478A8',
];

const kCoverEmojis = <String>[
  '🎭',
  '🌙',
  '✨',
  '🦊',
  '🌹',
  '🦋',
  '💫',
  '🎸',
  '📖',
  '🍷',
  '🔮',
  '🪽',
];

/// 按名字稳定分配创建时的默认表情 / 色 / 场景（与后端 persona_visuals 思路一致）
({String emoji, String color, String backgroundKey}) pickCreateVisualDefaults(
  String name, {
  List<String> tags = const [],
}) {
  final seed = name.trim().isEmpty ? 'persona' : name.trim();
  var h = 0;
  for (final u in seed.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  final emojiPool = <String>[...kCoverEmojis];
  // 简单标签偏好
  const tagMap = <String, List<String>>{
    '温柔': ['🌸', '💗', '🌙'],
    '治愈': ['🌿', '☀️', '💚'],
    '甜宠': ['🎀', '💗', '🥰'],
    '强势': ['🔥', '👑', '⚔️'],
    '吐槽': ['😏', '😼', '💬'],
    '幻想': ['🪄', '🌌', '🔮'],
    '悬疑': ['🕵️', '🌑', '🗝️'],
  };
  for (final t in tags) {
    for (final e in tagMap[t] ?? const <String>[]) {
      if (!emojiPool.contains(e)) emojiPool.insert(0, e);
    }
  }
  final bgKeys = [for (final p in kBackgroundPresets) p['key']!];
  return (
    emoji: emojiPool[h % emojiPool.length],
    color: kCoverColors[(h ~/ 7) % kCoverColors.length],
    backgroundKey: bgKeys[(h ~/ 13) % bgKeys.length],
  );
}

/// 聊天场景模板（命名对齐猫箱；与后端 BACKGROUND_PRESETS 对齐）
const kBackgroundPresets = <Map<String, String>>[
  {
    'key': 'bg_default',
    'name': '窗台午后',
    'color_from': '#3A4A3A',
    'color_mid': '#1E2A1E',
    'color_to': '#0E1410',
  },
  {
    'key': 'bg_mist',
    'name': '星空书房',
    'color_from': '#1A2840',
    'color_mid': '#121C30',
    'color_to': '#0A1018',
  },
  {
    'key': 'bg_warm',
    'name': '雨夜咖啡馆',
    'color_from': '#3A2A1E',
    'color_mid': '#241810',
    'color_to': '#120E0A',
  },
  {
    'key': 'bg_violet',
    'name': '暮色窗台',
    'color_from': '#3A2848',
    'color_mid': '#221830',
    'color_to': '#100C18',
  },
  {
    'key': 'bg_ocean',
    'name': '深空书房',
    'color_from': '#143048',
    'color_mid': '#0E2030',
    'color_to': '#081018',
  },
  {
    'key': 'bg_rose',
    'name': '樱花小径',
    'color_from': '#4A2838',
    'color_mid': '#2A1822',
    'color_to': '#140C10',
  },
];
