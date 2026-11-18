import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/review_note.dart';
import '../core/models/review_note_refs.dart';
import '../core/models/workspace.dart';
import '../state/doc_controller.dart';
import '../state/workspace_controller.dart';
import 'canvas/canvas_controller.dart';
import 'document_actions.dart' show DocTypeDot;
import 'palette/command_palette.dart' show gotoDfd, gotoFlowchart, gotoScreenFlow, gotoWireframe;
import 'start_page.dart' show relativeTimeLabel;
import 'theme.dart';

/// ตัวกรองรายการโน้ต
enum NoteFilter { all, todo, done, question }

bool noteMatches(ReviewNote n, NoteFilter f) => switch (f) {
      NoteFilter.all => true,
      NoteFilter.todo => n.kind == NoteKind.todo && !n.done,
      NoteFilter.done => n.done,
      NoteFilter.question => n.kind == NoteKind.question && !n.done,
    };

/// เลขหมุดของโน้ต [id] ในเอกสาร [doc] (นับเฉพาะที่ปักหมุด ตามลำดับที่เพิ่ม เริ่ม 1) ; ไม่ได้ปัก = null
int? notePinNumber(ProjectDocument doc, String id) {
  var i = 0;
  for (final n in doc.reviewNotes) {
    if (!n.pinned) continue;
    i++;
    if (n.id == id) return i;
  }
  return null;
}

/// จำนวนงานที่ยังค้าง (ต้องทำ/คำถามที่ยังไม่เสร็จ) ทั้งโปรเจกต์
int openNoteCount(Workspace w) => w.documents.fold(0, (a, d) => a + d.reviewNotes.where((n) => n.open).length);

/// ไปยังเอกสาร [docId] และเลือกวัตถุ [elementId] (ถ้ามี)
void gotoNoteTarget(BuildContext context, String docId, {String? elementId}) {
  final w = context.read<WorkspaceController>();
  final doc = w.workspace.documentById(docId);
  if (doc == null) return;
  switch (doc.type) {
    case DocType.dfd:
      gotoDfd(context, docId, node: elementId);
    case DocType.flowchart:
      gotoFlowchart(context, docId, node: elementId);
    case DocType.wireframe:
      gotoWireframe(context, docId, component: elementId);
    case DocType.screenflow:
      gotoScreenFlow(context, docId, node: elementId);
    case DocType.er:
      if (!w.openDocument(docId)) return;
      final er = w.erController(docId);
      final t = elementId == null ? null : er?.project.tableById(elementId);
      if (er != null && t != null) {
        er.selectTable(t.id);
        context.read<CanvasController>().focusTable(t);
      }
    case null:
      return;
  }
}

/// แผงโน้ตและงานค้าง (Artboard `Review`): แท็บ "หน้านี้" / "ทั้งโปรเจกต์" · ตัวกรอง · รายการ · ช่องเพิ่มโน้ต
/// แสดงแทนแผงขวาของเอกสารเมื่อ [WorkspaceController.notesPanel] เปิดอยู่
class NotesPanel extends StatefulWidget {
  const NotesPanel({super.key});

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  bool _all = false;
  NoteFilter _filter = NoteFilter.all;
  NoteKind _kind = NoteKind.todo;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add(DocController c) {
    if (c.addReviewNote(_text.text, kind: _kind) != null) {
      _text.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final c = w.controllerOf(w.activeId);
    if (c == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final here = [for (final n in c.reviewNotes) (doc: c.doc, note: n)];
        final all = [
          for (final d in w.documents)
            if (d.type != null)
              for (final n in d.reviewNotes) (doc: d, note: n),
        ];
        final src = _all ? all : here;
        int count(NoteFilter f) => src.where((x) => noteMatches(x.note, f)).length;
        final shown = [for (final x in src) if (noteMatches(x.note, _filter)) x];

        return Container(
          key: const ValueKey('notes-panel'),
          decoration: BoxDecoration(color: C.surface, border: Border(left: BorderSide(color: C.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 0),
              child: Row(children: [
                Expanded(
                  child: Text(tr('โน้ตและงานค้าง'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: C.text)),
                ),
                IconButton(
                  key: const ValueKey('notes-close'),
                  tooltip: tr('ปิดแผงโน้ต'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () => w.showNotesPanel(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: SegmentedButton<bool>(
                key: const ValueKey('notes-scope'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                segments: [
                  ButtonSegment(value: false, label: Text(tr('หน้านี้ · {0}', [here.length]), style: const TextStyle(fontSize: 12))),
                  ButtonSegment(value: true, label: Text(tr('ทั้งโปรเจกต์ · {0}', [all.length]), style: const TextStyle(fontSize: 12))),
                ],
                selected: {_all},
                onSelectionChanged: (s) => setState(() => _all = s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in NoteFilter.values)
                  ChoiceChip(
                    key: ValueKey('notes-filter-${f.name}'),
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    label: Text(
                      switch (f) {
                        NoteFilter.all => tr('ทั้งหมด'),
                        NoteFilter.todo => tr('ต้องทำ {0}', [count(f)]),
                        NoteFilter.done => tr('เสร็จ {0}', [count(f)]),
                        NoteFilter.question => tr('คำถาม {0}', [count(f)]),
                      },
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            Divider(height: 1, color: C.border),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          src.isEmpty ? tr('ยังไม่มีโน้ต — พิมพ์ด้านล่างเพื่อเพิ่ม') : tr('ไม่มีโน้ตตามตัวกรองนี้'),
                          key: const ValueKey('notes-empty'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: C.muted),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: C.borderSoft),
                      itemBuilder: (context, i) => _NoteTile(doc: shown[i].doc, note: shown[i].note, showDoc: _all),
                    ),
            ),
            Divider(height: 1, color: C.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  key: const ValueKey('notes-new'),
                  controller: _text,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: tr('โน้ตใหม่ของ {0}', [c.doc.name]),
                    hintText: tr('ใช้ # อ้างถึงตารางหรือเอกสาร'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: SegmentedButton<NoteKind>(
                      key: const ValueKey('notes-kind'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      segments: [
                        for (final k in NoteKind.values)
                          ButtonSegment(value: k, label: Text(noteKindLabel(k), style: const TextStyle(fontSize: 11.5))),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const ValueKey('notes-add-pin'),
                    tooltip: tr('เพิ่มแล้วปักหมุดบนแคนวาส (คลิกตำแหน่งบนแคนวาส)'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _text.text.trim().isEmpty
                        ? null
                        : () {
                            w.requestPin(text: _text.text, kind: _kind);
                            _text.clear();
                            setState(() {});
                          },
                    icon: const Icon(Icons.push_pin_outlined, size: 18),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    key: const ValueKey('notes-add'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 14)),
                    onPressed: _text.text.trim().isEmpty ? null : () => _add(c),
                    child: Text(tr('เพิ่ม'), style: const TextStyle(fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(tr('โน้ตเก็บในไฟล์ .nsln · ใช้งานออฟไลน์ได้ทั้งหมด'),
                    style: TextStyle(fontSize: 11, color: C.muted)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.doc, required this.note, required this.showDoc});
  final ProjectDocument doc;
  final ReviewNote note;
  final bool showDoc;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final c = w.controllerOf(doc.id)!;
    final pin = notePinNumber(doc, note.id);
    final anchor = noteAnchorLabel(doc, note.anchorId);
    final meta = [
      if (showDoc) doc.name,
      ?anchor,
      relativeTimeLabel(note.created, DateTime.now()),
    ].join(' · ');
    final checkable = note.kind != NoteKind.memo;
    final kindColor = switch (note.kind) {
      NoteKind.todo => C.primary,
      NoteKind.question => C.warnText,
      NoteKind.memo => C.muted,
    };

    return InkWell(
      key: ValueKey('note-${note.id}'),
      onTap: () => gotoNoteTarget(context, doc.id, elementId: note.anchorId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 2, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 32,
            child: checkable
                ? Checkbox(
                    key: ValueKey('note-done-${note.id}'),
                    value: note.done,
                    visualDensity: VisualDensity.compact,
                    onChanged: (_) => c.toggleReviewNoteDone(note.id),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(Icons.notes_rounded, size: 16, color: C.muted),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (pin != null) ...[
                    Container(
                      key: ValueKey('note-num-${note.id}'),
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: kindColor, shape: BoxShape.circle),
                      child: Text('$pin', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: C.surface)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (showDoc) ...[DocTypeDot(doc.type, size: 7), const SizedBox(width: 5)],
                  Text(noteKindLabel(note.kind), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kindColor)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.muted)),
                  ),
                ]),
                const SizedBox(height: 3),
                NoteText(note: note, docId: doc.id),
              ]),
            ),
          ),
          PopupMenuButton<String>(
            key: ValueKey('note-menu-${note.id}'),
            tooltip: tr('ตัวเลือกโน้ต'),
            iconSize: 16,
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert_rounded, size: 16, color: C.muted),
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  final t = await _editText(context, note.text);
                  if (t != null) c.updateReviewNote(note.id, text: t);
                case 'unpin':
                  c.moveReviewNote(note.id, null, null);
                case 'pin':
                  w.requestPin(noteId: note.id);
                case 'delete':
                  c.deleteReviewNote(note.id);
                default:
                  final k = NoteKind.values.asNameMap()[v];
                  if (k != null) c.updateReviewNote(note.id, kind: k);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', height: 34, child: Text(tr('แก้ข้อความ…'), style: const TextStyle(fontSize: 13))),
              for (final k in NoteKind.values)
                if (k != note.kind)
                  PopupMenuItem(
                    value: k.name,
                    height: 34,
                    child: Text(tr('เปลี่ยนเป็น "{0}"', [noteKindLabel(k)]), style: const TextStyle(fontSize: 13)),
                  ),
              if (!note.pinned && w.activeId == doc.id)
                PopupMenuItem(value: 'pin', height: 34, child: Text(tr('ปักหมุดบนแคนวาส…'), style: const TextStyle(fontSize: 13))),
              if (note.pinned)
                PopupMenuItem(value: 'unpin', height: 34, child: Text(tr('ถอดหมุดออกจากแคนวาส'), style: const TextStyle(fontSize: 13))),
              PopupMenuItem(
                value: 'delete',
                height: 34,
                child: Text(tr('ลบโน้ต'), style: TextStyle(fontSize: 13, color: C.danger)),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

Future<String?> _editText(BuildContext context, String initial) =>
    showDialog<String>(context: context, builder: (_) => _EditNoteDialog(initial: initial));

/// กล่องแก้ข้อความโน้ต — ถือ controller เอง (ทิ้งตอน State ถูกทิ้ง หลังแอนิเมชันปิดจบ)
class _EditNoteDialog extends StatefulWidget {
  const _EditNoteDialog({required this.initial});
  final String initial;

  @override
  State<_EditNoteDialog> createState() => _EditNoteDialogState();
}

class _EditNoteDialogState extends State<_EditNoteDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('แก้ข้อความโน้ต')),
        content: SizedBox(
          width: 360,
          child: TextField(key: const ValueKey('note-edit-field'), controller: _ctl, autofocus: true, minLines: 2, maxLines: 6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
          FilledButton(
            key: const ValueKey('note-edit-ok'),
            onPressed: () => Navigator.pop(context, _ctl.text.trim().isEmpty ? null : _ctl.text),
            child: Text(tr('บันทึก')),
          ),
        ],
      );
}

/// ข้อความโน้ต: คำอ้างอิง `#ชื่อ` ที่หาปลายทางได้เป็นลิงก์ (กด = เปิดเอกสาร/ตารางนั้น) ; ที่หาไม่ได้แสดงเป็นตัวเอียงสีจาง
class NoteText extends StatefulWidget {
  const NoteText({super.key, required this.note, required this.docId});
  final ReviewNote note;
  final String docId;

  @override
  State<NoteText> createState() => _NoteTextState();
}

class _NoteTextState extends State<NoteText> {
  final List<TapGestureRecognizer> _taps = [];

  void _clearTaps() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clearTaps();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearTaps();
    final note = widget.note;
    final w = context.read<WorkspaceController>();
    final base = TextStyle(
      fontSize: 13,
      color: note.done ? C.muted : C.text,
      decoration: note.done ? TextDecoration.lineThrough : null,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in kNoteRefPattern.allMatches(note.text)) {
      if (m.start > last) spans.add(TextSpan(text: note.text.substring(last, m.start)));
      final target = resolveNoteRef(w.workspace, m.group(1)!.replaceAll(RegExp(r'[.\-/]+$'), ''), preferDocId: widget.docId);
      TapGestureRecognizer? tap;
      if (target != null) {
        tap = TapGestureRecognizer()..onTap = () => gotoNoteTarget(context, target.docId, elementId: target.tableId);
        _taps.add(tap);
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: target == null
            ? TextStyle(fontStyle: FontStyle.italic, color: C.muted)
            : TextStyle(color: C.primary, fontWeight: FontWeight.w600),
        recognizer: tap,
      ));
      last = m.end;
    }
    if (last < note.text.length) spans.add(TextSpan(text: note.text.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans), key: ValueKey('note-text-${note.id}'));
  }
}
