import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_ui_kit/flutter_ai_ui_kit.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/chat_local_store.dart';
import '../../services/app_state.dart';
import '../../services/greeting_prefs.dart';
import '../../services/voice_reply_planner.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_widgets.dart';
import '../../widgets/gift_svga_overlay.dart';
import '../../widgets/voice_play_chip.dart';
import '../../widgets/scene_memory_card.dart';
import '../../widgets/scene_quota_badge.dart';
import '../memory/memory_page.dart';
import '../personas/persona_cover.dart';
import '../personas/persona_detail_page.dart';
import '../wallet/membership_benefits_page.dart';
import 'chat_backdrop.dart';
import 'chat_top_bar.dart';
import 'bond_display.dart';
import 'voice_call_page.dart';

class _TtsSeg {
  _TtsSeg({
    required this.seq,
    required this.text,
    this.url = '',
    this.pending = false,
    this.error = false,
  });

  final int seq;
  String text;
  String url;
  bool pending;
  bool error;
}

/// 私聊：沉浸壳 + kit 气泡；输入区自研（Web 上套件 Send 常点不动）
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.personaId,
    required this.personaName,
    this.personaOneLiner,
    this.personaCoverUrl,
    this.personaCoverEmoji,
    this.personaCoverColor,
    this.personaBackgroundKey,
    this.personaBackgroundUrl,
    this.initialDraft,
    this.autoSendDraft = false,
  });

  final String personaId;
  final String personaName;
  final String? personaOneLiner;
  final String? personaCoverUrl;
  final String? personaCoverEmoji;
  final String? personaCoverColor;
  final String? personaBackgroundKey;
  final String? personaBackgroundUrl;
  /// 从详情「试聊」带入的草稿
  final String? initialDraft;
  final bool autoSendDraft;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _messages = <ChatMessage>[];
  final _inputCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  String? _sessionId;
  String? _emotionLabel;
  String? _oneLiner;
  String? _coverUrl;
  String? _coverEmoji;
  String? _coverColor;
  String? _backgroundKey;
  String? _backgroundUrl;
  BondDto? _bond;
  bool _sending = false;
  bool _historyLoading = true;
  bool _historyRefreshing = false;
  bool _loadingMore = false;
  bool _hasMoreHistory = false;
  /// 当前已加载区间在全量历史中的起始下标（用于 before_index 上拉）
  int _historyStartIndex = 0;
  /// 服务端全量条数（摘要后仍保留原文，列表数字用这个）
  int _historyTotal = 0;
  String? _error;
  /// 当前列表仅开场白（可跳过；落库后仍为 true 直到用户开口）
  bool _greetingOnly = false;
  String? _greetingText;
  /// 上一轮召回的记忆短句（「TA 想起了」）
  List<String> _recalled = const [];
  /// 消息 id → 附件图 URL（相对或绝对）
  final Map<String, List<String>> _messageImages = {};
  /// 消息 id → 语音 URL
  final Map<String, String> _messageAudioUrls = {};
  /// 本地预览（发图改图等待中）
  final Map<String, Uint8List> _messageLocalBytes = {};
  final Map<String, _ChatMsgExtra> _chatExtras = {};
  int _scenePollGen = 0;
  VoiceReplyPlanner _voicePlanner = VoiceReplyPlanner();
  int? _sceneRemaining;
  int? _sceneLimit;
  /// 助手侧「制作中」占位
  final Set<String> _pendingGenMsgIds = {};
  final Set<String> _ttsLoadingIds = {};
  final _audioPlayer = AudioPlayer();
  String? _playingMsgId;
  String? _voiceProfileId;
  String? _cosyvoiceVoice;
  int? _imageEditRemaining;
  /// 当前全屏礼物特效 URL；播完清空
  String? _giftEffectUrl;
  Completer<void>? _ttsPlayWait;
  final Map<String, Map<int, _TtsSeg>> _messageSegs = {};
  /// 新回复多气泡：已露出的段数（收到即全露，不跟播放进度走）
  final Map<String, int> _segVisibleCount = {};
  /// 随机语音条：这条回复只显示语音，不显示文字。
  final Set<String> _voiceBarIds = {};
  /// 自动朗读的消息：句子语音按序自动播。
  final Set<String> _autoReadMsgIds = {};
  final Map<int, String> _ttsSeqUrls = {};
  final Map<int, String> _ttsSeqTexts = {};
  final Map<String, Map<int, String>> _messageTtsChunks = {};
  int _ttsExpectSeq = 0;
  bool _ttsPumping = false;
  String? _ttsQueueMsgId;
  String? _ttsRevealFull;
  String? _ttsRevealMsgId;
  /// JSON/礼物整段朗读：开声后再把正文填进气泡
  final Map<String, String> _pendingRevealText = {};

  bool get _hasTtsVoice =>
      (_voiceProfileId ?? '').trim().isNotEmpty ||
      (_cosyvoiceVoice ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_onInputFocus);
    _oneLiner = widget.personaOneLiner;
    _coverUrl = widget.personaCoverUrl;
    _coverEmoji = widget.personaCoverEmoji;
    _coverColor = widget.personaCoverColor;
    _backgroundKey = widget.personaBackgroundKey;
    _backgroundUrl = widget.personaBackgroundUrl;
    _scroll.addListener(_onScrollForOlder);
    _audioPlayer.onPlayerComplete.listen((_) {
      final w = _ttsPlayWait;
      if (w != null && !w.isCompleted) w.complete();
      if (mounted) setState(() => _playingMsgId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = AppStateScope.of(context);
      unawaited(
        s.api().markInboxRead(
          userId: s.userId,
          kind: 'direct',
          peerId: widget.personaId,
        ),
      );
      var fromCache = false;

      final local = await ChatLocalStore.instance.loadBootstrap(
        s.userId,
        widget.personaId,
      );
      if (local != null && mounted) {
        _applyBootstrapData(local);
        fromCache = true;
      } else {
        final mem = s.chatBootstrapCache(widget.personaId);
        if (mem != null && mounted) {
          _applyBootstrapData(mem);
          fromCache = true;
        }
      }

      if (fromCache && mounted) {
        setState(() {
          _historyLoading = false;
          _historyRefreshing = true;
        });
      }
      if (mounted) _loadHistory(fromCache: fromCache);
      unawaited(_loadVoicePlanner());
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

  Future<void> _loadVoicePlanner() async {
    final s = AppStateScope.of(context);
    final planner = await VoiceReplyPlanner.load(
      userId: s.userId,
      scopeId: widget.personaId,
    );
    planner.syncTurnCount(_messages.where((m) => m.isUser).length);
    if (mounted) _voicePlanner = planner;
  }

  @override
  void dispose() {
    _markRead();
    WidgetsBinding.instance.removeObserver(this);
    _focus.removeListener(_onInputFocus);
    _scroll.removeListener(_onScrollForOlder);
    final w = _ttsPlayWait;
    if (w != null && !w.isCompleted) w.complete();
    _audioPlayer.dispose();
    _inputCtrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _syncPreviewOnLeave() {
    // 返回列表前再推一次最后一句，防止中途预览被静默 API 覆盖
    if (_messages.isEmpty || !mounted) return;
    final last = _messages.last;
    final text = _listPreviewText(
      text: last.text,
      fromUser: last.isUser,
      msgId: last.id,
    );
    if (text.isEmpty) return;
    AppStateScope.of(context).updateSessionPreview(
      personaId: widget.personaId,
      personaName: widget.personaName,
      oneLiner: _oneLiner,
      text: text,
      fromUser: last.isUser,
      totalMessages: _previewTotal(),
    );
    unawaited(_persistLocalSnapshot());
    _markRead();
  }

  Future<void> _persistLocalSnapshot() async {
    if (_messages.isEmpty || !mounted) return;
    final s = AppStateScope.of(context);
    final raw = <Map<String, dynamic>>[];
    final baseTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final segs = _orderedSegs(m.id);
      final map = <String, dynamic>{
        'id': m.id,
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
        'ts': baseTs - (_messages.length - i),
      };
      if (_voiceBarIds.contains(m.id)) {
        final audio = _messageAudioUrls[m.id] ?? '';
        map['type'] = 'voice';
        map['meta'] = {'voice_reply': true};
        map['payload'] = {
          'text': m.text,
          'voice_reply': true,
          if (audio.isNotEmpty)
            'attachments': [
              {'kind': 'audio', 'url': audio},
            ],
        };
      } else if (segs.isNotEmpty) {
        map['payload'] = {
          'text': m.text,
          'tts_chunks': [
            for (final seg in segs)
              {
                'seq': seg.seq,
                'text': seg.text,
                'audio_url': seg.url,
                'error': seg.error,
              },
          ],
        };
      }
      raw.add(map);
    }

    final bond = _bond;
    final data = <String, dynamic>{
      'session_id': _sessionId,
      'messages': raw,
      'start_index': _historyStartIndex,
      'end_index': _historyStartIndex + raw.length,
      'total_messages': _previewTotal(),
      'has_more': _hasMoreHistory,
      if (bond != null)
        'bond': {
          'bond': bond.bond,
          'stage': bond.stage,
          'stage_label': bond.stageLabel,
          'progress_in_stage': bond.progressInStage,
        },
      'persona': {
        'id': widget.personaId,
        'name': widget.personaName,
        'one_liner': _oneLiner ?? widget.personaOneLiner,
        'greeting': _greetingText,
        'cover_url': _coverUrl ?? widget.personaCoverUrl,
        'cover_emoji': _coverEmoji ?? widget.personaCoverEmoji,
        'cover_color': _coverColor ?? widget.personaCoverColor,
        'background_key': _backgroundKey ?? widget.personaBackgroundKey,
        'background_url': _backgroundUrl ?? widget.personaBackgroundUrl,
        'voice_profile_id': _voiceProfileId,
      },
    };

    await ChatLocalStore.instance.saveBootstrap(
      s.userId,
      widget.personaId,
      data,
      personaName: widget.personaName,
      oneLiner: _oneLiner ?? widget.personaOneLiner,
      coverUrl: _coverUrl ?? widget.personaCoverUrl,
      coverEmoji: _coverEmoji ?? widget.personaCoverEmoji,
      coverColor: _coverColor ?? widget.personaCoverColor,
    );
    s.setChatBootstrapCache(widget.personaId, data);
  }

  int _previewTotal() {
    final n = _messages.where((m) => m.isUser || m.isAssistant).length;
    final loaded = _historyStartIndex + n;
    if (_historyTotal > loaded) return _historyTotal;
    return loaded;
  }

  void _markRead() {
    if (!mounted) return;
    final s = AppStateScope.of(context);
    final readTotal = _historyTotal > 0
        ? (_historyTotal > _previewTotal() ? _historyTotal : _previewTotal())
        : _previewTotal();
    unawaited(ChatLocalStore.instance.setLastReadTotal(
      s.userId,
      widget.personaId,
      readTotal,
    ));
  }

  /// 会话列表预览：多气泡 assistant 取最后一段，避免单行省略只露出第一句。
  String _listPreviewText({
    required String text,
    required bool fromUser,
    String? msgId,
  }) {
    if (fromUser) return text.trim();
    if (msgId != null && _voiceBarIds.contains(msgId)) return '[语音]';
    if (msgId != null) {
      final segs = _orderedSegs(msgId);
      if (segs.isNotEmpty) {
        final last = segs.last.text.trim();
        if (last.isNotEmpty) return last;
      }
    }
    return text.trim();
  }

  List<ChatMessage> _mapRawMessages(
    List raw, {
    bool clearImages = true,
    int indexOffset = 0,
  }) {
      if (clearImages) {
      _messageImages.clear();
      _messageAudioUrls.clear();
      _messageSegs.clear();
      _segVisibleCount.clear();
      _voiceBarIds.clear();
      _autoReadMsgIds.clear();
      _chatExtras.clear();
    }
    final out = <ChatMessage>[];
    for (var i = 0; i < raw.length; i++) {
      final m = ChatMessageDto.fromJson(
        Map<String, dynamic>.from(raw[i] as Map),
      );
      final id = (m.id != null && m.id!.isNotEmpty)
          ? m.id!
          : 'hist_${indexOffset + i}';
      final msg = _ingestDto(m, id);
      if (msg != null) out.add(msg);
    }
    return out;
  }

  ChatMessage? _ingestDto(ChatMessageDto m, String id) {
    if (m.imageUrls.isNotEmpty) {
      _messageImages[id] = List<String>.from(m.imageUrls);
    }
    if (m.audioUrl != null && m.audioUrl!.isNotEmpty) {
      _messageAudioUrls[id] = m.audioUrl!;
    }
    final imageUrl = m.memoryImageUrl;
    if (imageUrl.isNotEmpty && (_messageImages[id] ?? const []).isEmpty) {
      _messageImages[id] = [imageUrl];
    }
    _chatExtras[id] = _ChatMsgExtra(
      isMemory: m.isMemory,
      isSceneImage: m.isSceneImage,
      sceneTitle: m.isMemory ? m.memoryCardTitle : m.sceneTitle,
      summary: m.memorySummary,
      imageUrl: imageUrl,
    );
    final text = m.content.isNotEmpty
        ? m.content
        : (m.imageUrls.isNotEmpty ? '[图片]' : '');
    if (m.isVoiceReply) {
      _voiceBarIds.add(id);
    } else if (m.ttsChunks.isNotEmpty) {
      _ingestTtsChunks(id, m.ttsChunks);
      _segVisibleCount[id] = _orderedSegs(id).length;
    }
    if (m.isMemory) {
      return ChatMessage.assistant(
        id: id,
        text: text,
        senderName: widget.personaName,
      );
    }
    if (m.role == 'assistant') {
      return ChatMessage.assistant(
        id: id,
        text: text,
        senderName: widget.personaName,
      );
    }
    return ChatMessage.user(id: id, text: text);
  }

  bool _appendRawMessage(Map<String, dynamic> raw) {
    final m = ChatMessageDto.fromJson(raw);
    final id = (m.id != null && m.id!.isNotEmpty) ? m.id! : '';
    if (id.isEmpty || _messages.any((x) => x.id == id)) return false;
    final msg = _ingestDto(m, id);
    if (msg == null) return false;
    _messages.add(msg);
    return true;
  }

  Future<void> _pollSceneFollowups() async {
    final gen = ++_scenePollGen;
    final s = AppStateScope.of(context);
    var stableRounds = 0;
    for (var i = 0; i < 30; i++) {
      if (!mounted || gen != _scenePollGen) return;
      await Future<void>.delayed(Duration(seconds: i == 0 ? 3 : 2));
      if (!mounted || gen != _scenePollGen) return;
      try {
        final data = await s.api().getChat(
          userId: s.userId,
          personaId: widget.personaId,
          limit: 40,
        );
        if (gen != _scenePollGen) return;
        final raw = (data['messages'] as List?) ?? const [];
        var gotNew = false;
        for (final item in raw) {
          if (item is! Map) continue;
          if (_appendRawMessage(Map<String, dynamic>.from(item))) {
            gotNew = true;
          }
        }
        if (gotNew) {
          stableRounds = 0;
          if (mounted) {
            setState(() {});
            _scrollToBottom();
            _markRead();
          }
          unawaited(_persistLocalSnapshot());
          unawaited(_refreshSceneQuota());
        } else {
          stableRounds++;
          if (stableRounds >= 3 && i >= 2) break;
        }
      } catch (_) {/* ignore */ }
    }
    unawaited(_refreshSceneQuota());
  }

  Future<void> _rememberMessage(ChatMessage message) async {
    final extra = _chatExtras[message.id];
    if (extra?.isMemory == true) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgDarkElevated,
        title: const Text('记住这一刻'),
        content: const Text('把这条消息保存成场景记忆卡？'),
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
      final data = await s.api().rememberChatMessage(
        userId: s.userId,
        personaId: widget.personaId,
        messageId: message.id,
      );
      final cardRaw = data['message'];
      if (cardRaw is Map && _appendRawMessage(Map<String, dynamic>.from(cardRaw))) {
        if (mounted) {
          setState(() {});
          _scrollToBottom();
          _markRead();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已记住这一刻')),
          );
        }
        unawaited(_persistLocalSnapshot());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记住失败：$e')),
        );
      }
    }
  }

  void _applyHistoryPageMeta(Map<String, dynamic> data) {
    _historyStartIndex = (data['start_index'] as num?)?.toInt() ?? 0;
    final total = (data['total_messages'] as num?)?.toInt();
    if (total != null && total >= 0) {
      _historyTotal = total;
    }
    final hasMore = data['has_more'];
    if (hasMore is bool) {
      _hasMoreHistory = hasMore;
    } else {
      final n = total ?? 0;
      _hasMoreHistory = _historyStartIndex > 0 || n > _messages.length;
    }
  }

  void _onScrollForOlder() {
    if (!_scroll.hasClients || _historyLoading || _loadingMore || !_hasMoreHistory) {
      return;
    }
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 72) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMore || !_hasMoreHistory || _historyLoading) return;
    final s = AppStateScope.of(context);
    setState(() => _loadingMore = true);
    try {
      final data = await s.api().getChat(
            userId: s.userId,
            personaId: widget.personaId,
            limit: 30,
            beforeIndex: _historyStartIndex,
          );
      if (!mounted) return;
      final raw = (data['messages'] as List?) ?? [];
      if (raw.isEmpty) {
        setState(() {
          _hasMoreHistory = false;
          _loadingMore = false;
        });
        return;
      }
      final older = _mapRawMessages(
        raw,
        clearImages: false,
        indexOffset: (data['start_index'] as num?)?.toInt() ?? 0,
      );
      final existingIds = _messages.map((m) => m.id).toSet();
      final unique = older.where((m) => !existingIds.contains(m.id)).toList();
      if (unique.isEmpty) {
        setState(() {
          _applyHistoryPageMeta(data);
          _hasMoreHistory = false;
          _loadingMore = false;
        });
        return;
      }

      final prevPixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
      final prevMax =
          _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;

      setState(() {
        _messages.insertAll(0, unique);
        _applyHistoryPageMeta(data);
        _loadingMore = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final newMax = _scroll.position.maxScrollExtent;
        final delta = newMax - prevMax;
        _scroll.jumpTo(prevPixels + delta);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _applyBootstrapData(Map<String, dynamic> data) {
    _sessionId = data['session_id'] as String?;
    final emo = EmotionDto.fromJson(
      data['emotion'] is Map
          ? Map<String, dynamic>.from(data['emotion'] as Map)
          : null,
    );
    _emotionLabel = emo.label;
    final raw = (data['messages'] as List?) ?? [];
    final start = (data['start_index'] as num?)?.toInt() ?? 0;
    _messages
      ..clear()
      ..addAll(_mapRawMessages(raw, indexOffset: start));
    _applyHistoryPageMeta(data);
    _greetingOnly = false;
    _greetingText = null;
    _error = null;

    final bondRaw = data['bond'];
    if (bondRaw is Map) {
      _bond = BondDto.fromJson(Map<String, dynamic>.from(bondRaw));
    }

    final personaRaw = data['persona'];
    if (personaRaw is Map) {
      _applyPersonaLite(Map<String, dynamic>.from(personaRaw));
    }
    _voicePlanner.syncTurnCount(_messages.where((m) => m.isUser).length);
    _markRead();
  }

  Future<void> _loadHistory({bool fromCache = false}) async {
    final s = AppStateScope.of(context);
    final api = s.api();
    if (mounted && !fromCache) setState(() => _historyLoading = true);
    try {
      Map<String, dynamic> data;
      try {
        final parts = await Future.wait([
          api.getChat(
            userId: s.userId,
            personaId: widget.personaId,
            limit: 30,
            seedGreeting: false,
          ),
          api.getChatMeta(
            userId: s.userId,
            personaId: widget.personaId,
          ),
        ]);
        final chat = parts[0];
        final meta = parts[1];
        data = <String, dynamic>{
          ...chat,
          'persona': meta['persona'],
          'bond': meta['bond'],
          'greeting': meta['greeting'] ?? chat['greeting'],
        };
      } catch (_) {
        // 旧服务端无 /chat/meta 时回退 bootstrap
        try {
          data = await api.getChatBootstrap(
            userId: s.userId,
            personaId: widget.personaId,
            limit: 30,
          );
        } catch (_) {
          data = await api.getChat(
            userId: s.userId,
            personaId: widget.personaId,
            limit: 30,
            seedGreeting: false,
          );
        }
      }

      _applyBootstrapData(data);
      if (mounted) {
        setState(() {
          _historyLoading = false;
          _historyRefreshing = false;
        });
        _scrollToBottom(animated: false, force: !fromCache);
        _maybeApplyInitialDraft();
      }

      s.setChatBootstrapCache(widget.personaId, data);
      unawaited(
        ChatLocalStore.instance.saveBootstrap(
          s.userId,
          widget.personaId,
          data,
          personaName: widget.personaName,
          oneLiner: _oneLiner ?? widget.personaOneLiner,
          coverUrl: _coverUrl ?? widget.personaCoverUrl,
          coverEmoji: _coverEmoji ?? widget.personaCoverEmoji,
          coverColor: _coverColor ?? widget.personaCoverColor,
        ),
      );

      final seeded = data['seeded'] == true;
      if (!seeded && _messages.isEmpty) {
        unawaited(_maybeSeedGreeting(api, s));
      } else {
        _markGreetingOnlyFromMessages();
      }
    } catch (e) {
      _error = apiErrorMessage(e);
      if (mounted) {
        setState(() {
          _historyLoading = false;
          _historyRefreshing = false;
        });
      }
    }
  }

  void _markGreetingOnlyFromMessages() {
    if (_messages.length == 1 &&
        _messages.first.isAssistant &&
        (_greetingText == null ||
            _messages.first.text.trim() == _greetingText)) {
      _greetingOnly = true;
      if (mounted) setState(() {});
    }
  }

  void _applyPersonaLite(Map<String, dynamic> p) {
    _oneLiner = '${p['one_liner'] ?? ''}'.trim().isNotEmpty
        ? '${p['one_liner']}'
        : _oneLiner;
    final cover = p['cover_url'] as String?;
    if (cover != null && cover.isNotEmpty) _coverUrl = cover;
    final emoji = p['cover_emoji'] as String?;
    if (emoji != null && emoji.isNotEmpty) _coverEmoji = emoji;
    final color = p['cover_color'] as String?;
    if (color != null && color.isNotEmpty) _coverColor = color;
    final bgKey = p['background_key'] as String?;
    _backgroundKey = (bgKey != null && bgKey.isNotEmpty) ? bgKey : _backgroundKey;
    final bgUrl = p['background_url'] as String?;
    // 没有专用背景时清空，ChatBackdrop 会用封面
    _backgroundUrl = (bgUrl != null && bgUrl.isNotEmpty) ? bgUrl : null;
    final g = '${p['greeting'] ?? ''}'.trim();
    _greetingText = g.isNotEmpty ? g : null;
    final vp = '${p['voice_profile_id'] ?? ''}'.trim();
    if (vp.isNotEmpty) _voiceProfileId = vp;
    final cv = '${p['cosyvoice_voice'] ?? ''}'.trim();
    if (cv.isNotEmpty) _cosyvoiceVoice = cv;
  }

  void _applyPersonaDetail(PersonaDetail persona) {
    _oneLiner = persona.oneLiner?.isNotEmpty == true
        ? persona.oneLiner
        : _oneLiner;
    _coverUrl =
        persona.coverUrl?.isNotEmpty == true ? persona.coverUrl : _coverUrl;
    _coverEmoji = persona.coverEmoji?.isNotEmpty == true
        ? persona.coverEmoji
        : _coverEmoji;
    _coverColor = persona.coverColor?.isNotEmpty == true
        ? persona.coverColor
        : _coverColor;
    _backgroundKey = persona.backgroundKey?.isNotEmpty == true
        ? persona.backgroundKey
        : _backgroundKey;
    _backgroundUrl = persona.backgroundUrl?.isNotEmpty == true
        ? persona.backgroundUrl
        : _backgroundUrl;
    final g = persona.greeting?.trim();
    _greetingText = (g != null && g.isNotEmpty) ? g : null;
    _voiceProfileId = persona.voiceProfileId;
    _cosyvoiceVoice = persona.cosyvoiceVoice;
  }

  Future<void> _maybeSeedGreeting(ApiClient api, AppState s) async {
    if (_messages.isEmpty && _greetingText != null) {
      final skipped = await GreetingPrefs.isSkipped(
        userId: s.userId,
        personaId: widget.personaId,
      );
      if (!skipped) {
        final seeded = await api.seedGreeting(
          userId: s.userId,
          personaId: widget.personaId,
        );
        _sessionId = seeded['session_id'] as String? ?? _sessionId;
        _applyBond(seeded['bond']);
        final seededMsgs = (seeded['messages'] as List?) ?? [];
        if (seededMsgs.isNotEmpty) {
          _messages
            ..clear()
            ..addAll(_mapRawMessages(seededMsgs));
        } else {
          _messages.add(
            ChatMessage.assistant(
              id: const Uuid().v4(),
              text: _greetingText!,
              senderName: widget.personaName,
            ),
          );
        }
        _greetingOnly = _messages.length == 1 && _messages.first.isAssistant;
        if (_greetingOnly) {
          s.updateSessionPreview(
            personaId: widget.personaId,
            personaName: widget.personaName,
            oneLiner: _oneLiner,
            text: _messages.first.text,
            fromUser: false,
            totalMessages: 1,
          );
        }
        if (mounted) {
          setState(() {
            _greetingOnly = _messages.length == 1 && _messages.first.isAssistant;
          });
          _scrollToBottom(animated: false);
        }
      }
    } else if (_messages.length == 1 &&
        _messages.first.isAssistant &&
        _greetingText != null &&
        _messages.first.text.trim() == _greetingText) {
      _greetingOnly = true;
    }
  }

  void _maybeApplyInitialDraft() {
    final draft = widget.initialDraft?.trim();
    if (draft == null || draft.isEmpty) return;
    _inputCtrl.text = draft;
    if (widget.autoSendDraft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onSend(draft);
      });
    }
  }

  Future<void> _skipGreeting() async {
    if (!_greetingOnly || _sending) return;
    final s = AppStateScope.of(context);
    try {
      await s.api().clearChat(
        userId: s.userId,
        personaId: widget.personaId,
      );
      s.clearChatBootstrapCache(widget.personaId);
      await ChatLocalStore.instance.clearSession(s.userId, widget.personaId);
      await GreetingPrefs.setSkipped(
        userId: s.userId,
        personaId: widget.personaId,
        skipped: true,
      );
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _historyStartIndex = 0;
        _historyTotal = 0;
        _hasMoreHistory = false;
        _greetingOnly = false;
      });
      s.clearSessionPreview(widget.personaId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已跳过开场白，直接开聊吧')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.offset.abs() < 4;
  }

  void _scrollToBottom({bool animated = true, bool force = false}) {
    if (!force && _isNearBottom()) return;

    Future<void> run(int left) async {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      const target = 0.0;
      if (animated && left <= 1) {
        await _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
      if (left <= 1 || !mounted || !_scroll.hasClients) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!mounted || !_scroll.hasClients) return;
      if (!_isNearBottom()) {
        await run(left - 1);
      }
    }

    unawaited(run(4));
  }

  void _onInputFocus() {
    if (_focus.hasFocus) _scrollToBottomAfterKeyboard();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    if (MediaQuery.viewInsetsOf(context).bottom > 0 && _focus.hasFocus) {
      _scrollToBottomAfterKeyboard();
    }
  }

  void _scrollToBottomAfterKeyboard() {
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _scrollToBottom(force: true);
    });
  }

  void _applyBond(dynamic raw) {
    if (raw is! Map) return;
    final m = Map<String, dynamic>.from(raw);
    final cur = _bond;
    final prevStage = cur?.stage;
    // 聊天响应里的 bond 是快照，不含贴纸列表；合并进现有对象
    if (cur == null) {
      _bond = BondDto.fromJson({
        ...m,
        'stickers': const [],
        'quick_replies_extra': const [],
      });
      return;
    }
    _bond = BondDto(
      bond: (m['bond'] as num?)?.toInt() ?? cur.bond,
      stage: '${m['stage'] ?? cur.stage}',
      stageLabel: '${m['stage_label'] ?? cur.stageLabel}',
      progressInStage:
          (m['progress_in_stage'] as num?)?.toDouble() ?? cur.progressInStage,
      stickers: cur.stickers,
      quickRepliesExtra: cur.quickRepliesExtra,
    );
    _maybeAnnounceStageUp(prevStage, _bond);
  }

  /// 本窗口随机抽一轮：回复是一条语音，不是文字。与自动朗读无关。
  bool _wantRandomVoiceTts(AppState s) {
    if (!_hasTtsVoice) return false;
    return _voicePlanner.markUserSent();
  }

  bool _wantAutoPlayVoice(AppState s) {
    if (s.user?.nightMode ?? false) return false;
    return s.autoTts;
  }

  Future<void> _persistVoicePlanner() async {
    if (!mounted) return;
    final s = AppStateScope.of(context);
    await _voicePlanner.save(userId: s.userId, scopeId: widget.personaId);
  }

  /// 随机语音条：整段合成一条语音，界面只留语音条。
  Future<void> _finishVoiceBar({
    required AppState s,
    required String messageId,
    required String text,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;
    _voiceBarIds.add(messageId);
    if (mounted) {
      setState(() => _ttsLoadingIds.add(messageId));
    }
    try {
      final data = await s.api().chatTts(
        userId: s.userId,
        personaId: widget.personaId,
        messageId: messageId,
        sessionId: _sessionId,
        text: body,
      );
      final url = '${data['audio_url'] ?? ''}'.trim();
      if (!mounted) return;
      if (url.isNotEmpty) {
        _messageAudioUrls[messageId] = url;
      }
      setState(() => _ttsLoadingIds.remove(messageId));
      unawaited(_persistLocalSnapshot());
      final night = s.user?.nightMode ?? false;
      if (url.isNotEmpty && !night) {
        final abs = resolvePersonaCoverUrl(s.baseUrl, url) ?? url;
        await _playAbsAudioWait(abs, messageId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _ttsLoadingIds.remove(messageId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  Future<void> _playVoiceBar(ChatMessage m) async {
    if (_ttsLoadingIds.contains(m.id)) return;
    final existing = (_messageAudioUrls[m.id] ?? '').trim();
    if (existing.isNotEmpty) {
      final s = AppStateScope.of(context);
      final abs = resolvePersonaCoverUrl(s.baseUrl, existing) ?? existing;
      await _playAbsAudioWait(abs, m.id);
      return;
    }
    final s = AppStateScope.of(context);
    await _finishVoiceBar(s: s, messageId: m.id, text: m.text);
  }

  void _maybeAnnounceStageUp(String? prevStage, BondDto? next) {
    if (!mounted || next == null || prevStage == null) return;
    if (prevStage == next.stage) return;
    // 仅在阶段前进时提示（降级不弹庆祝）
    const order = ['stranger', 'familiar', 'close', 'bonded'];
    final a = order.indexOf(prevStage);
    final b = order.indexOf(next.stage);
    if (a < 0 || b <= a) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim, _) {
        return Center(
          child: Material(
            color: const Color(0xFF1C241C),
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('✨', style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 10),
                    const Text(
                      '关系升级了',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      BondDisplay.stageUpTitle(next.stage),
                      style: const TextStyle(
                        color: Color(0xFFB8D4B8),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      BondDisplay.progressHint(next.progressInStage),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('继续聊'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
    );
  }

  void _applyRecalled(dynamic raw) {
    if (raw is! List) {
      if (mounted) setState(() => _recalled = const []);
      return;
    }
    final list = <String>[
      for (final x in raw)
        if ('$x'.trim().isNotEmpty) '$x'.trim(),
    ];
    if (mounted) setState(() => _recalled = list.take(3).toList());
  }

  Future<void> _refreshBond() async {
    if (!mounted) return;
    try {
      final s = AppStateScope.of(context);
      final prevStage = _bond?.stage;
      final b = await s.api().getBond(
            userId: s.userId,
            personaId: widget.personaId,
          );
      if (mounted) {
        setState(() => _bond = b);
        _maybeAnnounceStageUp(prevStage, b);
      }
    } catch (_) {/* ignore */}
  }

  static bool _looksLikeSticker(String text) {
    final t = text.trim();
    if (t.isEmpty || t.length > 8) return false;
    // 单枚/少量 emoji：无字母数字为主
    return !RegExp(r'[A-Za-z0-9\u4e00-\u9fff]').hasMatch(t);
  }

  void _playGiftEffect(GiftDto gift) {
    final raw = gift.effectUrl.trim();
    if (raw.isEmpty) return;
    final url = AppStateScope.of(context).api().resolveUrl(raw);
    if (url.isEmpty) return;
    setState(() => _giftEffectUrl = url);
  }

  Future<void> _sendGift(GiftDto gift) async {
    if (_sending) return;
    final s = AppStateScope.of(context);
    final api = s.api();
    final display = '🎁 ${gift.name}';
    setState(() {
      if (_greetingOnly) _greetingOnly = false;
      _messages.add(ChatMessage.user(id: const Uuid().v4(), text: display));
      _sending = true;
    });
    _playGiftEffect(gift);
    await GreetingPrefs.setSkipped(
      userId: s.userId,
      personaId: widget.personaId,
      skipped: false,
    );
    s.updateSessionPreview(
      personaId: widget.personaId,
      personaName: widget.personaName,
      oneLiner: _oneLiner,
      text: display,
      fromUser: true,
      totalMessages: _previewTotal(),
    );
    _scrollToBottom();
    try {
      final data = await api.sendGift(
        userId: s.userId,
        personaId: widget.personaId,
        sessionId: _sessionId,
        giftId: gift.id,
      );
      _sessionId = data['session_id'] as String? ?? _sessionId;
      final emo = EmotionDto.fromJson(
        data['emotion'] is Map
            ? Map<String, dynamic>.from(data['emotion'] as Map)
            : null,
      );
      _emotionLabel = emo.label ?? _emotionLabel;
      _applyBond(data['bond']);
      final reply = '${data['reply'] ?? ''}';
      final fb = data['feedback'];
      if (!mounted) return;
      final replyId = _serverMessageId(data) ?? const Uuid().v4();
      setState(() {
        _messages.add(
          ChatMessage.assistant(
            id: replyId,
            text: reply,
            senderName: widget.personaName,
          ),
        );
      });
      _pushPreview(reply, fromUser: false, msgId: replyId);
      if (fb is Map && mounted) {
        final toast = '${fb['toast'] ?? ''}';
        if (toast.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(toast)),
          );
        }
        final eu = '${fb['effect_url'] ?? ''}'.trim();
        if ((_giftEffectUrl == null || _giftEffectUrl!.isEmpty) &&
            eu.isNotEmpty) {
          final url = AppStateScope.of(context).api().resolveUrl(eu);
          if (url.isNotEmpty) {
            setState(() => _giftEffectUrl = url);
          }
        }
      }
      await _refreshBond();
      // 送礼不自动朗读；有后端分段则多气泡展示
      if (mounted) {
        _applyBackendChunks(
          replyId,
          _chunksFromChatPayload(Map<String, dynamic>.from(data)),
        );
      }
    } catch (e) {
      _showSendError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _submit() async {
    final trimmed = _inputCtrl.text.trim();
    if (trimmed.isEmpty || _sending) return;
    _inputCtrl.clear();
    await _onSend(trimmed);
    _focus.requestFocus();
  }

  Future<void> _onSend(String trimmed) async {
    final s = AppStateScope.of(context);
    final api = s.api();

    setState(() {
      if (_greetingOnly) {
        // 开场白已落库并保留；用户开口后不再显示「跳过」
        _greetingOnly = false;
      }
      _messages.add(ChatMessage.user(id: const Uuid().v4(), text: trimmed));
      _sending = true;
    });
    // 用户开口后允许下次清空聊天再看开场白
    await GreetingPrefs.setSkipped(
      userId: s.userId,
      personaId: widget.personaId,
      skipped: false,
    );
    // 立刻更新会话列表预览（用户句），返回列表不必等二次请求
    s.updateSessionPreview(
      personaId: widget.personaId,
      personaName: widget.personaName,
      oneLiner: _oneLiner,
      text: trimmed,
      fromUser: true,
      totalMessages: _previewTotal(),
    );
    _scrollToBottom();

    final preferStream = s.useStream;
    final voiceBar = _wantRandomVoiceTts(s);
    final autoRead = !voiceBar && _hasTtsVoice && _wantAutoPlayVoice(s);
    unawaited(_persistVoicePlanner());

    try {
      if (preferStream) {
        await _sendStream(
          api,
          s,
          trimmed,
          voiceBar: voiceBar,
          autoRead: autoRead,
        );
      } else {
        await _sendJson(
          api,
          s,
          trimmed,
          voiceBar: voiceBar,
          autoRead: autoRead,
        );
      }
    } catch (e) {
      if (preferStream) {
        try {
          await _sendJson(
            api,
            s,
            trimmed,
            voiceBar: voiceBar,
            autoRead: autoRead,
          );
        } catch (e2) {
          _showSendError(e2);
        }
      } else {
        _showSendError(e);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _pushPreview(String text, {required bool fromUser, String? msgId}) {
    if (!mounted) return;
    final preview = _listPreviewText(
      text: text,
      fromUser: fromUser,
      msgId: msgId,
    );
    if (preview.isEmpty) return;
    AppStateScope.of(context).updateSessionPreview(
      personaId: widget.personaId,
      personaName: widget.personaName,
      oneLiner: _oneLiner,
      text: preview,
      fromUser: fromUser,
      totalMessages: _previewTotal(),
    );
    _markRead();
  }

  void _showSendError(Object e) {
    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage.assistant(
          id: const Uuid().v4(),
          text: '发送失败：$e',
          senderName: '系统',
        ),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('发送失败：$e')),
    );
  }

  String? _serverMessageId(Map<String, dynamic> data) {
    final msgs = data['messages'];
    if (msgs is List && msgs.isNotEmpty && msgs.first is Map) {
      final id = '${(msgs.first as Map)['id'] ?? ''}'.trim();
      if (id.isNotEmpty) return id;
    }
    final mid = '${data['message_id'] ?? ''}'.trim();
    return mid.isEmpty ? null : mid;
  }

  Future<void> _sendJson(
    ApiClient api,
    AppState s,
    String trimmed, {
    bool voiceBar = false,
    bool autoRead = false,
  }) async {
    final data = await api.chat(
      userId: s.userId,
      personaId: widget.personaId,
      sessionId: _sessionId,
      message: trimmed,
      voiceBar: voiceBar,
    );
    _sessionId = data['session_id'] as String? ?? _sessionId;
    final emo = EmotionDto.fromJson(
      data['emotion'] is Map
          ? Map<String, dynamic>.from(data['emotion'] as Map)
          : null,
    );
    _emotionLabel = emo.label ?? _emotionLabel;
    _applyBond(data['bond']);
    _applyRecalled(data['recalled']);
    final reply = '${data['reply'] ?? ''}';
    final replyId = _serverMessageId(data) ?? const Uuid().v4();
    if (!mounted) return;
    if (voiceBar) _voiceBarIds.add(replyId);
    if (autoRead) _autoReadMsgIds.add(replyId);
    setState(() {
      _messages.add(
        ChatMessage.assistant(
          id: replyId,
          text: reply,
          senderName: widget.personaName,
        ),
      );
    });
    if (voiceBar && reply.trim().isNotEmpty) {
      _pushPreview('[语音]', fromUser: false, msgId: replyId);
      unawaited(_finishVoiceBar(s: s, messageId: replyId, text: reply));
    } else if (mounted && reply.trim().isNotEmpty) {
      final chunks = _chunksFromChatPayload(Map<String, dynamic>.from(data));
      if (chunks.isNotEmpty) {
        _applyBackendChunks(replyId, chunks);
      }
      _pushPreview(reply, fromUser: false, msgId: replyId);
      if (autoRead) {
        unawaited(_synthSegsInOrder(replyId));
      }
    }
    await _refreshBond();
    unawaited(_persistLocalSnapshot());
    unawaited(_pollSceneFollowups());
  }

  Future<void> _sendStream(
    ApiClient api,
    AppState s,
    String trimmed, {
    bool voiceBar = false,
    bool autoRead = false,
  }) async {
    var assistantId = const Uuid().v4();
    var assembled = '';
    if (voiceBar) _voiceBarIds.add(assistantId);
    if (autoRead) _autoReadMsgIds.add(assistantId);
    setState(() {
      _messages.add(
        ChatMessage.assistant(
          id: assistantId,
          text: voiceBar ? '' : '…',
          senderName: widget.personaName,
        ),
      );
      if (voiceBar) _ttsLoadingIds.add(assistantId);
    });
    void adoptServerId(String serverId) {
      final sid = serverId.trim();
      if (sid.isEmpty || sid == assistantId) return;
      final oldId = assistantId;
      assistantId = sid;
      final idx = _messages.indexWhere((m) => m.id == oldId);
      if (idx >= 0 && mounted) {
        final keep = _messages[idx].text;
        setState(() {
          _messages[idx] = ChatMessage.assistant(
            id: assistantId,
            text: voiceBar ? keep : (assembled.isEmpty ? '…' : assembled),
            senderName: widget.personaName,
          );
        });
      }
      final audio = _messageAudioUrls.remove(oldId);
      if (audio != null) _messageAudioUrls[assistantId] = audio;
      final chunks = _messageTtsChunks.remove(oldId);
      if (chunks != null) _messageTtsChunks[assistantId] = chunks;
      final segs = _messageSegs.remove(oldId);
      if (segs != null) _messageSegs[assistantId] = segs;
      final vis = _segVisibleCount.remove(oldId);
      if (vis != null) _segVisibleCount[assistantId] = vis;
      if (_voiceBarIds.remove(oldId)) _voiceBarIds.add(assistantId);
      if (_autoReadMsgIds.remove(oldId)) _autoReadMsgIds.add(assistantId);
      if (_ttsQueueMsgId == oldId) _ttsQueueMsgId = assistantId;
      final pending = _pendingRevealText.remove(oldId);
      if (pending != null) _pendingRevealText[assistantId] = pending;
      if (_ttsLoadingIds.remove(oldId)) _ttsLoadingIds.add(assistantId);
      if (_playingMsgId == oldId) _playingMsgId = assistantId;
    }

    if (autoRead) {
      await _audioPlayer.stop();
      _resetTtsQueue(assistantId);
    }
    var gotTtsChunks = false;
    await for (final token in api.chatStreamTokens(
      userId: s.userId,
      personaId: widget.personaId,
      sessionId: _sessionId,
      message: trimmed,
      ttsEnabled: autoRead,
      voiceBar: voiceBar,
      onMessageId: adoptServerId,
      onTtsChunk: (seq, url, text, pending, error) {
        if (voiceBar) return;
        gotTtsChunks = true;
        _upsertSeg(
          assistantId,
          seq,
          text: text,
          url: url,
          pending: pending && url.isEmpty && !error,
          error: error,
          rebuild: false,
        );
        _showAllSegs(assistantId);
        if (url.trim().isNotEmpty) {
          _enqueueTtsChunk(assistantId, seq, url, text);
        }
      },
      onFinal: (finalPayload) {
        _sessionId = finalPayload['session_id'] as String? ?? _sessionId;
        final sid = _serverMessageId(finalPayload);
        if (sid != null) adoptServerId(sid);
        final emo = EmotionDto.fromJson(
          finalPayload['emotion'] is Map
              ? Map<String, dynamic>.from(finalPayload['emotion'] as Map)
              : null,
        );
        _emotionLabel = emo.label ?? _emotionLabel;
        _applyBond(finalPayload['bond']);
        _applyRecalled(finalPayload['recalled']);
        if (voiceBar) return;
        final chunks = _chunksFromChatPayload(finalPayload);
        if (chunks.isNotEmpty && _orderedSegs(assistantId).isEmpty) {
          _applyBackendChunks(assistantId, chunks);
        }
      },
    )) {
      assembled += token;
      // 分段气泡或语音条都不把全文写进单气泡
      if (voiceBar || gotTtsChunks || autoRead) continue;
      final idx = _messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0 && mounted) {
        setState(() {
          _messages[idx] = ChatMessage.assistant(
            id: assistantId,
            text: assembled.isEmpty ? '…' : assembled,
            senderName: widget.personaName,
          );
        });
        _scrollToBottom();
      }
    }
    if (assembled.isEmpty && mounted && !voiceBar) {
      final idx = _messages.indexWhere((m) => m.id == assistantId);
      if (idx >= 0) {
        setState(() {
          _messages[idx] = ChatMessage.assistant(
            id: assistantId,
            text: '（空回复，请重试或关闭流式）',
            senderName: widget.personaName,
          );
        });
      }
    } else if (assembled.isNotEmpty) {
      if (voiceBar) {
        final idx = _messages.indexWhere((m) => m.id == assistantId);
        if (idx >= 0) {
          _messages[idx] = ChatMessage.assistant(
            id: assistantId,
            text: assembled,
            senderName: widget.personaName,
          );
        }
        _pushPreview('[语音]', fromUser: false, msgId: assistantId);
        if (mounted) setState(() {});
        unawaited(_finishVoiceBar(s: s, messageId: assistantId, text: assembled));
      } else {
        _pushPreview(assembled, fromUser: false, msgId: assistantId);
        if (mounted) {
          if (gotTtsChunks) {
            final idx = _messages.indexWhere((m) => m.id == assistantId);
            if (idx >= 0) {
              _messages[idx] = ChatMessage.assistant(
                id: assistantId,
                text: assembled,
                senderName: widget.personaName,
              );
            }
            _showAllSegs(assistantId);
            if (mounted) setState(() {});
          } else {
            _setAssistantBubble(assistantId, assembled);
          }
        }
      }
    }
    await _refreshBond();
    unawaited(_persistLocalSnapshot());
    unawaited(_pollSceneFollowups());
  }

  void _openMore() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgDarkElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('查看角色'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PersonaDetailPage(personaId: widget.personaId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('记忆本'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MemoryPage(personaId: widget.personaId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('清空聊天'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final s = AppStateScope.of(context);
                  await s.api().clearChat(
                    userId: s.userId,
                    personaId: widget.personaId,
                  );
                  s.clearChatBootstrapCache(widget.personaId);
      await ChatLocalStore.instance.clearSession(s.userId, widget.personaId);
                  await GreetingPrefs.setSkipped(
                    userId: s.userId,
                    personaId: widget.personaId,
                    skipped: false,
                  );
                  if (!mounted) return;
                  setState(() {
                    _messages.clear();
                    _historyStartIndex = 0;
                    _historyTotal = 0;
                    _hasMoreHistory = false;
                    _greetingOnly = false;
                    _historyLoading = true;
                  });
                  s.clearSessionPreview(widget.personaId);
                  await _loadHistory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('清空长期记忆'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final s = AppStateScope.of(context);
                  await s.api().clearMemory(userId: s.userId);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清空长期记忆')),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  bool _canRegenerate(int index) {
    if (_sending || _greetingOnly) return false;
    if (index < 0 || index >= _messages.length) return false;
    final m = _messages[index];
    if (!m.isAssistant) return false;
    // 仅允许重说「最后一条角色回复」，且前一条是用户
    if (index != _messages.length - 1) return false;
    if (index == 0) return false;
    return _messages[index - 1].isUser;
  }

  Future<void> _copyMessage(ChatMessage m) async {
    await Clipboard.setData(ClipboardData(text: m.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  void _quoteMessage(ChatMessage m) {
    final quote = m.text.trim();
    if (quote.isEmpty) return;
    final clipped =
        quote.length > 80 ? '${quote.substring(0, 80)}…' : quote;
    final prefix = '「$clipped」\n';
    final cur = _inputCtrl.text;
    _inputCtrl.text = cur.isEmpty ? prefix : '$prefix$cur';
    _inputCtrl.selection = TextSelection.collapsed(offset: _inputCtrl.text.length);
    _focus.requestFocus();
  }

  Future<void> _regenerateAt(int index) async {
    if (!_canRegenerate(index) || _sending) return;
    final s = AppStateScope.of(context);
    setState(() {
      // 先撤掉界面上的末条 assistant
      _messages.removeLast();
      _sending = true;
    });
    _scrollToBottom();
    try {
      final data = await s.api().regenerate(
        userId: s.userId,
        personaId: widget.personaId,
        sessionId: _sessionId,
      );
      _sessionId = data['session_id'] as String? ?? _sessionId;
      final emo = EmotionDto.fromJson(
        data['emotion'] is Map
            ? Map<String, dynamic>.from(data['emotion'] as Map)
            : null,
      );
      _emotionLabel = emo.label ?? _emotionLabel;
      final reply = '${data['reply'] ?? ''}';
      final replyId = _serverMessageId(data) ?? const Uuid().v4();
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage.assistant(
            id: replyId,
            text: reply,
            senderName: widget.personaName,
          ),
        );
      });
      _pushPreview(reply, fromUser: false, msgId: replyId);
      final chunks = _chunksFromChatPayload(Map<String, dynamic>.from(data));
      if (chunks.isNotEmpty) {
        _applyBackendChunks(replyId, chunks);
      }
      if (_hasTtsVoice && _wantAutoPlayVoice(s) && reply.trim().isNotEmpty) {
        _autoReadMsgIds.add(replyId);
        unawaited(_synthSegsInOrder(replyId));
      }
    } catch (e) {
      if (!mounted) return;
      // 失败时重新拉历史，避免本地与服务器不一致
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
      setState(() => _historyLoading = true);
      await _loadHistory();
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _openMessageActions(ChatMessage m, int index) async {
    final canRegen = _canRegenerate(index);
    final isMemory = _chatExtras[m.id]?.isMemory == true;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgDarkElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyMessage(m);
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_quote_outlined),
                title: const Text('引用'),
                onTap: () {
                  Navigator.pop(ctx);
                  _quoteMessage(m);
                },
              ),
              if (!m.isUser && !isMemory)
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: const Text('记住这一刻'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _rememberMessage(m);
                  },
                ),
              if (canRegen)
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('重说'),
                  subtitle: const Text('按上一句重新生成角色回复'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _regenerateAt(index);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 不用套件内置头像（默认会显示 You→「Y」），外层统一画账号/角色头像
  Widget _bubbleRow(ChatMessage m, {required bool animate, required int index}) {
    final isUser = m.isUser;
    final sticker = _looksLikeSticker(m.text);
    final images = _messageImages[m.id] ?? const <String>[];
    final localBytes = _messageLocalBytes[m.id];
    final pending = _pendingGenMsgIds.contains(m.id);
    final baseUrl = AppStateScope.of(context).baseUrl;
    final showText = !sticker &&
        m.text.trim().isNotEmpty &&
        m.text.trim() != '[图片]' &&
        !pending;
    final voiceBar = !isUser && _voiceBarIds.contains(m.id);
    final segs = _orderedSegs(m.id);
    final visibleN = (_segVisibleCount[m.id] ?? (segs.isEmpty ? 0 : segs.length))
        .clamp(0, segs.length);
    final shownSegs = segs.take(visibleN).toList();
    final hasVoice = !isUser && !voiceBar && !sticker && _hasTtsVoice;
    final useSegs = !isUser && !voiceBar && segs.isNotEmpty && shownSegs.isNotEmpty;
    final Widget textBubble;
    if (voiceBar) {
      textBubble = VoicePlayChip(
        playing: _playingMsgId == m.id,
        loading: _ttsLoadingIds.contains(m.id),
        label: '语音',
        onTap: () => unawaited(_playVoiceBar(m)),
      );
    } else if (sticker) {
      textBubble = _ImmersiveBubble(text: m.text.trim(), isUser: isUser, emoji: true);
    } else if (!showText) {
      textBubble = const SizedBox.shrink();
    } else if (useSegs) {
      textBubble = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < shownSegs.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            if (hasVoice) _segAudioChip(m.id, shownSegs[i]),
            _assistantSentenceBubble(shownSegs[i].text),
          ],
        ],
      );
    } else {
      textBubble = Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (hasVoice && m.text.trim() != '…')
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: VoicePlayChip(
                playing: _messageTtsPlaying(m.id),
                loading: _messageTtsLoading(m.id),
                label: '语音',
                onTap: () => unawaited(_playMessageTts(m)),
              ),
            ),
          _ImmersiveBubble(text: m.text, isUser: isUser),
        ],
      );
    }
    final mediaChildren = <Widget>[];
    final extra = _chatExtras[m.id];
    if (extra?.isSceneImage == true && extra!.sceneTitle.isNotEmpty) {
      mediaChildren.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            extra.sceneTitle,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.accentPink.withValues(alpha: 0.9),
            ),
          ),
        ),
      );
    }
    if (pending) {
      mediaChildren.add(const _ImageGenPlaceholder());
      if (showText || sticker) mediaChildren.add(const SizedBox(height: 6));
    } else if (localBytes != null) {
      mediaChildren.add(
        GestureDetector(
          onTap: () => _openImageViewer(bytes: localBytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 280),
              child: Image.memory(localBytes, fit: BoxFit.cover),
            ),
          ),
        ),
      );
      if (showText || sticker || images.isNotEmpty) {
        mediaChildren.add(const SizedBox(height: 6));
      }
    }
    for (final raw in images) {
      final url = resolvePersonaCoverUrl(baseUrl, raw) ?? raw;
      mediaChildren.add(
        GestureDetector(
          onTap: () => _openImageViewer(url: url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 280),
              child: _ChatNetworkImage(
                url: url,
                fit: BoxFit.cover,
                placeholderWidth: 160,
                placeholderHeight: 160,
              ),
            ),
          ),
        ),
      );
      if (showText || sticker) mediaChildren.add(const SizedBox(height: 6));
    }
    final bubble = Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        ...mediaChildren,
        textBubble,
      ],
    );
    return GestureDetector(
      onLongPress: sticker ? null : () => _openMessageActions(m, index),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(child: bubble),
        ],
      ),
    );
  }

  void _openImageViewer({String? url, Uint8List? bytes}) {
    if ((url == null || url.isEmpty) && bytes == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (_, __, ___) => _FullscreenImageViewer(
          url: url,
          bytes: bytes,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _ingestTtsChunks(String msgId, List<Map<String, dynamic>> raw) {
    for (final c in raw) {
      final seq = (c['seq'] as num?)?.toInt() ?? 0;
      final text = '${c['text'] ?? ''}'.trim();
      final url = '${c['audio_url'] ?? ''}'.trim();
      final explicitPending = c['pending'] == true;
      _upsertSeg(
        msgId,
        seq,
        text: text,
        url: url,
        pending: explicitPending && url.isEmpty && c['error'] != true,
        error: c['error'] == true,
        rebuild: false,
      );
    }
  }

  /// 从 chat / final 响应里取后端分段（不本地切句）
  List<Map<String, dynamic>> _chunksFromChatPayload(Map<String, dynamic> data) {
    final out = <Map<String, dynamic>>[];
    void take(dynamic raw) {
      if (raw is! List) return;
      for (final c in raw) {
        if (c is Map) out.add(Map<String, dynamic>.from(c));
      }
    }

    take(data['tts_chunks']);
    final msgs = data['messages'];
    if (out.isEmpty && msgs is List && msgs.isNotEmpty && msgs.first is Map) {
      final m = Map<String, dynamic>.from(msgs.first as Map);
      final payload = m['payload'];
      if (payload is Map) take(payload['tts_chunks']);
    }
    final message = data['message'];
    if (out.isEmpty && message is Map) {
      final payload = message['payload'];
      if (payload is Map) take(payload['tts_chunks']);
    }
    return out;
  }

  void _showAllSegs(String msgId) {
    final n = _orderedSegs(msgId).length;
    if (n <= 0) return;
    _segVisibleCount[msgId] = n;
    if (mounted) setState(() {});
  }

  void _applyBackendChunks(
    String msgId,
    List<Map<String, dynamic>> chunks,
  ) {
    if (chunks.isEmpty) return;
    _ingestTtsChunks(msgId, chunks);
    _showAllSegs(msgId);
  }

  void _upsertSeg(
    String msgId,
    int seq, {
    String text = '',
    String url = '',
    bool pending = false,
    bool error = false,
    bool rebuild = true,
  }) {
    final map = _messageSegs.putIfAbsent(msgId, () => <int, _TtsSeg>{});
    final cur = map[seq];
    if (cur == null) {
      map[seq] = _TtsSeg(
        seq: seq,
        text: text,
        url: url,
        pending: pending,
        error: error,
      );
    } else {
      if (text.isNotEmpty) cur.text = text;
      if (url.isNotEmpty) cur.url = url;
      cur.pending = pending;
      cur.error = error;
      if (url.isNotEmpty) {
        cur.pending = false;
        cur.error = false;
      }
    }
    final joined = (map.keys.toList()..sort())
        .map((k) => map[k]!.text)
        .where((t) => t.trim().isNotEmpty)
        .join();
    if (joined.isNotEmpty) {
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx >= 0) {
        _messages[idx] = ChatMessage.assistant(
          id: msgId,
          text: joined,
          senderName: widget.personaName,
        );
      }
    }
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _synthSegsInOrder(String msgId) async {
    final s = AppStateScope.of(context);
    final segs = _orderedSegs(msgId);
    for (final seg in segs) {
      if (!mounted) return;
      if (seg.url.isNotEmpty) {
        _enqueueTtsChunk(msgId, seg.seq, seg.url, seg.text);
        continue;
      }
      _upsertSeg(msgId, seg.seq, text: seg.text, pending: true);
      try {
        final data = await s.api().chatTts(
              userId: s.userId,
              personaId: widget.personaId,
              messageId: msgId,
              sessionId: _sessionId,
              text: seg.text,
              clip: true,
            );
        final url = '${data['audio_url'] ?? ''}'.trim();
        _upsertSeg(msgId, seg.seq, text: seg.text, url: url, pending: false, error: url.isEmpty);
        if (url.isNotEmpty) {
          _enqueueTtsChunk(msgId, seg.seq, url, seg.text);
        }
      } catch (_) {
        _upsertSeg(msgId, seg.seq, text: seg.text, pending: false, error: true);
      }
    }
    unawaited(_persistLocalSnapshot());
  }

  List<_TtsSeg> _orderedSegs(String msgId) {
    final map = _messageSegs[msgId];
    if (map == null || map.isEmpty) return const [];
    final keys = map.keys.toList()..sort();
    return [for (final k in keys) map[k]!];
  }

  String _segPlayId(String msgId, int seq) => '$msgId#$seq';

  Future<void> _onSegAudioTap(String msgId, _TtsSeg seg) async {
    final live = _orderedSegs(msgId).where((s) => s.seq == seg.seq);
    final target = live.isEmpty ? seg : live.first;
    if (target.pending) return;
    if (target.url.isEmpty || target.error) {
      await _retrySeg(msgId, target);
      return;
    }
    final s = AppStateScope.of(context);
    final abs = resolvePersonaCoverUrl(s.baseUrl, target.url) ?? target.url;
    await _playAbsAudioWait(abs, _segPlayId(msgId, target.seq));
  }

  Future<void> _retrySeg(String msgId, _TtsSeg seg) async {
    final s = AppStateScope.of(context);
    _upsertSeg(msgId, seg.seq, text: seg.text, pending: true, error: false);
    try {
      final data = await s.api().chatTts(
            userId: s.userId,
            personaId: widget.personaId,
            messageId: msgId,
            sessionId: _sessionId,
            text: seg.text,
            clip: true,
          );
      final url = '${data['audio_url'] ?? ''}'.trim();
      _upsertSeg(msgId, seg.seq, text: seg.text, url: url, pending: false, error: url.isEmpty);
      unawaited(_persistLocalSnapshot());
      if (url.isNotEmpty) {
        final abs = resolvePersonaCoverUrl(s.baseUrl, url) ?? url;
        await _playAbsAudioWait(abs, _segPlayId(msgId, seg.seq));
      }
    } catch (e) {
      _upsertSeg(msgId, seg.seq, text: seg.text, pending: false, error: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  bool _messageTtsLoading(String msgId) {
    if (_ttsLoadingIds.contains(msgId)) return true;
    return _orderedSegs(msgId).any((s) => s.pending);
  }

  bool _messageTtsPlaying(String msgId) {
    if (_playingMsgId == msgId) return true;
    return _orderedSegs(msgId)
        .any((s) => _playingMsgId == _segPlayId(msgId, s.seq));
  }

  Widget _segAudioChip(String msgId, _TtsSeg seg) {
    final playId = _segPlayId(msgId, seg.seq);
    final loading = seg.pending || _ttsLoadingIds.contains(playId);
    final playing = _playingMsgId == playId;
    String label = '语音';
    if (loading) {
      label = '生成中';
    } else if (playing) {
      label = '播放中';
    } else if (seg.error) {
      label = '重试';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: loading ? null : () => _onSegAudioTap(msgId, seg),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                )
              else
                Icon(
                  playing
                      ? Icons.volume_up_rounded
                      : (seg.error
                          ? Icons.refresh_rounded
                          : Icons.volume_up_outlined),
                  size: 16,
                  color: Colors.white70,
                ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assistantSentenceBubble(String text) {
    return _ImmersiveBubble(
      text: text.trim().isEmpty ? '…' : text.trim(),
      isUser: false,
    );
  }

  void _setAssistantBubble(String msgId, String text) {
    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx < 0 || !mounted) return;
    setState(() {
      _messages[idx] = ChatMessage.assistant(
        id: msgId,
        text: text.isEmpty ? '…' : text,
        senderName: widget.personaName,
      );
    });
    _scrollToBottom();
  }

  void _appendSpokenText(String msgId, String piece) {
    if (piece.isEmpty) return;
    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx < 0 || !mounted) return;
    var cur = _messages[idx].text;
    if (cur == '…') cur = '';
    _setAssistantBubble(msgId, '$cur$piece');
  }

  void _fillSpokenRemainder(String msgId) {
    final full = _ttsRevealFull;
    if (full == null || full.isEmpty) return;
    if (_ttsRevealMsgId != null && _ttsRevealMsgId != msgId) return;
    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    final shown = _messages[idx].text;
    if (shown == '…' || shown.isEmpty) {
      _setAssistantBubble(msgId, full);
      return;
    }
    if (full.length > shown.length &&
        (full.startsWith(shown) || shown == '…')) {
      _setAssistantBubble(msgId, full);
    }
  }

  void _resetTtsQueue(String msgId) {
    _ttsSeqUrls.clear();
    _ttsSeqTexts.clear();
    _ttsExpectSeq = 0;
    _ttsPumping = false;
    _ttsQueueMsgId = msgId;
    _ttsRevealFull = null;
    _ttsRevealMsgId = msgId;
    _messageTtsChunks[msgId] = {};
    final w = _ttsPlayWait;
    if (w != null && !w.isCompleted) w.complete();
  }

  void _enqueueTtsChunk(String msgId, int seq, String url, [String text = '']) {
    if (!_autoReadMsgIds.contains(msgId)) return;
    if (url.trim().isEmpty) return;
    _ttsQueueMsgId = msgId;
    (_messageTtsChunks[msgId] ??= {})[seq] = url;
    _ttsSeqUrls[seq] = url;
    if (text.isNotEmpty) _ttsSeqTexts[seq] = text;
    unawaited(_pumpTtsQueue());
  }

  Future<void> _pumpTtsQueue() async {
    if (_ttsPumping || !mounted) return;
    _ttsPumping = true;
    try {
      final s = AppStateScope.of(context);
      final baseUrl = s.baseUrl;
      final playId = _ttsQueueMsgId ?? '';
      while (_ttsSeqUrls.containsKey(_ttsExpectSeq)) {
        final seq = _ttsExpectSeq;
        final url = _ttsSeqUrls.remove(seq)!;
        final piece = _ttsSeqTexts.remove(seq) ?? '';
        _ttsExpectSeq++;
        final abs = resolvePersonaCoverUrl(baseUrl, url) ?? url;
        if (!mounted) return;
        if (_orderedSegs(playId).isEmpty) {
          _appendSpokenText(playId, piece);
        }
        await _playAbsAudioWait(abs, _segPlayId(playId, seq));
      }
      if (playId.isNotEmpty && _orderedSegs(playId).isEmpty) {
        _fillSpokenRemainder(playId);
      }
    } finally {
      _ttsPumping = false;
      if (_ttsSeqUrls.containsKey(_ttsExpectSeq) && mounted) {
        unawaited(_pumpTtsQueue());
      }
    }
  }

  Future<void> _playAbsAudioWait(String absUrl, String playId) async {
    final done = Completer<void>();
    _ttsPlayWait = done;
    try {
      await _playAbsAudio(absUrl, playId);
      await done.future.timeout(const Duration(seconds: 90));
    } on TimeoutException {
      // 单句超时则继续下一句
    } finally {
      if (identical(_ttsPlayWait, done)) _ttsPlayWait = null;
    }
  }

  /// 先拉完整音频再播，避免 UrlSource 显示「播放中」却长时间无声。
  Future<void> _playAbsAudio(String absUrl, String playId) async {
    final uri = Uri.parse(absUrl);
    final res = await http.get(uri).timeout(const Duration(seconds: 60));
    if (res.statusCode >= 400 || res.bodyBytes.isEmpty) {
      throw Exception('音频下载失败 HTTP ${res.statusCode}');
    }
    final bytes = res.bodyBytes;
    var mime = res.headers['content-type']?.split(';').first.trim();
    if (mime == null || mime.isEmpty || mime == 'application/octet-stream') {
      if (absUrl.toLowerCase().contains('.wav') ||
          (bytes.length >= 4 &&
              bytes[0] == 0x52 &&
              bytes[1] == 0x49 &&
              bytes[2] == 0x46 &&
              bytes[3] == 0x46)) {
        mime = 'audio/wav';
      } else {
        mime = 'audio/mpeg';
      }
    }
    await _audioPlayer.stop();
    await _audioPlayer.play(BytesSource(bytes, mimeType: mime));
    if (!mounted) return;
    final pending = _pendingRevealText.remove(playId);
    if (pending != null && pending.isNotEmpty) {
      _setAssistantBubble(playId, pending);
    }
    setState(() {
      _ttsLoadingIds.remove(playId);
      _playingMsgId = playId;
    });
  }

  Future<void> _playMessageTts(ChatMessage m) async {
    if (!m.isAssistant) return;
    if (_voiceBarIds.contains(m.id)) {
      await _playVoiceBar(m);
      return;
    }
    final text = m.text.trim();
    if (text.isEmpty || text.startsWith('[图片]')) return;
    if (!_hasTtsVoice) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该角色尚未绑定音色')),
      );
      return;
    }
    _autoReadMsgIds.add(m.id);
    if (_orderedSegs(m.id).isEmpty) {
      _upsertSeg(m.id, 0, text: text, pending: true, rebuild: false);
      _segVisibleCount[m.id] = 1;
    }
    unawaited(_synthSegsInOrder(m.id));
  }

  Future<void> _pickAndEditImage() async {
    if (_sending) return;
    final s = AppStateScope.of(context);
    final api = s.api();
    try {
      final q = await api.getImageEditQuota(userId: s.userId);
      final remaining = (q['remaining'] as num?)?.toInt() ?? 0;
      final limit = (q['limit'] as num?)?.toInt() ?? 5;
      if (mounted) setState(() => _imageEditRemaining = remaining);
      if (remaining <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('今日改图次数已用完（$limit/天），可在后台调整上限')),
        );
        return;
      }
    } catch (_) {
      /* 配额拉取失败仍允许尝试，由服务端拦截 */
    }

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final initialPrompt = _inputCtrl.text.trim();
    final remaining = _imageEditRemaining;
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => _ImageEditPromptDialog(
        initialPrompt: initialPrompt,
        remaining: remaining,
        imageBytes: Uint8List.fromList(bytes),
      ),
    );
    if (prompt == null || !mounted) return;
    if (prompt.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请写一句改图要求')),
      );
      return;
    }

    await _sendImageEdit(Uint8List.fromList(bytes), file.name, prompt.trim());
  }

  Future<void> _sendImageEdit(
    Uint8List bytes,
    String filename,
    String prompt,
  ) async {
    final s = AppStateScope.of(context);
    final api = s.api();
    final userMsgId = const Uuid().v4();
    final asstId = const Uuid().v4();
    setState(() {
      if (_greetingOnly) _greetingOnly = false;
      _messages.add(ChatMessage.user(id: userMsgId, text: '[图片] $prompt'));
      _messageLocalBytes[userMsgId] = bytes;
      _messages.add(
        ChatMessage.assistant(
          id: asstId,
          text: '图片制作中…',
          senderName: widget.personaName,
        ),
      );
      _pendingGenMsgIds.add(asstId);
      _sending = true;
      _inputCtrl.clear();
    });
    _scrollToBottom();
    try {
      final data = await api.chatImageEdit(
        userId: s.userId,
        personaId: widget.personaId,
        bytes: bytes,
        filename: filename.isNotEmpty ? filename : 'image.jpg',
        prompt: prompt,
        sessionId: _sessionId,
      );
      _sessionId = data['session_id'] as String? ?? _sessionId;
      final asst = data['assistant_message'];
      final user = data['user_message'];
      final quota = data['quota'];
      if (quota is Map) {
        _imageEditRemaining = (quota['remaining'] as num?)?.toInt();
      }
      if (!mounted) return;
      setState(() {
        _pendingGenMsgIds.remove(asstId);
        _messageLocalBytes.remove(userMsgId);
        if (user is Map) {
          final dto = ChatMessageDto.fromJson(Map<String, dynamic>.from(user));
          if (dto.imageUrls.isNotEmpty) {
            _messageImages[userMsgId] = List<String>.from(dto.imageUrls);
          }
        } else {
          final src = data['source_image_url'] as String?;
          if (src != null && src.isNotEmpty) {
            _messageImages[userMsgId] = [src];
          }
        }
        var reply = '';
        if (asst is Map) {
          final dto = ChatMessageDto.fromJson(Map<String, dynamic>.from(asst));
          reply = dto.content;
          if (dto.imageUrls.isNotEmpty) {
            _messageImages[asstId] = List<String>.from(dto.imageUrls);
          }
        } else {
          reply = '${data['assistant_message']?['content'] ?? ''}';
          final out = data['result_image_url'] as String?;
          if (out != null && out.isNotEmpty) {
            _messageImages[asstId] = [out];
          }
        }
        if (reply.isEmpty) reply = '改好了，你看看。';
        final idx = _messages.indexWhere((m) => m.id == asstId);
        final done = ChatMessage.assistant(
          id: asstId,
          text: reply,
          senderName: widget.personaName,
        );
        if (idx >= 0) {
          _messages[idx] = done;
        } else {
          _messages.add(done);
        }
      });
      _pushPreview('[图片] $prompt', fromUser: true);
      unawaited(_pollSceneFollowups());
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingGenMsgIds.remove(asstId);
          _messageLocalBytes.remove(userMsgId);
          _messageImages.remove(userMsgId);
          _messageImages.remove(asstId);
          _messages.removeWhere((m) => m.id == userMsgId || m.id == asstId);
        });
      }
      _showSendError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  ChatMessage? _lastAssistantMessage() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (!_messages[i].isUser) return _messages[i];
    }
    return null;
  }

  Future<void> _listenToHer() async {
    final last = _lastAssistantMessage();
    if (last != null) {
      await _playMessageTts(last);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('等她回一句，或先打个招呼')),
    );
  }

  bool _callQuotaChecking = false;

  /// 拨号前先查额度：免费时长用完时先说清要扣星尘，别让用户进了通话页才失败。
  Future<bool> _confirmCallQuota(String token) async {
    final s = AppStateScope.of(context);
    Map<String, dynamic>? quota;
    try {
      quota = await s.api().getCallQuota(accessToken: token);
    } catch (_) {
      // 预检失败不阻断拨号，仍由服务端 assert_call_allowed 把关
      return true;
    }
    if (!mounted) return false;

    if (quota['enabled'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音通话暂未开放')),
      );
      return false;
    }

    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    final remaining = asInt(quota['free_seconds_remaining']);
    if (remaining > 0) return true;

    final perMin = asInt(quota['stardust_per_minute']);
    if (perMin <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('免费通话时长已用完')),
      );
      return false;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('免费时长已用完'),
        content: Text('继续通话将按 $perMin 星尘/分钟扣费，要现在拨打吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('先不打'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续拨打'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _openVoiceCall() async {
    final s = AppStateScope.of(context);
    final token = s.accessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再拨打语音')),
      );
      return;
    }
    if (_callQuotaChecking) return;
    setState(() => _callQuotaChecking = true);
    final allowed = await _confirmCallQuota(token);
    if (mounted) setState(() => _callQuotaChecking = false);
    if (!mounted || !allowed) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceCallPage(
          personaId: widget.personaId,
          personaName: widget.personaName,
          sessionId: _sessionId,
          accessToken: token,
          baseUrl: s.baseUrl,
          coverUrl: _coverUrl,
          coverEmoji: _coverEmoji,
          coverColor: _coverColor,
          backgroundKey: _backgroundKey,
          backgroundUrl: _backgroundUrl,
          oneLiner: _oneLiner,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _messages.isEmpty && !_historyLoading) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.personaName),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$_error'),
          ),
        ),
      );
    }

    final topInset = MediaQuery.paddingOf(context).top;
    final bondLabel = _bond == null
        ? (_emotionLabel ?? _oneLiner ?? '私聊中')
        : BondDisplay.companionLabel(
            stageId: _bond!.stage,
            serverLabel: _bond!.stageLabel,
          );
    return Stack(
      children: [
    PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _syncPreviewOnLeave();
      },
      child: Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: ChatBackdrop(
              baseUrl: AppStateScope.of(context).baseUrl,
              backgroundKey: _backgroundKey,
              backgroundUrl: _backgroundUrl,
              coverUrl: _coverUrl,
            ),
          ),
          Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_messages.isEmpty)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      _EmptyChatState(
                        name: widget.personaName,
                        oneLiner: _oneLiner,
                        coverUrl: _coverUrl,
                        coverEmoji: _coverEmoji,
                        coverColor: _coverColor,
                        baseUrl: AppStateScope.of(context).baseUrl,
                      ),
                      if (_historyLoading)
                        const Padding(
                          padding: EdgeInsets.only(top: 120),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                    ],
                  )
                else
                  ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    cacheExtent: 2400,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      ChatTopBar.listTopPadding(
                        topInset,
                        showProgress: _historyRefreshing,
                      ),
                    ),
                    itemCount: _messages.length +
                        (_sending &&
                                (_messages.isEmpty || _messages.last.isUser)
                            ? 1
                            : 0) +
                        ((_hasMoreHistory || _loadingMore) ? 1 : 0),
                    itemBuilder: (context, i) {
                      final typing = _sending &&
                              (_messages.isEmpty || _messages.last.isUser)
                          ? 1
                          : 0;
                      if (typing == 1 && i == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: TypingIndicator(),
                        );
                      }
                      final fromBottom = i - typing;
                      if (fromBottom >= _messages.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white54,
                                    ),
                                  )
                                : Text(
                                    '上拉加载更早消息',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      }
                      final mi = _messages.length - 1 - fromBottom;
                      final msg = _messages[mi];
                      final extra = _chatExtras[msg.id];
                      if (extra?.isMemory == true) {
                        final baseUrl = AppStateScope.of(context).baseUrl;
                        final rawImg = (_messageImages[msg.id]?.isNotEmpty ?? false)
                            ? _messageImages[msg.id]!.first
                            : extra!.imageUrl;
                        final imageUrl = rawImg.isNotEmpty
                            ? (resolvePersonaCoverUrl(baseUrl, rawImg) ?? rawImg)
                            : '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SceneMemoryCard(
                            title: extra!.sceneTitle,
                            summary: extra.summary,
                            imageUrl: imageUrl,
                            onOpenImage: imageUrl.isNotEmpty
                                ? (url) => _openImageViewer(url: url)
                                : null,
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _bubbleRow(
                          msg,
                          index: mi,
                          animate: mi >= _messages.length - 2,
                        ),
                      );
                    },
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _ImmersiveChatHeader(
                    topInset: topInset,
                    name: widget.personaName,
                    subtitle: bondLabel,
                    sceneRemaining: _sceneRemaining,
                    sceneLimit: _sceneLimit,
                    refreshing: _historyRefreshing,
                    onBack: () => Navigator.of(context).maybePop(),
                    onCall: _openVoiceCall,
                    onMore: _openMore,
                  ),
                ),
              ],
            ),
          ),
          if (_recalled.isNotEmpty)
            _RecalledMemoryStrip(
              items: _recalled,
              onOpenMemory: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MemoryPage(personaId: widget.personaId),
                  ),
                );
              },
              onDismiss: () => setState(() => _recalled = const []),
            ),
          if (_greetingOnly && !_sending)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '这是开场白，已记入对话',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _skipGreeting,
                    child: const Text('跳过开场白'),
                  ),
                ],
              ),
            ),
          _ComposerBar(
            controller: _inputCtrl,
            focusNode: _focus,
            enabled: !_sending,
            sending: _sending,
            hint: '对她说…',
            showListen: _hasTtsVoice,
            onListen: () => unawaited(_listenToHer()),
            onGift: _sendGift,
            resolveAbsoluteUrl: (u) => AppStateScope.of(context).api().resolveUrl(u),
            onPickImage: _pickAndEditImage,
            onSubmit: _submit,
          ),
        ],
      ),
        ],
      ),
    ),
    ),
        if (_giftEffectUrl != null && _giftEffectUrl!.isNotEmpty)
          Positioned.fill(
            child: GiftSvgaOverlay(
              key: ValueKey(_giftEffectUrl),
              url: _giftEffectUrl!,
              onFinished: () {
                if (mounted) setState(() => _giftEffectUrl = null);
              },
            ),
          ),
      ],
    );
  }
}

class _ImmersiveChatHeader extends StatelessWidget {
  const _ImmersiveChatHeader({
    required this.topInset,
    required this.name,
    required this.subtitle,
    this.sceneRemaining,
    this.sceneLimit,
    required this.refreshing,
    required this.onBack,
    required this.onCall,
    required this.onMore,
  });

  final double topInset;
  final String name;
  final String subtitle;
  final int? sceneRemaining;
  final int? sceneLimit;
  final bool refreshing;
  final VoidCallback onBack;
  final VoidCallback onCall;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ChatTopBar(
      topInset: topInset,
      showProgress: refreshing,
      child: Row(
        children: [
          FrostIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (sceneRemaining != null &&
                    sceneLimit != null &&
                    sceneLimit! > 0) ...[
                  const SizedBox(height: 4),
                  SceneQuotaBadge(
                    remaining: sceneRemaining,
                    limit: sceneLimit,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
          FrostIconButton(
            icon: Icons.phone_outlined,
            onTap: onCall,
            tooltip: '语音通话',
          ),
          const SizedBox(width: 6),
          FrostIconButton(
            icon: Icons.more_horiz,
            onTap: onMore,
          ),
        ],
      ),
    );
  }
}

class _BondMiniLine extends StatelessWidget {
  const _BondMiniLine({required this.bond});

  final BondDto bond;

  @override
  Widget build(BuildContext context) {
    final progress = bond.progressInStage.clamp(0.0, 1.0);
    final label = BondDisplay.companionLabel(
      stageId: bond.stage,
      serverLabel: bond.stageLabel,
    );
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(gradient: AppColors.bondGradient),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$label · ${BondDisplay.progressHint(progress)}',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.accentPink.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BondProgressStrip extends StatelessWidget {
  const _BondProgressStrip({required this.bond});

  final BondDto bond;

  @override
  Widget build(BuildContext context) {
    final progress = bond.progressInStage.clamp(0.0, 1.0);
    final label = BondDisplay.companionLabel(
      stageId: bond.stage,
      serverLabel: bond.stageLabel,
    );
    return Material(
      color: AppColors.bgDarkElevated,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primaryLight.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    BondDisplay.progressHint(progress),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    color: AppColors.accentPink,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecalledMemoryStrip extends StatelessWidget {
  const _RecalledMemoryStrip({
    required this.items,
    required this.onOpenMemory,
    required this.onDismiss,
  });

  final List<String> items;
  final VoidCallback onOpenMemory;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.55)),
          gradient: LinearGradient(
            colors: [
              AppColors.accentCyan.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: 0.04),
            ],
          ),
        ),
        child: InkWell(
          onTap: onOpenMemory,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentCyan.withValues(alpha: 0.2),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: AppColors.accentCyan,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'TA 想起了  ',
                          style: TextStyle(
                            color: AppColors.accentCyan,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        TextSpan(
                          text: items.first,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({
    required this.name,
    this.oneLiner,
    this.coverUrl,
    this.coverEmoji,
    this.coverColor,
    required this.baseUrl,
  });

  final String name;
  final String? oneLiner;
  final String? coverUrl;
  final String? coverEmoji;
  final String? coverColor;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final hex = (coverColor ?? '#2A332A').replaceFirst('#', '');
    Color bg = AppColors.bgDarkElevated;
    try {
      bg = Color(int.parse(hex, radix: 16) + 0xFF000000);
    } catch (_) {/* keep */}
    final label = (coverEmoji != null && coverEmoji!.isNotEmpty)
        ? coverEmoji!
        : (name.isNotEmpty ? name.substring(0, 1) : '角');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PersonaCoverAvatar(
              baseUrl: baseUrl,
              coverUrl: coverUrl,
              fallbackColor: bg,
              fallbackLabel: label,
              radius: 40,
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
            ),
            if (oneLiner != null && oneLiner!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                oneLiner!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.55),
                      height: 1.4,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '说点什么吧，这里会记得你们的对话',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatNetworkImage extends StatelessWidget {
  const _ChatNetworkImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholderWidth = 160,
    this.placeholderHeight = 160,
  });

  final String url;
  final BoxFit fit;
  final double placeholderWidth;
  final double placeholderHeight;

  @override
  Widget build(BuildContext context) {
    return AppNetworkImage(
      url: url,
      fit: fit,
      placeholder: (_, __) => _ImageLoadingPlaceholder(
        width: placeholderWidth,
        height: placeholderHeight,
      ),
      errorWidget: (_, __, ___) => Container(
        width: placeholderWidth,
        height: placeholderHeight * 0.75,
        color: Colors.white12,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class _ImageLoadingPlaceholder extends StatelessWidget {
  const _ImageLoadingPlaceholder({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A36),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white70,
              backgroundColor: Colors.white12,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '加载中',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenImageViewer extends StatefulWidget {
  const _FullscreenImageViewer({this.url, this.bytes});

  final String? url;
  final Uint8List? bytes;

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  bool _saving = false;

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          messenger?.showSnackBar(
            const SnackBar(content: Text('需要相册权限才能保存')),
          );
          return;
        }
      }
      late final Uint8List data;
      if (widget.bytes != null) {
        data = widget.bytes!;
      } else {
        final file = await AppImageCacheManager.instance.getSingleFile(
          widget.url!,
          headers: kMediaRequestHeaders,
        );
        data = await file.readAsBytes();
      }
      final name = 'chat_${DateTime.now().millisecondsSinceEpoch}';
      await Gal.putImageBytes(data, name: name);
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('已保存到相册')),
      );
    } on GalException catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('保存失败：${e.type.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('保存失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.bytes != null
        ? Image.memory(widget.bytes!, fit: BoxFit.contain)
        : AppNetworkImage(
            url: widget.url!,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: _ImageLoadingPlaceholder(
                width: 200,
                height: 240,
              ),
            ),
            errorWidget: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(child: image),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveToGallery,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.92),
                        foregroundColor: Colors.black87,
                        disabledBackgroundColor:
                            Colors.white.withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 20),
                      label: Text(_saving ? '保存中…' : '保存到相册'),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '双指缩放 · 点击空白关闭',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageGenPlaceholder extends StatefulWidget {
  const _ImageGenPlaceholder();

  @override
  State<_ImageGenPlaceholder> createState() => _ImageGenPlaceholderState();
}

class _ImageGenPlaceholderState extends State<_ImageGenPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = 0.35 + 0.25 * _pulse.value;
        return Container(
          width: 180,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08 + t * 0.12),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 36,
                color: AppColors.accentPink.withValues(alpha: 0.55 + t * 0.4),
              ),
              const SizedBox(height: 12),
              Text(
                '图片制作中',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '按你的要求生成中…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accentPink.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ImageEditPromptDialog extends StatefulWidget {
  const _ImageEditPromptDialog({
    required this.initialPrompt,
    required this.imageBytes,
    this.remaining,
  });

  final String initialPrompt;
  final Uint8List imageBytes;
  final int? remaining;

  @override
  State<_ImageEditPromptDialog> createState() => _ImageEditPromptDialogState();
}

class _ImageEditPromptDialogState extends State<_ImageEditPromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('发图改图'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.remaining != null)
              Text(
                '今日剩余 ${widget.remaining} 次',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12.5),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              opaque: false,
                              barrierColor: Colors.black.withValues(alpha: 0.92),
                              pageBuilder: (_, __, ___) => _FullscreenImageViewer(
                                bytes: widget.imageBytes,
                              ),
                              transitionsBuilder: (_, anim, __, child) =>
                                  FadeTransition(opacity: anim, child: child),
                            ),
                          );
                        },
                        child: Image.memory(
                          widget.imageBytes,
                          width: 132,
                          height: 164,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '已选图片',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '一句话说明怎么改，例如：把背景换成雨夜',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('发送'),
        ),
      ],
    );
  }
}

class _ComposerBar extends StatefulWidget {
  const _ComposerBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.sending,
    required this.hint,
    required this.onSubmit,
    this.showListen = false,
    this.onListen,
    this.onGift,
    this.resolveAbsoluteUrl,
    this.onPickImage,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool sending;
  final String hint;
  final VoidCallback onSubmit;
  final bool showListen;
  final VoidCallback? onListen;
  final Future<void> Function(GiftDto gift)? onGift;
  final String Function(String url)? resolveAbsoluteUrl;
  final VoidCallback? onPickImage;

  @override
  State<_ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<_ComposerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _plusCtrl;
  late final Animation<double> _plusReveal;
  late final Animation<double> _plusTurn;
  bool _plusOpen = false;
  bool _giftOpen = false;
  List<GiftDto>? _gifts;
  int? _stardust;
  bool _giftsLoading = false;

  @override
  void initState() {
    super.initState();
    _plusCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    final curve = CurvedAnimation(
      parent: _plusCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _plusReveal = curve;
    _plusTurn = Tween<double>(begin: 0, end: 0.125).animate(curve);
  }

  @override
  void dispose() {
    _plusCtrl.dispose();
    super.dispose();
  }

  Future<void> _setPlusOpen(bool open) async {
    if (open == _plusOpen) return;
    widget.focusNode.unfocus();
    if (open) {
      setState(() {
        _plusOpen = true;
        _giftOpen = false;
      });
      await _plusCtrl.forward();
    } else {
      await _plusCtrl.reverse();
      if (mounted) setState(() => _plusOpen = false);
    }
  }

  Future<void> _onAction(VoidCallback? action, {bool openGift = false}) async {
    await _setPlusOpen(false);
    if (!mounted) return;
    if (openGift) {
      setState(() => _giftOpen = true);
      await _ensureGifts();
      return;
    }
    action?.call();
  }

  Future<void> _ensureGifts() async {
    if (_gifts != null || _giftsLoading) return;
    setState(() => _giftsLoading = true);
    try {
      final s = AppStateScope.of(context);
      final api = s.api();
      final gifts = await api.listGifts();
      WalletDto? wallet;
      try {
        wallet = await api.getWallet(userId: s.userId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
        _stardust = wallet?.stardust;
        _giftsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _giftsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizeTransition(
              sizeFactor: _plusReveal,
              child: FadeTransition(
                opacity: _plusReveal,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x88000000),
                          blurRadius: 32,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.glassSoft,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: AppColors.strokeStrong,
                              width: 1.2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 26, 10, 22),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _PlusAction(
                                  icon: Icons.image_outlined,
                                  label: '图片',
                                  onTap: widget.enabled
                                      ? () => unawaited(
                                            _onAction(widget.onPickImage),
                                          )
                                      : null,
                                ),
                                _PlusAction(
                                  icon: Icons.card_giftcard_rounded,
                                  label: '礼物',
                                  onTap: widget.enabled
                                      ? () => unawaited(
                                            _onAction(null, openGift: true),
                                          )
                                      : null,
                                ),
                                if (widget.showListen)
                                  _PlusAction(
                                    icon: Icons.volume_up_outlined,
                                    label: '听她说',
                                    onTap: widget.enabled
                                        ? () => unawaited(
                                              _onAction(widget.onListen),
                                            )
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_giftOpen)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _giftPicker(),
              ),
            _inputPill(),
          ],
        ),
      ),
    );
  }

  Widget _inputPill() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.glassSoft,
              borderRadius: BorderRadius.circular(AppColors.radiusPill),
              border: Border.all(
                color: AppColors.strokeStrong,
                width: 1.2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _plusButton(),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onTap: () {
                        if (_plusOpen) unawaited(_setPlusOpen(false));
                      },
                      onSubmitted: (_) {
                        if (widget.enabled && !widget.sending) {
                          widget.onSubmit();
                        }
                      },
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.35,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 11,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  _sendButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _plusButton() {
    return GestureDetector(
      onTap: widget.enabled
          ? () {
              HapticFeedback.selectionClick();
              unawaited(_setPlusOpen(!_plusOpen));
            }
          : null,
      child: SizedBox(
        width: 44,
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _plusOpen
                ? Colors.white.withValues(alpha: 0.32)
                : Colors.transparent,
          ),
          child: RotationTransition(
            turns: _plusTurn,
            child: Icon(
              _plusOpen ? Icons.close_rounded : Icons.add_rounded,
              color: Colors.white.withValues(alpha: 0.92),
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sendButton() {
    return GestureDetector(
      onTap: (widget.enabled && !widget.sending) ? widget.onSubmit : null,
      child: SizedBox(
        width: 40,
        height: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: widget.sending ? 0.16 : 0.34),
          ),
          child: Center(
            child: widget.sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Icons.arrow_upward_rounded,
                    color: Colors.white.withValues(alpha: 0.95),
                    size: 20,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _giftPicker() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.glassSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.strokeStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _stardust == null ? '星尘礼物' : '星尘礼物 · 余额 $_stardust',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _giftOpen = false),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_giftsLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in _gifts ?? const <GiftDto>[])
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: widget.enabled
                          ? () async {
                              if (_stardust != null &&
                                  _stardust! < g.price) {
                                final go = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AppColors.bgDarkElevated,
                                    title: const Text('星尘不足'),
                                    content: Text(
                                      '「${g.name}」需要 ${g.price} 星尘，'
                                      '当前余额 $_stardust。开通 VIP 可获赠星尘，去看看？',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('去开通 VIP'),
                                      ),
                                    ],
                                  ),
                                );
                                if (go == true && mounted) {
                                  final s = AppStateScope.of(context);
                                  final m = s.user?.membership ??
                                      const Membership();
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MembershipBenefitsPage(
                                        membership: m,
                                      ),
                                    ),
                                  );
                                  if (!mounted) return;
                                  try {
                                    final s = AppStateScope.of(context);
                                    final wallet = await s
                                        .api()
                                        .getWallet(userId: s.userId);
                                    if (mounted) {
                                      setState(
                                        () => _stardust = wallet.stardust,
                                      );
                                    }
                                  } catch (_) {/* ignore */}
                                }
                                return;
                              }
                              await widget.onGift?.call(g);
                              if (mounted) setState(() => _giftOpen = false);
                            }
                          : null,
                      child: Container(
                        width: 72,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.accentPink.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          children: [
                            if (g.thumbUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AppNetworkImage(
                                  url: widget.resolveAbsoluteUrl?.call(
                                        g.thumbUrl,
                                      ) ??
                                      g.thumbUrl,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => const Text(
                                    '🎁',
                                    style: TextStyle(fontSize: 22),
                                  ),
                                ),
                              )
                            else
                              const Text('🎁', style: TextStyle(fontSize: 22)),
                            const SizedBox(height: 4),
                            Text(
                              g.name,
                              style: const TextStyle(fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${g.price}·+${g.bondDelta}',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _ImmersiveBubble extends StatelessWidget {
  const _ImmersiveBubble({
    required this.text,
    required this.isUser,
    this.emoji = false,
  });

  final String text;
  final bool isUser;
  final bool emoji;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(24),
      topRight: const Radius.circular(24),
      bottomLeft: Radius.circular(isUser ? 24 : 10),
      bottomRight: Radius.circular(isUser ? 10 : 24),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isUser ? AppColors.glassLight : AppColors.glassSmoke,
              borderRadius: radius,
              border: Border.all(
                color: isUser ? AppColors.strokeStrong : AppColors.strokeSoft,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: emoji ? 14 : 16,
                vertical: emoji ? 10 : 13,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: emoji ? 40 : 15.5,
                    height: emoji ? 1.1 : 1.45,
                    fontWeight: FontWeight.w400,
                    shadows: const [
                      Shadow(blurRadius: 6, color: Color(0x66000000)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlusAction extends StatelessWidget {
  const _PlusAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.36),
                  width: 1.2,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMsgExtra {
  const _ChatMsgExtra({
    this.isMemory = false,
    this.isSceneImage = false,
    this.sceneTitle = '',
    this.summary = '',
    this.imageUrl = '',
  });

  final bool isMemory;
  final bool isSceneImage;
  final String sceneTitle;
  final String summary;
  final String imageUrl;
}
