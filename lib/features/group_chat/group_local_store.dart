import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../api/models.dart';

/// 群消息本地缓存 + 已读 seq（不进单聊 ChatLocalStore）
class GroupLocalStore {
  GroupLocalStore._();

  static final GroupLocalStore instance = GroupLocalStore._();

  static const _dbName = 'group_chat.db';
  static const _schemaVersion = 1;

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final base = await getDatabasesPath();
    _db = await openDatabase(
      p.join(base, _dbName),
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE group_messages_local (
            group_id TEXT NOT NULL,
            seq INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (group_id, seq)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_group_msg_seq ON group_messages_local(group_id, seq)',
        );
      },
    );
    return _db!;
  }

  Future<void> upsertMessages(String groupId, List<GroupMessageDto> msgs) async {
    final gid = groupId.trim();
    if (gid.isEmpty || msgs.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final m in msgs) {
      batch.insert(
        'group_messages_local',
        {
          'group_id': gid,
          'seq': m.seq,
          'json': jsonEncode(m.toJson()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<GroupMessageDto>> loadMessages(
    String groupId, {
    int sinceSeq = 0,
    int limit = 80,
  }) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return [];
    final db = await _open();
    // 首屏要最近 limit 条，倒序取完再翻回正序；顺序取会只拿到最老的那批。
    // sinceSeq > 0 是增量补齐，保持顺序取。
    final incremental = sinceSeq > 0;
    final rows = await db.query(
      'group_messages_local',
      where: 'group_id = ? AND seq > ?',
      whereArgs: [gid, sinceSeq],
      orderBy: incremental ? 'seq ASC' : 'seq DESC',
      limit: limit,
    );
    final ordered = incremental ? rows : rows.reversed;
    return ordered
        .map((r) => GroupMessageDto.fromJson(
              jsonDecode(r['json'] as String) as Map<String, dynamic>,
            ))
        .toList();
  }

  Future<int> getLastReadSeq(String groupId) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt('group_read_$groupId') ?? 0;
  }

  /// 首次见到这个群时，把当前进度记为已读起点并返回。
  ///
  /// 没有这层基线的话，本地读不到已读位点就会退成 0，整段历史都被算成未读
  /// （换设备、清数据、或群是别处建的都会踩到）。只有基线之后新增的消息才算未读。
  Future<int> ensureReadBaseline(String groupId, int lastSeq) async {
    final gid = groupId.trim();
    if (gid.isEmpty) return 0;
    final sp = await SharedPreferences.getInstance();
    final key = 'group_read_$gid';
    final existing = sp.getInt(key);
    if (existing != null) return existing;
    final baseline = lastSeq > 0 ? lastSeq : 0;
    await sp.setInt(key, baseline);
    return baseline;
  }

  Future<void> setLastReadSeq(String groupId, int seq) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('group_read_$groupId', seq);
  }

  Future<void> clearGroup(String groupId) async {
    final db = await _open();
    await db.delete(
      'group_messages_local',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final sp = await SharedPreferences.getInstance();
    await sp.remove('group_read_$groupId');
  }
}
