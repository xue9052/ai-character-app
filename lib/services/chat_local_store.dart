import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 本地聊天缓存：每角色最近 30 条 + 会话摘要（聊天页 / 聊天列表秒开）
class ChatLocalStore {
  ChatLocalStore._();

  static final ChatLocalStore instance = ChatLocalStore._();

  static const _dbName = 'chat_cache.db';
  static const _schemaVersion = 1;
  static const localMessageLimit = 30;

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final base = await getDatabasesPath();
    _db = await openDatabase(
      p.join(base, _dbName),
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chat_sessions (
            user_id TEXT NOT NULL,
            persona_id TEXT NOT NULL,
            session_id TEXT,
            persona_name TEXT NOT NULL DEFAULT '',
            one_liner TEXT NOT NULL DEFAULT '',
            cover_url TEXT,
            cover_emoji TEXT,
            cover_color TEXT,
            preview TEXT NOT NULL DEFAULT '',
            total_messages INTEGER NOT NULL DEFAULT 0,
            last_ts INTEGER NOT NULL DEFAULT 0,
            start_index INTEGER NOT NULL DEFAULT 0,
            end_index INTEGER NOT NULL DEFAULT 0,
            has_more INTEGER NOT NULL DEFAULT 0,
            bond_json TEXT,
            persona_json TEXT,
            emotion_json TEXT,
            updated_at INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (user_id, persona_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_messages (
            user_id TEXT NOT NULL,
            persona_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL DEFAULT '',
            payload_json TEXT,
            ts INTEGER NOT NULL DEFAULT 0,
            sort_index INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (user_id, persona_id, message_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_chat_messages_sort ON chat_messages(user_id, persona_id, sort_index)',
        );
        await db.execute(
          'CREATE INDEX idx_chat_sessions_ts ON chat_sessions(user_id, last_ts DESC)',
        );
      },
    );
    return _db!;
  }

  /// 供 ChatPage 首屏：形状对齐 bootstrap 响应
  Future<Map<String, dynamic>?> loadBootstrap(
    String userId,
    String personaId,
  ) async {
    final uid = userId.trim();
    final pid = personaId.trim();
    if (uid.isEmpty || pid.isEmpty) return null;

    final db = await _open();
    final sessionRows = await db.query(
      'chat_sessions',
      where: 'user_id = ? AND persona_id = ?',
      whereArgs: [uid, pid],
      limit: 1,
    );
    if (sessionRows.isEmpty) return null;

    final s = sessionRows.first;
    final msgRows = await db.query(
      'chat_messages',
      where: 'user_id = ? AND persona_id = ?',
      whereArgs: [uid, pid],
      orderBy: 'sort_index ASC',
      limit: localMessageLimit,
    );
    if (msgRows.isEmpty && (s['total_messages'] as int? ?? 0) <= 0) {
      return null;
    }

    final messages = msgRows.map(_messageRowToMap).toList();
    return {
      'session_id': s['session_id'],
      'persona_id': pid,
      'messages': messages,
      'total_messages': s['total_messages'] ?? messages.length,
      'start_index': s['start_index'] ?? 0,
      'end_index': s['end_index'] ?? messages.length,
      'has_more': (s['has_more'] as int? ?? 0) == 1,
      'bond': _decodeJson(s['bond_json'] as String?),
      'persona': _decodeJson(s['persona_json'] as String?),
      'emotion': _decodeJson(s['emotion_json'] as String?),
      '_local': true,
    };
  }

  /// 供 ChatListPage 首屏：形状对齐 /chat/sessions 单项
  Future<List<Map<String, dynamic>>> listSessions(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return [];

    final db = await _open();
    final rows = await db.query(
      'chat_sessions',
      where: 'user_id = ? AND total_messages > 0',
      whereArgs: [uid],
      orderBy: 'last_ts DESC',
      limit: 50,
    );
    return rows.map(_sessionRowToListItem).toList();
  }

  Future<void> saveBootstrap(
    String userId,
    String personaId,
    Map<String, dynamic> data, {
    String? personaName,
    String? oneLiner,
    String? coverUrl,
    String? coverEmoji,
    String? coverColor,
  }) async {
    final uid = userId.trim();
    final pid = personaId.trim();
    if (uid.isEmpty || pid.isEmpty) return;

    final rawMsgs = (data['messages'] as List?) ?? const [];
    if (rawMsgs.isEmpty && (data['total_messages'] as num? ?? 0) <= 0) {
      return;
    }

    final start = (data['start_index'] as num?)?.toInt() ?? 0;
    final end = (data['end_index'] as num?)?.toInt() ??
        (start + rawMsgs.length);
    final total = (data['total_messages'] as num?)?.toInt() ?? rawMsgs.length;
    final preview = _previewFromMessages(rawMsgs);
    final lastTs = _lastTsFromMessages(rawMsgs);

    final personaRaw = data['persona'];
    Map<String, dynamic>? personaMap;
    if (personaRaw is Map) {
      personaMap = Map<String, dynamic>.from(personaRaw);
    }

    final db = await _open();
    final batch = db.batch();

    batch.insert(
      'chat_sessions',
      {
        'user_id': uid,
        'persona_id': pid,
        'session_id': '${data['session_id'] ?? ''}',
        'persona_name': personaName ??
            personaMap?['name'] ??
            pid,
        'one_liner': oneLiner ?? personaMap?['one_liner'] ?? '',
        'cover_url': coverUrl ?? personaMap?['cover_url'],
        'cover_emoji': coverEmoji ?? personaMap?['cover_emoji'],
        'cover_color': coverColor ?? personaMap?['cover_color'],
        'preview': preview,
        'total_messages': total,
        'last_ts': lastTs,
        'start_index': start,
        'end_index': end,
        'has_more': (data['has_more'] == true) ? 1 : 0,
        'bond_json': _encodeJson(data['bond']),
        'persona_json': _encodeJson(personaMap ?? personaRaw),
        'emotion_json': _encodeJson(data['emotion']),
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    batch.delete(
      'chat_messages',
      where: 'user_id = ? AND persona_id = ?',
      whereArgs: [uid, pid],
    );

    final slice = rawMsgs.length > localMessageLimit
        ? rawMsgs.sublist(rawMsgs.length - localMessageLimit)
        : rawMsgs;
    final sliceStart = start + (rawMsgs.length - slice.length);

    for (var i = 0; i < slice.length; i++) {
      final m = slice[i];
      if (m is! Map) continue;
      final map = Map<String, dynamic>.from(m);
      final mid = '${map['id'] ?? map['message_id'] ?? 'local_${sliceStart + i}'}';
      batch.insert(
        'chat_messages',
        {
          'user_id': uid,
          'persona_id': pid,
          'message_id': mid,
          'role': '${map['role'] ?? 'user'}',
          'content': '${map['content'] ?? ''}',
          'payload_json': _encodeJson(map['payload']),
          'ts': _msgTs(map),
          'sort_index': sliceStart + i,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> saveSessionsFromApi(
    String userId,
    List<Map<String, dynamic>> sessions,
  ) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    final db = await _open();
    final batch = db.batch();
    for (final item in sessions) {
      final pid = '${item['persona_id'] ?? ''}'.trim();
      if (pid.isEmpty) continue;
      final total = (item['total_messages'] as num?)?.toInt() ?? 0;
      if (total <= 0) continue;

      batch.insert(
        'chat_sessions',
        {
          'user_id': uid,
          'persona_id': pid,
          'session_id': '${item['session_id'] ?? ''}',
          'persona_name': '${item['persona_name'] ?? pid}',
          'one_liner': '${item['one_liner'] ?? ''}',
          'cover_url': item['cover_url'],
          'cover_emoji': item['cover_emoji'],
          'cover_color': item['cover_color'],
          'preview': '${item['preview'] ?? '暂无消息，点此开始'}',
          'total_messages': total,
          'last_ts': (item['last_ts'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearSession(String userId, String personaId) async {
    final uid = userId.trim();
    final pid = personaId.trim();
    if (uid.isEmpty || pid.isEmpty) return;
    final db = await _open();
    await db.delete(
      'chat_sessions',
      where: 'user_id = ? AND persona_id = ?',
      whereArgs: [uid, pid],
    );
    await db.delete(
      'chat_messages',
      where: 'user_id = ? AND persona_id = ?',
      whereArgs: [uid, pid],
    );
  }

  Future<void> clearUser(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    final db = await _open();
    await db.delete('chat_sessions', where: 'user_id = ?', whereArgs: [uid]);
    await db.delete('chat_messages', where: 'user_id = ?', whereArgs: [uid]);
  }

  Map<String, dynamic> _sessionRowToListItem(Map<String, Object?> row) {
    return {
      'persona_id': row['persona_id'],
      'persona_name': row['persona_name'] ?? row['persona_id'],
      'one_liner': row['one_liner'] ?? '',
      'cover_url': row['cover_url'],
      'cover_emoji': row['cover_emoji'],
      'cover_color': row['cover_color'],
      'preview': row['preview'] ?? '暂无消息，点此开始',
      'total_messages': row['total_messages'] ?? 0,
      'last_ts': row['last_ts'] ?? 0,
      'stage_label': '',
      'source': 'custom',
      '_local': true,
    };
  }

  Map<String, dynamic> _messageRowToMap(Map<String, Object?> row) {
    final payload = _decodeJson(row['payload_json'] as String?);
    return {
      'id': row['message_id'],
      'role': row['role'],
      'content': row['content'],
      if (payload != null) 'payload': payload,
      'ts': row['ts'],
    };
  }

  static String _previewFromMessages(List raw) {
    if (raw.isEmpty) return '暂无消息，点此开始';
    final last = raw.last;
    if (last is! Map) return '（新消息）';
    final role = '${last['role'] ?? ''}';
    var text = '${last['content'] ?? ''}'.trim();
    final payload = last['payload'];
    if (text.isEmpty && payload is Map) {
      text = '${payload['text'] ?? ''}'.trim();
    }
    if (payload is Map && payload['tts_chunks'] is List) {
      final chunks = payload['tts_chunks'] as List;
      if (chunks.isNotEmpty) {
        final sorted = List<Map>.from(chunks.whereType<Map>())
          ..sort(
            (a, b) => ((a['seq'] as num?)?.toInt() ?? 0)
                .compareTo((b['seq'] as num?)?.toInt() ?? 0),
          );
        for (final c in sorted.reversed) {
          final seg = '${c['text'] ?? ''}'.trim();
          if (seg.isNotEmpty) {
            text = seg;
            break;
          }
        }
      }
    }
    if (text.isEmpty) return '（新消息）';
    final prefix = role == 'user' ? '我：' : '';
    final preview = '$prefix$text';
    return preview.length > 120 ? preview.substring(0, 120) : preview;
  }

  static int _lastTsFromMessages(List raw) {
    for (var i = raw.length - 1; i >= 0; i--) {
      final m = raw[i];
      if (m is! Map) continue;
      final ts = _msgTs(Map<String, dynamic>.from(m));
      if (ts > 0) return ts;
    }
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  static int _msgTs(Map<String, dynamic> m) {
    final raw = m['ts'] ?? m['created_at'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  static String? _encodeJson(dynamic v) {
    if (v == null) return null;
    try {
      return jsonEncode(v);
    } catch (_) {
      return null;
    }
  }

  static dynamic _decodeJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
