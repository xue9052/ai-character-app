String formatRelativeTime(int? epochSec) {
  if (epochSec == null || epochSec <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${t.month}/${t.day}';
}
