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
  if (s.contains('timed out') || s.contains('timeout')) {
    return '请求超时：声音复刻可能需要 1–2 分钟，请保持网络畅通后重试';
  }
  if (s.contains('failed host lookup') ||
      s.contains('connection refused') ||
      s.contains('connection timed out') ||
      s.contains('network is unreachable') ||
      s.contains('socketexception') ||
      s.contains('clientexception')) {
    return '无法连接服务器：请确认设置里 API 为 https://905299378.xyz，且手机网络正常';
  }
  if (raw.contains('HTTP 404') &&
      (raw.contains('Not Found') || raw.toLowerCase().contains('not found'))) {
    return '接口不存在(404)：后端版本过旧，请在电脑上重启 uvicorn 后再试';
  }
  final m = RegExp(r'^(Exception|ApiException):\s*(.*)$').firstMatch(raw);
  return (m?.group(2)?.isNotEmpty == true) ? m!.group(2)! : raw;
}
