import 'package:flutter/material.dart';

import '../../../api/models.dart';
import '../../../theme/app_theme.dart';
import '../../personas/persona_cover.dart';
import '../../../widgets/scene_memory_card.dart';
import '../../../widgets/app_network_image.dart';
import '../../../widgets/voice_play_chip.dart';

class GroupBubble extends StatelessWidget {
  const GroupBubble({
    super.key,
    required this.message,
    required this.baseUrl,
    this.memberCoverUrl = '',
    this.memberName = '',
    this.showDebug = false,
    this.imageHeaders,
    this.onMemberLongPress,
    this.onMessageLongPress,
    this.onOpenImage,
    this.onPlayVoice,
    this.voicePlaying = false,
    this.voiceLoading = false,
  });

  final GroupMessageDto message;
  final String baseUrl;
  final String memberCoverUrl;
  final String memberName;
  final bool showDebug;
  final Map<String, String>? imageHeaders;
  final void Function(String personaId, String name)? onMemberLongPress;
  final void Function(GroupMessageDto message)? onMessageLongPress;
  final void Function(String url)? onOpenImage;
  final void Function(GroupMessageDto message)? onPlayVoice;
  final bool voicePlaying;
  final bool voiceLoading;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem && message.isMemory) {
      return _memoryCard(context);
    }
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Center(
          child: Text(
            message.content,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
      );
    }

    final isUser = message.isUser;
    final name = isUser
        ? '我'
        : (message.senderName.isNotEmpty ? message.senderName : memberName);
    final bubble = _bubbleBody(context, isUser);
    final wrapped = onMessageLongPress != null && !message.isSystem
        ? GestureDetector(
            onLongPress: () => onMessageLongPress!(message),
            child: bubble,
          )
        : bubble;
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(48, 4, 12, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [Flexible(child: wrapped)],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 48, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: memberCoverUrl.isNotEmpty && onOpenImage != null
                ? () => onOpenImage!(_fullUrl(memberCoverUrl))
                : null,
            onLongPress: onMemberLongPress == null
                ? null
                : () => onMemberLongPress!(
                      message.senderId,
                      name,
                    ),
            child: PersonaCoverAvatar(
              baseUrl: baseUrl,
              coverUrl: memberCoverUrl,
              fallbackColor: AppColors.bgDarkElevated,
              fallbackLabel: name.isNotEmpty ? name.substring(0, 1) : '?',
              radius: 18,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                wrapped,
                if (showDebug && message.meta['pick_reason'] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Text(
                      '${message.meta['pick_reason']}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memoryCard(BuildContext context) {
    final summary = message.memorySummary;
    final title = message.sceneTitle.isNotEmpty
        ? message.sceneTitle
        : message.content.replaceAll('📌 ', '');
    final url = message.imageUrl.isNotEmpty ? _fullUrl(message.imageUrl) : '';
    return SceneMemoryCard(
      title: title,
      summary: summary,
      imageUrl: url,
      httpHeaders: imageHeaders,
      onOpenImage: onOpenImage,
    );
  }

  Widget _bubbleBody(BuildContext context, bool isUser) {
    final isGift = message.messageType == 'gift' || message.kind == 'gift';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isUser ? AppColors.glassLight : AppColors.glassSmoke,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppColors.radiusBubble),
          topRight: const Radius.circular(AppColors.radiusBubble),
          bottomLeft: Radius.circular(isUser ? AppColors.radiusBubble : 6),
          bottomRight: Radius.circular(isUser ? 6 : AppColors.radiusBubble),
        ),
        border: Border.all(
          color: isUser ? AppColors.strokeStrong : AppColors.strokeSoft,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isSceneImage && message.sceneTitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  message.sceneTitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.accentPink.withValues(alpha: 0.9),
                  ),
                ),
              ),
            if (message.isImage && message.imageUrl.isNotEmpty)
              _tappableImage(message.imageUrl, width: 200, height: 200),
            if (message.isImage && message.imageUrl.isNotEmpty)
              const SizedBox(height: 8),
            if (isGift)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_florist_outlined,
                    size: 16,
                    color: AppColors.accentPink,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      message.content,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              )
            else if (!message.isImage || message.content != '[图片]')
              Text(
                message.content,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            if (message.hasVoiceReply && onPlayVoice != null) ...[
              const SizedBox(height: 8),
              VoicePlayChip(
                playing: voicePlaying,
                loading: voiceLoading,
                label: '听听她怎么说',
                onTap: () => onPlayVoice!(message),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fullUrl(String path) {
    if (path.startsWith('http')) return path;
    final b = baseUrl.replaceAll(RegExp(r'/$'), '');
    return '$b$path';
  }

  Widget _tappableImage(String path, {required double width, required double height}) {
    final url = _fullUrl(path);
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AppNetworkImage(
        url: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        httpHeaders: imageHeaders,
      ),
    );
    if (onOpenImage == null) return image;
    return GestureDetector(
      onTap: () => onOpenImage!(url),
      child: image,
    );
  }
}
