import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_page.dart';
import 'look_image.dart';
import 'persona_compose.dart';
import 'persona_cover.dart';
import 'persona_look_gen_page.dart';
import 'persona_presets.dart';
import 'persona_template_more_page.dart';
import 'persona_templates.dart';

/// 猫箱式「创建/编辑角色」：形象占位 + 简介 + 设定 + 开场白
class PersonaEditorPage extends StatefulWidget {
  const PersonaEditorPage({super.key, this.personaId});

  /// 为空则创建；有值则编辑
  final String? personaId;

  @override
  State<PersonaEditorPage> createState() => _PersonaEditorPageState();
}

class _PersonaEditorPageState extends State<PersonaEditorPage> {
  final _nameCtrl = TextEditingController();
  final _oneLinerCtrl = TextEditingController();
  final _relationshipCtrl = TextEditingController();
  final _personalityCtrl = TextEditingController();
  final _scenarioCtrl = TextEditingController();
  final _speechStyleCtrl = TextEditingController();
  final _appearanceCtrl = TextEditingController();
  final _definitionCtrl = TextEditingController();
  final _greetingCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  String? _appliedTemplateId;
  List<PersonaTemplate> _templates = const [];
  bool _templatesLoading = true;
  String? _reviewStatus;
  String? _reviewReason;
  String _visibility = 'private';
  final Set<String> _tags = {};
  String _coverColor = kCoverColors.first;
  String _coverEmoji = '🎭';
  String _backgroundKey = 'bg_default';
  String _gender = ''; // female | male | other | ''
  String? _voiceProfileId;
  List<VoiceProfileDto> _voiceProfiles = const [];
  bool _partitionedMode = true;
  final List<TextEditingController> _altGreetingCtrls = [];
  Uint8List? _lookBytes; // 完整长方形形象图（聊天背景）
  String? _lookFilename;
  Uint8List? _avatarBytes; // 中心正方形头像
  String? _existingCoverUrl;
  String? _existingBgUrl;
  /// 套用模板时的封面（创角预览 + 保存时复制为角色头像）
  String? _templateCoverUrl;
  bool get _isEdit => widget.personaId != null && widget.personaId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadVoiceProfiles();
        await _load();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadTemplates();
        await _loadVoiceProfiles();
      });
    }
  }

  Future<void> _loadVoiceProfiles() async {
    try {
      final list = await AppStateScope.of(context).api().listVoiceProfiles();
      if (!mounted) return;
      setState(() {
        _voiceProfiles = list;
        _syncVoiceWithGender(preferKeep: true);
      });
    } catch (_) {
      /* 音色列表失败不阻断创角 */
    }
  }

  List<VoiceProfileDto> get _voicesForGender {
    if (_gender != 'female' && _gender != 'male') {
      return _voiceProfiles;
    }
    final matched = _voiceProfiles
        .where((v) => (v.gender ?? '') == _gender || (v.gender ?? '').isEmpty)
        .toList();
    return matched.isNotEmpty ? matched : _voiceProfiles;
  }

  void _syncVoiceWithGender({bool preferKeep = false}) {
    final filtered = _voicesForGender;
    if (_voiceProfileId != null &&
        filtered.any((v) => v.id == _voiceProfileId)) {
      return;
    }
    if (preferKeep &&
        _voiceProfileId != null &&
        _voiceProfiles.any((v) => v.id == _voiceProfileId) &&
        (_gender.isEmpty || _gender == 'other')) {
      return;
    }
    _voiceProfileId = filtered.isNotEmpty ? filtered.first.id : null;
  }

  void _onGenderSelected(String value) {
    setState(() {
      _gender = value;
      _syncVoiceWithGender();
    });
  }

  Future<void> _loadTemplates() async {
    if (!mounted) return;
    setState(() => _templatesLoading = true);
    try {
      final s = AppStateScope.of(context);
      final rows = await s.api().listPersonaTemplates();
      final list = [
        for (final j in rows) PersonaTemplate.fromJson(j),
      ].where((t) => t.id.isNotEmpty).toList();
      if (!mounted) return;
      final effective =
          list.isNotEmpty ? list : List<PersonaTemplate>.of(kPersonaTemplatesFallback);
      setState(() {
        _templates = effective;
        _templatesLoading = false;
        if (!_isEdit && _appliedTemplateId == null && effective.isNotEmpty) {
          _fillFromTemplate(effective.first);
        }
      });
    } catch (_) {
      if (!mounted) return;
      final fallback = List<PersonaTemplate>.of(kPersonaTemplatesFallback);
      setState(() {
        _templates = fallback;
        _templatesLoading = false;
        if (!_isEdit && _appliedTemplateId == null && fallback.isNotEmpty) {
          _fillFromTemplate(fallback.first);
        }
      });
    }
  }

  void _fillFromTemplate(PersonaTemplate t) {
    _nameCtrl.text = t.suggestedName;
    _oneLinerCtrl.text = t.oneLiner;
    _definitionCtrl.text = t.definition.trim();
    _greetingCtrl.text = t.greeting;
    _coverEmoji = t.emoji;
    _coverColor = t.coverColor;
    _templateCoverUrl =
        (t.coverUrl != null && t.coverUrl!.isNotEmpty) ? t.coverUrl : null;
    _lookBytes = null;
    _avatarBytes = null;
    _existingCoverUrl = null;
    _existingBgUrl = null;
    _partitionedMode = false;
    _appliedTemplateId = t.id;
    _voiceProfileId = t.voiceProfileId;
  }

  void _applyTemplateData(PersonaTemplate t) {
    setState(() => _fillFromTemplate(t));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _oneLinerCtrl.dispose();
    _relationshipCtrl.dispose();
    _personalityCtrl.dispose();
    _scenarioCtrl.dispose();
    _speechStyleCtrl.dispose();
    _appearanceCtrl.dispose();
    _definitionCtrl.dispose();
    _greetingCtrl.dispose();
    for (final c in _altGreetingCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _setAlternateGreetings(List<String> items) {
    for (final c in _altGreetingCtrls) {
      c.dispose();
    }
    _altGreetingCtrls
      ..clear()
      ..addAll(items.map((s) => TextEditingController(text: s)));
  }

  Future<void> _applyLookBytes(Uint8List bytes, {String filename = 'look.jpg'}) async {
    try {
      final avatar = await centerSquareAvatarBytes(bytes);
      if (!mounted) return;
      setState(() {
        _lookBytes = bytes;
        _lookFilename = filename;
        _avatarBytes = avatar;
        _templateCoverUrl = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片处理失败：${apiErrorMessage(e)}')),
      );
    }
  }

  Future<void> _pickLookFromAlbum() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    await _applyLookBytes(Uint8List.fromList(bytes), filename: file.name);
  }

  Future<void> _openLookSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _LookSourceSheet(),
    );
    if (!mounted || choice == null) return;
    if (choice == 'album') {
      await _pickLookFromAlbum();
      return;
    }
    if (choice == 'ai') {
      final genderHint = switch (_gender) {
        'female' => '女性角色',
        'male' => '男性角色',
        'other' => '中性气质角色',
        _ => '',
      };
      final hint = [
        if (genderHint.isNotEmpty) genderHint,
        if (_nameCtrl.text.trim().isNotEmpty) _nameCtrl.text.trim(),
        if (_appearanceCtrl.text.trim().isNotEmpty) _appearanceCtrl.text.trim(),
        if (_oneLinerCtrl.text.trim().isNotEmpty) _oneLinerCtrl.text.trim(),
      ].join('，');
      final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => PersonaLookGenPage(initialDescription: hint),
        ),
      );
      if (!mounted || bytes == null) return;
      await _applyLookBytes(bytes, filename: 'ai_look.jpg');
    }
  }

  Future<void> _load() async {
    final s = AppStateScope.of(context);
    try {
      final p = await s.api().getPersona(s.userId, widget.personaId!);
      if (!mounted) return;
      _nameCtrl.text = p.name;
      _oneLinerCtrl.text = p.oneLiner ?? '';
      _definitionCtrl.text = p.definition ?? '';
      _greetingCtrl.text = p.greeting ?? '';
      _appearanceCtrl.text = p.appearance ?? '';
      _scenarioCtrl.text = p.scenario ?? '';
      _relationshipCtrl.text = p.relationshipToUser ?? '';
      _personalityCtrl.text = p.personality.join('、');
      _speechStyleCtrl.text = p.speechStyle ?? '';
      _setAlternateGreetings(p.alternateGreetings);
      setState(() {
        _loading = false;
        _loadError = null;
        _reviewStatus = p.reviewStatus;
        _reviewReason = p.reviewReason;
        _visibility = p.visibility == 'public' ? 'public' : 'private';
        final hasStruct = (p.relationshipToUser ?? '').trim().isNotEmpty ||
            p.personality.isNotEmpty ||
            (p.speechStyle ?? '').trim().isNotEmpty ||
            (p.scenario ?? '').trim().isNotEmpty;
        _partitionedMode =
            (p.definition ?? '').trim().isEmpty || hasStruct;
        _existingCoverUrl = p.coverUrl;
        // 优先展示完整形象长图；没有则退回头像
        _existingBgUrl = (p.backgroundUrl != null && p.backgroundUrl!.isNotEmpty)
            ? p.backgroundUrl
            : p.coverUrl;
        _tags
          ..clear()
          ..addAll(p.tags);
        if (p.coverColor != null && p.coverColor!.isNotEmpty) {
          _coverColor = p.coverColor!;
        }
        if (p.coverEmoji != null && p.coverEmoji!.isNotEmpty) {
          _coverEmoji = p.coverEmoji!;
        }
        if (p.backgroundKey != null &&
            p.backgroundKey!.isNotEmpty &&
            p.backgroundKey != 'upload') {
          _backgroundKey = p.backgroundKey!;
        }
        _gender = p.gender ?? '';
        _voiceProfileId = p.voiceProfileId;
        _syncVoiceWithGender(preferKeep: true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = apiErrorMessage(e);
      });
    }
  }

  bool get _formDirty =>
      _nameCtrl.text.trim().isNotEmpty ||
      _oneLinerCtrl.text.trim().isNotEmpty ||
      _relationshipCtrl.text.trim().isNotEmpty ||
      _personalityCtrl.text.trim().isNotEmpty ||
      _scenarioCtrl.text.trim().isNotEmpty ||
      _speechStyleCtrl.text.trim().isNotEmpty ||
      _definitionCtrl.text.trim().isNotEmpty ||
      _greetingCtrl.text.trim().isNotEmpty ||
      _altGreetingCtrls.any((c) => c.text.trim().isNotEmpty);

  Future<void> _applyTemplate(PersonaTemplate t) async {
    if (_formDirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('套用模板？'),
          content: Text('将用「${t.title}」模板覆盖当前已填内容，可再改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖填入'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _applyTemplateData(t);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已填入「${t.title}」模板，可直接改名细调')),
    );
  }

  Future<void> _openMoreTemplates() async {
    final t = await Navigator.of(context).push<PersonaTemplate>(
      MaterialPageRoute(
        builder: (_) => PersonaTemplateMorePage(
          templates: _templates,
          selectedId: _appliedTemplateId,
          baseUrl: AppStateScope.of(context).baseUrl,
        ),
      ),
    );
    if (t != null && mounted) await _applyTemplate(t);
  }

  Future<void> _save({bool chatAfter = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameCtrl.text.trim();
    final oneLiner = _oneLinerCtrl.text.trim();
    final greeting = _greetingCtrl.text.trim();
    final definition = _partitionedMode
        ? composePersonaDefinition(
            name: name,
            relationship: _relationshipCtrl.text,
            personality: _personalityCtrl.text,
            scenario: _scenarioCtrl.text,
            speechStyle: _speechStyleCtrl.text,
            gender: _gender,
            appearance: _appearanceCtrl.text,
          )
        : _definitionCtrl.text.trim();
    final alternateGreetings = [
      for (final c in _altGreetingCtrls)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    final personalityText = _personalityCtrl.text.trim();
    final speechStyle = _speechStyleCtrl.text.trim();
    final relationship = _relationshipCtrl.text.trim();

    if (definition.length < 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('角色设定建议不少于 50 字，便于 AI 稳住人设')),
      );
      return;
    }

    final s = AppStateScope.of(context);
    setState(() => _saving = true);
    try {
      final saved = await s.api().upsertPersona(
        userId: s.userId,
        id: widget.personaId,
        name: name,
        oneLiner: oneLiner.isEmpty ? null : oneLiner,
        definition: definition,
        greeting: greeting.isEmpty ? null : greeting,
        visibility: _visibility,
        tags: _tags.toList(),
        coverEmoji: _coverEmoji,
        coverColor: _coverColor,
        backgroundKey: _lookBytes != null ? 'upload' : _backgroundKey,
        alternateGreetings: alternateGreetings,
        voiceProfileId: _voiceProfileId ?? '',
        gender: _gender,
        scenario: _scenarioCtrl.text.trim(),
        appearance: _appearanceCtrl.text.trim(),
        relationshipToUser: relationship.isEmpty ? null : relationship,
        personality: personalityText.isEmpty ? const [] : [personalityText],
        speechStyle: speechStyle,
      );
      var coverWarning = '';
      if (_lookBytes != null) {
        final avatar = _avatarBytes ??
            await centerSquareAvatarBytes(_lookBytes!);
        try {
          await s.api().uploadPersonaBackground(
            userId: s.userId,
            personaId: saved.id,
            bytes: _lookBytes!,
            filename: _lookFilename ?? 'look.jpg',
          );
        } catch (e) {
          coverWarning =
              '角色已保存，但形象长图上传失败：${apiErrorMessage(e)}';
        }
        try {
          await s.api().uploadPersonaCover(
            userId: s.userId,
            personaId: saved.id,
            bytes: avatar,
            filename: 'avatar.png',
          );
        } catch (e) {
          final msg = '头像裁剪上传失败：${apiErrorMessage(e)}';
          coverWarning = coverWarning.isEmpty ? msg : '$coverWarning\n$msg';
        }
      } else if (_templateCoverUrl != null && _templateCoverUrl!.isNotEmpty) {
        try {
          final url = resolvePersonaCoverUrl(s.baseUrl, _templateCoverUrl);
          if (url != null) {
            final res = await http.get(
              Uri.parse(url),
              headers: kMediaRequestHeaders,
            );
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              await s.api().uploadPersonaCover(
                userId: s.userId,
                personaId: saved.id,
                bytes: res.bodyBytes,
                filename: 'template_cover.jpg',
              );
            }
          }
        } catch (e) {
          coverWarning = '角色已保存，但模板头像复制失败：${apiErrorMessage(e)}';
        }
      }
      // 上传后重新拉一次，拿到 cover_url / background_url
      var latest = saved;
      try {
        latest = await s.api().getPersona(s.userId, saved.id);
      } catch (_) {
        /* 用本地 saved 兜底 */
      }
      await s.setLastPersona(latest.id);
      if (!mounted) return;
      if (coverWarning.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(coverWarning)),
        );
      }
      final msg = _visibility == 'private'
          ? '已保存「${latest.name}」（仅自己可见）'
          : (_isEdit
              ? '已保存「${latest.name}」，已重新提交公开审核'
              : '已创建「${latest.name}」，等待审核通过后上广场');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (chatAfter) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChatPage(
              personaId: latest.id,
              personaName: latest.name,
              personaCoverUrl: latest.coverUrl,
              personaCoverEmoji: latest.coverEmoji,
              personaCoverColor: latest.coverColor,
              personaBackgroundKey: latest.backgroundKey,
              personaBackgroundUrl: latest.backgroundUrl,
            ),
          ),
        );
      } else {
        Navigator.of(context).pop(latest);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：${apiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E1A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: Material(
              color: Colors.white.withValues(alpha: 0.08),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                ),
              ),
            ),
          ),
        ),
        title: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 14, color: AppColors.primaryLight.withValues(alpha: 0.9)),
                const SizedBox(width: 6),
                Text(
                  _isEdit ? '编辑角色' : '创建角色',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.auto_awesome, size: 14, color: AppColors.primaryLight.withValues(alpha: 0.9)),
              ],
            ),
            if (!_isEdit)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w500,
                    ),
                    children: const [
                      TextSpan(text: '你的专属 '),
                      TextSpan(
                        text: 'AI',
                        style: TextStyle(
                          color: AppColors.accentCyan,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(text: ' 陪伴，由你创造'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _StarryEditorBackdrop()),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(child: Text('加载失败：$_loadError'))
                    : Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                          children: [
                      if (_isEdit && (_reviewStatus == 'pending' || _reviewStatus == 'rejected')) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: _reviewStatus == 'rejected'
                                ? theme.colorScheme.errorContainer.withValues(alpha: 0.45)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _reviewStatus == 'rejected'
                                ? (_reviewReason?.trim().isNotEmpty == true
                                    ? '上次未通过：$_reviewReason\n修改后保存将重新进入审核。'
                                    : '上次未通过审核。修改后保存将重新进入审核。')
                                : '当前审核中。保存修改会重新排队等待审核；你仍可自己聊天。',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                      if (!_isEdit) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('从模板开始', style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    '选一套气质，再改名细调即可开聊',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_templates.length > kPersonaTemplatePreviewCount)
                              TextButton(
                                onPressed: _openMoreTemplates,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primaryLight,
                                  padding: const EdgeInsets.only(left: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('更多'),
                                    Icon(Icons.chevron_right_rounded, size: 18),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_templatesLoading && _templates.isEmpty)
                          const SizedBox(
                            height: 96,
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _templates.length > kPersonaTemplatePreviewCount
                                ? kPersonaTemplatePreviewCount
                                : _templates.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              mainAxisExtent: 96,
                            ),
                            itemBuilder: (context, i) {
                              final t = _templates[i];
                              return PersonaTemplateTile(
                                template: t,
                                selected: _appliedTemplateId == t.id,
                                baseUrl: AppStateScope.of(context).baseUrl,
                                onTap: () => _applyTemplate(t),
                              );
                            },
                          ),
                        const SizedBox(height: 20),
                      ],
                      _AppearanceBlock(
                        nameCtrl: _nameCtrl,
                        colorHex: _coverColor,
                        coverEmoji: _coverEmoji,
                        backgroundKey: _backgroundKey,
                        baseUrl: AppStateScope.of(context).baseUrl,
                        existingLookUrl: _existingBgUrl ?? _existingCoverUrl,
                        previewCoverUrl: _lookBytes == null
                            ? (_templateCoverUrl ?? _existingCoverUrl)
                            : null,
                        lookBytes: _lookBytes,
                        avatarBytes: _avatarBytes,
                        loading: !_isEdit &&
                            (_templatesLoading || _appliedTemplateId == null),
                        onTap: _openLookSheet,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _lookBytes != null || _existingBgUrl != null
                            ? '已设定形象：长图作聊天背景，中间裁方为头像'
                            : (_templateCoverUrl != null
                                ? '已使用模板头像；也可点击上传自定义形象'
                                : '正在加载模板形象…'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      _EditorGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel(Icons.person_outline, '角色名'),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _nameCtrl,
                              maxLength: 20,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(color: Colors.white),
                              decoration: _editorFieldDecoration(
                                hint: '给Ta起一个名字吧',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return '请填写角色名';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _EditorGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel(Icons.edit_outlined, '一句话简介'),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _oneLinerCtrl,
                              maxLength: 50,
                              maxLines: 3,
                              style: const TextStyle(color: Colors.white),
                              decoration: _editorFieldDecoration(
                                hint: '用一句话描述Ta的性格、背景或特点吧',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _EditorGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionLabel(Icons.visibility_outlined, '可见性'),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _VisibilityPick(
                                    selected: _visibility == 'private',
                                    icon: Icons.lock_outline,
                                    title: '私密',
                                    subtitle: '仅自己可见',
                                    onTap: () =>
                                        setState(() => _visibility = 'private'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _VisibilityPick(
                                    selected: _visibility == 'public',
                                    icon: Icons.public,
                                    title: '公开',
                                    subtitle: '所有人可见',
                                    onTap: () =>
                                        setState(() => _visibility = 'public'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _visibility == 'private'
                                  ? '仅你可见，可随时聊天，不上广场。'
                                  : '提交后需审核；通过后其他人才能在广场看到。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('标签（最多 5 个）', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in kPersonaTagPresets)
                            FilterChip(
                              label: Text(t),
                              selected: _tags.contains(t),
                              onSelected: (on) {
                                setState(() {
                                  if (on) {
                                    if (_tags.length >= 5) return;
                                    _tags.add(t);
                                  } else {
                                    _tags.remove(t);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('基础属性', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '性别决定可选音色；外貌会注入对话并用于生图提示',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final opt in const [
                            ('female', '女'),
                            ('male', '男'),
                            ('other', '其他'),
                          ])
                            ChoiceChip(
                              label: Text(opt.$2),
                              selected: _gender == opt.$1,
                              onSelected: (_) => _onGenderSelected(
                                _gender == opt.$1 ? '' : opt.$1,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _appearanceCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '外貌',
                          hintText: '发色、五官、穿着、气质（给 AI 与生图用）',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _scenarioCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '当前情境（可选）',
                          hintText: '你们现在在哪儿、刚发生什么',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text('角色设定', style: theme.textTheme.titleMedium),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _partitionedMode = !_partitionedMode),
                            child: Text(_partitionedMode ? '高级：整段编辑' : '分区填写'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _partitionedMode
                            ? '按身份 / 性格 / 说话方式分区填写，系统自动拼成设定'
                            : '高级模式：直接编辑完整设定文本',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_partitionedMode) ...[
                        TextFormField(
                          controller: _relationshipCtrl,
                          decoration: const InputDecoration(
                            labelText: '身份与关系',
                            hintText: '例如：你的大学室友，认识三年',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _personalityCtrl,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: '性格与动机',
                            hintText: '外向/内敛、习惯、在意什么',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _speechStyleCtrl,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: '说话方式',
                            hintText: '口语短句、爱用省略号、偶尔毒舌',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ] else
                        TextFormField(
                          controller: _definitionCtrl,
                          minLines: 8,
                          maxLines: 16,
                          decoration: const InputDecoration(
                            labelText: '角色设定',
                            hintText:
                                '我生于……性格……和你第一次见面时……\n说话习惯……禁忌……',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          validator: (v) {
                            if (!_partitionedMode &&
                                (v == null || v.trim().isEmpty)) {
                              return '请填写角色设定';
                            }
                            return null;
                          },
                        ),
                      const SizedBox(height: 20),
                      Text('开场白', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '可选 · 用「你」开场，带一点动作或未完成状态，更容易聊起来',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _greetingCtrl,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: '主开场白（可选）',
                          hintText: '你推门进来时，我正……',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('音色', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        _gender == 'female' || _gender == 'male'
                            ? '已按性别筛选音色库，点选即绑定'
                            : '请先选性别以便筛选；也可先浏览全部音色',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_voicesForGender.isEmpty)
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
                              onSelected: (_) =>
                                  setState(() => _voiceProfileId = null),
                            ),
                            for (final v in _voicesForGender)
                              ChoiceChip(
                                label: Text(
                                  v.category == null || v.category!.isEmpty
                                      ? v.label
                                      : '${v.label}·${v.category}',
                                ),
                                selected: _voiceProfileId == v.id,
                                onSelected: (_) =>
                                    setState(() => _voiceProfileId = v.id),
                              ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '备用开场白（最多 5 条）',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _altGreetingCtrls.length >= 5
                                ? null
                                : () => setState(
                                      () => _altGreetingCtrls.add(TextEditingController()),
                                    ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加'),
                          ),
                        ],
                      ),
                      for (var i = 0; i < _altGreetingCtrls.length; i++) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _altGreetingCtrls[i],
                                minLines: 2,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  labelText: '备用开场 ${i + 1}',
                                  border: const OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '删除',
                              onPressed: () => setState(() {
                                _altGreetingCtrls[i].dispose();
                                _altGreetingCtrls.removeAt(i);
                              }),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 28),
                      _CreateGradientButton(
                        onPressed: _saving ? null : () => _save(chatAfter: false),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isEdit ? '保存' : '创建并保存'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _saving ? null : () => _save(chatAfter: true),
                        child: const Text('保存并开始聊天'),
                      ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryLight),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.auto_awesome,
          size: 12,
          color: AppColors.primary.withValues(alpha: 0.8),
        ),
      ],
    );
  }

  InputDecoration _editorFieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.28),
      counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
      ),
    );
  }
}

class _EditorGlassCard extends StatelessWidget {
  const _EditorGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1830).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _VisibilityPick extends StatelessWidget {
  const _VisibilityPick({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primaryLight
                  : Colors.white.withValues(alpha: 0.08),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? AppColors.primaryLight
                    : Colors.white.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateGradientButton extends StatelessWidget {
  const _CreateGradientButton({required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: AppColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarryEditorBackdrop extends StatelessWidget {
  const _StarryEditorBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1540),
            Color(0xFF12101F),
            Color(0xFF0A0A12),
          ],
        ),
      ),
      child: CustomPaint(painter: _StarFieldPainter()),
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    const pts = [
      Offset(0.12, 0.08),
      Offset(0.28, 0.14),
      Offset(0.46, 0.06),
      Offset(0.68, 0.11),
      Offset(0.84, 0.07),
      Offset(0.18, 0.22),
      Offset(0.55, 0.18),
      Offset(0.78, 0.24),
      Offset(0.35, 0.28),
      Offset(0.92, 0.16),
    ];
    for (final p in pts) {
      canvas.drawCircle(
        Offset(p.dx * size.width, p.dy * size.height),
        1.4,
        paint,
      );
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.primaryLight.withValues(alpha: 0.22);
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.5, size.height * 0.18),
        radius: size.width * 0.38,
      ),
      -2.2,
      1.6,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AppearanceBlock extends StatelessWidget {
  const _AppearanceBlock({
    required this.nameCtrl,
    required this.colorHex,
    required this.coverEmoji,
    required this.backgroundKey,
    required this.baseUrl,
    required this.onTap,
    this.existingLookUrl,
    this.previewCoverUrl,
    this.lookBytes,
    this.avatarBytes,
    this.loading = false,
  });

  final TextEditingController nameCtrl;
  final String colorHex;
  final String coverEmoji;
  final String backgroundKey;
  final String baseUrl;
  final VoidCallback onTap;
  final String? existingLookUrl;
  /// 模板/已有封面（仅头像，非长图形象）
  final String? previewCoverUrl;
  final Uint8List? lookBytes;
  final Uint8List? avatarBytes;
  final bool loading;

  static const _accent = AppColors.accentCyan;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: nameCtrl,
      builder: (context, _) {
        final label =
            coverEmoji.isNotEmpty ? coverEmoji : '🎭';
        final networkUrl = lookBytes == null
            ? resolvePersonaBackgroundUrl(baseUrl, existingLookUrl)
            : null;
        final coverPreviewUrl = lookBytes == null && networkUrl == null
            ? resolvePersonaCoverUrl(baseUrl, previewCoverUrl)
            : null;
        final hasImage = lookBytes != null || networkUrl != null;
        final hasTemplateAvatar = coverPreviewUrl != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2.15,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(20),
                  child: CustomPaint(
                    painter: _GradientDashedRRectPainter(radius: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: loading
                          ? _loadingLook()
                          : hasImage
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                if (lookBytes != null)
                                  Image.memory(lookBytes!, fit: BoxFit.cover)
                                else
                                  AppNetworkImage(
                                    url: networkUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => _loadingLook(),
                                  ),
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: _CenterSquareGuidePainter(),
                                  ),
                                ),
                                if (avatarBytes != null)
                                  Positioned(
                                    right: 12,
                                    top: 12,
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _accent,
                                          width: 2,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Image.memory(
                                        avatarBytes!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    color: Colors.black54,
                                    child: const Text(
                                      '点击更换形象',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : hasTemplateAvatar
                              ? _templateAvatarLook(coverPreviewUrl!, label)
                              : _loadingLook(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _loadingLook() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1830).withValues(alpha: 0.85),
      ),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }

  Widget _templateAvatarLook(String coverUrl, String label) {
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
            parseHexColor(preset['color_from']!),
            parseHexColor(colorHex),
            parseHexColor(preset['color_to']!),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: PersonaCoverAvatar(
              baseUrl: baseUrl,
              coverUrl: coverUrl,
              fallbackColor: parseHexColor(colorHex),
              fallbackLabel: label,
              radius: 52,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: Colors.black54,
              child: const Text(
                '点击更换形象',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LookSourceSheet extends StatelessWidget {
  const _LookSourceSheet();

  static const _accent = AppColors.accentCyan;
  static const _panel = AppColors.bgDarkElevated;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.auto_awesome, color: _accent),
                    title: const Text(
                      'AI 生成形象',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, 'ai'),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  ListTile(
                    title: const Text(
                      '从相册选取',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => Navigator.pop(context, 'album'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: _panel,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      '取消',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientDashedRRectPainter extends CustomPainter {
  _GradientDashedRRectPainter({this.radius = 20});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        stroke / 2,
        stroke / 2,
        size.width - stroke,
        size.height - stroke,
      ),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFE8C547),
          Color(0xFF5CE1E6),
          Color(0xFF7B6CF6),
          Color(0xFFA78BFA),
        ],
      ).createShader(Offset.zero & size);
    const dash = 7.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    this.radius = 16,
    this.strokeWidth = 1.4,
    this.dash = 6,
    this.gap = 4,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _CenterSquareGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.42;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: side,
      height: side,
    );
    final paint = Paint()
      ..color = AppColors.accentCyan.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}