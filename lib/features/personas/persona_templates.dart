/// 创角模板（优先从 API / 数据库拉取；失败时用本地兜底）
class PersonaTemplate {
  const PersonaTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.suggestedName,
    required this.oneLiner,
    required this.definition,
    required this.greeting,
    this.coverColor = '#5B8A72',
    this.coverUrl,
    this.hasCover = false,
    this.voiceProfileId,
  });

  final String id;
  final String title;
  final String subtitle;
  final String emoji;
  final String suggestedName;
  final String oneLiner;
  final String definition;
  final String greeting;
  final String coverColor;
  final String? coverUrl;
  final bool hasCover;
  final String? voiceProfileId;

  factory PersonaTemplate.fromJson(Map<String, dynamic> j) {
    final rawVoice = '${j['voice_profile_id'] ?? ''}'.trim();
    return PersonaTemplate(
      id: (j['id'] as String?) ?? '',
      title: (j['title'] as String?) ?? '',
      subtitle: (j['subtitle'] as String?) ?? '',
      emoji: (j['emoji'] as String?)?.isNotEmpty == true
          ? j['emoji'] as String
          : '🎭',
      suggestedName: (j['suggested_name'] as String?) ?? '',
      oneLiner: (j['one_liner'] as String?) ?? '',
      definition: (j['definition'] as String?) ?? '',
      greeting: (j['greeting'] as String?) ?? '',
      coverColor: (j['cover_color'] as String?)?.isNotEmpty == true
          ? j['cover_color'] as String
          : '#5B8A72',
      coverUrl: j['cover_url'] as String?,
      hasCover: j['has_cover'] == true,
      voiceProfileId: rawVoice.isEmpty ? null : rawVoice,
    );
  }
}

/// 本地兜底（API 不可用时）；权威数据在服务端数据库
const List<PersonaTemplate> kPersonaTemplatesFallback = [
  PersonaTemplate(
    id: 'roommate',
    title: '室友',
    subtitle: '合租日常 · 拌嘴也亲近',
    emoji: '🏠',
    suggestedName: '陈澄',
    oneLiner: '和你合租的室友，嘴上嫌弃家里乱，其实会默默把你的杯子洗好放回原位。',
    definition: '我是你的合租室友。',
    greeting: '你钥匙声一响我就知道是你。',
  ),
];

/// @Deprecated('用 API；保留别名以免旧引用报错')
const List<PersonaTemplate> kPersonaTemplates = kPersonaTemplatesFallback;
