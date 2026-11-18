import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/codegen/gen_targets.dart';
import '../core/codegen/gen_writer.dart';
import '../core/l10n/l10n.dart';
import '../state/workspace_controller.dart';
import 'theme.dart';

String genSourceLabel(GenSource s) => switch (s) {
  GenSource.database => tr('ฐานข้อมูล · จาก ER'),
  GenSource.models => tr('โมเดล · จาก ER'),
  GenSource.api => tr('API · จาก API Designer'),
  GenSource.screens => tr('หน้าจอ · จาก Wireframe'),
};

String genTargetLabel(GenTarget t) => switch (t) {
  GenTarget.sqlDdl => tr('SQL DDL (ตาม dialect ของ ER)'),
  GenTarget.laravelMigration => 'Migration · Laravel',
  GenTarget.prisma => 'Prisma schema',
  GenTarget.seedSql => tr('ข้อมูลตั้งต้น (seed)'),
  GenTarget.typescript => 'TypeScript types',
  GenTarget.dart => 'Dart model (Flutter)',
  GenTarget.java => 'Java (JPA)',
  GenTarget.csharp => 'C# (EF Core)',
  GenTarget.openApi => 'OpenAPI 3.1 (JSON)',
  GenTarget.laravelRoutes => tr('Route + Controller ว่าง (Laravel)'),
  GenTarget.flutterScreen => tr('Flutter widget โครงหน้า'),
  GenTarget.htmlTailwind => 'HTML + Tailwind',
};

/// หน้าสร้างโค้ด (Artboard `Codegen`): เลือกเป้าหมาย · ไฟล์ที่จะได้ · พรีวิว · เขียนลงโฟลเดอร์ (ถามก่อนทับไฟล์ที่แก้ด้วยมือ)
/// แสดงแทนแคนวาสขณะ [WorkspaceController.page] == [WorkspacePage.codegen]
class CodegenView extends StatefulWidget {
  const CodegenView({super.key});

  @override
  State<CodegenView> createState() => _CodegenViewState();
}

class _CodegenViewState extends State<CodegenView> {
  late Set<GenTarget> _targets;
  late final TextEditingController _folder;
  String? _previewPath;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final preset = context.read<WorkspaceController>().codegenPreset;
    final byName = GenTarget.values.asNameMap();
    _targets = preset == null ? {GenTarget.sqlDdl, GenTarget.typescript} : {for (final n in preset.targets) ?byName[n]};
    _folder = TextEditingController(text: preset?.folder ?? '');
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final p = await FilePicker.getDirectoryPath(dialogTitle: tr('เลือกโฟลเดอร์ปลายทาง'));
    if (p != null) setState(() => _folder.text = p);
  }

  void _toast(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  Future<void> _generate(List<GenFile> files) async {
    final folder = _folder.text.trim();
    if (folder.isEmpty) {
      _toast(tr('เลือกโฟลเดอร์ปลายทางก่อน'));
      return;
    }
    setState(() => _busy = true);
    try {
      final plan = await planWrite(Directory(folder), files);
      var overwrite = false;
      if (plan.edited.isNotEmpty) {
        if (!mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (_) => _EditedDialog(paths: [for (final f in plan.edited) f.path]),
        );
        if (choice == null) return;
        overwrite = choice == 'overwrite';
      }
      final n = await applyWrite(plan, overwriteEdited: overwrite);
      final skipped = overwrite ? 0 : plan.edited.length;
      _toast(
        skipped == 0
            ? tr('เขียนแล้ว {0} ไฟล์ · ไม่เปลี่ยน {1} ไฟล์', [n, plan.unchanged.length])
            : tr('เขียนแล้ว {0} ไฟล์ · ไม่เปลี่ยน {1} ไฟล์ · ข้ามไฟล์ที่แก้ด้วยมือ {2} ไฟล์', [n, plan.unchanged.length, skipped]),
      );
    } catch (e) {
      _toast(tr('เขียนไฟล์ไม่ได้: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final avail = {
      for (final t in GenTarget.values)
        if (targetAvailable(w.workspace, t)) t,
    };
    final chosen = _targets.intersection(avail);
    final result = generateFiles(w.workspace, chosen);
    final files = result.files;
    final preview = files.where((f) => f.path == _previewPath).firstOrNull ?? files.firstOrNull;

    final targetsPanel = Material(
      color: C.surface,
      shape: Border(right: BorderSide(color: C.border)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('สร้างอะไรบ้าง'),
              style: TextStyle(fontWeight: FontWeight.w700, color: C.text),
            ),
            for (final s in GenSource.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
                child: Text(
                  genSourceLabel(s),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.muted),
                ),
              ),
              for (final t in GenTarget.values.where((t) => t.source == s))
                CheckboxListTile(
                  key: ValueKey('gen-target-${t.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: chosen.contains(t),
                  onChanged: avail.contains(t) ? (v) => setState(() => v == true ? _targets.add(t) : _targets.remove(t)) : null,
                  title: Text(genTargetLabel(t), style: const TextStyle(fontSize: 13)),
                ),
            ],
            const SizedBox(height: 14),
            Text(
              tr('ส่งออกไปที่โฟลเดอร์'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.muted),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('gen-folder'),
                    controller: _folder,
                    style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                    decoration: const InputDecoration(isDense: true, hintText: r'C:\project'),
                  ),
                ),
                IconButton(
                  key: const ValueKey('gen-browse'),
                  tooltip: tr('เลือกโฟลเดอร์…'),
                  onPressed: _browse,
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final tree = Material(
      color: C.surface,
      shape: Border(right: BorderSide(color: C.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Text(
              tr('ไฟล์ที่จะได้ · {0}', [files.length]),
              key: const ValueKey('gen-count'),
              style: TextStyle(fontWeight: FontWeight.w700, color: C.text),
            ),
          ),
          for (final m in result.warnings)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(m, style: TextStyle(fontSize: 12, color: C.warnText)),
            ),
          Expanded(
            child: files.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        avail.isEmpty
                            ? tr('ยังไม่มีเอกสารที่สร้างโค้ดได้ (ER ที่มีตาราง / API ที่มี endpoint / Wireframe ที่มีชิ้นส่วน)')
                            : tr('เลือกเป้าหมายทางซ้าย'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: C.muted),
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final f in files)
                        Material(
                          color: f.path == preview?.path ? C.primaryTint : Colors.transparent,
                          child: InkWell(
                            key: ValueKey('gen-file-${f.path}'),
                            onTap: () => setState(() => _previewPath = f.path),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                              child: Text(
                                f.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: C.text),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );

    final previewPane = Container(
      color: C.bg,
      child: preview == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preview.path,
                              style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', color: C.text),
                            ),
                            Text(
                              tr('จาก {0} · {1}', [preview.origin, genTargetLabel(preview.target)]),
                              style: TextStyle(fontSize: 12, color: C.muted),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('gen-copy'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: preview.content));
                          _toast(tr('คัดลอกแล้ว'));
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(tr('คัดลอก')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      color: C.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: C.border),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        preview.content,
                        key: const ValueKey('gen-preview'),
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: C.text, height: 1.45),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );

    final bottom = Material(
      color: C.surface,
      shape: Border(top: BorderSide(color: C.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tr('{0} ชนิดเป้าหมาย · {1} ไฟล์', [chosen.length, files.length]),
                style: TextStyle(fontSize: 12.5, color: C.muted),
              ),
            ),
            OutlinedButton(
              key: const ValueKey('gen-save-preset'),
              onPressed: () {
                w.setCodegenPreset([
                  for (final t in GenTarget.values)
                    if (_targets.contains(t)) t.name,
                ], _folder.text);
                _toast(tr('บันทึกชุดตั้งค่าในโปรเจกต์แล้ว (บันทึกไฟล์เพื่อเก็บถาวร)'));
              },
              child: Text(tr('บันทึกเป็นชุดตั้งค่า')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('gen-write'),
              onPressed: files.isEmpty || _busy ? null : () => _generate(files),
              child: Text(tr('สร้างไฟล์')),
            ),
          ],
        ),
      ),
    );

    return Container(
      key: const ValueKey('codegen-view'),
      color: C.bg,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth < 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 250, child: targetsPanel),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: tree),
                            Expanded(flex: 2, child: previewPane),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 270, child: targetsPanel),
                    SizedBox(width: 290, child: tree),
                    Expanded(child: previewPane),
                  ],
                );
              },
            ),
          ),
          bottom,
        ],
      ),
    );
  }
}

class _EditedDialog extends StatelessWidget {
  const _EditedDialog({required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('gen-edited-dialog'),
    title: Text(tr('{0} ไฟล์ในโฟลเดอร์ถูกแก้ด้วยมือ', [paths.length])),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('ไฟล์เหล่านี้ต่างจากที่โปรแกรมสร้างไว้ครั้งก่อน (หรือมีอยู่ก่อนแล้ว) — เขียนทับจะทำให้การแก้ไขหาย')),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(
              shrinkWrap: true,
              children: [for (final p in paths) Text(p, style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'))],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
      OutlinedButton(
        key: const ValueKey('gen-skip-edited'),
        onPressed: () => Navigator.pop(context, 'skip'),
        child: Text(tr('ข้ามไฟล์เหล่านี้')),
      ),
      FilledButton(
        key: const ValueKey('gen-overwrite-edited'),
        style: FilledButton.styleFrom(backgroundColor: C.danger),
        onPressed: () => Navigator.pop(context, 'overwrite'),
        child: Text(tr('เขียนทับ')),
      ),
    ],
  );
}
