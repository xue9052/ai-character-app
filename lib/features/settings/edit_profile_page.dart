import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../services/app_state.dart';
import '../../theme/app_widgets.dart';
import '../../widgets/user_avatar.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, this.fromRegister = false});

  final bool fromRegister;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nickCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  List<AvatarPreset> _presets = const [];
  String? _avatarKey;
  String _avatarEmoji = '🌙';
  String _avatarColor = '#5B7C99';
  String _avatarUrl = '';
  Uint8List? _pendingBytes;
  String _pendingName = 'avatar.jpg';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final s = AppStateScope.of(context);
      final u = s.user;
      if (u != null) {
        _nickCtrl.text = u.nickname;
        _bioCtrl.text = u.bio;
        _avatarKey = u.avatarKey;
        _avatarEmoji = u.avatarEmoji;
        _avatarColor = u.avatarColor;
        _avatarUrl = u.avatarUrl;
      }
      final presets = await s.api().avatarPresets();
      if (!mounted) return;
      setState(() {
        _presets = presets;
        if (_avatarKey == null && presets.isNotEmpty) {
          _avatarKey = presets.first.key;
          _avatarEmoji = presets.first.emoji;
          _avatarColor = presets.first.color;
        }
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 768,
        maxHeight: 768,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingBytes = bytes;
        _pendingName = x.name.isNotEmpty ? x.name : 'avatar.jpg';
        _avatarKey = 'upload';
        _avatarEmoji = '📷';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选图失败：$e')),
      );
    }
  }

  Future<void> _save() async {
    final s = AppStateScope.of(context);
    final token = s.accessToken;
    if (token == null) return;
    final nick = _nickCtrl.text.trim();
    if (nick.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写昵称')),
      );
      return;
    }
    if (_avatarKey == null && _pendingBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择头像')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      AuthUser user;
      if (_pendingBytes != null) {
        await s.api().uploadAvatar(
          accessToken: token,
          bytes: _pendingBytes!,
          filename: _pendingName,
        );
        user = await s.api().updateMe(
          accessToken: token,
          nickname: nick,
          bio: _bioCtrl.text.trim(),
        );
      } else {
        user = await s.api().updateMe(
          accessToken: token,
          nickname: nick,
          avatarKey: _avatarKey,
          bio: _bioCtrl.text.trim(),
        );
      }
      await s.applyUser(user);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资料已保存')),
      );
      if (!widget.fromRegister) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skip() async {
    final s = AppStateScope.of(context);
    final token = s.accessToken;
    if (token == null) return;
    setState(() => _saving = true);
    try {
      final nick = _nickCtrl.text.trim();
      final user = await s.api().updateMe(
        accessToken: token,
        nickname: nick.isEmpty ? (s.user?.nickname ?? '') : nick,
        avatarKey: _avatarKey,
        bio: _bioCtrl.text.trim(),
      );
      await s.applyUser(user);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = AppStateScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromRegister ? '完善资料' : '编辑资料'),
        actions: [
          if (!widget.fromRegister)
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                if (widget.fromRegister) ...[
                  Text(
                    '先挑个喜欢的样子，也可以上传自己的照片',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 12),
                ],
                Center(
                  child: UserAvatar(
                    emoji: _avatarEmoji,
                    colorHex: _avatarColor,
                    image: _pendingBytes != null
                        ? MemoryImage(_pendingBytes!)
                        : null,
                    imageUrl: _pendingBytes == null
                        ? s.absoluteAvatarUrl(_avatarUrl)
                        : null,
                    radius: 40,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickImage,
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('上传照片'),
                  ),
                ),
                const SizedBox(height: 20),
                Text('头像预设', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final p in _presets)
                      InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () => setState(() {
                          _avatarKey = p.key;
                          _avatarEmoji = p.emoji;
                          _avatarColor = p.color;
                          _pendingBytes = null;
                          _avatarUrl = '';
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _avatarKey == p.key && _pendingBytes == null
                                  ? scheme.primary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: UserAvatar(
                            emoji: p.emoji,
                            colorHex: p.color,
                            radius: 22,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nickCtrl,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: '昵称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bioCtrl,
                  maxLength: 120,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '简介（选填）',
                    hintText: '一句话介绍自己',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                FrostButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
                if (widget.fromRegister) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : _skip,
                    child: const Text('暂时跳过'),
                  ),
                ],
              ],
            ),
    );
  }
}
