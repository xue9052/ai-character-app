import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/api_client.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../widgets/app_network_image.dart';

class PersonaVoiceSelection {
  const PersonaVoiceSelection({
    required this.mode,
    this.voiceProfileId,
    this.voiceCloneJobId,
    this.existingCosyvoiceVoice,
  });

  final String mode; // preset | custom
  final String? voiceProfileId;
  final String? voiceCloneJobId;
  final String? existingCosyvoiceVoice;

  bool get hasVoice =>
      (voiceProfileId ?? '').isNotEmpty ||
      (voiceCloneJobId ?? '').isNotEmpty ||
      (existingCosyvoiceVoice ?? '').isNotEmpty;
}

class PersonaVoiceSection extends StatefulWidget {
  const PersonaVoiceSection({
    super.key,
    required this.api,
    required this.baseUrl,
    required this.userId,
    required this.profiles,
    required this.gender,
    required this.onChanged,
    this.initialVoiceProfileId,
    this.initialCosyvoiceVoice,
  });

  final ApiClient api;
  final String baseUrl;
  final String userId;
  final List<VoiceProfileDto> profiles;
  final String gender;
  final String? initialVoiceProfileId;
  final String? initialCosyvoiceVoice;
  final ValueChanged<PersonaVoiceSelection> onChanged;

  @override
  State<PersonaVoiceSection> createState() => _PersonaVoiceSectionState();
}

class _PersonaVoiceSectionState extends State<PersonaVoiceSection> {
  final _player = AudioPlayer();
  String _mode = 'preset';
  String? _voiceProfileId;
  String? _playingId;
  bool _playing = false;

  VoiceCloneRequirementsDto? _req;
  bool _reqLoading = true;
  bool _cloneBusy = false;
  String? _cloneError;
  VoiceCloneJobDto? _cloneJob;
  String? _pickedName;

  @override
  void initState() {
    super.initState();
    _voiceProfileId = widget.initialVoiceProfileId;
    if ((widget.initialCosyvoiceVoice ?? '').trim().isNotEmpty) {
      _mode = 'custom';
    }
    _loadRequirements();
    _emit();
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _playingId = null;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PersonaVoiceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gender != widget.gender) {
      _syncVoiceWithGender();
    }
    if (oldWidget.initialVoiceProfileId != widget.initialVoiceProfileId) {
      _voiceProfileId = widget.initialVoiceProfileId;
      _emit();
    }
    if (oldWidget.initialCosyvoiceVoice != widget.initialCosyvoiceVoice &&
        (widget.initialCosyvoiceVoice ?? '').trim().isNotEmpty) {
      _mode = 'custom';
    }
  }

  Future<void> _loadRequirements() async {
    try {
      final req = await widget.api.voiceCloneRequirements();
      if (!mounted) return;
      setState(() {
        _req = req;
        _reqLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _reqLoading = false);
    }
  }

  List<VoiceProfileDto> get _voicesForGender {
    if (widget.gender != 'female' && widget.gender != 'male') {
      return widget.profiles;
    }
    final matched = widget.profiles
        .where((v) => (v.gender ?? '') == widget.gender || (v.gender ?? '').isEmpty)
        .toList();
    return matched.isNotEmpty ? matched : widget.profiles;
  }

  void _syncVoiceWithGender() {
    final filtered = _voicesForGender;
    if (_voiceProfileId != null && filtered.any((v) => v.id == _voiceProfileId)) {
      return;
    }
    if (_voiceProfileId != null &&
        widget.profiles.any((v) => v.id == _voiceProfileId) &&
        widget.gender.isEmpty) {
      return;
    }
    setState(() {
      _voiceProfileId = filtered.isNotEmpty ? filtered.first.id : null;
    });
    _emit();
  }

  void _emit() {
    widget.onChanged(
      PersonaVoiceSelection(
        mode: _mode,
        voiceProfileId: _mode == 'preset' ? _voiceProfileId : null,
        voiceCloneJobId: _mode == 'custom' ? _cloneJob?.id : null,
        existingCosyvoiceVoice:
            _mode == 'custom' ? widget.initialCosyvoiceVoice : null,
      ),
    );
  }

  Future<void> _playPreset(VoiceProfileDto profile) async {
    final rel = profile.previewUrl;
    if (rel == null || rel.isEmpty) {
      _toast('该音色暂无试听，请联系管理员在后台生成');
      return;
    }
    final uri = Uri.parse(widget.baseUrl).resolve(rel);
    await _player.stop();
    setState(() {
      _playingId = profile.id;
      _playing = true;
    });
    try {
      final res = await http
          .get(uri, headers: kMediaRequestHeaders)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty) {
        throw Exception('HTTP ${res.statusCode}');
      }
      var mime = 'audio/mpeg';
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('wav')) mime = 'audio/wav';
      await _player.play(BytesSource(res.bodyBytes, mimeType: mime));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _playingId = null;
      });
      _toast('播放失败：${apiErrorMessage(e)}');
    }
  }

  Future<void> _playClonePreview() async {
    final job = _cloneJob;
    if (job == null || !job.isReady || job.previewUrl.isEmpty) return;
    final uri = Uri.parse(widget.baseUrl)
        .resolve(job.previewUrl)
        .replace(queryParameters: {'user_id': widget.userId});
    await _player.stop();
    setState(() {
      _playingId = 'clone';
      _playing = true;
    });
    try {
      final res = await http.get(uri, headers: widget.api.authHeaders());
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty) {
        throw Exception('HTTP ${res.statusCode}');
      }
      await _player.play(BytesSource(res.bodyBytes, mimeType: 'audio/mpeg'));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _playingId = null;
      });
      _toast('试听播放失败：${apiErrorMessage(e)}');
    }
  }

  Future<void> _pickAndClone() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'm4a'],
      withData: false,
    );
    final file = result?.files.single;
    if (file == null) return;
    final path = file.path?.trim();
    final bytes = file.bytes;
    if ((path == null || path.isEmpty) && (bytes == null || bytes.isEmpty)) {
      _toast('无法读取音频文件，请换 mp3 或从文件管理器选择');
      return;
    }
    setState(() {
      _cloneBusy = true;
      _cloneError = null;
      _pickedName = file.name;
      _cloneJob = null;
    });
    try {
      final started = await widget.api.createVoiceCloneJob(
        userId: widget.userId,
        filename: file.name,
        filePath: path,
        bytes: bytes,
      );
      if (!mounted) return;
      VoiceCloneJobDto job = started;
      if (job.isProcessing) {
        job = await widget.api.waitVoiceCloneJob(
          userId: widget.userId,
          jobId: job.id,
        );
      }
      if (!mounted) return;
      if (job.isFailed) {
        setState(() {
          _cloneBusy = false;
          _cloneError = job.error.isNotEmpty ? job.error : '声音复刻失败';
        });
        return;
      }
      setState(() {
        _cloneJob = job;
        _cloneBusy = false;
      });
      _emit();
      _toast('复刻完成，请试听确认');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cloneBusy = false;
        _cloneError = apiErrorMessage(e);
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final req = _req;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('音色', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'preset', label: Text('预设音色')),
            ButtonSegment(value: 'custom', label: Text('自定义复刻')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            setState(() => _mode = s.first);
            _emit();
          },
        ),
        const SizedBox(height: 12),
        if (_mode == 'preset') _buildPresetSection(theme),
        if (_mode == 'custom') _buildCustomSection(theme, req),
      ],
    );
  }

  Widget _buildPresetSection(ThemeData theme) {
    final voices = _voicesForGender;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.gender == 'female' || widget.gender == 'male'
              ? '已按性别筛选；点选绑定，喇叭试听'
              : '可先试听，建议先选性别以便筛选',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (voices.isEmpty)
          Text(
            '暂无可用音色',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('不绑定'),
                selected: _voiceProfileId == null,
                onSelected: (_) {
                  setState(() => _voiceProfileId = null);
                  _emit();
                },
              ),
              for (final v in voices)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChoiceChip(
                      label: Text(
                        v.category == null || v.category!.isEmpty
                            ? v.label
                            : '${v.label}·${v.category}',
                      ),
                      selected: _voiceProfileId == v.id,
                      onSelected: (_) {
                        setState(() => _voiceProfileId = v.id);
                        _emit();
                      },
                    ),
                    IconButton(
                      tooltip: '试听',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: _cloneBusy ? null : () => _playPreset(v),
                      icon: Icon(
                        _playing && _playingId == v.id
                            ? Icons.volume_up
                            : Icons.play_arrow,
                        size: 22,
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCustomSection(ThemeData theme, VoiceCloneRequirementsDto? req) {
    final tips = req?.tips ?? const [
      '请上传 10–30 秒清晰人声，尽量无背景音乐',
      '支持 WAV / MP3 / M4A，不超过 10MB',
    ];
    final existing = (widget.initialCosyvoiceVoice ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CosyVoice ${req?.targetModel ?? 'v3.5-flash'} 声音复刻',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        if (_reqLoading)
          const Text('加载要求…')
        else ...[
          Text(
            '格式：${(req?.formats ?? const ['wav', 'mp3', 'm4a']).join(' / ')} · '
            '时长 ${req?.minSeconds?.toStringAsFixed(0) ?? '10'}–'
            '${req?.maxSeconds?.toStringAsFixed(0) ?? '30'} 秒 · '
            '≤ ${((req?.maxBytes ?? 10485760) / (1024 * 1024)).toStringAsFixed(0)}MB',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final t in tips)
            Text(
              '· $t',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
        if (existing.isNotEmpty && _cloneJob == null) ...[
          const SizedBox(height: 8),
          Text(
            '当前角色已绑定自定义音色（保存时不改动除非重新上传）',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _cloneBusy ? null : _pickAndClone,
          icon: _cloneBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file),
          label: Text(_cloneBusy ? '复刻中…' : '上传样本并复刻'),
        ),
        if (_pickedName != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('已选：$_pickedName', style: theme.textTheme.bodySmall),
          ),
        if (_cloneError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_cloneError!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (_cloneJob?.isReady == true) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _playClonePreview,
                icon: Icon(
                  _playing && _playingId == 'clone'
                      ? Icons.volume_up
                      : Icons.play_arrow,
                ),
                label: const Text('试听复刻效果'),
              ),
              const SizedBox(width: 8),
              Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 4),
              const Text('合格后可保存角色'),
            ],
          ),
        ],
      ],
    );
  }
}
