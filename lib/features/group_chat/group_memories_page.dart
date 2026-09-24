import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_fmt.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/fullscreen_image_viewer.dart';
import '../personas/persona_cover.dart';

class GroupMemoriesPage extends StatefulWidget {
  const GroupMemoriesPage({
    super.key,
    required this.groupId,
    required this.groupTitle,
  });

  final String groupId;
  final String groupTitle;

  @override
  State<GroupMemoriesPage> createState() => _GroupMemoriesPageState();
}

class _GroupMemoriesPageState extends State<GroupMemoriesPage> {
  List<GroupMemoryDto> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = AppStateScope.of(context);
      final items = await s.api().listGroupMemories(widget.groupId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _openImage(String raw) {
    final s = AppStateScope.of(context);
    final url = resolvePersonaCoverUrl(s.baseUrl, raw) ?? raw;
    openFullscreenImage(context, url: url);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStateScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('${widget.groupTitle} · 记忆'),
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _buildBody(s.baseUrl),
      ),
    );
  }

  Widget _buildBody(String baseUrl) {
    if (_loading && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text('加载失败：$_error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('重试')),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 64),
          Icon(
            Icons.push_pin_outlined,
            size: 48,
            color: AppColors.accentPink.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有群记忆',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '在聊天里长按消息「记住这一刻」，或场景结束时自动记录',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final m = _items[i];
        final imageUrl = m.imageUrl.isNotEmpty
            ? (resolvePersonaCoverUrl(baseUrl, m.imageUrl) ?? m.imageUrl)
            : '';
        final time = formatRelativeTime(m.createdAt);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.glassSmoke,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.strokeSoft),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.push_pin_outlined,
                      size: 16,
                      color: AppColors.accentPink,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        m.title.isNotEmpty ? m.title : '群记忆',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (!m.auto)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.glassSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '手动',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                  ],
                ),
                if (imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _openImage(imageUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AppNetworkImage(
                        url: imageUrl,
                        width: double.infinity,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
                if (m.summary.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    m.summary.trim(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
