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
  GenTarget.openApiYaml => 'OpenAPI 3.1 (YAML)',
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
  String _filter = '';
  final Set<String> _collapsed = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final preset = context.read<WorkspaceController>().codegenPreset;
    final byName = GenTarget.values.asNameMap();
    _targets = preset == null
        ? {GenTarget.sqlDdl, GenTarget.typescript}
        : {for (final n in preset.targets) ?byName[n]};
    _folder = TextEditingController(text: preset?.folder ?? '');
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final p = await FilePicker.getDirectoryPath(
      dialogTitle: tr('เลือกโฟลเดอร์ปลายทาง'),
    );
    if (p != null) setState(() => _folder.text = p);
  }

  void _toast(String m) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(m)));

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
          builder: (_) =>
              _EditedDialog(paths: [for (final f in plan.edited) f.path]),
        );
        if (choice == null) return;
        overwrite = choice == 'overwrite';
      }
      final n = await applyWrite(plan, overwriteEdited: overwrite);
      final skipped = overwrite ? 0 : plan.edited.length;
      _toast(
        skipped == 0
            ? tr('เขียนแล้ว {0} ไฟล์ · ไม่เปลี่ยน {1} ไฟล์', [
                n,
                plan.unchanged.length,
              ])
            : tr(
                'เขียนแล้ว {0} ไฟล์ · ไม่เปลี่ยน {1} ไฟล์ · ข้ามไฟล์ที่แก้ด้วยมือ {2} ไฟล์',
                [n, plan.unchanged.length, skipped],
              ),
      );
    } catch (e) {
      _toast(tr('เขียนไฟล์ไม่ได้: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _dir(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? './' : path.substring(0, i + 1);
  }

  /// ชื่อที่โชว์ในรายการ : ตัดโฟลเดอร์ออก และย่อ timestamp หน้าชื่อ migration ให้เห็นชื่อตารางชัด ๆ
  static String _shortName(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    return name.replaceFirst(RegExp(r'^\d{4}_\d{2}_\d{2}_\d{6}_'), '…');
  }

  static String _size(String s) {
    final b = s.length;
    return b < 1024 ? '$b B' : '${(b / 1024).toStringAsFixed(1)} KB';
  }

  Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: C.text,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

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
    final preview =
        files.where((f) => f.path == _previewPath).firstOrNull ??
        files.firstOrNull;
    final perTarget = <GenTarget, int>{};
    for (final f in files) {
      perTarget[f.target] = (perTarget[f.target] ?? 0) + 1;
    }
    final q = _filter.trim().toLowerCase();
    final shown = q.isEmpty
        ? files
        : [
            for (final f in files)
              if (f.path.toLowerCase().contains(q)) f,
          ];
    final folders = <String, List<GenFile>>{};
    for (final f in shown) {
      folders.putIfAbsent(_dir(f.path), () => []).add(f);
    }
    final allFolders = {for (final f in files) _dir(f.path)};

    // ───── ซ้าย : เลือกว่าจะสร้างอะไร (การ์ดต่อกลุ่ม) + โฟลเดอร์ปลายทาง ─────
    final targetsPanel = Material(
      color: C.surface,
      shape: Border(right: BorderSide(color: C.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            tr('สร้างอะไรบ้าง'),
            trailing: Text(
              tr('เปิด {0} จาก {1}', [chosen.length, avail.length]),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: C.primaryDark,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final s in GenSource.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: C.bg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: C.borderSoft),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                            child: Text(
                              genSourceLabel(s),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: C.muted,
                              ),
                            ),
                          ),
                          Divider(height: 1, color: C.borderSoft),
                          for (final t in GenTarget.values.where(
                            (t) => t.source == s,
                          ))
                            CheckboxListTile(
                              key: ValueKey('gen-target-${t.name}'),
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              value: chosen.contains(t),
                              onChanged: avail.contains(t)
                                  ? (v) => setState(
                                      () => v == true
                                          ? _targets.add(t)
                                          : _targets.remove(t),
                                    )
                                  : null,
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      genTargetLabel(t),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  if (chosen.contains(t))
                                    Text(
                                      '${perTarget[t] ?? 0}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: C.muted,
                                        fontFamily: kMono,
                                        fontFamilyFallback: const ['Consolas'],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: C.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('ส่งออกไปที่โฟลเดอร์'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: C.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('gen-folder'),
                        controller: _folder,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: r'C:\project',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.outlined(
                      key: const ValueKey('gen-browse'),
                      tooltip: tr('เลือกโฟลเดอร์…'),
                      onPressed: _browse,
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // ───── กลาง : ไฟล์ที่จะได้ จัดเป็นโฟลเดอร์ ─────
    final tree = Material(
      color: C.surface,
      shape: Border(right: BorderSide(color: C.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            tr('ไฟล์ที่จะได้'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: C.field,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${files.length}',
                key: const ValueKey('gen-count'),
                style: TextStyle(fontSize: 12, color: C.muted),
              ),
            ),
          ),
          if (files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                key: const ValueKey('gen-filter'),
                onChanged: (v) => setState(() => _filter = v),
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('กรองไฟล์'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
                            ? tr(
                                'ยังไม่มีเอกสารที่สร้างโค้ดได้ (ER ที่มีตาราง / API ที่มี endpoint / Wireframe ที่มีชิ้นส่วน)',
                              )
                            : tr('เลือกเป้าหมายทางซ้าย'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: C.muted),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: [
                      for (final e in folders.entries) ...[
                        InkWell(
                          key: ValueKey('gen-folder-${e.key}'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setState(
                            () => _collapsed.contains(e.key)
                                ? _collapsed.remove(e.key)
                                : _collapsed.add(e.key),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _collapsed.contains(e.key) && q.isEmpty
                                      ? Icons.chevron_right_rounded
                                      : Icons.expand_more_rounded,
                                  size: 16,
                                  color: C.muted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    e.key,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: C.muted,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                Text(
                                  '${e.value.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: C.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (q.isNotEmpty || !_collapsed.contains(e.key))
                          for (final f in e.value)
                            Tooltip(
                              message: f.path,
                              waitDuration: const Duration(milliseconds: 500),
                              child: Material(
                                color: f.path == preview?.path
                                    ? C.primaryTint
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                child: InkWell(
                                  key: ValueKey('gen-file-${f.path}'),
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () =>
                                      setState(() => _previewPath = f.path),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      26,
                                      5,
                                      8,
                                      5,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.insert_drive_file_outlined,
                                          size: 14,
                                          color: C.muted,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _shortName(f.path),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: C.text,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );

    // ───── ขวา : พรีวิวไฟล์ ─────
    final previewPane = Container(
      color: C.bg,
      child: preview == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preview.path,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                                color: C.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${tr('จาก {0} · {1}', [preview.origin, genTargetLabel(preview.target)])}'
                              ' · ${tr('{0} บรรทัด', ['\n'.allMatches(preview.content).length + 1])} · ${_size(preview.content)}',
                              style: TextStyle(fontSize: 12, color: C.muted),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('gen-copy'),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: preview.content),
                          );
                          _toast(tr('คัดลอกแล้ว'));
                        },
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        label: Text(tr('คัดลอก')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    decoration: BoxDecoration(
                      color: C.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.border),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: SelectableText(
                        preview.content,
                        key: const ValueKey('gen-preview'),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: C.text,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );

    // ───── แถบล่าง : สรุป + ปุ่มหลัก ─────
    final folderText = _folder.text.trim();
    final bottom = Material(
      color: C.surface,
      shape: Border(top: BorderSide(color: C.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Text(
              tr('{0} ชนิดเป้าหมาย · {1} ไฟล์ · {2} โฟลเดอร์', [
                chosen.length,
                files.length,
                allFolders.length,
              ]),
              style: TextStyle(fontSize: 13, color: C.muted),
            ),
            if (folderText.isNotEmpty) ...[
              const SizedBox(width: 14),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: C.field,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_outlined, size: 14, color: C.muted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          folderText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: C.muted,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Spacer(),
            OutlinedButton(
              key: const ValueKey('gen-save-preset'),
              onPressed: () {
                w.setCodegenPreset([
                  for (final t in GenTarget.values)
                    if (_targets.contains(t)) t.name,
                ], _folder.text);
                _toast(
                  tr(
                    'บันทึกชุดตั้งค่าในโปรเจกต์แล้ว (บันทึกไฟล์เพื่อเก็บถาวร)',
                  ),
                );
              },
              child: Text(tr('บันทึกเป็นชุดตั้งค่า')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('gen-write'),
              onPressed: files.isEmpty || _busy ? null : () => _generate(files),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(
                files.isEmpty
                    ? tr('สร้างไฟล์')
                    : tr('สร้าง {0} ไฟล์', [files.length]),
              ),
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
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: C.borderSoft)),
            ),
            child: Row(
              children: [
                Icon(Icons.code_rounded, size: 20, color: C.primaryDark),
                const SizedBox(width: 10),
                Text(
                  tr('สร้างโค้ด'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: C.text,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('เลือกสิ่งที่จะสร้าง ดูไฟล์ แล้วเขียนลงโฟลเดอร์'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: C.muted),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth < 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 270, child: targetsPanel),
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
                    SizedBox(width: 300, child: targetsPanel),
                    SizedBox(width: 340, child: tree),
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
          Text(
            tr(
              'ไฟล์เหล่านี้ต่างจากที่โปรแกรมสร้างไว้ครั้งก่อน (หรือมีอยู่ก่อนแล้ว) — เขียนทับจะทำให้การแก้ไขหาย',
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in paths)
                  Text(
                    p,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('ยกเลิก')),
      ),
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
