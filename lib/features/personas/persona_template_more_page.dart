import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'persona_cover.dart';
import 'persona_templates.dart';

/// 创建页预览：2 行 × 4 列
const kPersonaTemplatePreviewCount = 8;

class PersonaTemplateTile extends StatelessWidget {
  const PersonaTemplateTile({
    super.key,
    required this.template,
    required this.selected,
    required this.baseUrl,
    required this.onTap,
    this.showSubtitle = false,
  });

  final PersonaTemplate template;
  final bool selected;
  final String baseUrl;
  final VoidCallback onTap;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primaryLight : Colors.transparent,
                  width: 2,
                ),
              ),
              child: PersonaCoverAvatar(
                baseUrl: baseUrl,
                coverUrl: template.coverUrl,
                fallbackColor: parseHexColor(
                  template.coverColor,
                  fallback: 0xFF5B8A72,
                ),
                fallbackLabel: template.emoji,
                radius: 28,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              template.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primaryLight : Colors.white,
              ),
            ),
            if (showSubtitle && template.subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                template.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 全部创角模板；点选后 pop 回所选模板，由创建页套用。
class PersonaTemplateMorePage extends StatelessWidget {
  const PersonaTemplateMorePage({
    super.key,
    required this.templates,
    required this.baseUrl,
    this.selectedId,
  });

  final List<PersonaTemplate> templates;
  final String baseUrl;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '更多模板',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 8,
          mainAxisExtent: 118,
        ),
        itemCount: templates.length,
        itemBuilder: (context, i) {
          final t = templates[i];
          return PersonaTemplateTile(
            template: t,
            selected: selectedId == t.id,
            baseUrl: baseUrl,
            showSubtitle: true,
            onTap: () => Navigator.of(context).pop(t),
          );
        },
      ),
    );
  }
}
