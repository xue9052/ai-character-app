import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';

export '../api/api_exception.dart' show ApiException, apiErrorMessage;

class AppState extends ChangeNotifier {
  AppState({
    required String userId,
    required String baseUrl,
    required this.useStream,
    required this.autoTts,
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
  String? lastPersonaId;
  /// 私聊有更新时递增，聊天列表监听后刷新预览
  int chatListVersion = 0;
  /// personaId → 最新预览（乐观更新，避免 Web/缓存导致返回列表仍是旧句）
  final Map<String, ChatSessionPreview> sessionPreviews = {};

  String get userId => _user?.id ?? _userId;
  String get baseUrl => _baseUrl;
  String? get accessToken => _accessToken;
  AuthUser? get user => _user;
  bool get isLoggedIn =>
      _accessToken != null && _accessToken!.isNotEmpty && _user != null;

  /// 带 401 自动登出的 API 客户端（登录态失效时 AuthGate 会回到登录页）
  ApiClient api() => ApiClient(
        _baseUrl,
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
      );
    }

    final state = AppState(
      userId: cachedId ?? defaultUserId,
      baseUrl: base,
      useStream: sp.getBool(_kStream) ?? !kIsWeb,
      autoTts: sp.getBool(_kAutoTts) ?? true,
      lastPersonaId: sp.getString(_kPersona),
      accessToken: token,
      user: cachedUser,
    );

    if (state.isLoggedIn) {
      try {
        final me = await state.api().me(token!);
        await state.applySession(AuthSession(accessToken: token, user: me));
      } catch (_) {
        // 过期 / 无效令牌：清会话，交给 AuthGate 回登录
        await state.logout();
      }
    }
    return state;
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
    notifyListeners();
  }

  Future<void> applyUser(AuthUser user) async {
    if (_accessToken == null || _accessToken!.isEmpty) return;
    await applySession(AuthSession(accessToken: _accessToken!, user: user));
  }

  Future<void> logout() async {
    _accessToken = null;
    _user = null;
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
