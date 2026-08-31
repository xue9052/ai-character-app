import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'models.dart';

class ApiClient {
  ApiClient(this.baseUrl, {this.accessToken, this.onUnauthorized});

  final String baseUrl;
  /// 登录态 JWT；用户相关接口必带
  final String? accessToken;
  /// 收到 401 时回调（通常用于清登录态回到登录页）
  final FutureOr<void> Function()? onUnauthorized;

  Map<String, String> _headers({
    bool json = false,
    bool auth = true,
    Map<String, String>? extra,
  }) {
    final h = <String, String>{if (extra != null) ...extra};
    if (json) h['Content-Type'] = 'application/json';
    final t = accessToken?.trim();
    if (auth && t != null && t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  Uri _u(String path, [Map<String, String>? q]) {
    final b = baseUrl.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$b$path').replace(queryParameters: q);
  }

  String resolveUrl(String pathOrUrl) {
    final s = pathOrUrl.trim();
    if (s.isEmpty) return s;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    final b = baseUrl.replaceAll(RegExp(r'/$'), '');
    if (s.startsWith('/')) return '$b$s';
    return '$b/$s';
  }

  Future<PlazaFeed> listPlaza(String userId, {String? tag}) async {
    final q = <String, String>{'user_id': userId};
    if (tag != null && tag.isNotEmpty) q['tag'] = tag;
    final res = await http.get(_u('/v1/personas', q), headers: _headers());
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    List<PersonaSummary> parseList(String primary, String fallback) {
      final raw = (data[primary] as List?) ?? (data[fallback] as List?) ?? const [];
      return [
        for (final p in raw)
          PersonaSummary.fromJson(Map<String, dynamic>.from(p as Map)),
      ];
    }
    return PlazaFeed(
      strip: parseList('strip', 'featured'),
      grid: parseList('grid', 'public'),
      tagPresets: [
        for (final t in (data['tag_presets'] as List? ?? const [])) '$t',
      ],
    );
  }

  /// 仅刷新广场网格（切标签时用；横滑 strip 客户端缓存不变）
  Future<List<PersonaSummary>> listPlazaGrid(String userId, {String? tag}) async {
    final feed = await listPlaza(userId, tag: tag);
    return feed.grid;
  }

  Future<List<PersonaSummary>> listPersonas(String userId, {String? tag}) async {
    final feed = await listPlaza(userId, tag: tag);
    return feed.grid;
  }

  /// 广场搜索：名字 / 简介 / 标签
  Future<PersonaSearchResult> searchPersonas(
    String userId, {
    String q = '',
    String? tag,
    int limit = 50,
  }) async {
    final query = <String, String>{
      'user_id': userId,
      'limit': '$limit',
    };
    final trimmed = q.trim();
    if (trimmed.isNotEmpty) query['q'] = trimmed;
    if (tag != null && tag.isNotEmpty) query['tag'] = tag;
    final res = await http.get(_u('/v1/personas/search', query), headers: _headers());
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return PersonaSearchResult.fromJson(data);
  }

  /// 我创建的角色（含待审 / 驳回）
  Future<List<PersonaSummary>> listMyPersonas(String userId) async {
    final res = await http.get(
      _u('/v1/personas/mine', {'user_id': userId}),
      headers: _headers(),
    );
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final rows = data['personas'] as List? ?? const [];
    return [
      for (final p in rows)
        PersonaSummary.fromJson(Map<String, dynamic>.from(p as Map)),
    ];
  }

  /// 创角模板（服务端数据库；emoji 缓存头像 + 可选封面）
  Future<List<Map<String, dynamic>>> listPersonaTemplates() async {
    final res = await http.get(_u('/v1/persona-templates'), headers: _headers(auth: false));
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final rows = data['templates'] as List? ?? const [];
    return [
      for (final p in rows) Map<String, dynamic>.from(p as Map),
    ];
  }

  Future<PersonaDetail> getPersona(String userId, String id) async {
    final res = await http.get(
      _u('/v1/personas/${Uri.encodeComponent(id)}', {'user_id': userId}),
      headers: _headers(),
    );
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return PersonaDetail.fromJson(data);
  }

  /// 创建或更新自定义角色（对齐 Web 角色工坊 / 猫箱创建角色）
  Future<PersonaDetail> upsertPersona({
    required String userId,
    String? id,
    required String name,
    String? oneLiner,
    required String definition,
    String? greeting,
    String? visibility,
    List<String>? tags,
    String? coverEmoji,
    String? coverColor,
    String? backgroundKey,
    List<String>? alternateGreetings,
    String? creatorNotes,
    String? voiceProfileId,
    String? gender,
    String? scenario,
    String? appearance,
    String? relationshipToUser,
    List<String>? personality,
    String? speechStyle,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'definition': definition,
      if (id != null && id.isNotEmpty) 'id': id,
      if (oneLiner != null && oneLiner.trim().isNotEmpty) 'one_liner': oneLiner.trim(),
      if (greeting != null && greeting.trim().isNotEmpty) 'greeting': greeting.trim(),
      if (visibility != null) 'visibility': visibility,
      if (tags != null) 'tags': tags,
      if (coverEmoji != null) 'cover_emoji': coverEmoji,
      if (coverColor != null) 'cover_color': coverColor,
      if (backgroundKey != null && backgroundKey.isNotEmpty)
        'background_key': backgroundKey,
      if (alternateGreetings != null) 'alternate_greetings': alternateGreetings,
      if (creatorNotes != null && creatorNotes.trim().isNotEmpty)
        'creator_notes': creatorNotes.trim(),
      if (voiceProfileId != null) 'voice_profile_id': voiceProfileId,
      if (gender != null) 'gender': gender,
      if (scenario != null) 'scenario': scenario,
      if (appearance != null) 'appearance': appearance,
      if (relationshipToUser != null) 'relationship_to_user': relationshipToUser,
      if (personality != null) 'personality': personality,
      if (speechStyle != null) 'speech_style': speechStyle,
    };
    final res = await http.post(
      _u('/v1/personas', {'user_id': userId}),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final persona = data['persona'];
    if (persona is Map) {
      return PersonaDetail.fromJson(Map<String, dynamic>.from(persona));
    }
    return PersonaDetail.fromJson(data);
  }

  /// 上传角色封面图（本地存储，返回后 persona.coverUrl 可用）
  Future<void> uploadPersonaCover({
    required String userId,
    required String personaId,
    required List<int> bytes,
    required String filename,
  }) async {
    final uri = _u(
      '/v1/personas/${Uri.encodeComponent(personaId)}/cover',
      {'user_id': userId},
    );
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_headers());
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> uploadPersonaBackground({
    required String userId,
    required String personaId,
    required List<int> bytes,
    required String filename,
  }) async {
    final uri = _u(
      '/v1/personas/${Uri.encodeComponent(personaId)}/background',
      {'user_id': userId},
    );
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_headers());
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<List<BackgroundPreset>> backgroundPresets() async {
    final res = await http.get(_u('/v1/persona-background-presets'), headers: _headers(auth: false));
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = (data['presets'] as List? ?? const []);
    return [
      for (final item in list)
        if (item is Map)
          BackgroundPreset.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<LookStylesPayload> lookStyles() async {
    final res = await http.get(_u('/v1/image-gen/look-styles'), headers: _headers(auth: false));
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return LookStylesPayload.fromJson(data);
  }

  Future<GeneratedLook> generatePersonaLook({
    required String userId,
    String? description,
    String? styleKey,
  }) async {
    final res = await http.post(
      _u('/v1/image-gen/persona-look'),
      headers: _headers(json: true),
      body: jsonEncode({
        'user_id': userId,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (styleKey != null && styleKey.isNotEmpty) 'style_key': styleKey,
      }),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '形象生成失败');
    }
    return GeneratedLook.fromJson(data);
  }

  Future<String> polishPersonaLookPrompt({
    required String userId,
    required String description,
    String? styleKey,
  }) async {
    final res = await http.post(
      _u('/v1/image-gen/persona-look/polish'),
      headers: _headers(json: true),
      body: jsonEncode({
        'user_id': userId,
        'description': description,
        if (styleKey != null && styleKey.isNotEmpty) 'style_key': styleKey,
      }),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '润色失败');
    }
    return '${data['description'] ?? description}';
  }

  Future<void> deletePersona({required String userId, required String id}) async {
    final res = await http.delete(
      _u('/v1/personas/${Uri.encodeComponent(id)}', {'user_id': userId}),
      headers: _headers(),
    );
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<Map<String, dynamic>> getChat({
    required String userId,
    required String personaId,
    int limit = 30,
    int? beforeIndex,
    bool allowFallback = false,
  }) async {
    final q = <String, String>{
      'persona_id': personaId,
      'limit': '$limit',
      'allow_fallback': allowFallback ? 'true' : 'false',
      // 防 Flutter Web / 浏览器把会话预览 GET 缓存成旧数据
      '_ts': '${DateTime.now().millisecondsSinceEpoch}',
    };
    if (beforeIndex != null) {
      q['before_index'] = '$beforeIndex';
    }
    final res = await http.get(
      _u('/v1/users/${Uri.encodeComponent(userId)}/chat', q),
      headers: _headers(extra: const {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      }),
    );
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// 进聊天页：历史 + 亲密度 + 人设摘要，一次请求
  Future<Map<String, dynamic>> getChatBootstrap({
    required String userId,
    required String personaId,
    int limit = 30,
  }) async {
    final res = await http.get(
      _u('/v1/users/${Uri.encodeComponent(userId)}/chat/bootstrap', {
        'persona_id': personaId,
        'limit': '$limit',
        '_ts': '${DateTime.now().millisecondsSinceEpoch}',
      }),
      headers: _headers(extra: const {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      }),
    );
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '加载聊天失败');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> listChatSessions({
    required String userId,
    int limit = 50,
  }) async {
    final res = await http.get(
      _u('/v1/users/${Uri.encodeComponent(userId)}/chat/sessions', {
        'limit': '$limit',
        '_ts': '${DateTime.now().millisecondsSinceEpoch}',
      }),
      headers: _headers(extra: const {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      }),
    );
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final raw = (data['sessions'] as List?) ?? const [];
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  Future<Map<String, dynamic>> getImageEditQuota({required String userId}) async {
    final res = await http.get(
      _u('/v1/chat/image-edit/quota', {'user_id': userId}),
      headers: _headers(),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '获取改图配额失败');
    }
    return data;
  }

  Future<List<VoiceProfileDto>> listVoiceProfiles() async {
    final res = await http.get(_u('/v1/voice-profiles'), headers: _headers(auth: false));
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '获取音色列表失败');
    }
    final raw = (data['profiles'] as List?) ?? const [];
    return [
      for (final e in raw)
        if (e is Map)
          VoiceProfileDto.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<Map<String, dynamic>> chatTts({
    required String userId,
    required String personaId,
    required String messageId,
    String? sessionId,
    String? text,
    bool clip = false,
  }) async {
    final res = await http.post(
      _u('/v1/chat/tts'),
      headers: _headers(json: true),
      body: jsonEncode({
        'user_id': userId,
        'persona_id': personaId,
        'message_id': messageId,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
        if (clip) 'clip': true,
      }),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '语音生成失败');
    }
    return data;
  }

  /// 聊天改图：图 + 一句话
  Future<Map<String, dynamic>> chatImageEdit({
    required String userId,
    required String personaId,
    required List<int> bytes,
    required String filename,
    required String prompt,
    String? sessionId,
  }) async {
    final req = http.MultipartRequest('POST', _u('/v1/chat/image-edit'));
    req.headers.addAll(_headers());
    req.fields['user_id'] = userId;
    req.fields['persona_id'] = personaId;
    req.fields['prompt'] = prompt;
    if (sessionId != null && sessionId.isNotEmpty) {
      req.fields['session_id'] = sessionId;
    }
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '改图失败');
    }
    return data;
  }

  /// 空会话写入角色开场白（第一条 assistant）
  Future<Map<String, dynamic>> seedGreeting({
    required String userId,
    required String personaId,
  }) async {
    final res = await http.post(
      _u('/v1/users/${Uri.encodeComponent(userId)}/chat/seed-greeting', {
        'persona_id': personaId,
      }),
      headers: _headers(),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '开场白写入失败');
    }
    return data;
  }

  Future<Map<String, dynamic>> chat({
    required String userId,
    required String personaId,
    required dynamic message,
    String? sessionId,
    String? modelProfile,
  }) async {
    final res = await http.post(
      _u('/v1/chat'),
      headers: _headers(json: true),
      body: jsonEncode({
        'user_id': userId,
        'persona_id': personaId,
        'session_id': sessionId,
        'message': message,
        'model_profile': modelProfile ?? 'deepseek_default',
      }),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '发送失败');
    }
    return data;
  }

  Future<BondDto> getBond({
    required String userId,
    required String personaId,
  }) async {
    final res = await http.get(
      _u('/v1/users/${Uri.encodeComponent(userId)}/bonds/${Uri.encodeComponent(personaId)}'),
      headers: _headers(),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '加载关系失败');
    }
    return BondDto.fromJson(data);
  }

  Future<List<GiftDto>> listGifts() async {
    final res = await http.get(_u('/v1/gifts'), headers: _headers(auth: false));
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '加载礼物失败');
    }
    final list = data['gifts'] as List? ?? const [];
    return list
        .map((e) => GiftDto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<WalletDto> getWallet({required String userId}) async {
    final res = await http.get(
      _u('/v1/users/${Uri.encodeComponent(userId)}/wallet'),
      headers: _headers(),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '加载星尘失败');
    }
    return WalletDto.fromJson(data);
  }

  /// 送礼：走 /v1/chat type=gift，返回完整 chat 响应（含 feedback / reply）
  Future<Map<String, dynamic>> sendGift({
    required String userId,
    required String personaId,
    required String giftId,
    String? sessionId,
    String? modelProfile,
  }) {
    return chat(
      userId: userId,
      personaId: personaId,
      sessionId: sessionId,
      modelProfile: modelProfile,
      message: {
        'type': 'gift',
        'payload': {'gift_id': giftId},
      },
    );
  }

  /// 重说末轮：服务端撤回 assistant+user 后按原用户句再生成
  Future<Map<String, dynamic>> regenerate({
    required String userId,
    required String personaId,
    String? sessionId,
    String? modelProfile,
  }) async {
    final res = await http.post(
      _u('/v1/chat/regenerate'),
      headers: _headers(json: true),
      body: jsonEncode({
        'user_id': userId,
        'persona_id': personaId,
        'session_id': sessionId,
        'model_profile': modelProfile ?? 'deepseek_default',
      }),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '重说失败');
    }
    return data;
  }

  /// SSE：yield token 文本；最后 yield 完整 final JSON（以 map 形式通过回调）
  Stream<String> chatStreamTokens({
    required String userId,
    required String personaId,
    required String message,
    String? sessionId,
    String? modelProfile,
    bool ttsEnabled = false,
    void Function(Map<String, dynamic> finalPayload)? onFinal,
    void Function(String messageId)? onMessageId,
    void Function(int seq, String audioUrl, String text, bool pending, bool error)? onTtsChunk,
    void Function()? onTtsDone,
  }) async* {
    final req = http.Request('POST', _u('/v1/chat/stream'));
    req.headers.addAll(_headers(json: true, extra: {'Accept': 'text/event-stream'}));
    req.body = jsonEncode({
      'user_id': userId,
      'persona_id': personaId,
      'session_id': sessionId,
      'message': message,
      'model_profile': modelProfile ?? 'deepseek_default',
      'tts_enabled': ttsEnabled,
    });
    final client = http.Client();
    var messageIdSent = false;
    void takeMessageId(Map<String, dynamic> data) {
      if (messageIdSent || onMessageId == null) return;
      final id = '${data['id'] ?? ''}'.trim();
      if (id.isEmpty) return;
      messageIdSent = true;
      onMessageId(id);
    }

    try {
      final res = await client.send(req);
      if (res.statusCode >= 400) {
        if (res.statusCode == 401) {
          final cb = onUnauthorized;
          if (cb != null) Future.sync(cb);
        }
        throw Exception('HTTP ${res.statusCode}');
      }
      var buf = '';
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        buf += chunk;
        final parts = buf.split('\n\n');
        buf = parts.removeLast();
        for (final block in parts) {
          var event = 'message';
          final dataLines = <String>[];
          for (final line in block.split('\n')) {
            if (line.startsWith('event:')) {
              event = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              dataLines.add(line.substring(5).trim());
            }
          }
          if (dataLines.isEmpty) continue;
          final raw = dataLines.join();
          Map<String, dynamic> data;
          try {
            data = jsonDecode(raw) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          if (event == 'message_start') {
            takeMessageId(data);
          } else if (event == 'token' && data['text'] is String) {
            takeMessageId(data);
            yield data['text'] as String;
          } else if (event == 'final') {
            final msgs = data['messages'];
            if (msgs is List && msgs.isNotEmpty && msgs.first is Map) {
              takeMessageId(Map<String, dynamic>.from(msgs.first as Map));
            }
            onFinal?.call(data);
          } else if (event == 'message_end') {
            // 兼容仅有 message_end、无 final 的情况
            final msg = data['message'];
            if (msg is Map) {
              final m = Map<String, dynamic>.from(msg);
              takeMessageId(m);
              if (onFinal != null) {
                final payload = m['payload'];
                final text = payload is Map ? '${payload['text'] ?? ''}' : '';
                onFinal({
                  'reply': text,
                  'session_id': m['session_id'],
                  'messages': [m],
                  'emotion': (m['meta'] is Map)
                      ? (m['meta'] as Map)['emotion']
                      : null,
                });
              }
            }
          } else if (event == 'tts_chunk') {
            takeMessageId(data);
            final seq = (data['seq'] as num?)?.toInt() ?? 0;
            final url = '${data['audio_url'] ?? ''}'.trim();
            if (url.isNotEmpty || '${data['text'] ?? ''}'.trim().isNotEmpty) {
              onTtsChunk?.call(
                seq,
                url,
                '${data['text'] ?? ''}',
                data['pending'] == true,
                data['error'] == true,
              );
            }
          } else if (event == 'tts_done') {
            onTtsDone?.call();
          } else if (event == 'error') {
            throw Exception('${data['detail'] ?? 'stream error'}');
          }
        }
      }
    } finally {
      client.close();
    }
  }

  Future<List<MemoryItemDto>> listMemories({
    required String userId,
    required String personaId,
    String? category,
    String? q,
    int limit = 60,
  }) async {
    final res = await http.get(
      _u('/v1/users/${Uri.encodeComponent(userId)}/memories', {
        'persona_id': personaId,
        'limit': '$limit',
        if (category != null && category.isNotEmpty && category != 'all')
          'category': category,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      }),
      headers: _headers(),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '加载记忆失败');
    }
    final list = (data['memories'] as List?) ?? [];
    return list
        .map((e) => MemoryItemDto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<MemoryItemDto> pinMemory({
    required String userId,
    required String memoryId,
    required bool pinned,
  }) async {
    final res = await http.patch(
      _u(
        '/v1/users/${Uri.encodeComponent(userId)}/memories/${Uri.encodeComponent(memoryId)}',
      ),
      headers: _headers(json: true),
      body: jsonEncode({'pinned': pinned}),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '更新失败');
    }
    return MemoryItemDto.fromJson(
      Map<String, dynamic>.from(data['memory'] as Map),
    );
  }

  Future<void> deleteMemoryItem({
    required String userId,
    required String memoryId,
  }) async {
    final res = await http.delete(
      _u(
        '/v1/users/${Uri.encodeComponent(userId)}/memories/${Uri.encodeComponent(memoryId)}',
      ),
      headers: _headers(),
    );
    if (res.statusCode >= 400) {
      final data = _decodeMap(res);
      _throwHttp(res, data, '删除失败');
    }
  }

  Future<void> clearChat({required String userId, required String personaId}) async {
    await http.delete(
      _u('/v1/users/${Uri.encodeComponent(userId)}/chat', {
        'persona_id': personaId,
      }),
      headers: _headers(),
    );
  }

  Future<void> clearMemory({required String userId}) async {
    await http.delete(
      _u('/v1/users/${Uri.encodeComponent(userId)}/memory'),
      headers: _headers(json: true),
      body: jsonEncode({'clear_sessions': false}),
    );
  }

  Future<Map<String, dynamic>> pushConfig() async {
    final res = await http.get(_u('/v1/app/push-config'));
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '拉取推送配置失败');
    }
    return data;
  }

  Future<void> registerPushDevice({
    required String userId,
    required String platform,
    required String registrationId,
    String appVersion = '',
    bool enabled = true,
  }) async {
    final res = await http.post(
      _u('/v1/users/${Uri.encodeComponent(userId)}/push/register'),
      headers: _headers(json: true),
      body: jsonEncode({
        'platform': platform,
        'registration_id': registrationId,
        'app_version': appVersion,
        'enabled': enabled,
      }),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '注册推送设备失败');
    }
  }

  Future<void> revokePushDevice({
    required String userId,
    required String platform,
    required String registrationId,
  }) async {
    final res = await http.post(
      _u('/v1/users/${Uri.encodeComponent(userId)}/push/revoke'),
      headers: _headers(json: true),
      body: jsonEncode({
        'platform': platform,
        'registration_id': registrationId,
      }),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '注销推送设备失败');
    }
  }

  Future<Map<String, dynamic>> testPush({required String userId}) async {
    final res = await http.post(
      _u('/v1/users/${Uri.encodeComponent(userId)}/push/test'),
      headers: _headers(json: true),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '测试推送失败');
    }
    return data;
  }

  Future<Map<String, dynamic>> health() async {
    final res = await http.get(_u('/health'));
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  String _errDetail(Map<String, dynamic> data, int status, String fallback) {
    final d = data['detail'];
    if (d is String && d.isNotEmpty) return d;
    if (d is List && d.isNotEmpty) {
      return d.map((e) => e is Map ? '${e['msg'] ?? e}' : '$e').join('；');
    }
    return '$fallback（$status）';
  }

  int? _retryAfter(http.Response res, Map<String, dynamic> data) {
    final h = res.headers['retry-after'] ?? res.headers['Retry-After'];
    if (h != null) {
      final n = int.tryParse(h);
      if (n != null && n > 0) return n;
    }
    final body = data['retry_after'];
    if (body is num) return body.toInt();
    final detail = data['detail']?.toString() ?? '';
    final m = RegExp(r'(\d+)\s*秒').firstMatch(detail);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  Never _throwHttp(http.Response res, Map<String, dynamic> data, String fallback) {
    final status = res.statusCode;
    if (status == 401) {
      final cb = onUnauthorized;
      if (cb != null) {
        // fire-and-forget：不阻塞当前 throw
        Future.sync(cb);
      }
    }
    throw ApiException(
      _errDetail(data, status, fallback),
      statusCode: status,
      retryAfter: _retryAfter(res, data),
    );
  }

  Map<String, dynamic> _decodeMap(http.Response res) {
    try {
      final raw = jsonDecode(utf8.decode(res.bodyBytes));
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {
      /* fallthrough */
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    required String purpose,
    String? accessToken,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    final res = await http.post(
      _u('/v1/auth/email/send-code'),
      headers: headers,
      body: jsonEncode({'email': email, 'purpose': purpose}),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '验证码发送失败');
    }
    return data;
  }

  Future<AuthSession> register({
    required String email,
    required String code,
    required String password,
  }) async {
    final res = await http.post(
      _u('/v1/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code, 'password': password}),
    );
    return _parseAuthSession(res);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      _u('/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _parseAuthSession(res);
  }

  Future<AuthSession> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final res = await http.post(
      _u('/v1/auth/password/reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'code': code,
        'new_password': newPassword,
      }),
    );
    return _parseAuthSession(res);
  }

  Future<AuthUser> me(String accessToken) async {
    final res = await http.get(
      _u('/v1/auth/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '登录已失效，请重新登录');
    }
    return AuthUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<AuthUser> updateMe({
    required String accessToken,
    String? nickname,
    String? avatarKey,
    String? bio,
  }) async {
    final body = <String, dynamic>{};
    if (nickname != null) body['nickname'] = nickname;
    if (avatarKey != null) body['avatar_key'] = avatarKey;
    if (bio != null) body['bio'] = bio;
    final res = await http.patch(
      _u('/v1/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '保存失败');
    }
    return AuthUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<AuthUser> uploadAvatar({
    required String accessToken,
    required List<int> bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest('POST', _u('/v1/auth/me/avatar'));
    req.headers['Authorization'] = 'Bearer $accessToken';
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '上传失败');
    }
    return AuthUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<AuthSession> changePassword({
    required String accessToken,
    required String oldPassword,
    required String newPassword,
  }) async {
    final res = await http.post(
      _u('/v1/auth/password/change'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );
    return _parseAuthSession(res);
  }

  Future<AuthSession> rebindEmail({
    required String accessToken,
    required String newEmail,
    required String code,
    required String password,
  }) async {
    final res = await http.post(
      _u('/v1/auth/email/rebind'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'new_email': newEmail,
        'code': code,
        'password': password,
      }),
    );
    return _parseAuthSession(res);
  }

  Future<void> deleteAccount({
    required String accessToken,
    required String password,
    required String confirm,
  }) async {
    final res = await http.delete(
      _u('/v1/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'password': password,
        'confirm': confirm,
      }),
    );
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '注销失败');
    }
  }

  Future<List<AvatarPreset>> avatarPresets() async {
    final res = await http.get(_u('/v1/auth/avatar-presets'));
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '加载头像失败');
    }
    final list = (data['presets'] as List? ?? const []);
    return list
        .map((e) => AvatarPreset.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  AuthSession _parseAuthSession(http.Response res) {
    final data = _decodeMap(res);
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '请求失败');
    }
    return AuthSession.fromJson(data);
  }

  Future<Map<String, dynamic>> getCallQuota({required String accessToken}) async {
    final res = await http
        .get(
          _u('/v1/calls/quota'),
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(const Duration(seconds: 20));
    final data = _decodeMap(res);
    if (res.statusCode == 401) {
      await onUnauthorized?.call();
      _throwHttp(res, data, '登录已失效');
    }
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '获取通话额度失败');
    }
    return data;
  }

  Future<Map<String, dynamic>> startVoiceCall({
    required String accessToken,
    required String personaId,
    String? sessionId,
  }) async {
    final body = <String, dynamic>{'persona_id': personaId};
    if (sessionId != null && sessionId.isNotEmpty) {
      body['session_id'] = sessionId;
    }
    final res = await http
        .post(
          _u('/v1/calls/start'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 90));
    final data = _decodeMap(res);
    if (res.statusCode == 401) {
      await onUnauthorized?.call();
      _throwHttp(res, data, '登录已失效');
    }
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '发起通话失败');
    }
    return data;
  }

  Future<Map<String, dynamic>> hangupVoiceCall({
    required String accessToken,
    required String callId,
  }) async {
    final res = await http.post(
      _u('/v1/calls/hangup'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'call_id': callId}),
    );
    final data = _decodeMap(res);
    if (res.statusCode == 401) {
      await onUnauthorized?.call();
      _throwHttp(res, data, '登录已失效');
    }
    if (res.statusCode >= 400) {
      _throwHttp(res, data, '挂断失败');
    }
    return data;
  }
}
