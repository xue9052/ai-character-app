import 'dart:async' show TimeoutException, unawaited;
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_local_store.dart';
import 'group_ws_manager.dart';
import 'keep_alive_service.dart';
import 'push_service.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models.dart';

export '../api/api_exception.dart' show ApiException, apiErrorMessage;

class AppState extends ChangeNotifier {
  AppState({
    required String userId,
    required String baseUrl,
    required this.useStream,
    required this.autoTts,
    required this.pushReminders,
    required this.keepAliveBackground,
    this.lastPersonaId,
    String? accessToken,
    AuthUser? user,
  })  : _userId = userId,
        _baseUrl = baseUrl,
        _accessToken = accessToken,
        _user = user;

  String _userId;
  String _baseUrl;
  String? _accessToken;
  AuthUser? _user;
  bool useStream;
  bool autoTts;
  /// 主动关怀推送提醒（极光 JPush；默认关）
  bool pushReminders;
  /// 后台保持在线（Android 常驻前台服务，维持群聊长连接）
  bool keepAliveBackground;
  String? lastPersonaId;
  /// 私聊有更新时递增，聊天列表监听后刷新预览
  int chatListVersion = 0;
  /// personaId → 最新预览（乐观更新，避免 Web/缓存导致返回列表仍是旧句）
  final Map<String, ChatSessionPreview> sessionPreviews = {};
  /// 群聊灰度配置（启动后拉一次）
  GroupChatConfig? groupChatConfig;
  int groupListVersion = 0;
  /// 群列表缓存（IM 长连接实时更新预览/未读）
  final Map<String, GroupSummaryDto> groupCache = {};

  String get userId => _user?.id ?? _userId;
  String get baseUrl => _baseUrl;
  String? get accessToken => _accessToken;
  AuthUser? get user => _user;
  bool get isLoggedIn =>
      _accessToken != null && _accessToken!.isNotEmpty && _user != null;

  /// 带 401 自动登出的 API 客户端（登录态失效时 AuthGate 会回到登录页）
  ApiClient api() => ApiClient(
        _baseUrl,
        accessToken: _accessToken,
        onUnauthorized: () async {
          await logout();
        },
      );

  /// 把相对头像路径拼成可加载的绝对 URL
  String? absoluteAvatarUrl([String? relative]) {
    final r = (relative ?? _user?.avatarUrl ?? '').trim();
    if (r.isEmpty) return null;
    if (r.startsWith('http://') || r.startsWith('https://')) return r;
    final b = _baseUrl.replaceAll(RegExp(r'/$'), '');
    return '$b$r';
  }

  void notifyChatUpdated() {
    chatListVersion++;
    notifyListeners();
  }

  void notifyGroupListUpdated() {
    groupListVersion++;
    chatListVersion++;
    notifyListeners();
  }

  Future<void> refreshGroupChatConfig() async {
    if (!isLoggedIn) return;
    try {
      groupChatConfig = await api().getGroupChatConfig();
      notifyListeners();
      if (groupChatConfig?.enabled == true) {
        await _startGroupIm();
      } else {
        await GroupWsManager.instance.stop();
        groupCache.clear();
        await syncKeepAlive();
      }
    } catch (_) {
      groupChatConfig = GroupChatConfig(enabled: false);
      notifyListeners();
      await GroupWsManager.instance.stop();
      await syncKeepAlive();
    }
  }

  Future<void> _startGroupIm() async {
    PushService.instance.onGroupPush = _onGroupPush;
    await GroupWsManager.instance.start(this);
    await syncKeepAlive();
  }

  /// 长连接可用且用户没关开关时，才拉起常驻前台服务。
  bool get keepAliveWanted =>
      keepAliveBackground &&
      isLoggedIn &&
      groupChatConfig?.enabled == true &&
      KeepAliveService.supported;

  Future<void> syncKeepAlive() async {
    if (!KeepAliveService.supported) return;
    if (keepAliveWanted) {
      await KeepAliveService.instance.start();
    } else {
      await KeepAliveService.instance.stop();
    }
  }

  void _onGroupPush(String groupId) {
    unawaited(GroupWsManager.instance.syncGroups());
    notifyGroupListUpdated();
  }

  void cacheGroups(List<GroupSummaryDto> groups) {
    final incoming = <String>{};
    for (final g in groups) {
      incoming.add(g.id);
      final prev = groupCache[g.id];
      if (prev == null) {
        groupCache[g.id] = g;
        continue;
      }
      final apiNewer = g.lastSeq >= prev.lastSeq;
      groupCache[g.id] = GroupSummaryDto(
        id: g.id,
        title: g.title.isNotEmpty ? g.title : prev.title,
        coverUrl: g.coverUrl.isNotEmpty ? g.coverUrl : prev.coverUrl,
        lastPreview: apiNewer && g.lastPreview.isNotEmpty
            ? g.lastPreview
            : prev.lastPreview,
        lastSeq: apiNewer ? g.lastSeq : prev.lastSeq,
        lastMessageAt: g.lastMessageAt >= prev.lastMessageAt
            ? g.lastMessageAt
            : prev.lastMessageAt,
        canSend: g.canSend,
        members: g.members.isNotEmpty ? g.members : prev.members,
        memberCovers:
            g.memberCovers.isNotEmpty ? g.memberCovers : prev.memberCovers,
      );
    }
    groupCache.removeWhere((id, _) => !incoming.contains(id));
    notifyGroupListUpdated();
  }

  void applyGroupMessage(String groupId, GroupMessageDto msg) {
    final g = groupCache[groupId];
    final base = g ??
        GroupSummaryDto(
          id: groupId,
          title: '',
          coverUrl: '',
          lastPreview: '',
          lastSeq: 0,
          lastMessageAt: 0,
          canSend: true,
        );
    final prefix = msg.isUser
        ? '我：'
        : (msg.senderName.isNotEmpty ? '${msg.senderName}：' : '');
    final preview = '$prefix${msg.content}'.trim();
    groupCache[groupId] = GroupSummaryDto(
      id: base.id,
      title: base.title,
      coverUrl: base.coverUrl,
      lastPreview: preview.isNotEmpty ? preview : base.lastPreview,
      lastSeq: msg.seq > base.lastSeq ? msg.seq : base.lastSeq,
      lastMessageAt: msg.createdAt > 0 ? msg.createdAt : base.lastMessageAt,
      canSend: base.canSend,
      members: base.members,
      memberCovers: base.memberCovers,
    );
    groupListVersion++;
    notifyListeners();
  }

  void patchGroupLastSeq(String groupId, int lastSeq) {
    final g = groupCache[groupId];
    if (g == null || lastSeq <= g.lastSeq) return;
    groupCache[groupId] = GroupSummaryDto(
      id: g.id,
      title: g.title,
      coverUrl: g.coverUrl,
      lastPreview: g.lastPreview,
      lastSeq: lastSeq,
      lastMessageAt: g.lastMessageAt,
      canSend: g.canSend,
      members: g.members,
      memberCovers: g.memberCovers,
    );
    groupListVersion++;
    notifyListeners();
  }

  void removeGroupFromCache(String groupId) {
    groupCache.remove(groupId);
    notifyGroupListUpdated();
  }

  void updateSessionPreview({
    required String personaId,
    required String personaName,
    String? oneLiner,
    required String text,
    required bool fromUser,
    int? totalMessages,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final prefix = fromUser ? '我：' : '';
    final prev = sessionPreviews[personaId];
    sessionPreviews[personaId] = ChatSessionPreview(
      personaId: personaId,
      personaName: personaName,
      oneLiner: oneLiner ?? prev?.oneLiner,
      preview: '$prefix$trimmed',
      lastTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      total: totalMessages ?? ((prev?.total ?? 0) + 1),
    );
    lastPersonaId = personaId;
    chatListVersion++;
    notifyListeners();
  }

  void clearSessionPreview(String personaId) {
    sessionPreviews.remove(personaId);
    chatListVersion++;
    notifyListeners();
  }

  static const defaultUserId = 'u_web_tester';

  static const _kUser = 'user_id';
  static const _kBase = 'api_base';
  static const _kStream = 'use_stream';
  static const _kAutoTts = 'auto_tts';
  static const _kPushReminders = 'push_reminders';
  static const _kKeepAlive = 'keep_alive_background';
  static const _kPersona = 'last_persona_id';
  static const _kToken = 'access_token';
  static const _kNickname = 'nickname';
  static const _kEmail = 'email';
  static const _kBio = 'bio';
  static const _kAvatarKey = 'avatar_key';
  static const _kAvatarEmoji = 'avatar_emoji';
  static const _kAvatarColor = 'avatar_color';
  static const _kAvatarUrl = 'avatar_url';
  static const _kProfileCompleted = 'profile_completed';
  static const _kOnboardingCompleted = 'onboarding_completed';
  static const _kMembership = 'membership';

  /// 冷启动先用缓存的会员身份渲染，随后 profile 刷新会覆盖成服务端口径
  static Membership _decodeMembership(String? raw) {
    if (raw == null || raw.isEmpty) return const Membership();
    try {
      final j = jsonDecode(raw);
      if (j is Map) return Membership.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {
      // 缓存坏了就按免费档，等下次刷新
    }
    return const Membership();
  }

  static Future<AppState> load() async {
    final sp = await SharedPreferences.getInstance();
    var base = sp.getString(_kBase) ?? _defaultBase();
    // 旧包常缓存本机/模拟器地址；升级后自动切到线上
    if (_isLocalDevBase(base)) {
      base = _defaultBase();
      await sp.setString(_kBase, base);
    }
    final token = sp.getString(_kToken);
    AuthUser? cachedUser;
    final cachedId = sp.getString(_kUser);
    final cachedEmail = sp.getString(_kEmail);
    if (token != null &&
        token.isNotEmpty &&
        cachedId != null &&
        cachedEmail != null) {
      cachedUser = AuthUser(
        id: cachedId,
        email: cachedEmail,
        nickname: sp.getString(_kNickname) ?? '',
        avatarKey: sp.getString(_kAvatarKey) ?? 'a01',
        avatarEmoji: sp.getString(_kAvatarEmoji) ?? '🌙',
        avatarColor: sp.getString(_kAvatarColor) ?? '#5B7C99',
        avatarUrl: sp.getString(_kAvatarUrl) ?? '',
        bio: sp.getString(_kBio) ?? '',
        profileCompleted: sp.getBool(_kProfileCompleted) ?? false,
        onboardingCompleted: sp.getBool(_kOnboardingCompleted) ?? false,
        membership: _decodeMembership(sp.getString(_kMembership)),
      );
    }

    final state = AppState(
      userId: cachedId ?? defaultUserId,
      baseUrl: base,
      useStream: sp.getBool(_kStream) ?? !kIsWeb,
      autoTts: sp.getBool(_kAutoTts) ?? true,
      pushReminders: sp.getBool(_kPushReminders) ?? true,
      keepAliveBackground: sp.getBool(_kKeepAlive) ?? true,
      lastPersonaId: sp.getString(_kPersona),
      accessToken: token,
      user: cachedUser,
    );

    if (state.isLoggedIn) {
      // 冷启动不阻塞 runApp：先用本地缓存渲染，后台校验 token（见 refreshSessionFromServer）
      unawaited(state.refreshGroupChatConfig());
    }
    return state;
  }

  /// 启动后后台拉 /v1/auth/me；仅 401 清登录态，网络失败保留本地会话。
  Future<void> refreshSessionFromServer() async {
    final token = _accessToken?.trim();
    if (token == null || token.isEmpty || _user == null) return;
    try {
      final me = await api()
          .me(token)
          .timeout(const Duration(seconds: 8));
      await applySession(AuthSession(accessToken: token, user: me));
    } on ApiException catch (e) {
      if (e.isUnauthorized) await logout();
    } on TimeoutException {
      // 弱网保留缓存会话，避免冷启动被踢回登录
    } catch (_) {
      // 其它网络错误同上
    }
  }

  /// 默认连 Cloudflare Tunnel（免备案 HTTPS）；设置页可改回内网联调
  static const productionBaseUrl = 'https://905299378.xyz';

  static String _defaultBase() => productionBaseUrl;

  static bool _isLocalDevBase(String url) {
    final u = url.trim().toLowerCase();
    return u.contains('10.0.2.2') ||
        u.contains('127.0.0.1') ||
        u.contains('localhost') ||
        u.contains('124.221.29.21') ||
        u.startsWith('http://');
  }

  Future<void> applySession(AuthSession session) async {
    _accessToken = session.accessToken;
    _user = session.user;
    _userId = session.user.id;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, session.accessToken);
    await sp.setString(_kUser, session.user.id);
    await sp.setString(_kEmail, session.user.email);
    await sp.setString(_kNickname, session.user.nickname);
    await sp.setString(_kBio, session.user.bio);
    await sp.setString(_kAvatarKey, session.user.avatarKey);
    await sp.setString(_kAvatarEmoji, session.user.avatarEmoji);
    await sp.setString(_kAvatarColor, session.user.avatarColor);
    await sp.setString(_kAvatarUrl, session.user.avatarUrl);
    await sp.setBool(_kProfileCompleted, session.user.profileCompleted);
    await sp.setBool(_kOnboardingCompleted, session.user.onboardingCompleted);
    await sp.setString(
      _kMembership,
      jsonEncode(session.user.membership.toJson()),
    );
    notifyListeners();
    unawaited(refreshGroupChatConfig());
    // 推送是可选能力：后台尝试，成败都不影响登录/注册主流程。
    if (pushReminders) {
      unawaited(syncPush());
    }
  }

  Future<void> applyUser(AuthUser user) async {
    if (_accessToken == null || _accessToken!.isEmpty) return;
    await applySession(AuthSession(accessToken: _accessToken!, user: user));
  }

  Future<void> logout() async {
    final uid = userId;
    await GroupWsManager.instance.stop();
    await KeepAliveService.instance.stop();
    groupCache.clear();
    PushService.instance.onGroupPush = null;
    await PushService.instance.onLogout(api: isLoggedIn ? api() : null, userId: uid);
    _accessToken = null;
    _user = null;
    _chatBootstrapCache.clear();
    sessionPreviews.clear();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kEmail);
    await sp.remove(_kNickname);
    await sp.remove(_kBio);
    await sp.remove(_kAvatarKey);
    await sp.remove(_kAvatarEmoji);
    await sp.remove(_kAvatarColor);
    await sp.remove(_kAvatarUrl);
    await sp.remove(_kProfileCompleted);
    await sp.remove(_kOnboardingCompleted);
    await sp.remove(_kMembership);
    if (uid.isNotEmpty) {
      await ChatLocalStore.instance.clearUser(uid);
    }
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'/$'), '');
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kBase, _baseUrl);
    notifyListeners();
  }

  Future<void> setUseStream(bool v) async {
    useStream = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kStream, v);
    notifyListeners();
  }

  Future<void> setAutoTts(bool v) async {
    autoTts = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAutoTts, v);
    notifyListeners();
  }

  Future<void> setPushReminders(bool v) async {
    pushReminders = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPushReminders, v);
    notifyListeners();
    await syncPush();
  }

  Future<void> setKeepAliveBackground(bool v) async {
    keepAliveBackground = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kKeepAlive, v);
    notifyListeners();
    await syncKeepAlive();
  }

  Future<void> syncPush() async {
    if (!isLoggedIn) return;
    await PushService.instance.syncAfterLogin(
      api: api(),
      userId: userId,
      remindersEnabled: pushReminders,
    );
  }

  /// personaId → 最近一次 bootstrap 快照（二次进聊天先秒开再后台刷新）
  final Map<String, Map<String, dynamic>> _chatBootstrapCache = {};

  Map<String, dynamic>? chatBootstrapCache(String personaId) =>
      _chatBootstrapCache[personaId];

  void setChatBootstrapCache(String personaId, Map<String, dynamic> data) {
    _chatBootstrapCache[personaId] = Map<String, dynamic>.from(data);
  }

  void clearChatBootstrapCache(String personaId) {
    _chatBootstrapCache.remove(personaId);
  }

  Future<void> setLastPersona(String id) async {
    lastPersonaId = id;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPersona, id);
    notifyListeners();
  }
}

class ChatSessionPreview {
  ChatSessionPreview({
    required this.personaId,
    required this.personaName,
    required this.preview,
    required this.lastTs,
    required this.total,
    this.oneLiner,
  });

  final String personaId;
  final String personaName;
  final String? oneLiner;
  final String preview;
  final int lastTs;
  final int total;
}

class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found');
    return scope!.notifier!;
  }
}
