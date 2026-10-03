import 'dart:convert';

/// 会员身份，由后台开通；客户端只读展示。
class Membership {
  const Membership({
    this.tier = 'free',
    this.label = '体验',
    this.expiresAt,
    this.isMember = false,
    this.expired = false,
  });

  final String tier;
  final String label;

  /// unix 秒；null 表示永久有效
  final int? expiresAt;
  final bool isMember;

  /// 曾经是会员但已过期，用于提示续费
  final bool expired;

  DateTime? get expiresOn => expiresAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000);

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        tier: '${j['tier'] ?? 'free'}',
        label: '${j['label'] ?? '体验'}',
        expiresAt:
            j['expires_at'] == null ? null : int.tryParse('${j['expires_at']}'),
        isMember: j['is_member'] == true,
        expired: j['expired'] == true,
      );

  Map<String, dynamic> toJson() => {
        'tier': tier,
        'label': label,
        'expires_at': expiresAt,
        'is_member': isMember,
        'expired': expired,
      };
}

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
    this.companionPreference = 'female',
    this.onboardingCompleted = false,
    this.nightMode = false,
    this.eveningGreetingEnabled = false,
    this.membership = const Membership(),
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
  final String companionPreference;
  final bool onboardingCompleted;
  final bool nightMode;
  final bool eveningGreetingEnabled;
  final Membership membership;

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
        companionPreference: '${j['companion_preference'] ?? 'female'}',
        onboardingCompleted: j['onboarding_completed'] == true,
        nightMode: j['night_mode'] == true,
        eveningGreetingEnabled: j['evening_greeting_enabled'] == true,
        membership: j['membership'] is Map
            ? Membership.fromJson(
                Map<String, dynamic>.from(j['membership'] as Map),
              )
            : const Membership(),
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
      id == 'aurora' || source == 'builtin' || ownerUserId == 'u_seed_official';
  bool get isCustom => source == 'custom' || id.startsWith('c_');
  bool get isPending => reviewStatus == 'pending';
  bool get isRejected => reviewStatus == 'rejected';
  bool get isApproved =>
      reviewStatus == null ||
      reviewStatus == 'approved' ||
      reviewStatus!.isEmpty;
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
    this.voiceCompanionFeatured = const [],
  });

  final List<PersonaSummary> strip;
  final List<PersonaSummary> grid;
  final List<String> tagPresets;
  final List<PersonaSummary> voiceCompanionFeatured;

  @Deprecated('use strip')
  List<PersonaSummary> get featured => strip;

  @Deprecated('use grid')
  List<PersonaSummary> get all => grid;
}

class OnboardingConfig {
  OnboardingConfig({
    required this.onboardingCompleted,
    required this.companionPreference,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.nicknameTitle,
    required this.nicknameSubtitle,
    required this.floorTitle,
    required this.floorSubtitle,
  });

  final bool onboardingCompleted;
  final String companionPreference;
  final String title;
  final String subtitle;
  final List<OnboardingOption> options;
  final String nicknameTitle;
  final String nicknameSubtitle;
  final String floorTitle;
  final String floorSubtitle;

  factory OnboardingConfig.fromJson(Map<String, dynamic> j) => OnboardingConfig(
        onboardingCompleted: j['onboarding_completed'] == true,
        companionPreference: '${j['companion_preference'] ?? 'female'}',
        title: '${j['title'] ?? '你更想和谁聊天？'}',
        subtitle: '${j['subtitle'] ?? ''}',
        options: [
          for (final o in (j['options'] as List? ?? const []))
            OnboardingOption.fromJson(Map<String, dynamic>.from(o as Map)),
        ],
        nicknameTitle: '${j['nickname_title'] ?? '怎么称呼你？'}',
        nicknameSubtitle: '${j['nickname_subtitle'] ?? ''}',
        floorTitle: '${j['floor_title'] ?? '精选'}',
        floorSubtitle: '${j['floor_subtitle'] ?? ''}',
      );
}

class OnboardingOption {
  OnboardingOption({
    required this.value,
    required this.label,
    this.hint = '',
  });

  final String value;
  final String label;
  final String hint;

  factory OnboardingOption.fromJson(Map<String, dynamic> j) => OnboardingOption(
        value: '${j['value']}',
        label: '${j['label'] ?? ''}',
        hint: '${j['hint'] ?? ''}',
      );
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
    this.cosyvoiceVoice,
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
  final String? cosyvoiceVoice;
  final String? gender;
  final String? scenario;
  final String? appearance;
  final String? relationshipToUser;
  final List<String> personality;
  final String? speechStyle;

  bool get isOfficial =>
      id == 'aurora' || source == 'builtin' || ownerUserId == 'u_seed_official';
  bool get isCustom => source == 'custom' || id.startsWith('c_');
  bool get isPending => reviewStatus == 'pending';
  bool get isRejected => reviewStatus == 'rejected';
  bool get isPrivate => visibility == 'private';

  bool get hasTtsVoice =>
      (voiceProfileId ?? '').trim().isNotEmpty ||
      (cosyvoiceVoice ?? '').trim().isNotEmpty;

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
        voiceProfileId:
            (j['voice_profile_id'] as String?)?.trim().isEmpty == true
                ? null
                : j['voice_profile_id'] as String?,
        cosyvoiceVoice:
            (j['cosyvoice_voice'] as String?)?.trim().isEmpty == true
                ? null
                : j['cosyvoice_voice'] as String?,
        gender: (j['gender'] as String?)?.trim().isEmpty == true
            ? null
            : j['gender'] as String?,
        scenario: (j['scenario'] as String?)?.trim().isEmpty == true
            ? null
            : j['scenario'] as String?,
        appearance: (j['appearance'] as String?)?.trim().isEmpty == true
            ? null
            : j['appearance'] as String?,
        relationshipToUser:
            (j['relationship_to_user'] as String?)?.trim().isEmpty == true
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
    this.previewUrl = '',
  });

  final String key;
  final String name;
  final String category;
  final String color;
  final String badge;
  final String previewUrl;

  factory LookStyle.fromJson(Map<String, dynamic> j) => LookStyle(
        key: '${j['key']}',
        name: '${j['name'] ?? j['key']}',
        category: '${j['category'] ?? '精选'}',
        color: '${j['color'] ?? '#5B7C99'}',
        badge: '${j['badge'] ?? ''}',
        previewUrl: '${j['preview_url'] ?? ''}',
      );
}

class LookStylesPayload {
  LookStylesPayload({required this.categories, required this.styles});

  final List<String> categories;
  final List<LookStyle> styles;

  factory LookStylesPayload.fromJson(Map<String, dynamic> j) =>
      LookStylesPayload(
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
    this.meta = const {},
    this.payload = const {},
  });

  final String? id;
  final String role;
  final String content;
  final int? ts;
  final String type;
  final List<String> imageUrls;
  final String? audioUrl;
  final List<Map<String, dynamic>> ttsChunks;
  final Map<String, dynamic> meta;
  final Map<String, dynamic> payload;

  bool get isMemory =>
      type == 'memory' ||
      meta['memory_card'] == true ||
      meta['kind'] == 'memory_card';

  bool get isSceneImage => meta['scene_image'] != null;

  /// 随机语音条：这条回复是语音，不是文字气泡。
  bool get isVoiceReply =>
      type == 'voice' ||
      meta['voice_reply'] == true ||
      payload['voice_reply'] == true;

  String get sceneTitle {
    final scene = meta['scene_image'];
    if (scene is Map && '${scene['scene_title'] ?? ''}'.trim().isNotEmpty) {
      return '${scene['scene_title']}'.trim();
    }
    return '${payload['scene_title'] ?? ''}'.trim();
  }

  String get memorySummary =>
      '${payload['summary'] ?? payload['text'] ?? meta['summary'] ?? ''}'
          .trim();

  String get memoryImageUrl =>
      '${payload['image_url'] ?? meta['image_url'] ?? ''}'.trim();

  String get memoryCardTitle {
    if (sceneTitle.isNotEmpty) return sceneTitle;
    final c = content.trim();
    if (c.startsWith('📌')) {
      return c.replaceFirst('📌 ', '').replaceFirst('记住了：', '').trim();
    }
    return c.isNotEmpty ? c : '记住了这一刻';
  }

  factory ChatMessageDto.fromJson(Map<String, dynamic> j) {
    final rawTs = j['ts'] ?? j['created_at'];
    int? ts;
    if (rawTs is int) {
      ts = rawTs;
    } else if (rawTs is num) {
      ts = rawTs.toInt();
    }
    final payload = j['payload'] is Map
        ? Map<String, dynamic>.from(j['payload'] as Map)
        : <String, dynamic>{};
    final meta = Map<String, dynamic>.from(j['meta'] as Map? ?? const {});
    if (meta.isEmpty && payload['_meta'] is Map) {
      meta.addAll(Map<String, dynamic>.from(payload['_meta'] as Map));
    }
    final fromPayload = payload['text'];
    final content = '${j['content'] ?? fromPayload ?? ''}';
    final type = '${j['type'] ?? (payload['type']) ?? 'text'}';
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
    collect(payload['attachments']);
    final chunks = <Map<String, dynamic>>[];
    if (payload['tts_chunks'] is List) {
      for (final c in payload['tts_chunks'] as List) {
        if (c is Map) chunks.add(Map<String, dynamic>.from(c));
      }
    }
    final memUrl = '${payload['image_url'] ?? ''}'.trim();
    if (memUrl.isNotEmpty && !urls.contains(memUrl)) {
      urls.add(memUrl);
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
      meta: meta,
      payload: payload,
    );
  }

  /// 会话列表预览文案（多段回复取最后一段）。
  String get listPreviewText {
    if (isVoiceReply) return '[语音]';
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

class VoiceCloneRequirementsDto {
  VoiceCloneRequirementsDto({
    required this.targetModel,
    required this.formats,
    required this.minSeconds,
    required this.maxSeconds,
    required this.maxBytes,
    required this.tips,
  });

  final String targetModel;
  final List<String> formats;
  final double minSeconds;
  final double maxSeconds;
  final int maxBytes;
  final List<String> tips;

  factory VoiceCloneRequirementsDto.fromJson(Map<String, dynamic> j) =>
      VoiceCloneRequirementsDto(
        targetModel: '${j['target_model'] ?? 'cosyvoice-v3.5-flash'}',
        formats: [
          for (final f
              in (j['formats'] as List? ?? const ['wav', 'mp3', 'm4a']))
            '$f',
        ],
        minSeconds: (j['min_seconds'] as num?)?.toDouble() ?? 10,
        maxSeconds: (j['max_seconds'] as num?)?.toDouble() ?? 30,
        maxBytes: (j['max_bytes'] as num?)?.toInt() ?? 10485760,
        tips: [for (final t in (j['tips'] as List? ?? const [])) '$t'],
      );
}

class VoiceCloneJobDto {
  VoiceCloneJobDto({
    required this.id,
    required this.status,
    required this.previewUrl,
    this.voiceId,
    this.error = '',
  });

  final String id;
  final String status;
  final String previewUrl;
  final String? voiceId;
  final String error;

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';
  bool get isProcessing => status == 'processing' || status == 'uploaded';

  factory VoiceCloneJobDto.fromJson(Map<String, dynamic> j) => VoiceCloneJobDto(
        id: '${j['id']}',
        status: '${j['status'] ?? ''}',
        previewUrl: '${j['preview_url'] ?? ''}',
        voiceId: (j['voice_id'] as String?)?.trim().isEmpty == true
            ? null
            : j['voice_id'] as String?,
        error: '${j['error'] ?? ''}',
      );
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

/// 充值套餐（展示用，暂不接支付发货）
class RechargePackageDto {
  RechargePackageDto({
    required this.id,
    required this.title,
    required this.stardust,
    required this.priceCny,
    this.badge = '',
    this.benefits = const [],
  });

  final String id;
  final String title;
  final int stardust;
  final double priceCny;
  final String badge;
  final List<String> benefits;

  factory RechargePackageDto.fromJson(Map<String, dynamic> j) =>
      RechargePackageDto(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        stardust: (j['stardust'] as num?)?.toInt() ?? 0,
        priceCny: (j['price_cny'] as num?)?.toDouble() ?? 0,
        badge: '${j['badge'] ?? ''}'.trim(),
        benefits: [
          for (final b in (j['benefits'] as List? ?? const []))
            if ('$b'.trim().isNotEmpty) '$b'.trim(),
        ],
      );
}

class RechargeCatalogDto {
  RechargeCatalogDto({
    this.currency = '星尘',
    this.note = '',
    this.contactHint = '',
    this.purchaseEnabled = false,
    this.packages = const [],
  });

  final String currency;
  final String note;
  final String contactHint;
  final bool purchaseEnabled;
  final List<RechargePackageDto> packages;

  factory RechargeCatalogDto.fromJson(Map<String, dynamic> j) =>
      RechargeCatalogDto(
        currency: '${j['currency'] ?? '星尘'}',
        note: '${j['note'] ?? ''}'.trim(),
        contactHint: '${j['contact_hint'] ?? ''}'.trim(),
        purchaseEnabled: j['purchase_enabled'] == true,
        packages: [
          for (final p in (j['packages'] as List? ?? const []))
            RechargePackageDto.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
      );
}

/// VIP 订阅商品（开通送星尘）
class VipSubscriptionDto {
  VipSubscriptionDto({
    required this.id,
    required this.tier,
    required this.title,
    required this.days,
    required this.priceCny,
    this.originalPriceCny = 0,
    this.badge = '',
    this.stardustGift = 0,
    this.appleProductId = '',
  });

  final String id;
  final String tier;
  final String title;
  final int days;
  final double priceCny;
  final double originalPriceCny;
  final String badge;
  final int stardustGift;
  final String appleProductId;

  factory VipSubscriptionDto.fromJson(Map<String, dynamic> j) =>
      VipSubscriptionDto(
        id: '${j['id'] ?? ''}',
        tier: '${j['tier'] ?? ''}',
        title: '${j['title'] ?? ''}',
        days: (j['days'] as num?)?.toInt() ?? 30,
        priceCny: (j['price_cny'] as num?)?.toDouble() ?? 0,
        originalPriceCny: (j['original_price_cny'] as num?)?.toDouble() ?? 0,
        badge: '${j['badge'] ?? ''}'.trim(),
        stardustGift: (j['stardust_gift'] as num?)?.toInt() ?? 0,
        appleProductId: '${j['apple_product_id'] ?? ''}',
      );
}

class VipBenefitRowDto {
  VipBenefitRowDto({
    required this.key,
    required this.label,
    this.values = const {},
  });

  final String key;
  final String label;
  final Map<String, String> values;

  factory VipBenefitRowDto.fromJson(Map<String, dynamic> j) {
    final raw = j['values'];
    final values = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final key = '$k'.trim();
        final val = '$v'.trim();
        if (key.isNotEmpty && val.isNotEmpty) values[key] = val;
      });
    }
    return VipBenefitRowDto(
      key: '${j['key'] ?? ''}',
      label: '${j['label'] ?? ''}',
      values: values,
    );
  }

  String valueFor(String tier) => values[tier] ?? '—';
}

class VipCatalogDto {
  VipCatalogDto({
    this.defaultTier = 'free',
    this.currency = '星尘',
    this.contactHint = '',
    this.purchaseEnabled = false,
    this.subscriptions = const [],
    this.benefitRows = const [],
  });

  final String defaultTier;
  final String currency;
  final String contactHint;
  final bool purchaseEnabled;
  final List<VipSubscriptionDto> subscriptions;
  final List<VipBenefitRowDto> benefitRows;

  factory VipCatalogDto.fromJson(Map<String, dynamic> j) => VipCatalogDto(
        defaultTier: '${j['default_tier'] ?? 'free'}',
        currency: '${j['currency'] ?? '星尘'}',
        contactHint: '${j['contact_hint'] ?? ''}'.trim(),
        purchaseEnabled: j['purchase_enabled'] == true,
        subscriptions: [
          for (final s in (j['subscriptions'] as List? ?? const []))
            VipSubscriptionDto.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        benefitRows: [
          for (final r in (j['benefit_rows'] as List? ?? const []))
            VipBenefitRowDto.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
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
        .map(
            (e) => BondStickerDto.fromJson(Map<String, dynamic>.from(e as Map)))
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

class GroupChatConfig {
  GroupChatConfig({
    required this.enabled,
    this.jealousyEnabled = true,
    this.resolvePayEnabled = true,
    this.icebreakOnOpen = true,
    this.debug = false,
    this.maxGroupsPerUser = 10,
  });

  final bool enabled;
  final bool jealousyEnabled;
  final bool resolvePayEnabled;
  final bool icebreakOnOpen;
  final bool debug;
  final int maxGroupsPerUser;

  factory GroupChatConfig.fromJson(Map<String, dynamic> j) => GroupChatConfig(
        enabled: j['group_chat_enabled'] == true,
        jealousyEnabled: j['jealousy_enabled'] != false,
        resolvePayEnabled: j['resolve_pay_enabled'] != false,
        icebreakOnOpen: j['icebreak_on_open'] != false,
        debug: j['debug'] == true,
        maxGroupsPerUser: (j['max_groups_per_user'] as num?)?.toInt() ?? 10,
      );
}

class GroupMemberDto {
  GroupMemberDto({
    required this.personaId,
    required this.name,
    this.nameSnapshot = '',
    this.coverUrl = '',
    this.active = true,
    this.deleted = false,
    this.jealousy = 0,
    this.tier = 'normal',
    this.renamed = false,
  });

  final String personaId;
  final String name;
  final String nameSnapshot;
  final String coverUrl;
  final bool active;
  final bool deleted;
  final int jealousy;
  final String tier;
  final bool renamed;

  String tierLabel() {
    switch (tier) {
      case 'jealous':
        return '吃醋';
      case 'cold_war':
        return '冷战';
      default:
        return '平静';
    }
  }

  factory GroupMemberDto.fromJson(Map<String, dynamic> j) => GroupMemberDto(
        personaId: '${j['persona_id'] ?? ''}',
        name: '${j['name'] ?? j['name_snapshot'] ?? ''}',
        nameSnapshot: '${j['name_snapshot'] ?? ''}',
        coverUrl: '${j['cover_url'] ?? ''}',
        active: j['active'] != false,
        deleted: j['deleted'] == true,
        jealousy: (j['jealousy'] as num?)?.toInt() ?? 0,
        tier: '${j['tier'] ?? 'normal'}',
        renamed: j['renamed'] == true,
      );
}

class GroupSummaryDto {
  GroupSummaryDto({
    required this.id,
    required this.title,
    this.coverUrl = '',
    this.lastPreview = '',
    this.lastSeq = 0,
    this.lastMessageAt = 0,
    this.canSend = true,
    this.members = const [],
    this.memberCovers = const [],
  });

  final String id;
  final String title;
  final String coverUrl;
  final String lastPreview;
  final int lastSeq;
  final int lastMessageAt;
  final bool canSend;
  final List<GroupMemberDto> members;
  final List<String> memberCovers;

  factory GroupSummaryDto.fromJson(Map<String, dynamic> j) => GroupSummaryDto(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        coverUrl: '${j['cover_url'] ?? ''}',
        lastPreview: '${j['last_preview'] ?? ''}',
        lastSeq: (j['last_seq'] as num?)?.toInt() ?? 0,
        lastMessageAt: (j['last_message_at'] as num?)?.toInt() ?? 0,
        canSend: j['can_send'] != false,
        members: [
          for (final m in (j['members'] as List? ?? const []))
            GroupMemberDto.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
        memberCovers: [
          for (final u in (j['member_covers'] as List? ?? const [])) '$u',
        ],
      );

  /// 列表接口带 member_covers；详情页从成员 cover 推导。
  List<String> get effectiveMemberCovers {
    if (memberCovers.isNotEmpty) return memberCovers;
    return members
        .where((m) => m.active && !m.deleted && m.coverUrl.isNotEmpty)
        .map((m) => m.coverUrl)
        .toList();
  }

  /// 背景：自定义群头像优先，否则用第一个成员封面。
  String? get backdropCoverUrl {
    if (coverUrl.isNotEmpty) return coverUrl;
    final covers = effectiveMemberCovers;
    return covers.isNotEmpty ? covers.first : null;
  }
}

class GroupMessageDto {
  GroupMessageDto({
    required this.id,
    required this.groupId,
    required this.seq,
    required this.senderType,
    this.senderId = '',
    this.content = '',
    this.messageType = 'text',
    this.meta = const {},
    this.createdAt = 0,
  });

  final String id;
  final String groupId;
  final int seq;
  final String senderType;
  final String senderId;
  final String content;
  final String messageType;
  final Map<String, dynamic> meta;
  final int createdAt;

  String get kind => '${meta['kind'] ?? ''}';
  String get senderName => '${meta['sender_name'] ?? ''}';
  String? get clientMsgId => meta['client_msg_id'] as String?;
  bool get resolveOffer => meta['resolve_offer'] == true;

  bool get isUser => senderType == 'user';
  bool get isAi => senderType == 'ai';
  bool get isSystem => senderType == 'system';
  bool get isImage => messageType == 'image' || meta['image_url'] != null;
  String get imageUrl => '${meta['image_url'] ?? ''}';
  String get giftName => '${meta['gift_name'] ?? ''}';
  String get giftPersonaName => '${meta['persona_name'] ?? ''}';
  bool get isMemory => messageType == 'memory' || kind == 'memory_card';
  bool get isSceneImage => kind == 'scene_image';
  String get sceneTitle => '${meta['scene_title'] ?? ''}';
  String get memorySummary => '${meta['summary'] ?? ''}';
  bool get isAiGift => meta['ai_gift'] == true;
  String get audioUrl => '${meta['audio_url'] ?? ''}';
  bool get hasVoiceReply => audioUrl.isNotEmpty || meta['voice_reply'] == true;

  factory GroupMessageDto.fromJson(Map<String, dynamic> j) => GroupMessageDto(
        id: '${j['id']}',
        groupId: '${j['group_id'] ?? ''}',
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        senderType: '${j['sender_type'] ?? ''}',
        senderId: '${j['sender_id'] ?? ''}',
        content: '${j['content'] ?? ''}',
        messageType: '${j['message_type'] ?? 'text'}',
        meta: Map<String, dynamic>.from(j['meta'] as Map? ?? const {}),
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'seq': seq,
        'sender_type': senderType,
        'sender_id': senderId,
        'content': content,
        'message_type': messageType,
        'meta': meta,
        'created_at': createdAt,
      };
}

class GroupMemoryDto {
  GroupMemoryDto({
    required this.id,
    required this.groupId,
    this.sceneId = '',
    this.title = '',
    this.summary = '',
    this.imageUrl = '',
    this.auto = true,
    this.createdAt = 0,
  });

  final String id;
  final String groupId;
  final String sceneId;
  final String title;
  final String summary;
  final String imageUrl;
  final bool auto;
  final int createdAt;

  factory GroupMemoryDto.fromJson(Map<String, dynamic> j) => GroupMemoryDto(
        id: '${j['id']}',
        groupId: '${j['group_id'] ?? ''}',
        sceneId: '${j['scene_id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        summary: '${j['summary'] ?? ''}',
        imageUrl: '${j['image_url'] ?? ''}',
        auto: j['auto'] == true,
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );
}
