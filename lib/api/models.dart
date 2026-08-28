import 'dart:convert';

class AuthUser {
  AuthUser({
    required this.id,
    required this.email,
    required this.nickname,
    required this.avatarKey,
    required this.avatarEmoji,
    required this.avatarColor,
    this.avatarUrl = '',
    this.bio = '',
    this.profileCompleted = false,
  });

  final String id;
  final String email;
  final String nickname;
  final String avatarKey;
  final String avatarEmoji;
  final String avatarColor;
  final String avatarUrl;
  final String bio;
  final bool profileCompleted;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: '${j['id']}',
        email: '${j['email'] ?? ''}',
        nickname: '${j['nickname'] ?? ''}',
        avatarKey: '${j['avatar_key'] ?? 'a01'}',
        avatarEmoji: '${j['avatar_emoji'] ?? '🌙'}',
        avatarColor: '${j['avatar_color'] ?? '#5B7C99'}',
        avatarUrl: '${j['avatar_url'] ?? ''}',
        bio: '${j['bio'] ?? ''}',
        profileCompleted: j['profile_completed'] == true,
      );
}

class AvatarPreset {
  AvatarPreset({
    required this.key,
    required this.emoji,
    required this.color,
  });

  final String key;
  final String emoji;
  final String color;

  factory AvatarPreset.fromJson(Map<String, dynamic> j) => AvatarPreset(
        key: '${j['key']}',
        emoji: '${j['emoji'] ?? '🌙'}',
        color: '${j['color'] ?? '#5B7C99'}',
      );
}

class AuthSession {
  AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
        accessToken: '${j['access_token']}',
        user: AuthUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
      );
}

class PersonaSummary {
  PersonaSummary({
    required this.id,
    required this.name,
    this.oneLiner,
    this.source,
    this.reviewStatus,
    this.reviewReason,
    this.ownerUserId,
    this.mine = false,
    this.visibility,
    this.tags = const [],
    this.coverEmoji,
    this.coverColor,
    this.coverUrl,
    this.backgroundKey,
    this.backgroundUrl,
    this.featured = false,
    this.chatterCount,
    this.recentChatted = false,
  });

  final String id;
  final String name;
  final String? oneLiner;
  final String? source;
  final String? reviewStatus;
  final String? reviewReason;
  final String? ownerUserId;
  final bool mine;
  final String? visibility;
  final List<String> tags;
  final String? coverEmoji;
  final String? coverColor;
  final String? coverUrl;
  final String? backgroundKey;
  final String? backgroundUrl;
  final bool featured;
  final int? chatterCount;
  final bool recentChatted;

  bool get isOfficial =>
      id == 'aurora' ||
      source == 'builtin' ||
      ownerUserId == 'u_seed_official';
  bool get isCustom => source == 'custom' || id.startsWith('c_');
  bool get isPending => reviewStatus == 'pending';
  bool get isRejected => reviewStatus == 'rejected';
  bool get isApproved =>
      reviewStatus == null || reviewStatus == 'approved' || reviewStatus!.isEmpty;
  bool get isPrivate => visibility == 'private';
  bool get isPublic => visibility == 'public' || visibility == null;

  factory PersonaSummary.fromJson(Map<String, dynamic> j) => PersonaSummary(
        id: '${j['id']}',
        name: '${j['name'] ?? j['id']}',
        oneLiner: j['one_liner'] as String?,
        source: j['source'] as String?,
        reviewStatus: j['review_status'] as String?,
        reviewReason: j['review_reason'] as String?,
        ownerUserId: j['owner_user_id']?.toString(),
        mine: j['mine'] == true,
        visibility: j['visibility'] as String?,
        tags: [
          for (final t in (j['tags'] as List? ?? const [])) '$t',
        ],
        coverEmoji: j['cover_emoji'] as String?,
        coverColor: j['cover_color'] as String?,
        coverUrl: j['cover_url'] as String?,
        backgroundKey: j['background_key'] as String?,
        backgroundUrl: j['background_url'] as String?,
        featured: j['featured'] == true,
        chatterCount: (j['chatter_count'] as num?)?.toInt(),
        recentChatted: j['recent_chatted'] == true,
      );
}

class PlazaFeed {
  PlazaFeed({
    required this.strip,
    required this.grid,
    this.tagPresets = const [],
  });

  final List<PersonaSummary> strip;
  final List<PersonaSummary> grid;
  final List<String> tagPresets;

  @Deprecated('use strip')
  List<PersonaSummary> get featured => strip;

  @Deprecated('use grid')
  List<PersonaSummary> get all => grid;
}

class PersonaSearchResult {
  PersonaSearchResult({
    required this.items,
    this.tagPresets = const [],
  });

  final List<PersonaSummary> items;
  final List<String> tagPresets;

  factory PersonaSearchResult.fromJson(Map<String, dynamic> j) =>
      PersonaSearchResult(
        items: [
          for (final p in (j['items'] as List? ?? const []))
            PersonaSummary.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        tagPresets: [
          for (final t in (j['tag_presets'] as List? ?? const [])) '$t',
        ],
      );
}

class PersonaDetail {
  PersonaDetail({
    required this.id,
    required this.name,
    this.oneLiner,
    this.definition,
    this.greeting,
    this.source,
    this.reviewStatus,
    this.reviewReason,
    this.ownerUserId,
    this.definitionHidden = false,
    this.visibility,
    this.tags = const [],
    this.coverEmoji,
    this.coverColor,
    this.coverUrl,
    this.backgroundKey,
    this.backgroundUrl,
    this.alternateGreetings = const [],
    this.voiceProfileId,
    this.gender,
    this.scenario,
    this.appearance,
    this.relationshipToUser,
    this.personality = const [],
    this.speechStyle,
  });

  final String id;
  final String name;
  final String? oneLiner;
  final String? definition;
  final String? greeting;
  final String? source;
  final String? reviewStatus;
  final String? reviewReason;
  final String? ownerUserId;
  final bool definitionHidden;
  final String? visibility;
  final List<String> tags;
  final String? coverEmoji;
  final String? coverColor;
  final String? coverUrl;
  final String? backgroundKey;
  final String? backgroundUrl;
  final List<String> alternateGreetings;
  final String? voiceProfileId;
  final String? gender;
  final String? scenario;
  final String? appearance;
  final String? relationshipToUser;
  final List<String> personality;
  final String? speechStyle;

  bool get isOfficial =>
      id == 'aurora' ||
      source == 'builtin' ||
      ownerUserId == 'u_seed_official';
  bool get isCustom => source == 'custom' || id.startsWith('c_');
  bool get isPending => reviewStatus == 'pending';
  bool get isRejected => reviewStatus == 'rejected';
  bool get isPrivate => visibility == 'private';

  bool isOwnedBy(String? userId) =>
      userId != null && ownerUserId != null && ownerUserId == userId;

  factory PersonaDetail.fromJson(Map<String, dynamic> j) => PersonaDetail(
        id: '${j['id']}',
        name: '${j['name'] ?? j['id']}',
        oneLiner: j['one_liner'] as String?,
        definition: j['definition'] as String? ?? j['custom_prompt'] as String?,
        greeting: j['greeting'] as String?,
        source: j['source'] as String? ??
            (j['owner_user_id'] != null ? 'custom' : null),
        reviewStatus: j['review_status'] as String?,
        reviewReason: j['review_reason'] as String?,
        ownerUserId: j['owner_user_id']?.toString(),
        definitionHidden: j['definition_hidden'] == true,
        visibility: j['visibility'] as String?,
        tags: [
          for (final t in (j['tags'] as List? ?? const [])) '$t',
        ],
        coverEmoji: j['cover_emoji'] as String?,
        coverColor: j['cover_color'] as String?,
        coverUrl: j['cover_url'] as String?,
        backgroundKey: j['background_key'] as String?,
        backgroundUrl: j['background_url'] as String?,
        alternateGreetings: [
          for (final g in (j['alternate_greetings'] as List? ?? const [])) '$g',
        ],
        voiceProfileId: (j['voice_profile_id'] as String?)?.trim().isEmpty == true
            ? null
            : j['voice_profile_id'] as String?,
        gender: (j['gender'] as String?)?.trim().isEmpty == true
            ? null
            : j['gender'] as String?,
        scenario: (j['scenario'] as String?)?.trim().isEmpty == true
            ? null
            : j['scenario'] as String?,
        appearance: (j['appearance'] as String?)?.trim().isEmpty == true
            ? null
            : j['appearance'] as String?,
        relationshipToUser: (j['relationship_to_user'] as String?)?.trim().isEmpty == true
            ? null
            : j['relationship_to_user'] as String?,
        personality: [
          for (final t in (j['personality'] as List? ?? const [])) '$t',
        ],
        speechStyle: (j['speech_style'] as String?)?.trim().isEmpty == true
            ? null
            : j['speech_style'] as String?,
      );
}

class BackgroundPreset {
  BackgroundPreset({
    required this.key,
    required this.name,
    required this.colorFrom,
    required this.colorTo,
    this.colorMid,
  });

  final String key;
  final String name;
  final String colorFrom;
  final String colorTo;
  final String? colorMid;

  factory BackgroundPreset.fromJson(Map<String, dynamic> j) => BackgroundPreset(
        key: '${j['key']}',
        name: '${j['name'] ?? j['key']}',
        colorFrom: '${j['color_from'] ?? '#1A221A'}',
        colorTo: '${j['color_to'] ?? '#0E1410'}',
        colorMid: j['color_mid'] as String?,
      );
}

class LookStyle {
  LookStyle({
    required this.key,
    required this.name,
    required this.category,
    required this.color,
    this.badge = '',
  });

  final String key;
  final String name;
  final String category;
  final String color;
  final String badge;

  factory LookStyle.fromJson(Map<String, dynamic> j) => LookStyle(
        key: '${j['key']}',
        name: '${j['name'] ?? j['key']}',
        category: '${j['category'] ?? '精选'}',
        color: '${j['color'] ?? '#5B7C99'}',
        badge: '${j['badge'] ?? ''}',
      );
}

class LookStylesPayload {
  LookStylesPayload({required this.categories, required this.styles});

  final List<String> categories;
  final List<LookStyle> styles;

  factory LookStylesPayload.fromJson(Map<String, dynamic> j) => LookStylesPayload(
        categories: [
          for (final c in (j['categories'] as List? ?? const [])) '$c',
        ],
        styles: [
          for (final s in (j['styles'] as List? ?? const []))
            if (s is Map) LookStyle.fromJson(Map<String, dynamic>.from(s)),
        ],
      );
}

class GeneratedLook {
  GeneratedLook({
    required this.bytes,
    this.provider,
    this.model,
    this.contentType = 'image/jpeg',
  });

  final List<int> bytes;
  final String? provider;
  final String? model;
  final String contentType;

  factory GeneratedLook.fromJson(Map<String, dynamic> j) {
    final b64 = '${j['image_base64'] ?? ''}';
    if (b64.isEmpty) {
      throw Exception('未返回图片数据');
    }
    return GeneratedLook(
      bytes: base64Decode(b64),
      provider: j['provider'] as String?,
      model: j['model'] as String?,
      contentType: '${j['content_type'] ?? 'image/jpeg'}',
    );
  }
}


class ChatMessageDto {
  ChatMessageDto({
    this.id,
    required this.role,
    required this.content,
    this.ts,
    this.type = 'text',
    this.imageUrls = const [],
    this.audioUrl,
    this.ttsChunks = const [],
  });

  final String? id;
  final String role;
  final String content;
  final int? ts;
  final String type;
  final List<String> imageUrls;
  final String? audioUrl;
  final List<Map<String, dynamic>> ttsChunks;

  factory ChatMessageDto.fromJson(Map<String, dynamic> j) {
    final rawTs = j['ts'] ?? j['created_at'];
    int? ts;
    if (rawTs is int) {
      ts = rawTs;
    } else if (rawTs is num) {
      ts = rawTs.toInt();
    }
    final payload = j['payload'];
    final fromPayload = payload is Map ? payload['text'] : null;
    final content = '${j['content'] ?? fromPayload ?? ''}';
    final type = '${j['type'] ?? (payload is Map ? payload['type'] : null) ?? 'text'}';
    final urls = <String>[];
    String? audioUrl;
    void collect(dynamic list) {
      if (list is! List) return;
      for (final a in list) {
        if (a is! Map) continue;
        final kind = '${a['kind'] ?? ''}';
        final url = '${a['url'] ?? ''}';
        if (url.isEmpty) continue;
        if (kind == 'audio') {
          audioUrl ??= url;
        } else if (kind == 'image' || kind.isEmpty) {
          urls.add(url);
        }
      }
    }

    collect(j['attachments']);
    if (payload is Map) collect(payload['attachments']);
    final chunks = <Map<String, dynamic>>[];
    if (payload is Map && payload['tts_chunks'] is List) {
      for (final c in payload['tts_chunks'] as List) {
        if (c is Map) chunks.add(Map<String, dynamic>.from(c));
      }
    }
    final rawId = '${j['id'] ?? j['message_id'] ?? ''}'.trim();
    return ChatMessageDto(
      id: rawId.isEmpty ? null : rawId,
      role: '${j['role'] ?? 'user'}',
      content: content,
      ts: ts,
      type: type,
      imageUrls: urls,
      audioUrl: audioUrl,
      ttsChunks: chunks,
    );
  }

  /// 会话列表预览文案（多段回复取最后一段）。
  String get listPreviewText {
    if (ttsChunks.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(ttsChunks)
        ..sort(
          (a, b) => ((a['seq'] as num?)?.toInt() ?? 0)
              .compareTo((b['seq'] as num?)?.toInt() ?? 0),
        );
      for (final c in sorted.reversed) {
        final t = '${c['text'] ?? ''}'.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return content.trim();
  }
}

class VoiceProfileDto {
  VoiceProfileDto({
    required this.id,
    required this.label,
    this.category,
    this.gender,
    this.previewUrl,
  });

  final String id;
  final String label;
  final String? category;
  final String? gender;
  final String? previewUrl;

  factory VoiceProfileDto.fromJson(Map<String, dynamic> j) {
    final rawGender = '${j['gender'] ?? ''}'.trim();
    final category = j['category'] as String?;
    var gender = rawGender.isEmpty ? null : rawGender;
    if (gender == null && category != null) {
      if (category.contains('女')) gender = 'female';
      if (category.contains('男')) gender = 'male';
    }
    return VoiceProfileDto(
      id: '${j['id']}',
      label: '${j['label'] ?? j['id']}',
      category: category,
      gender: gender,
      previewUrl: j['preview_url'] as String?,
    );
  }
}

class EmotionDto {
  EmotionDto({this.valence, this.arousal, this.label});

  final double? valence;
  final double? arousal;
  final String? label;

  factory EmotionDto.fromJson(Map<String, dynamic>? j) {
    if (j == null) return EmotionDto();
    return EmotionDto(
      valence: (j['valence'] as num?)?.toDouble(),
      arousal: (j['arousal'] as num?)?.toDouble(),
      label: j['label'] as String?,
    );
  }
}

class BondStickerDto {
  BondStickerDto({
    required this.id,
    required this.emoji,
    required this.label,
    required this.unlocked,
    this.minStage,
  });

  final String id;
  final String emoji;
  final String label;
  final bool unlocked;
  final String? minStage;

  factory BondStickerDto.fromJson(Map<String, dynamic> j) => BondStickerDto(
        id: '${j['id'] ?? ''}',
        emoji: '${j['emoji'] ?? ''}',
        label: '${j['label'] ?? ''}',
        unlocked: j['unlocked'] == true,
        minStage: j['min_stage']?.toString(),
      );
}

class GiftDto {
  GiftDto({
    required this.id,
    required this.name,
    required this.price,
    required this.bondDelta,
    this.thumbUrl = '',
    this.effectUrl = '',
    this.rarity = 'common',
    this.blurb = '',
  });

  final String id;
  final String name;
  final int price;
  final int bondDelta;
  final String thumbUrl;
  final String effectUrl;
  final String rarity;
  final String blurb;

  factory GiftDto.fromJson(Map<String, dynamic> j) => GiftDto(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        price: (j['price'] as num?)?.toInt() ?? 0,
        bondDelta: (j['bond_delta'] as num?)?.toInt() ?? 0,
        thumbUrl: '${j['thumb_url'] ?? ''}',
        effectUrl: '${j['effect_url'] ?? ''}',
        rarity: '${j['rarity'] ?? 'common'}',
        blurb: '${j['blurb'] ?? ''}',
      );
}

class WalletDto {
  WalletDto({required this.stardust, this.currency = '星尘'});

  final int stardust;
  final String currency;

  factory WalletDto.fromJson(Map<String, dynamic> j) => WalletDto(
        stardust: (j['stardust'] as num?)?.toInt() ?? 0,
        currency: '${j['currency'] ?? '星尘'}',
      );
}

class BondDto {
  BondDto({
    required this.bond,
    required this.stage,
    required this.stageLabel,
    required this.progressInStage,
    required this.stickers,
    required this.quickRepliesExtra,
  });

  final int bond;
  final String stage;
  final String stageLabel;
  final double progressInStage;
  final List<BondStickerDto> stickers;
  final List<String> quickRepliesExtra;

  factory BondDto.fromJson(Map<String, dynamic> j) {
    final stickers = (j['stickers'] as List? ?? const [])
        .map((e) => BondStickerDto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final extras = (j['quick_replies_extra'] as List? ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList();
    return BondDto(
      bond: (j['bond'] as num?)?.toInt() ?? 0,
      stage: '${j['stage'] ?? 'stranger'}',
      stageLabel: '${j['stage_label'] ?? '初识'}',
      progressInStage: (j['progress_in_stage'] as num?)?.toDouble() ?? 0,
      stickers: stickers,
      quickRepliesExtra: extras,
    );
  }
}

class MemoryItemDto {
  MemoryItemDto({
    required this.id,
    required this.text,
    this.category,
    this.factKey,
    this.pinned = false,
    this.createdAt,
  });

  final String id;
  final String text;
  final String? category;
  final String? factKey;
  final bool pinned;
  final double? createdAt;

  factory MemoryItemDto.fromJson(Map<String, dynamic> j) => MemoryItemDto(
        id: '${j['id']}',
        text: '${j['text'] ?? ''}',
        category: j['category'] as String?,
        factKey: j['fact_key'] as String?,
        pinned: j['pinned'] == true,
        createdAt: (j['created_at'] is num)
            ? (j['created_at'] as num).toDouble()
            : null,
      );

  MemoryItemDto copyWith({bool? pinned}) => MemoryItemDto(
        id: id,
        text: text,
        category: category,
        factKey: factKey,
        pinned: pinned ?? this.pinned,
        createdAt: createdAt,
      );

  static String categoryLabel(String? c) {
    switch (c) {
      case 'biographical':
        return '生平';
      case 'preference':
        return '偏好';
      case 'relation':
        return '关系';
      case 'event':
        return '事件';
      case 'safety':
        return '安全';
      case 'reflection':
        return '反思';
      default:
        return c?.isNotEmpty == true ? c! : '其他';
    }
  }
}
