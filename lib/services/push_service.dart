import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';

/// 极光 JPush（Android + iOS 系统通知）。
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final JPushFlutterInterface _jpush = JPush.newJPush();
  bool _inited = false;
  String? _registrationId;
  bool _serverEnabled = false;

  String? get registrationId => _registrationId;
  bool get serverEnabled => _serverEnabled;

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<bool> _ensureAndroidNotifyPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final req = await Permission.notification.request();
    return req.isGranted;
  }

  Future<String?> _waitRegistrationId({int attempts = 8}) async {
    for (var i = 0; i < attempts; i++) {
      final rid = (await _jpush.getRegistrationID()).trim();
      if (rid.isNotEmpty) return rid;
      await Future<void>.delayed(Duration(milliseconds: 400 + i * 200));
    }
    return null;
  }

  Future<void> syncAfterLogin({
    required ApiClient api,
    required String userId,
    required bool remindersEnabled,
  }) async {
    if (!supported) return;
    try {
      final cfg = await api.pushConfig();
      _serverEnabled = cfg['jpush_enabled'] == true;
      final appKey = '${cfg['jpush_app_key'] ?? ''}'.trim();
      if (!_serverEnabled || appKey.isEmpty) return;

      final iosProduction = cfg['jpush_ios_production'] == true;

      if (!_inited) {
        _jpush.addEventHandler(
          onReceiveNotification: (event) async {
            debugPrint('[jpush] receive: $event');
          },
          onOpenNotification: (event) async {
            debugPrint('[jpush] open: $event');
          },
        );
        _jpush.setup(
          appKey: appKey,
          channel: 'ai-character',
          production: Platform.isIOS ? iosProduction : true,
          debug: kDebugMode,
        );
        if (Platform.isIOS) {
          _jpush.applyPushAuthority(
            const NotificationSettingsIOS(
              sound: true,
              alert: true,
              badge: true,
            ),
          );
        }
        _inited = true;
      }

      if (!remindersEnabled) {
        await _jpush.stopPush();
        if (_registrationId != null && _registrationId!.isNotEmpty) {
          await api.revokePushDevice(
            userId: userId,
            platform: _platform,
            registrationId: _registrationId!,
          );
        }
        return;
      }

      final granted = await _ensureAndroidNotifyPermission();
      if (!granted) {
        debugPrint('[jpush] notification permission denied');
        return;
      }

      await _jpush.resumePush();
      final rid = await _waitRegistrationId();
      if (rid == null || rid.isEmpty) {
        debugPrint('[jpush] empty registration id');
        return;
      }
      _registrationId = rid;
      await api.registerPushDevice(
        userId: userId,
        platform: _platform,
        registrationId: rid,
        appVersion: '0.1.0',
        enabled: true,
      );
      debugPrint('[jpush] registered platform=$_platform rid=$rid');
    } catch (e) {
      debugPrint('[jpush] sync failed: ${apiErrorMessage(e)}');
    }
  }

  Future<void> onLogout({
    ApiClient? api,
    String? userId,
  }) async {
    if (!supported || !_inited) return;
    try {
      await _jpush.stopPush();
      if (api != null &&
          userId != null &&
          _registrationId != null &&
          _registrationId!.isNotEmpty) {
        await api.revokePushDevice(
          userId: userId,
          platform: _platform,
          registrationId: _registrationId!,
        );
      }
    } catch (e) {
      debugPrint('[jpush] logout revoke failed: $e');
    } finally {
      _registrationId = null;
    }
  }
}
