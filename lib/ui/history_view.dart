import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/diff/schema_diff.dart';
import '../core/diff/visual_diff.dart';
import '../core/l10n/l10n.dart';
import '../core/models/project.dart';
import '../core/models/workspace.dart';
import '../core/storage/history_store.dart';
import '../state/version_history.dart';
import '../state/workspace_controller.dart';
import 'migration_dialog.dart';
import 'start_page.dart' show relativeTimeLabel;
import 'theme.dart';

/// เวลาแบบ "เมื่อวาน 16:10"
String versionTimeLabel(DateTime t, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final rel = relativeTimeLabel(t, now);
  return rel.contains('-') ? '$rel ${two(t.hour)}:${two(t.minute)}' : '$rel · ${two(t.hour)}:${two(t.minute)}';
}

/// ชื่อที่แสดงของรายการประวัติ
String versionTitle(VersionEntry e) {
  if (e.named) return e.info.label.isEmpty ? 'v${e.number}' : 'v${e.number} · ${e.info.label}';
  return switch (e.info.kind) {
    SnapshotKind.save => tr('บันทึกไฟล์'),
    SnapshotKind.beforeRestore => e.info.label.isEmpty ? tr('ก่อนย้อนกลับ') : e.info.label,
    SnapshotKind.discarded => tr('งานที่ไม่ได้บันทึก (ก่อนทิ้ง)'),
    SnapshotKind.external => tr('ก่อนไฟล์ถูกแก้จากภายนอก'),
    SnapshotKind.manual => e.info.label,
  };
}

/// หน้าประวัติเวอร์ชันและ Diff (Artboard `History`): เส้นเวลา | ภาพ diff ของ ER | รายการความเปลี่ยนแปลง + migration / ย้อนกลับ
/// แสดงแทนแคนวาสขณะ [WorkspaceController.page] == [WorkspacePage.history]
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  String? _selectedId;
  String? _erId;
  Workspace? _old;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final v = context.read<VersionHistory>();
      await v.refresh();
      if (!mounted) return;
      final first = v.named.isNotEmpty ? v.named.first : (v.entries.isEmpty ? null : v.entries.first);
      if (first != null) await _select(first.info.id);
    });
  }

  Future<void> _select(String id) async {
    setState(() {
      _selectedId = id;
      _loading = true;
    });
    final w = await context.read<VersionHistory>().load(id);
    if (!mounted || _selectedId != id) return;
    setState(() {
      _old = w;
      _loading = false;
    });
  }

  Future<void> _saveVersion() async {
    final v = context.read<VersionHistory>();
    final label = await showDialog<String>(context: context, builder: (_) => _NameDialog(suggested: tr('เวอร์ชัน {0}', [v.named.length + 1])));
    if (label == null) return;
    final e = await v.saveVersion(label);
    if (e != null && mounted) await _select(e.info.id);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final v = context.watch<VersionHistory>();
    final ers = w.workspace.documentsOf(DocType.er).toList();
    final erId = ers.any((d) => d.id == _erId) ? _erId! : w.currentEr.docId;
    final cur = w.workspace.documentById(erId)!.er!;
    final old = _old;
    final oldEr = old == null ? null : (old.documentById(erId)?.er ?? Project(name: cur.name));
    VersionEntry? entry;
    for (final e in v.entries) {
      if (e.info.id == _selectedId) entry = e;
    }

    final timeline = _Timeline(
      versions: v,
      dirty: w.dirty,
      selectedId: _selectedId,
      onSelect: _select,
      onSaveVersion: v.enabled ? _saveVersion : null,
    );
    final Widget main;
    if (!v.enabled) {
      main = _Message(tr('ไม่มีที่เก็บประวัติเวอร์ชันในเครื่องนี้ (หาโฟลเดอร์ข้อมูลของแอปไม่พบ)'));
    } else if (v.entries.isEmpty) {
      main = _Message(tr('ยังไม่มีเวอร์ชัน — กด "+ บันทึกเวอร์ชันนี้" หรือบันทึกไฟล์ แล้วจะเทียบความต่างได้ที่นี่'));
    } else if (oldEr == null || entry == null) {
      main = _loading ? const Center(child: CircularProgressIndicator()) : _Message(tr('เลือกเวอร์ชันทางซ้ายเพื่อเทียบกับปัจจุบัน'));
    } else {
      final diff = diffProjects(oldEr, cur);
      final lines = [...diff.summary(oldEr, cur), ...documentChanges(old!, w.workspace)];
      main = _Compare(
        entry: entry,
        ers: ers,
        erId: erId,
        onEr: (id) => setState(() => _erId = id),
        tables: visualDiff(oldEr, cur, diff),
        lines: lines,
        oldEr: oldEr,
        cur: cur,
      );
    }

    return Container(
      key: const ValueKey('history-view'),
      color: C.bg,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 270, child: timeline),
        Expanded(child: main),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, key: const ValueKey('history-message'), textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
        ),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.versions, required this.dirty, required this.selectedId, required this.onSelect, required this.onSaveVersion});
  final VersionHistory versions;
  final bool dirty;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback? onSaveVersion;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    Widget item(VersionEntry e) {
      final on = e.info.id == selectedId;
      return Material(
        color: on ? C.primaryTint : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('history-item-${e.info.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelect(e.info.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(versionTitle(e),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: e.named ? FontWeight.w600 : FontWeight.w400, color: on ? C.primaryDark : C.text)),
              Text(
                [versionTimeLabel(e.info.savedAt, now), if (on) tr('เทียบกับปัจจุบัน')].join(' · '),
                style: TextStyle(fontSize: 11.5, color: C.muted),
              ),
            ]),
          ),
        ),
      );
    }

    return Material(
      color: C.surface,
      shape: Border(right: BorderSide(color: C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: FilledButton(
            key: const ValueKey('history-save-version'),
            onPressed: onSaveVersion,
            child: Text(tr('+ บันทึกเวอร์ชันนี้')),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(tr('เวอร์ชัน'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                Icon(Icons.circle, size: 8, color: dirty ? C.warnText : C.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(dirty ? tr('ปัจจุบัน (ยังไม่บันทึก)') : tr('ปัจจุบัน'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: C.text)),
                ),
              ]),
            ),
            for (final e in versions.named) item(e),
            if (versions.automatic.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
                child: Text(tr('บันทึกอัตโนมัติ · {0}', [versions.automatic.length]),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted)),
              ),
              for (final e in versions.automatic) item(e),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Compare extends StatelessWidget {
  const _Compare({
    required this.entry,
    required this.ers,
    required this.erId,
    required this.onEr,
    required this.tables,
    required this.lines,
    required this.oldEr,
    required this.cur,
  });
  final VersionEntry entry;
  final List<ProjectDocument> ers;
  final String erId;
  final ValueChanged<String> onEr;
  final List<VisualTable> tables;
  final List<ChangeLine> lines;
  final Project oldEr, cur;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final erName = w.workspace.documentById(erId)?.name ?? '';
    final title = entry.named ? 'v${entry.number}' : versionTitle(entry);
    final destructive = lines.where((l) => l.destructive).length;
    final changedTables = tables.where((t) => t.mark != DiffMark.same).length;

    final diffArea = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
          Icon(Icons.arrow_forward_rounded, size: 16, color: C.muted),
          Text(tr('ปัจจุบัน'), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
          if (ers.length > 1)
            DropdownButton<String>(
              key: const ValueKey('history-er'),
              value: erId,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [for (final d in ers) DropdownMenuItem(value: d.id, child: Text('ER · ${d.name}', style: const TextStyle(fontSize: 13)))],
              onChanged: (v) => v == null ? null : onEr(v),
            )
          else
            Text('· ER $erName', style: TextStyle(color: C.muted)),
          for (final m in [DiffMark.added, DiffMark.changed, DiffMark.dropped]) _Legend(m),
        ]),
      ),
      Expanded(
        child: tables.isEmpty
            ? _Message(tr('ER นี้ยังไม่มีตาราง'))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Wrap(spacing: 14, runSpacing: 14, children: [
                  for (final t in tables) _TableCard(t),
                ]),
              ),
      ),
      if (changedTables == 0 && lines.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(tr('ไม่มีความต่างจากเวอร์ชันนี้'), key: const ValueKey('history-same'), style: TextStyle(color: C.muted)),
        ),
    ]);

    final changes = Material(
      color: C.surface,
      shape: Border(left: BorderSide(color: C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(tr('ความเปลี่ยนแปลง · {0}', [lines.length]),
              key: const ValueKey('history-change-count'), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _KindChip(l.kind),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.text, style: TextStyle(fontSize: 12.5, color: C.text))),
                ]),
              ),
          ]),
        ),
        if (destructive > 0)
          Container(
            key: const ValueKey('history-destructive'),
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.dangerBg, borderRadius: BorderRadius.circular(8)),
            child: Text(tr('การลบ/เปลี่ยนชนิด {0} รายการจะทำให้ข้อมูลหายถ้ารันบนฐานข้อมูลจริง', [destructive]),
                style: TextStyle(fontSize: 12, color: C.dangerText)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton(
              key: const ValueKey('history-migration'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => MigrationDialog(old: oldEr, neu: cur, oldLabel: '$title · ER $erName'),
              ),
              child: Text(tr('สร้าง migration จากความต่างนี้')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('history-restore'),
              onPressed: () => restoreErToVersion(context, erId: erId, version: oldEr, title: title),
              child: Text(tr('ย้อน ER นี้กลับไปเวอร์ชัน {0}', [title])),
            ),
          ]),
        ),
      ]),
    );

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 760) {
        return Column(children: [Expanded(flex: 3, child: diffArea), Expanded(flex: 2, child: changes)]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: diffArea),
        SizedBox(width: 320, child: changes),
      ]);
    });
  }
}

/// ย้อนเนื้อหา ER [erId] กลับไปเป็น [version] หลังผู้ใช้ยืนยัน — เก็บสำเนาก่อนย้อนในประวัติ แล้วแทนเนื้อหาแบบ undo ได้ (Ctrl+Z ในแท็บ ER)
Future<void> restoreErToVersion(BuildContext context, {required String erId, required Project version, required String title}) async {
  final w = context.read<WorkspaceController>();
  final v = context.read<VersionHistory>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('ย้อน ER กลับไปเวอร์ชัน {0}?', [title])),
      content: Text(tr('ตาราง/ความสัมพันธ์ของ ER นี้จะกลับเป็นเหมือนเวอร์ชันนั้น (เอกสารอื่นไม่เปลี่ยน) — กด Ctrl+Z ในแท็บ ER เพื่อยกเลิกได้ และสำเนาก่อนย้อนจะอยู่ในประวัติ')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
        FilledButton(key: const ValueKey('history-restore-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ย้อนกลับ@@restore'))),
      ],
    ),
  );
  if (ok != true) return;
  final er = w.erController(erId);
  if (er == null) return;
  await v.beforeRestore(tr('ก่อนย้อน ER {0} ไป {1}', [w.workspace.documentById(erId)?.name ?? '', title]));
  er.replaceContent(version);
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('ย้อนแล้ว — กด Ctrl+Z ในแท็บ ER เพื่อยกเลิก'))));
  }
}

(Color, Color) _markColors(DiffMark m) => switch (m) {
      DiffMark.added => (C.primaryTint, C.primaryDark),
      DiffMark.changed => (C.warnBg, C.warnText),
      DiffMark.dropped => (C.dangerBg, C.dangerText),
      DiffMark.same => (C.surface, C.text),
    };

String _markLabel(DiffMark m) => switch (m) {
      DiffMark.added => tr('เพิ่ม@@diff'),
      DiffMark.changed => tr('แก้'),
      DiffMark.dropped => tr('ลบ@@diff'),
      DiffMark.same => '',
    };

class _Legend extends StatelessWidget {
  const _Legend(this.mark);
  final DiffMark mark;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _markColors(mark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(_markLabel(mark), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip(this.kind);
  final ChangeKind kind;

  @override
  Widget build(BuildContext context) => _Legend(switch (kind) {
        ChangeKind.add => DiffMark.added,
        ChangeKind.change => DiffMark.changed,
        ChangeKind.drop => DiffMark.dropped,
      });
}

class _TableCard extends StatelessWidget {
  const _TableCard(this.t);
  final VisualTable t;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _markColors(t.mark);
    final border = t.mark == DiffMark.same ? C.border : fg;
    return Container(
      key: ValueKey('history-table-${t.name}'),
      width: 220,
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: t.mark == DiffMark.same ? 1 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: t.mark == DiffMark.same ? C.tableHead : bg,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            [if (t.mark == DiffMark.added) '+', t.name, if (t.oldName != null) '(${tr('เดิมชื่อ {0}', [t.oldName!])})'].join(' '),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: t.mark == DiffMark.same ? C.text : fg,
              decoration: t.mark == DiffMark.dropped ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        for (final c in t.columns)
          Container(
            color: c.mark == DiffMark.same || t.mark != DiffMark.changed ? null : _markColors(c.mark).$1,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text(
              [if (c.mark == DiffMark.added && t.mark != DiffMark.added) '+', c.name, ?c.detail].join(' '),
              style: TextStyle(
                fontSize: 12,
                color: c.mark == DiffMark.same ? C.text : _markColors(c.mark).$2,
                decoration: c.mark == DiffMark.dropped ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
      ]),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.suggested});
  final String suggested;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctl = TextEditingController(text: widget.suggested);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('บันทึกเวอร์ชันนี้')),
        content: SizedBox(
          width: 360,
          child: TextField(
            key: const ValueKey('history-version-name'),
            controller: _ctl,
            autofocus: true,
            decoration: InputDecoration(labelText: tr('ชื่อเวอร์ชัน (เช่น ส่งให้ลูกค้าดู)')),
            onSubmitted: (_) => Navigator.pop(context, _ctl.text),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
          FilledButton(
            key: const ValueKey('history-version-ok'),
            onPressed: () => Navigator.pop(context, _ctl.text),
            child: Text(tr('บันทึก')),
          ),
        ],
      );
}
