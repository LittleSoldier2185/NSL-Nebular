import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../core/storage/recent_files.dart';
import '../state/app_settings.dart';
import '../state/project_controller.dart';
import '../state/project_templates.dart';
import 'document_actions.dart' show DocTypeDot, docTypeIcon;
import 'file_actions.dart';
import 'new_project_dialog.dart';
import 'template_labels.dart';
import 'theme.dart';

/// ข้อความเวลาแบบสั้นของไฟล์ล่าสุด ("เมื่อวาน", "3 วันที่แล้ว") — เกิน 30 วันแสดงเป็นวันที่
String relativeTimeLabel(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.isNegative || d.inMinutes < 1) return tr('เมื่อสักครู่');
  if (d.inMinutes < 60) return tr('{0} นาทีที่แล้ว', [d.inMinutes]);
  if (d.inHours < 24) return tr('{0} ชั่วโมงที่แล้ว', [d.inHours]);
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days == 1) return tr('เมื่อวาน');
  if (days <= 30) return tr('{0} วันที่แล้ว', [days]);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

String _docLabel(DocType t) => switch (t) {
      DocType.er => 'ER Diagram',
      DocType.dfd => 'Data Flow',
      DocType.flowchart => 'Flowchart',
      DocType.wireframe => 'Wireframe',
      DocType.screenflow => 'Screen Flow',
    };

/// หน้าเปิดโปรแกรม (แสดงเมื่อเปิดแอปโดยไม่มีไฟล์ให้เปิด): สร้างใหม่ด่วน / ไฟล์ล่าสุด / เริ่มจากจุดเริ่มต้นสำเร็จรูป
class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  @override
  void initState() {
    super.initState();
    // ตัดไฟล์ที่ไม่มีอยู่แล้วออกจากรายการ (หลังเฟรมแรก — ห้ามแจ้ง listener ระหว่าง build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppSettings>().pruneRecent((p) {
        try {
          return File(p).existsSync();
        } catch (_) {
          return false;
        }
      });
    });
  }

  ProjectController get _er => context.read<ProjectController>();

  /// สร้างโปรเจกต์ใหม่: ถามบันทึกงานเดิมก่อน (หน้า Start เปิดตอนเริ่ม งานเดิมสะอาดจึงไม่ถาม)
  Future<void> _create(Iterable<DocType> docs, {String? name}) async {
    final c = _er;
    if (!await FileActions.confirmDiscard(context, c)) return;
    if (!mounted) return;
    createProject(c.workspaceController, docs: docs, name: name);
  }

  Future<void> _newProjectDialog() async {
    final r = await showNewProjectDialog(context);
    if (r == null || !mounted) return;
    await _create(r.docs, name: r.name);
  }

  Future<void> _openRecent(RecentFile f) async {
    final settings = context.read<AppSettings>();
    final c = _er;
    final exists = File(f.path).existsSync();
    if (!mounted) return;
    if (!exists) {
      settings.removeRecent(f.path);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ไม่พบไฟล์ {0} — เอาออกจากรายการล่าสุดแล้ว', [f.path]))));
      return;
    }
    if (!await FileActions.confirmDiscard(context, c)) return;
    if (!mounted) return;
    final ok = await FileActions.openPath(context, c, f.path);
    // เปิดไม่ได้ (ไฟล์เสีย): คงรายการไว้ให้ผู้ใช้เห็นข้อความแจ้งเตือน ไม่ลบเอง
    if (!ok || !mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final recent = settings.recentFiles;
    return Row(key: const ValueKey('start-page'), children: [
      _Sidebar(onNew: _newProjectDialog, onOpen: () => FileActions.open(context, _er)),
      Expanded(
        child: ColoredBox(
          color: C.bg,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 36, 40, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1060),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('สวัสดี ออกแบบอะไรดีวันนี้'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 28),
                  _section(tr('สร้างใหม่')),
                  _QuickCreate(onBlank: _newProjectDialog, onType: (t) => _create([t])),
                  const SizedBox(height: 32),
                  _section(tr('ล่าสุด')),
                  if (recent.isEmpty)
                    _EmptyRecent(onOpen: () => FileActions.open(context, _er))
                  else
                    Wrap(spacing: 16, runSpacing: 16, children: [
                      for (final f in recent)
                        _RecentCard(
                          key: ValueKey('recent-${recentKey(f.path)}'),
                          file: f,
                          onOpen: () => _openRecent(f),
                          onPin: () => settings.toggleRecentPin(f.path),
                          onRemove: () => settings.removeRecent(f.path),
                        ),
                    ]),
                  const SizedBox(height: 32),
                  _section(tr('เริ่มจากจุดเริ่มต้นสำเร็จรูป')),
                  Wrap(spacing: 14, runSpacing: 14, children: [
                    for (final t in const [ProjectTemplate.analysis, ProjectTemplate.appDesign, ProjectTemplate.full])
                      _TemplateCard(template: t, onTap: () => _create(t.extraDocs)),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.onNew, required this.onOpen});
  final VoidCallback onNew, onOpen;

  @override
  Widget build(BuildContext context) {
    const ink = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.7);
    return Container(
      width: 232,
      color: C.tableHead,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Text(kAppName, style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        FilledButton(
          key: const ValueKey('start-new'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40), backgroundColor: C.primary, foregroundColor: C.palette.surface),
          onPressed: onNew,
          child: Text(tr('+ โปรเจกต์ใหม่')),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('start-open'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: ink, side: BorderSide(color: muted)),
          onPressed: onOpen,
          child: Text(tr('เปิดไฟล์...')),
        ),
        const Spacer(),
        Padding(padding: const EdgeInsets.all(6), child: Text(appVersionLabel, style: TextStyle(color: muted, fontSize: 12))),
      ]),
    );
  }
}

class _QuickCreate extends StatelessWidget {
  const _QuickCreate({required this.onBlank, required this.onType});
  final VoidCallback onBlank;
  final void Function(DocType) onType;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 12, runSpacing: 12, children: [
      _Tile(
        key: const ValueKey('start-quick-blank'),
        label: tr('โปรเจกต์ว่าง'),
        color: C.tableHead,
        icon: Icons.add_rounded,
        onTap: onBlank,
      ),
      for (final t in DocType.values)
        _Tile(
          key: ValueKey('start-quick-${t.name}'),
          label: _docLabel(t),
          color: C.doc(t).main,
          icon: docTypeIcon(t),
          onTap: () => onType(t),
        ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.color, required this.icon, required this.onTap});
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 140,
        child: Material(
          color: C.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: C.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 14),
              child: Column(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 10),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
          ),
        ),
      );
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({super.key, required this.file, required this.onOpen, required this.onPin, required this.onRemove});
  final RecentFile file;
  final VoidCallback onOpen, onPin, onRemove;

  @override
  Widget build(BuildContext context) {
    final types = [for (final n in file.docTypes) DocType.values.where((t) => t.name == n).firstOrNull].whereType<DocType>();
    return SizedBox(
      width: 240,
      child: Material(
        color: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: C.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                InkResponse(
                  key: ValueKey('recent-pin-${recentKey(file.path)}'),
                  radius: 16,
                  onTap: onPin,
                  child: Tooltip(
                    message: file.pinned ? tr('เลิกปักหมุด') : tr('ปักหมุด'),
                    child: Icon(file.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 16, color: file.pinned ? C.primary : C.muted),
                  ),
                ),
                const SizedBox(width: 6),
                InkResponse(
                  key: ValueKey('recent-remove-${recentKey(file.path)}'),
                  radius: 16,
                  onTap: onRemove,
                  child: Tooltip(message: tr('เอาออกจากรายการ'), child: Icon(Icons.close_rounded, size: 16, color: C.muted)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                '${tr('{0} เอกสาร', [file.docCount])} · ${relativeTimeLabel(file.openedAt, clock.now())}',
                style: TextStyle(fontSize: 12, color: C.muted),
              ),
              const SizedBox(height: 8),
              Row(children: [for (final t in types) Padding(padding: const EdgeInsets.only(right: 5), child: DocTypeDot(t, size: 9))]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('recent-empty'),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          border: Border.all(color: C.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(Icons.folder_open_outlined, color: C.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(tr('ยังไม่มีไฟล์ล่าสุด — เปิดหรือบันทึกโปรเจกต์แล้วจะมาอยู่ที่นี่'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: onOpen, child: Text(tr('เปิดไฟล์...'))),
        ]),
      );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});
  final ProjectTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 240,
        child: Material(
          color: C.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: C.border)),
          child: InkWell(
            key: ValueKey('start-template-${template.name}'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(templateName(template), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(templateDesc(template), style: TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ),
        ),
      );
}
