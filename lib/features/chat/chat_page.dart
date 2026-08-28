import 'dart:async';

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
import '../../theme/app_theme.dart';
import '../../widgets/gift_svga_overlay.dart';
import '../../widgets/user_avatar.dart';
import '../memory/memory_page.dart';
import '../personas/persona_cover.dart';
import '../personas/persona_detail_page.dart';
import '../personas/persona_presets.dart';
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

class _ChatPageState extends State<ChatPage> {
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
  /// 助手侧「制作中」占位
  final Set<String> _pendingGenMsgIds = {};
  final Set<String> _ttsLoadingIds = {};
  final _audioPlayer = AudioPlayer();
  String? _playingMsgId;
  String? _voiceProfileId;
  int? _imageEditRemaining;
  /// 当前全屏礼物特效 URL；播完清空
  String? _giftEffectUrl;
  Completer<void>? _ttsPlayWait;
  final Map<String, Map<int, _TtsSeg>> _messageSegs = {};
  /// 新回复多气泡：已露出的段数（历史默认全露）
  final Map<String, int> _segVisibleCount = {};
  /// 防止多次 stagger 并发把气泡一下拉满
  final Map<String, int> _segStaggerGen = {};
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

  @override
  void initState() {
    super.initState();
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
    });
  }

  @override
  void dispose() {
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
      if (segs.isNotEmpty) {
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

  /// 会话列表预览：多气泡 assistant 取最后一段，避免单行省略只露出第一句。
  String _listPreviewText({
    required String text,
    required bool fromUser,
    String? msgId,
  }) {
    if (fromUser) return text.trim();
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
      _segStaggerGen.clear();
    }
    final out = <ChatMessage>[];
    for (var i = 0; i < raw.length; i++) {
      final m = ChatMessageDto.fromJson(
        Map<String, dynamic>.from(raw[i] as Map),
      );
      final id = (m.id != null && m.id!.isNotEmpty)
          ? m.id!
          : 'hist_${indexOffset + i}';
      if (m.imageUrls.isNotEmpty) {
        _messageImages[id] = List<String>.from(m.imageUrls);
      }
      if (m.audioUrl != null && m.audioUrl!.isNotEmpty) {
        _messageAudioUrls[id] = m.audioUrl!;
      }
      final text = m.content.isNotEmpty
          ? m.content
          : (m.imageUrls.isNotEmpty ? '[图片]' : '');
      if (m.ttsChunks.isNotEmpty) {
        _ingestTtsChunks(id, m.ttsChunks);
        _segVisibleCount[id] = _orderedSegs(id).length;
      }
      // 无后端 tts_chunks 时不本地切句：单气泡展示全文
      if (m.role == 'assistant') {
        out.add(
          ChatMessage.assistant(
            id: id,
            text: text,
            senderName: widget.personaName,
          ),
        );
      } else {
        out.add(ChatMessage.user(id: id, text: text));
      }
    }
    return out;
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
  }

  Future<void> _loadHistory({bool fromCache = false}) async {
    final s = AppStateScope.of(context);
    final api = s.api();
    if (mounted && !fromCache) setState(() => _historyLoading = true);
    try {
      Map<String, dynamic> data;
      try {
        data = await api.getChatBootstrap(
          userId: s.userId,
          personaId: widget.personaId,
          limit: 30,
        );
      } catch (_) {
        // 旧服务端无 bootstrap 时回退
        data = await api.getChat(
          userId: s.userId,
          personaId: widget.personaId,
          limit: 30,
        );
      }

      s.setChatBootstrapCache(widget.personaId, data);
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
      _applyBootstrapData(data);

      if (_bond == null || data['persona'] == null) {
        try {
          final persona = await api.getPersona(s.userId, widget.personaId);
          _applyPersonaDetail(persona);
        } catch (_) {/* ignore */}
      }

      if (mounted) {
        setState(() {
          _historyLoading = false;
          _historyRefreshing = false;
        });
        _scrollToBottom(animated: false, force: !fromCache);
        _maybeApplyInitialDraft();
      }

      // 开场白落库不阻塞首屏；有历史时几乎立即返回
      unawaited(_maybeSeedGreeting(api, s));
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
    if (bgKey != null && bgKey.isNotEmpty) _backgroundKey = bgKey;
    final bgUrl = p['background_url'] as String?;
    if (bgUrl != null && bgUrl.isNotEmpty) _backgroundUrl = bgUrl;
    final g = '${p['greeting'] ?? ''}'.trim();
    _greetingText = g.isNotEmpty ? g : null;
    final vp = '${p['voice_profile_id'] ?? ''}'.trim();
    if (vp.isNotEmpty) _voiceProfileId = vp;
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
                      next.stageLabel,
                      style: const TextStyle(
                        color: Color(0xFFB8D4B8),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '亲密值 ${next.bond}',
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
          stagger: true,
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

    try {
      if (preferStream) {
        await _sendStream(api, s, trimmed);
      } else {
        await _sendJson(api, s, trimmed);
      }
    } catch (e) {
      if (preferStream) {
        try {
          await _sendJson(api, s, trimmed);
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

  Future<void> _sendJson(ApiClient api, AppState s, String trimmed) async {
    final data = await api.chat(
      userId: s.userId,
      personaId: widget.personaId,
      sessionId: _sessionId,
      message: trimmed,
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
    final hasVoice = (_voiceProfileId ?? '').trim().isNotEmpty &&
        reply.trim().isNotEmpty;
    final autoVoice = s.autoTts && hasVoice;
    setState(() {
      _messages.add(
        ChatMessage.assistant(
          id: replyId,
          text: reply,
          senderName: widget.personaName,
        ),
      );
    });
    if (mounted && reply.trim().isNotEmpty) {
      final chunks = _chunksFromChatPayload(Map<String, dynamic>.from(data));
      if (chunks.isNotEmpty) {
        _applyBackendChunks(
          replyId,
          chunks,
          stagger: true,
          revealAll: false,
        );
      }
      if (autoVoice) {
        unawaited(_synthSegsInOrder(replyId));
      }
    }
    _pushPreview(reply, fromUser: false, msgId: replyId);
    await _refreshBond();
    unawaited(_persistLocalSnapshot());
  }

  Future<void> _sendStream(ApiClient api, AppState s, String trimmed) async {
    var assistantId = const Uuid().v4();
    var assembled = '';
    final wantTts =
        s.autoTts && (_voiceProfileId ?? '').trim().isNotEmpty;
    setState(() {
      _messages.add(
        ChatMessage.assistant(
          id: assistantId,
          text: '…',
          senderName: widget.personaName,
        ),
      );
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
            text: wantTts
                ? (keep.isEmpty ? '…' : keep)
                : (assembled.isEmpty ? '…' : assembled),
            senderName: widget.personaName,
          );
        });
      }
      // 迁移本地音频缓存键
      final audio = _messageAudioUrls.remove(oldId);
      if (audio != null) _messageAudioUrls[assistantId] = audio;
      final chunks = _messageTtsChunks.remove(oldId);
      if (chunks != null) _messageTtsChunks[assistantId] = chunks;
      final segs = _messageSegs.remove(oldId);
      if (segs != null) _messageSegs[assistantId] = segs;
      final vis = _segVisibleCount.remove(oldId);
      if (vis != null) _segVisibleCount[assistantId] = vis;
      if (_ttsQueueMsgId == oldId) _ttsQueueMsgId = assistantId;
      final pending = _pendingRevealText.remove(oldId);
      if (pending != null) _pendingRevealText[assistantId] = pending;
      if (_ttsLoadingIds.remove(oldId)) _ttsLoadingIds.add(assistantId);
      if (_playingMsgId == oldId) _playingMsgId = assistantId;
    }

    if (wantTts) {
      await _audioPlayer.stop();
      _resetTtsQueue(assistantId);
    }
    var gotTtsChunks = false;
    await for (final token in api.chatStreamTokens(
      userId: s.userId,
      personaId: widget.personaId,
      sessionId: _sessionId,
      message: trimmed,
      ttsEnabled: wantTts,
      onMessageId: adoptServerId,
      onTtsChunk: (seq, url, text, pending, error) {
        gotTtsChunks = true;
        // 先锁可见段数，再 upsert（避免 setState 时 visible 为空→闪出全文/全段）
        final map = _messageSegs.putIfAbsent(assistantId, () => <int, _TtsSeg>{});
        final willBeNew = !map.containsKey(seq);
        if (willBeNew && !_segVisibleCount.containsKey(assistantId)) {
          _segVisibleCount[assistantId] = 1;
        }
        _upsertSeg(
          assistantId,
          seq,
          text: text,
          url: url,
          pending: pending && url.isEmpty && !error,
          error: error,
          rebuild: false,
        );
        _onBackendSegArrived(assistantId, seq);
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
        final chunks = _chunksFromChatPayload(finalPayload);
        if (chunks.isNotEmpty && _orderedSegs(assistantId).isEmpty) {
          _applyBackendChunks(
            assistantId,
            chunks,
            stagger: true,
            revealAll: false,
          );
        }
      },
    )) {
      assembled += token;
      // 已有后端分段 / 自动朗读：不写全文进单气泡
      if (gotTtsChunks || wantTts) continue;
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
    if (assembled.isEmpty && mounted) {
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
      _pushPreview(assembled, fromUser: false, msgId: assistantId);
      if (mounted) {
        if (gotTtsChunks) {
          // 只同步全文到消息（供预览/复制），展示仍只看 visible 段
          final idx = _messages.indexWhere((m) => m.id == assistantId);
          if (idx >= 0) {
            _messages[idx] = ChatMessage.assistant(
              id: assistantId,
              text: assembled,
              senderName: widget.personaName,
            );
          }
          final n = _orderedSegs(assistantId).length;
          _segVisibleCount.putIfAbsent(assistantId, () => 1);
          if (n > (_segVisibleCount[assistantId] ?? 1)) {
            unawaited(_staggerRevealSegs(assistantId, n));
          }
          if (wantTts) {
            _ttsRevealFull = assembled;
            _ttsRevealMsgId = assistantId;
          }
          if (mounted) setState(() {});
        } else {
          _setAssistantBubble(assistantId, assembled);
        }
      }
    }
    await _refreshBond();
    unawaited(_persistLocalSnapshot());
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

  String get _initial {
    final n = widget.personaName.trim();
    return n.isNotEmpty ? n.substring(0, 1) : '角';
  }

  /// 与「我的」同一套：色块 + emoji 预设 / 上传图
  Widget _userAvatar({double radius = 18}) {
    final s = AppStateScope.of(context);
    final u = s.user;
    return UserAvatar(
      emoji: u?.avatarEmoji ?? '🌙',
      colorHex: u?.avatarColor ?? '#5B7C99',
      imageUrl: s.absoluteAvatarUrl(u?.avatarUrl),
      radius: radius,
    );
  }

  Color get _personaCoverBg {
    final hex = (_coverColor ?? '#7B6CF6').replaceFirst('#', '');
    try {
      return Color(int.parse(hex, radix: 16) + 0xFF000000);
    } catch (_) {
      return AppColors.primary;
    }
  }

  String get _personaFallbackLabel {
    if (_coverEmoji != null && _coverEmoji!.isNotEmpty) return _coverEmoji!;
    return _initial;
  }

  /// 角色侧：封面图优先，否则 coverEmoji / 名字首字
  Widget _personaAvatar({double radius = 18}) {
    final s = AppStateScope.of(context);
    return PersonaCoverAvatar(
      baseUrl: s.baseUrl,
      coverUrl: _coverUrl,
      fallbackColor: _personaCoverBg,
      fallbackLabel: _personaFallbackLabel,
      radius: radius,
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
    final segs = _orderedSegs(m.id);
    // 有后端分段时：只按可见段画气泡；缺省先露 1 条（避免先闪全文/全段）
    final visibleN = (_segVisibleCount[m.id] ?? (segs.isEmpty ? 0 : 1))
        .clamp(0, segs.length);
    final shownSegs = segs.take(visibleN).toList();
    final hasVoice = !isUser &&
        showText &&
        !sticker &&
        (_voiceProfileId ?? '').trim().isNotEmpty;
    // 有后端段就走分段气泡（哪怕暂时只露 1 条），禁止用 m.text 全文冒充单气泡
    final useSegs = !isUser && segs.isNotEmpty && shownSegs.isNotEmpty;
    // 关自动朗读时后端仍可能推纯文本段；此时段内无音频芯片，需在顶部保留手动播放
    final anySegAudioUi = useSegs && shownSegs.any(_segHasAudioUi);
    final showTopPlay =
        hasVoice && m.text.trim() != '…' && (!useSegs || !anySegAudioUi);
    final Widget textBubble;
    if (sticker) {
      textBubble = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(m.text.trim(), style: const TextStyle(fontSize: 40, height: 1.1)),
      );
    } else if (!showText) {
      textBubble = const SizedBox.shrink();
    } else if (useSegs) {
      textBubble = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < shownSegs.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            // 仅文本段（关自动朗读）不显示「重试」芯片；有音频/合成中/失败才显示
            if (hasVoice && _segHasAudioUi(shownSegs[i]))
              _segAudioChip(m.id, shownSegs[i]),
            _assistantSentenceBubble(shownSegs[i].text),
          ],
        ],
      );
    } else {
      textBubble = ChatBubble(
        message: m,
        showAvatar: false,
        animate: animate,
        enableCopy: false,
        onLongPress: () => _openMessageActions(m, index),
      );
    }
    final mediaChildren = <Widget>[];
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
        if (showTopPlay)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: () => unawaited(_playMessageTts(m)),
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
                    if (_ttsLoadingIds.contains(m.id))
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
                        _playingMsgId == m.id
                            ? Icons.volume_up_rounded
                            : Icons.volume_up_outlined,
                        size: 16,
                        color: Colors.white70,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _ttsLoadingIds.contains(m.id)
                          ? '生成中'
                          : (_playingMsgId == m.id ? '播放中' : '语音'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          if (!isUser) ...[
            _personaAvatar(radius: 18),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
          if (isUser) ...[
            const SizedBox(width: 8),
            _userAvatar(radius: 18),
          ],
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

  void _applyBackendChunks(
    String msgId,
    List<Map<String, dynamic>> chunks, {
    required bool stagger,
    bool revealAll = false,
  }) {
    if (chunks.isEmpty) return;
    if (!_segVisibleCount.containsKey(msgId)) {
      _segVisibleCount[msgId] = revealAll ? chunks.length : 1;
    }
    _ingestTtsChunks(msgId, chunks);
    final n = _orderedSegs(msgId).length;
    if (n <= 0) return;
    if (revealAll || !stagger || n <= 1) {
      _segVisibleCount[msgId] = n;
    } else {
      _segVisibleCount[msgId] = 1;
      unawaited(_staggerRevealSegs(msgId, n));
    }
    if (mounted) setState(() {});
  }

  void _onBackendSegArrived(String msgId, int seq) {
    // 气泡一律约 1s 逐条露；自动朗读只负责播音频，不一次掀开全部气泡
    final total = _orderedSegs(msgId).length;
    if (total <= 0) return;
    if (!_segVisibleCount.containsKey(msgId)) {
      _segVisibleCount[msgId] = 1;
    }
    if (total > (_segVisibleCount[msgId] ?? 1)) {
      unawaited(_staggerRevealSegs(msgId, total));
    }
    if (mounted) setState(() {});
  }

  void _revealSegsAtLeast(String msgId, int count) {
    final total = _orderedSegs(msgId).length;
    if (total <= 0) return;
    final next = count.clamp(1, total);
    final cur = _segVisibleCount[msgId] ?? 1;
    if (next <= cur) return;
    _segVisibleCount[msgId] = next;
    if (mounted) setState(() {});
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

  Future<void> _staggerRevealSegs(String msgId, int total) async {
    final gen = (_segStaggerGen[msgId] ?? 0) + 1;
    _segStaggerGen[msgId] = gen;
    var n = _segVisibleCount[msgId] ?? 1;
    while (n < total) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      if (_segStaggerGen[msgId] != gen) return;
      final liveTotal = _orderedSegs(msgId).length;
      final target = total < liveTotal ? liveTotal : total;
      if ((_segVisibleCount[msgId] ?? 0) >= target) return;
      n = (_segVisibleCount[msgId] ?? 1) + 1;
      if (n > target) return;
      setState(() => _segVisibleCount[msgId] = n);
      _scrollToBottom();
    }
    if (!mounted || _segStaggerGen[msgId] != gen) return;
    final segs = _orderedSegs(msgId);
    if (segs.isNotEmpty) {
      _pushPreview(segs.last.text, fromUser: false, msgId: msgId);
    }
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

  bool _segHasAudioUi(_TtsSeg seg) {
    return seg.pending || seg.error || seg.url.trim().isNotEmpty;
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
    } else if (seg.error || seg.url.isEmpty) {
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
                      : (seg.error || seg.url.isEmpty
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
    final body = text.trim().isEmpty ? '…' : text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        body,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.45,
        ),
      ),
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
        // 播到哪句，至少露到哪句（不拖慢音频；避免先全文后拆开）
        _revealSegsAtLeast(playId, seq + 1);
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
    final text = m.text.trim();
    if (text.isEmpty || text.startsWith('[图片]')) return;
    final voiceId = (_voiceProfileId ?? '').trim();
    if (voiceId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该角色尚未绑定音色')),
      );
      return;
    }
    if (_orderedSegs(m.id).isNotEmpty) {
      unawaited(_synthSegsInOrder(m.id));
      return;
    }
    // 无后端分段：整段一次合成
    _upsertSeg(m.id, 0, text: text, pending: true, rebuild: false);
    _segVisibleCount[m.id] = 1;
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

    return Stack(
      children: [
    PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _syncPreviewOnLeave();
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.25),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            _personaAvatar(radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.personaName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_bond != null)
                    _BondMiniLine(bond: _bond!)
                  else
                    Text(
                      _emotionLabel ?? _oneLiner ?? '私聊中',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '语音通话',
            icon: const Icon(Icons.phone_outlined),
            onPressed: () {
              final s = AppStateScope.of(context);
              final token = s.accessToken;
              if (token == null || token.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先登录后再拨打语音')),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VoiceCallPage(
                    personaId: widget.personaId,
                    personaName: widget.personaName,
                    sessionId: _sessionId,
                    accessToken: token,
                    baseUrl: s.baseUrl,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: _openMore,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_historyRefreshing)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: AppColors.primaryLight,
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _ChatBackdrop(
                    baseUrl: AppStateScope.of(context).baseUrl,
                    backgroundKey: _backgroundKey,
                    backgroundUrl: _backgroundUrl,
                    coverUrl: _coverUrl,
                  ),
                ),
                Positioned(
                  right: -20,
                  bottom: 80,
                  child: IgnorePointer(
                    child: Text(
                      _initial,
                      style: TextStyle(
                        fontSize: 220,
                        height: 1,
                        fontWeight: FontWeight.w200,
                        color: AppColors.primaryLight.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
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
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    cacheExtent: 2400,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      16 + MediaQuery.paddingOf(context).bottom,
                      12,
                      MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
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
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _bubbleRow(
                          _messages[mi],
                          index: mi,
                          animate: mi >= _messages.length - 2,
                        ),
                      );
                    },
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
            hint: '输入消息...',
            onGift: _sendGift,
            resolveAbsoluteUrl: (u) => AppStateScope.of(context).api().resolveUrl(u),
            onPickImage: _pickAndEditImage,
            onSubmit: _submit,
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

class _BondMiniLine extends StatelessWidget {
  const _BondMiniLine({required this.bond});

  final BondDto bond;

  @override
  Widget build(BuildContext context) {
    final progress = bond.progressInStage.clamp(0.0, 1.0);
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
          '${bond.stageLabel} ${(progress * 100).round()}%',
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
                    bond.stageLabel,
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
                    '亲密 ${bond.bond} · 本阶段 ${(progress * 100).round()}%',
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

class _ChatBackdrop extends StatelessWidget {
  const _ChatBackdrop({
    required this.baseUrl,
    this.backgroundKey,
    this.backgroundUrl,
    this.coverUrl,
  });

  final String baseUrl;
  final String? backgroundKey;
  final String? backgroundUrl;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    // 优先专用背景；没有则用封面立绘，避免聊天永远同一张渐变
    final url = resolvePersonaBackgroundUrl(baseUrl, backgroundUrl) ??
        resolvePersonaCoverUrl(baseUrl, coverUrl);
    if (url != null && url.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AppNetworkImage(
            url: url,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.2),
            errorWidget: (_, __, ___) =>
                _PresetBackdrop(backgroundKey: backgroundKey),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x661A1A2E),
                  Color(0xB31A1A2E),
                  Color(0xE61A1A2E),
                ],
              ),
            ),
          ),
          CustomPaint(painter: _VignettePainter()),
        ],
      );
    }
    return _PresetBackdrop(backgroundKey: backgroundKey);
  }
}

class _PresetBackdrop extends StatelessWidget {
  const _PresetBackdrop({this.backgroundKey});

  final String? backgroundKey;

  @override
  Widget build(BuildContext context) {
    Map<String, String>? preset;
    for (final p in kBackgroundPresets) {
      if (p['key'] == backgroundKey) {
        preset = p;
        break;
      }
    }
    preset ??= kBackgroundPresets.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            parseHexColor(preset['color_from']!, fallback: 0xFF1A1A2E),
            parseHexColor(preset['color_mid']!, fallback: 0xFF12121F),
            parseHexColor(preset['color_to']!, fallback: 0xFF0A0A14),
          ],
        ),
      ),
      child: CustomPaint(painter: _VignettePainter()),
    );
  }
}

class _VignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.2),
        radius: 1.15,
        colors: [
          const Color(0xFF7B6CF6).withValues(alpha: 0.16),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
  final Future<void> Function(GiftDto gift)? onGift;
  final String Function(String url)? resolveAbsoluteUrl;
  final VoidCallback? onPickImage;

  @override
  State<_ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<_ComposerBar> {
  bool _giftOpen = false;
  List<GiftDto>? _gifts;
  int? _stardust;
  bool _giftsLoading = false;

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
    return Material(
      color: AppColors.bgDark.withValues(alpha: 0.94),
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 输入框上方快捷句标签暂隐藏
            // 亲密贴纸面板已下线，不再展示
            if (_giftOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stardust == null ? '星尘礼物' : '星尘礼物 · 余额 $_stardust',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
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
                                      await widget.onGift?.call(g);
                                      if (mounted) {
                                        setState(() => _giftOpen = false);
                                      }
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
                                          url: widget.resolveAbsoluteUrl?.call(g.thumbUrl) ??
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
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                            ),
                                          ),
                                          errorWidget: (_, __, ___) =>
                                              const Text('🎁', style: TextStyle(fontSize: 22)),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  Material(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.enabled ? widget.onPickImage : null,
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(Icons.image_outlined, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.enabled
                          ? () async {
                              final open = !_giftOpen;
                              setState(() => _giftOpen = open);
                              if (open) await _ensureGifts();
                            }
                          : null,
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(Icons.card_giftcard_rounded, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (widget.enabled && !widget.sending) widget.onSubmit();
                      },
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.1),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    elevation: 0,
                    shadowColor: AppColors.primary.withValues(alpha: 0.5),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: (widget.enabled && !widget.sending)
                          ? widget.onSubmit
                          : null,
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: Center(
                          child: widget.sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
