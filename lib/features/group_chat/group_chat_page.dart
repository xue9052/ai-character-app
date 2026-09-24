import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../services/group_ws_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';
import '../../widgets/fullscreen_image_viewer.dart';
import '../../widgets/scene_quota_badge.dart';
import '../chat/chat_top_bar.dart';
import '../personas/persona_cover.dart';
import 'group_local_store.dart';
import 'group_settings_page.dart';
import 'widgets/group_avatar.dart';
import 'widgets/group_bubble.dart';
import 'widgets/group_chat_backdrop.dart';
import 'widgets/group_input_bar.dart';
import 'widgets/group_typing.dart';
import 'widgets/resolve_bar.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({
    super.key,
    required this.group,
    this.initialMessages = const [],
  });

  final GroupSummaryDto group;
  final List<GroupMessageDto> initialMessages;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> with WidgetsBindingObserver {
  final _messages = <GroupMessageDto>[];
  final _inputCtrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _uuid = const Uuid();
  final _typing = <String, String>{};
  final _audioPlayer = AudioPlayer();
  String? _playingVoiceMsgId;
  String? _voiceLoadingMsgId;

  late GroupSummaryDto _group;
  bool _sending = false;
  bool _inputEnabled = true;
  String _inputHint = '说点什么…';
  String? _banner;
  bool _giftSending = false;
  bool _giftOpen = false;
  Set<String> _giftPreselected = {};
  int? _sceneRemaining;
  int? _sceneLimit;

  Map<String, String>? get _imageHeaders {
    final token = AppStateScope.of(context).api().authHeaders();
    return token.isEmpty ? null : token;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_onInputFocus);
    _group = widget.group;
    _messages.addAll(widget.initialMessages);
    _messages.sort((a, b) => a.seq.compareTo(b.seq));
    GroupWsManager.instance.addListener(_onManager);
    GroupWsManager.instance.subscribe(_group.id, _onWsEvent);
    GroupWsManager.instance.setActiveGroup(_group.id);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = AppStateScope.of(context);
      unawaited(
        s.api().markInboxRead(
          userId: s.userId,
          kind: 'group',
          peerId: _group.id,
        ),
      );
      await _bootstrap();
      await GroupWsManager.instance.ensureGroup(_group.id);
      unawaited(_refreshSceneQuota());
    });
  }

  Future<void> _refreshSceneQuota() async {
    if (!mounted) return;
    final s = AppStateScope.of(context);
    try {
      final q = await s.api().getSceneImageQuota(s.userId);
      if (!mounted) return;
      setState(() {
        _sceneRemaining = (q['remaining'] as num?)?.toInt();
        _sceneLimit = (q['limit'] as num?)?.toInt();
      });
    } catch (_) {/* ignore */}
  }

  void _onManager() {
    if (mounted) setState(() {});
  }

  bool get _connecting => !GroupWsManager.instance.isConnected(_group.id);

  @override
  void dispose() {
    final lastSeq = _messages.isEmpty
        ? _group.lastSeq
        : _messages.map((m) => m.seq).reduce((a, b) => a > b ? a : b);
    unawaited(GroupLocalStore.instance.setLastReadSeq(_group.id, lastSeq));
    WidgetsBinding.instance.removeObserver(this);
    _focus.removeListener(_onInputFocus);
    GroupWsManager.instance.removeListener(_onManager);
    GroupWsManager.instance.unsubscribe(_group.id, _onWsEvent);
    if (GroupWsManager.instance.activeGroupId == _group.id) {
      GroupWsManager.instance.setActiveGroup(null);
    }
    _audioPlayer.dispose();
    _inputCtrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _playGroupVoice(GroupMessageDto msg) async {
    final raw = msg.audioUrl.trim();
    if (raw.isEmpty || !mounted) return;
    final s = AppStateScope.of(context);
    final url = resolvePersonaCoverUrl(s.baseUrl, raw) ?? raw;
    setState(() {
      _voiceLoadingMsgId = msg.id;
      _playingVoiceMsgId = null;
    });
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty) {
        throw Exception('音频加载失败');
      }
      await _audioPlayer.stop();
      await _audioPlayer.play(
        BytesSource(res.bodyBytes, mimeType: 'audio/mpeg'),
      );
      if (!mounted) return;
      setState(() {
        _voiceLoadingMsgId = null;
        _playingVoiceMsgId = msg.id;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voiceLoadingMsgId = null;
        _playingVoiceMsgId = null;
      });
    }
  }

  Future<void> _bootstrap() async {
    final local = await GroupLocalStore.instance.loadMessages(_group.id);
    if (local.isNotEmpty && _messages.isEmpty) {
      setState(() => _messages.addAll(local));
    }
    try {
      if (!mounted) return;
      final s = AppStateScope.of(context);
      final data = await s.api().getGroupDetail(_group.id);
      if (!mounted) return;
      final group = GroupSummaryDto.fromJson(
        Map<String, dynamic>.from(data['group'] as Map),
      );
      final msgs = [
        for (final m in (data['messages'] as List? ?? const []))
          GroupMessageDto.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
      setState(() {
        _group = group;
        _mergeMessages(msgs);
      });
      await GroupLocalStore.instance.upsertMessages(_group.id, _messages);
      final readSeq = _messages.isEmpty
          ? _group.lastSeq
          : _messages.map((m) => m.seq).reduce((a, b) => a > b ? a : b);
      await GroupLocalStore.instance.setLastReadSeq(
        _group.id,
        readSeq > _group.lastSeq ? readSeq : _group.lastSeq,
      );
    } catch (_) {/* offline ok */}
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = '${event['type'] ?? ''}';
    if (type == '_closed' || type == '_error') {
      if (mounted) {
        setState(() => _banner = '连接已断开，正在重连…');
      }
      return;
    }
    if (type == 'snapshot') {
      setState(() => _banner = null);
    }
    switch (type) {
      case 'snapshot':
        final msgs = [
          for (final m in (event['messages'] as List? ?? const []))
            GroupMessageDto.fromJson(Map<String, dynamic>.from(m as Map)),
        ];
        final members = [
          for (final m in (event['members'] as List? ?? const []))
            GroupMemberDto.fromJson(Map<String, dynamic>.from(m as Map)),
        ];
        setState(() {
          _mergeMessages(msgs);
          if (members.isNotEmpty) {
            _group = GroupSummaryDto(
              id: _group.id,
              title: _group.title,
              coverUrl: _group.coverUrl,
              lastPreview: _group.lastPreview,
              lastSeq: (event['last_seq'] as num?)?.toInt() ?? _group.lastSeq,
              lastMessageAt: _group.lastMessageAt,
              canSend: _group.canSend,
              members: members,
              memberCovers: _group.memberCovers,
            );
          }
        });
        break;
      case 'message':
        final msg = GroupMessageDto.fromJson(
          Map<String, dynamic>.from(event['message'] as Map),
        );
        _upsertMessage(msg);
        if (msg.isSceneImage) {
          unawaited(_refreshSceneQuota());
        }
        break;
      case 'typing':
        final pid = '${event['persona_id'] ?? ''}';
        final name = _memberName(pid);
        if (pid.isNotEmpty) {
          setState(() => _typing[pid] = name);
        }
        break;
      case 'typing_end':
        final pid = '${event['persona_id'] ?? ''}';
        setState(() => _typing.remove(pid));
        break;
      case 'member_state':
        final pid = '${event['persona_id'] ?? ''}';
        final jealousy = (event['jealousy'] as num?)?.toInt();
        final tier = '${event['tier'] ?? ''}';
        setState(() {
          _group = GroupSummaryDto(
            id: _group.id,
            title: _group.title,
            coverUrl: _group.coverUrl,
            lastPreview: _group.lastPreview,
            lastSeq: _group.lastSeq,
            lastMessageAt: _group.lastMessageAt,
            canSend: _group.canSend,
            members: _group.members.map((m) {
              if (m.personaId != pid) return m;
              return GroupMemberDto(
                personaId: m.personaId,
                name: m.name,
                nameSnapshot: m.nameSnapshot,
                coverUrl: m.coverUrl,
                active: m.active,
                deleted: m.deleted,
                jealousy: jealousy ?? m.jealousy,
                tier: tier.isNotEmpty ? tier : m.tier,
                renamed: m.renamed,
              );
            }).toList(),
            memberCovers: _group.memberCovers,
          );
        });
        break;
      case 'backpressure':
        setState(() {
          _inputEnabled = false;
          _inputHint = '她们还在回…';
        });
        break;
      case 'warning':
        final msg = '${event['message'] ?? ''}';
        if (msg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
        break;
      case 'error':
        final msg = '${event['message'] ?? '发送失败'}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        break;
      case 'pong':
        break;
    }
  }

  void _mergeMessages(List<GroupMessageDto> incoming) {
    for (final m in incoming) {
      _upsertMessage(m, scroll: false);
    }
    _messages.sort((a, b) => a.seq.compareTo(b.seq));
    if (mounted) setState(() {});
    _scrollToEnd();
    unawaited(GroupLocalStore.instance.upsertMessages(_group.id, _messages));
  }

  void _openImage(String url) {
    if (url.isEmpty) return;
    openFullscreenImage(
      context,
      url: url,
      httpHeaders: _imageHeaders,
    );
  }

  Future<void> _markRead(int seq) async {
    if (seq <= 0) return;
    await GroupLocalStore.instance.setLastReadSeq(_group.id, seq);
    if (seq > _group.lastSeq) {
      setState(() {
        _group = GroupSummaryDto(
          id: _group.id,
          title: _group.title,
          coverUrl: _group.coverUrl,
          lastPreview: _group.lastPreview,
          lastSeq: seq,
          lastMessageAt: _group.lastMessageAt,
          canSend: _group.canSend,
          members: _group.members,
          memberCovers: _group.memberCovers,
        );
      });
    }
  }

  void _upsertMessage(GroupMessageDto msg, {bool scroll = true}) {
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    final isNew = idx < 0;
    if (idx >= 0) {
      _messages[idx] = msg;
    } else {
      final byClient = msg.clientMsgId;
      if (byClient != null && byClient.isNotEmpty) {
        final cidx = _messages.indexWhere(
          (m) => m.meta['client_msg_id'] == byClient,
        );
        if (cidx >= 0) {
          _messages[cidx] = msg;
        } else {
          _messages.add(msg);
        }
      } else {
        _messages.add(msg);
      }
    }
    _messages.sort((a, b) => a.seq.compareTo(b.seq));
    if (scroll && mounted) {
      setState(() {});
      _scrollToEnd();
      unawaited(GroupLocalStore.instance.upsertMessages(_group.id, [msg]));
    }
    if (msg.isUser) {
      setState(() {
        _inputEnabled = true;
        _inputHint = '说点什么…';
      });
    }
    unawaited(_markRead(msg.seq));
    if (isNew && msg.isAi && msg.hasVoiceReply) {
      unawaited(_playGroupVoice(msg));
    }
  }

  void _scrollToEnd({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      const target = 0.0;
      if (animated) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  void _onInputFocus() {
    if (_focus.hasFocus) _scrollToEndAfterKeyboard();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    if (MediaQuery.viewInsetsOf(context).bottom > 0 && _focus.hasFocus) {
      _scrollToEndAfterKeyboard();
    }
  }

  void _scrollToEndAfterKeyboard() {
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _scrollToEnd();
    });
  }

  String _memberName(String personaId) {
    return _group.members
            .firstWhere(
              (m) => m.personaId == personaId,
              orElse: () => GroupMemberDto(personaId: personaId, name: ''),
            )
            .name;
  }

  String _memberCover(String personaId, {Map<String, dynamic>? meta}) {
    final member = _group.members.firstWhere(
      (m) => m.personaId == personaId,
      orElse: () => GroupMemberDto(personaId: personaId, name: ''),
    );
    var url = member.coverUrl;
    if (url.isEmpty) return '';
    final v = meta?['cover_v'];
    if (v != null && '$v'.isNotEmpty && !url.contains('v=')) {
      final sep = url.contains('?') ? '&' : '?';
      url = '$url${sep}v=$v';
    }
    return url;
  }

  List<String> get _memberCoverList => _group.effectiveMemberCovers;

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending || !_inputEnabled) return;
    final clientId = 'c_${_uuid.v4()}';
    _inputCtrl.clear();
    final optimistic = GroupMessageDto(
      id: clientId,
      groupId: _group.id,
      seq: _messages.isEmpty ? 1 : _messages.last.seq + 1,
      senderType: 'user',
      senderId: AppStateScope.of(context).userId,
      content: text,
      meta: {'client_msg_id': clientId},
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    setState(() {
      _sending = true;
      _messages.add(optimistic);
    });
    _scrollToEnd();
    try {
      final s = AppStateScope.of(context);
      final data = await s.api().sendGroupMessage(
        groupId: _group.id,
        content: text,
        clientMsgId: clientId,
      );
      if (!mounted) return;
      final msg = GroupMessageDto.fromJson(
        Map<String, dynamic>.from(data['message'] as Map),
      );
      _upsertMessage(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == clientId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMentionSheet() {
    final active = _group.members.where((m) => m.active && !m.deleted).toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgDarkElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择要 @ 的成员'),
              ),
              ...active.map((m) {
                return ListTile(
                  title: Text(m.name),
                  onTap: () {
                    _insertMention(m.name);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _insertMention(String name) {
    final cur = _inputCtrl.text;
    _inputCtrl.text = cur.isEmpty ? '@$name ' : '$cur@$name ';
    _inputCtrl.selection = TextSelection.collapsed(offset: _inputCtrl.text.length);
    _focus.requestFocus();
  }

  void _showMemberActions(String personaId, String name) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgDarkElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              ListTile(
                leading: const Icon(Icons.alternate_email_rounded),
                title: Text('@$name'),
                onTap: () {
                  Navigator.pop(ctx);
                  _insertMention(name);
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_florist_outlined, color: AppColors.accentPink),
                title: Text('送给$name 礼物'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openGiftPanel(preselect: {personaId});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openGiftPanel({Set<String>? preselect}) {
    setState(() {
      _giftOpen = true;
      _giftPreselected = Set<String>.from(preselect ?? const {});
    });
  }

  Future<void> _rememberMessage(GroupMessageDto message) async {
    if (message.isMemory) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgDarkElevated,
        title: const Text('记住这一刻'),
        content: const Text('把这条消息保存成群记忆卡？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('记住'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final s = AppStateScope.of(context);
      final data = await s.api().rememberGroupMessage(
        groupId: _group.id,
        messageId: message.id,
      );
      final card = GroupMessageDto.fromJson(
        Map<String, dynamic>.from(data['message'] as Map),
      );
      _upsertMessage(card);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已记住这一刻')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记住失败：$e')),
        );
      }
    }
  }

  List<GroupMemberDto> get _activeMembers =>
      _group.members.where((m) => m.active && !m.deleted).toList();

  Future<void> _sendGifts(GiftDto gift, List<String> personaIds) async {
    if (_giftSending || !_group.canSend || personaIds.isEmpty) return;
    setState(() => _giftSending = true);
    try {
      final s = AppStateScope.of(context);
      final data = await s.api().sendGroupGift(
        groupId: _group.id,
        personaIds: personaIds,
        giftId: gift.id,
      );
      if (!mounted) return;
      final rawMsgs = data['messages'] as List?;
      final msgs = <GroupMessageDto>[];
      if (rawMsgs != null) {
        for (final m in rawMsgs) {
          msgs.add(
            GroupMessageDto.fromJson(Map<String, dynamic>.from(m as Map)),
          );
        }
      } else if (data['message'] is Map) {
        msgs.add(
          GroupMessageDto.fromJson(
            Map<String, dynamic>.from(data['message'] as Map),
          ),
        );
      }
      final seen = <String>{};
      for (final msg in msgs) {
        if (msg.id.isEmpty || seen.contains(msg.id)) continue;
        seen.add(msg.id);
        _upsertMessage(msg);
      }
      _applyMemberStates(data['member_states'] as List? ?? const []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            personaIds.length > 1
                ? '已送出${gift.name}（${personaIds.length}人）'
                : '已送出${gift.name}',
          ),
        ),
      );
      setState(() => _giftOpen = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _giftSending = false);
    }
  }

  /// 送花化解：走专门的 resolve 接口（降幅更大且不牵连他人），
  /// 礼物用灰度下发的 resolve_gift_id，客户端不指定。
  Future<void> _resolveJealousy(String personaId, String personaName) async {
    if (_giftSending || !_group.canSend || personaId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgDarkElevated,
        title: const Text('送花哄哄她'),
        content: Text('给$personaName送一支花，她会消消气。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('先不了'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('送花'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _giftSending = true);
    try {
      final s = AppStateScope.of(context);
      final data = await s.api().resolveGroupJealousy(
        groupId: _group.id,
        personaId: personaId,
      );
      if (!mounted) return;
      if (data['message'] is Map) {
        _upsertMessage(
          GroupMessageDto.fromJson(
            Map<String, dynamic>.from(data['message'] as Map),
          ),
        );
      }
      _applyMemberStates(data['member_states'] as List? ?? const []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已送花给$personaName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _giftSending = false);
    }
  }

  void _applyMemberStates(List<dynamic> states) {
    for (final raw in states) {
      if (raw is! Map) continue;
      final pid = '${raw['persona_id'] ?? ''}';
      final jealousy = (raw['jealousy'] as num?)?.toInt();
      final tier = '${raw['tier'] ?? ''}';
      if (pid.isEmpty) continue;
      setState(() {
        _group = GroupSummaryDto(
          id: _group.id,
          title: _group.title,
          coverUrl: _group.coverUrl,
          lastPreview: _group.lastPreview,
          lastSeq: _group.lastSeq,
          lastMessageAt: _group.lastMessageAt,
          canSend: _group.canSend,
          members: _group.members.map((m) {
            if (m.personaId != pid) return m;
            return GroupMemberDto(
              personaId: m.personaId,
              name: m.name,
              nameSnapshot: m.nameSnapshot,
              coverUrl: m.coverUrl,
              active: m.active,
              deleted: m.deleted,
              jealousy: jealousy ?? m.jealousy,
              tier: tier.isNotEmpty ? tier : m.tier,
              renamed: m.renamed,
            );
          }).toList(),
          memberCovers: _group.memberCovers,
        );
      });
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_sending || !_inputEnabled || !_group.canSend) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return;

    String caption = '';
    final capCtrl = TextEditingController(text: _inputCtrl.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgDarkElevated,
        title: const Text('发送图片'),
        content: TextField(
          controller: capCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '配文（可选）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('发送')),
        ],
      ),
    );
    if (ok != true) {
      capCtrl.dispose();
      return;
    }
    caption = capCtrl.text.trim();
    capCtrl.dispose();
    _inputCtrl.clear();

    final bytes = await file.readAsBytes();
    final clientId = 'c_${_uuid.v4()}';
    final optimistic = GroupMessageDto(
      id: clientId,
      groupId: _group.id,
      seq: _messages.isEmpty ? 1 : _messages.last.seq + 1,
      senderType: 'user',
      senderId: AppStateScope.of(context).userId,
      content: caption.isNotEmpty ? caption : '[图片]',
      messageType: 'image',
      meta: {'client_msg_id': clientId},
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    setState(() {
      _sending = true;
      _messages.add(optimistic);
    });
    _scrollToEnd();
    try {
      final s = AppStateScope.of(context);
      final data = await s.api().sendGroupImage(
        groupId: _group.id,
        bytes: bytes,
        filename: file.name,
        caption: caption,
        clientMsgId: clientId,
      );
      if (!mounted) return;
      final msg = GroupMessageDto.fromJson(
        Map<String, dynamic>.from(data['message'] as Map),
      );
      _upsertMessage(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => m.id == clientId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送图片失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openSettings() async {
    final dissolved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GroupSettingsPage(
          group: _group,
          onUpdated: (g) => setState(() => _group = g),
          onDissolved: () {},
        ),
      ),
    );
    if (dissolved == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    final typingLabels = _typing.values.toList();
    final showDebug = s.groupChatConfig?.debug == true;
    final memberCovers = _memberCoverList;
    final topInset = MediaQuery.paddingOf(context).top;
    final listTop = ChatTopBar.listTopPadding(topInset);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GroupChatBackdrop(
              baseUrl: s.baseUrl,
              memberCovers: memberCovers,
            ),
          ),
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.only(
                        left: 0,
                        right: 0,
                        top: 8,
                        bottom: listTop,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[_messages.length - 1 - i];
                        final bubble = GroupBubble(
                          message: m,
                          baseUrl: s.baseUrl,
                          memberCoverUrl: _memberCover(
                            m.senderId,
                            meta: m.meta,
                          ),
                          memberName: _memberName(m.senderId),
                          showDebug: showDebug,
                          imageHeaders: _imageHeaders,
                          onMemberLongPress: m.isAi ? _showMemberActions : null,
                          onMessageLongPress: _rememberMessage,
                          onOpenImage: _openImage,
                          onPlayVoice: _playGroupVoice,
                          voicePlaying: _playingVoiceMsgId == m.id,
                          voiceLoading: _voiceLoadingMsgId == m.id,
                        );
                        final children = <Widget>[bubble];
                        if (m.isAi &&
                            m.kind == 'jealous_line' &&
                            m.resolveOffer &&
                            s.groupChatConfig?.resolvePayEnabled == true) {
                          children.add(
                            ResolveBar(
                              personaName: m.senderName.isNotEmpty
                                  ? m.senderName
                                  : _memberName(m.senderId),
                              onTap: () => _resolveJealousy(
                                m.senderId,
                                m.senderName.isNotEmpty
                                    ? m.senderName
                                    : _memberName(m.senderId),
                              ),
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        );
                      },
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ChatTopBar(
                        topInset: topInset,
                        child: Row(
                          children: [
                            FrostIconButton(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () => Navigator.of(context).maybePop(),
                            ),
                            const SizedBox(width: 4),
                            GroupAvatar(
                              baseUrl: s.baseUrl,
                              coverUrl: _group.coverUrl,
                              memberCovers: memberCovers,
                              radius: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _group.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_connecting)
                                    Text(
                                      '连接中…',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.45),
                                      ),
                                    ),
                                  if (_sceneRemaining != null &&
                                      _sceneLimit != null &&
                                      _sceneLimit! > 0) ...[
                                    const SizedBox(height: 4),
                                    SceneQuotaBadge(
                                      remaining: _sceneRemaining,
                                      limit: _sceneLimit,
                                      compact: true,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: FrostIconButton(
                                icon: Icons.more_horiz,
                                onTap: _openSettings,
                                tooltip: '群设置',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_banner != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    _banner!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              if (!_group.canSend)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: FrostSurface(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '群里有效成员不足 2 人，暂时无法发消息。请到群设置添加成员。',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              GroupTypingBar(labels: typingLabels),
              GroupInputBar(
                controller: _inputCtrl,
                focusNode: _focus,
                onSubmit: _send,
                enabled: _inputEnabled && _group.canSend,
                sending: _sending || _giftSending,
                hint: _group.canSend ? _inputHint : '成员不足，无法发送',
                onAtTap: _group.canSend ? _showMentionSheet : null,
                onImageTap: _group.canSend ? _pickAndSendImage : null,
                giftMembers: _activeMembers,
                baseUrl: s.baseUrl,
                userId: s.userId,
                onSendGift: _group.canSend ? _sendGifts : null,
                giftOpen: _giftOpen,
                giftPreselectedIds: _giftPreselected,
                onGiftOpenChanged: (open) => setState(() {
                  _giftOpen = open;
                  if (!open) _giftPreselected = {};
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
