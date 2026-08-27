/// 统一 API 错误，便于 UI 展示文案 / 处理 401 / 验证码冷却。
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.retryAfter,
  });

  final String message;
  final int? statusCode;
  final int? retryAfter;

  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;
  bool get isMailFailed => statusCode == 502;

  @override
  String toString() => message;
}

/// SnackBar 用：去掉 `Exception:` 前缀，保留可读文案。
String apiErrorMessage(Object error) {
  if (error is ApiException) return error.message;
  final raw = '$error';
  final s = raw.toLowerCase();
  if (s.contains('failed host lookup') ||
      s.contains('connection refused') ||
      s.contains('connection timed out') ||
      s.contains('network is unreachable') ||
      s.contains('socketexception') ||
      s.contains('clientexception')) {
    return '无法连接服务器：请确认 API 地址、手机与电脑同一 Wi‑Fi，且后端已用 --host 0.0.0.0 启动';
  }
  if (raw.contains('HTTP 404') &&
      (raw.contains('Not Found') || raw.toLowerCase().contains('not found'))) {
    return '接口不存在(404)：后端版本过旧，请在电脑上重启 uvicorn 后再试';
  }
  final m = RegExp(r'^(Exception|ApiException):\s*(.*)$').firstMatch(raw);
  return (m?.group(2)?.isNotEmpty == true) ? m!.group(2)! : raw;
}
