import 'package:flutter/material.dart';

import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../state/project_templates.dart';
import 'document_actions.dart' show DocTypeDot;
import 'template_labels.dart';
import 'theme.dart';

/// ผลของกล่องสร้างโปรเจกต์ใหม่
class NewProjectResult {
  const NewProjectResult(this.name, this.docs);
  final String name;

  /// เอกสารที่จะสร้างต่อจาก ER (ER มีเสมอ)
  final Set<DocType> docs;
}

String _typeLabel(DocType t) => switch (t) {
      DocType.er => 'ER Diagram',
      DocType.dfd => 'Data Flow',
      DocType.flowchart => 'Flowchart',
      DocType.wireframe => 'Wireframe',
      DocType.screenflow => 'Screen Flow',
    };

/// กล่องสร้างโปรเจกต์ใหม่: เลือกจุดเริ่มต้น + ตั้งชื่อ + ติ๊กเอกสารที่จะมีตั้งแต่แรก — คืน null เมื่อยกเลิก
Future<NewProjectResult?> showNewProjectDialog(BuildContext context, {ProjectTemplate initial = ProjectTemplate.blank}) =>
    showDialog<NewProjectResult>(context: context, builder: (_) => NewProjectDialog(initial: initial));

class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key, this.initial = ProjectTemplate.blank});
  final ProjectTemplate initial;

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  late ProjectTemplate _preset = widget.initial;
  late Set<DocType> _docs = {...widget.initial.extraDocs};
  late final TextEditingController _name = TextEditingController(text: tr('โปรเจกต์ใหม่'));

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _pick(ProjectTemplate t) => setState(() {
        _preset = t;
        _docs = {...t.extraDocs};
      });

  void _submit() {
    final name = _name.text.trim();
    Navigator.pop(context, NewProjectResult(name.isEmpty ? tr('โปรเจกต์ใหม่') : name, {..._docs}));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 560),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('โปรเจกต์ใหม่'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(tr('เลือกจุดเริ่มต้น'), style: TextStyle(color: C.muted)),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final t in ProjectTemplate.values) _PresetCard(template: t, selected: t == _preset, onTap: () => _pick(t)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Container(
            width: 300,
            decoration: BoxDecoration(border: Border(left: BorderSide(color: C.borderSoft))),
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('รายละเอียด'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('newproject-name'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('ชื่อโปรเจกต์'), isDense: true, border: const OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Text(tr('เอกสารเริ่มต้น'), style: TextStyle(fontSize: 12, color: C.muted)),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final t in DocType.values)
                      CheckboxListTile(
                        key: ValueKey('newproject-doc-${t.name}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        // ER มีเสมอ: โปรเจกต์ต้องมี ER อย่างน้อยหนึ่งอัน
                        value: t == DocType.er || _docs.contains(t),
                        onChanged: t == DocType.er
                            ? null
                            : (v) => setState(() => v == true ? _docs.add(t) : _docs.remove(t)),
                        title: Row(children: [DocTypeDot(t), const SizedBox(width: 8), Text(_typeLabel(t))]),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก')))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(key: const ValueKey('newproject-create'), onPressed: _submit, child: Text(tr('สร้างโปรเจกต์')))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.template, required this.selected, required this.onTap});
  final ProjectTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: Material(
          color: C.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? C.primary : C.border, width: selected ? 2 : 1),
          ),
          child: InkWell(
            key: ValueKey('newproject-preset-${template.name}'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  for (final t in [DocType.er, ...template.extraDocs]) Padding(padding: const EdgeInsets.only(right: 5), child: DocTypeDot(t)),
                ]),
                const SizedBox(height: 10),
                Text(templateName(template), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(templateDesc(template), style: TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ),
        ),
      );
}
