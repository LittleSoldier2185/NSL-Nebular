import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/export/dictionary_model.dart';
import '../core/export/html_doc_export.dart';
import '../core/export/markdown_export.dart';
import '../core/l10n/l10n.dart';
import '../core/models/review_note_refs.dart';
import '../core/models/table_model.dart';
import '../core/models/workspace.dart';
import '../state/workspace_controller.dart';
import 'document_actions.dart' show DocTypeDot;
import 'file_actions.dart';
import 'notes_panel.dart' show gotoNoteTarget;
import 'theme.dart';

/// รูปแบบไฟล์ที่ส่งออกจากหน้าพจนานุกรม (PDF/Word ยังไม่รองรับ — ต้องเพิ่มไลบรารี ; ดู progress.md Phase 6)
enum DictFormat { html, markdown }

/// เนื้อหาไฟล์พจนานุกรมที่จะส่งออก ตามตัวเลือก (ภาษา [lang] ใช้ชั่วคราวระหว่างสร้าง แล้วคืนภาษาเดิม)
String buildDictionaryExport(Workspace w, {required DictFormat format, bool diagrams = true, bool notes = true, Lang? lang}) {
  final old = currentLang;
  if (lang != null) currentLang = lang;
  try {
    return switch (format) {
      DictFormat.html => exportHtmlDocument(w, includeDiagrams: diagrams, includeNotes: notes),
      DictFormat.markdown => exportWorkspaceDictionary(w, includeNotes: notes),
    };
  } finally {
    currentLang = old;
  }
}

/// หน้าพจนานุกรมข้อมูล (Artboard `Dictionary`): สารบัญ | หน้ากระดาษ (แก้คำอธิบายได้ในที่) | ส่งออก
/// แสดงแทนแคนวาสขณะ [WorkspaceController.dictionaryView]
class DictionaryView extends StatefulWidget {
  const DictionaryView({super.key});

  @override
  State<DictionaryView> createState() => _DictionaryViewState();
}

class _DictionaryViewState extends State<DictionaryView> {
  final Map<String, GlobalKey> _tableKeys = {};
  final Map<String, FocusNode> _fieldFocus = {};
  DictSlot? _cursor;

  GlobalKey _keyOf(String docId, String tableId) => _tableKeys.putIfAbsent('$docId/$tableId', GlobalKey.new);

  FocusNode _focusOf(DictSlot s) => _fieldFocus.putIfAbsent('${s.docId}/${s.tableId}/${s.columnId ?? ''}', FocusNode.new);

  @override
  void dispose() {
    for (final f in _fieldFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _scrollTo(String docId, String tableId) {
    final ctx = _keyOf(docId, tableId).currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.05);
  }

  void _gotoNextMissing(Workspace w) {
    final s = nextMissing(w, _cursor);
    if (s == null) return;
    _cursor = s;
    _scrollTo(s.docId, s.tableId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusOf(s).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final ers = w.workspace.documentsOf(DocType.er).toList();
    final missing = missingDescriptions(w.workspace).length;
    final total = descriptionSlotCount(w.workspace);

    final toc = _Toc(
      ers: ers,
      missing: missing,
      onTable: _scrollTo,
      onNextMissing: missing == 0 ? null : () => _gotoNextMissing(w.workspace),
    );
    final paper = _Paper(ers: ers, total: total, missing: missing, keyOf: _keyOf, focusOf: _focusOf);
    const exportPanel = _ExportPanel();

    return Container(
      key: const ValueKey('dictionary-view'),
      color: C.bg,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 1100;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 220, child: toc),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: paper),
                  ),
                ),
                const SizedBox(width: 270, child: exportPanel),
              ],
            );
          }
          // แคบ: สารบัญซ่อน (ใช้ปุ่มไปช่องถัดไปในหัวกระดาษแทน) แผงส่งออกต่อท้ายกระดาษ
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (missing > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('dict-next-missing-narrow'),
                      onPressed: () => _gotoNextMissing(w.workspace),
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: Text(tr('{0} ช่องยังไม่มีคำอธิบาย · ไปช่องถัดไป', [missing])),
                    ),
                  ),
                Center(child: paper),
                const SizedBox(height: 16),
                exportPanel,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Toc extends StatelessWidget {
  const _Toc({required this.ers, required this.missing, required this.onTable, required this.onNextMissing});
  final List<ProjectDocument> ers;
  final int missing;
  final void Function(String docId, String tableId) onTable;
  final VoidCallback? onNextMissing;

  @override
  Widget build(BuildContext context) {
    final multi = ers.length > 1;
    return Material(
      color: C.surface,
      shape: Border(right: BorderSide(color: C.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              tr('สารบัญ'),
              style: TextStyle(fontWeight: FontWeight.w700, color: C.text),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final d in ers) ...[
                  if (multi)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                      child: Row(
                        children: [
                          DocTypeDot(d.type, size: 7),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final t in d.er!.tables)
                    InkWell(
                      key: ValueKey('dict-toc-${d.id}-${t.id}'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => onTable(d.id, t.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: C.text),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Container(
            key: const ValueKey('dict-missing'),
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: missing > 0 ? C.warnBg : C.primaryTint, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  missing > 0 ? tr('{0} ช่องยังไม่มีคำอธิบาย', [missing]) : tr('ทุกตารางและคอลัมน์มีคำอธิบายแล้ว'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: missing > 0 ? C.warnText : C.primaryDark),
                ),
                if (onNextMissing != null) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    key: const ValueKey('dict-next-missing'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: onNextMissing,
                    child: Text(tr('ไปเติมทีละช่อง →'), style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({required this.ers, required this.total, required this.missing, required this.keyOf, required this.focusOf});
  final List<ProjectDocument> ers;
  final int total, missing;
  final GlobalKey Function(String docId, String tableId) keyOf;
  final FocusNode Function(DictSlot s) focusOf;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final name = w.workspace.name.trim().isEmpty ? tr('(ไม่มีชื่อ)') : w.workspace.name;
    final tables = ers.fold<int>(0, (a, d) => a + d.er!.tables.length);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Material(
        color: C.surface,
        elevation: 2,
        shadowColor: C.palette.shadow,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('พจนานุกรมข้อมูล'), style: TextStyle(fontSize: 12, color: C.muted, letterSpacing: 0.5)),
              Text(
                name,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: C.text),
              ),
              const SizedBox(height: 4),
              Text(
                tr('{0} ตาราง · กรอกคำอธิบายแล้ว {1} จาก {2} ช่อง', [tables, total - missing, total]),
                key: const ValueKey('dict-summary'),
                style: TextStyle(fontSize: 13, color: C.muted),
              ),
              if (tables == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(tr('ยังไม่มีตาราง'), style: TextStyle(color: C.muted)),
                ),
              for (final d in ers) ...[
                if (ers.length > 1 && d.er!.tables.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Text(
                      'ER: ${d.name}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.doc(DocType.er).ink),
                    ),
                  ),
                for (final t in d.er!.tables) _TableSection(key: keyOf(d.id, t.id), doc: d, table: t, focusOf: focusOf),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TableSection extends StatelessWidget {
  const _TableSection({super.key, required this.doc, required this.table, required this.focusOf});
  final ProjectDocument doc;
  final TableModel table;
  final FocusNode Function(DictSlot s) focusOf;

  @override
  Widget build(BuildContext context) {
    final w = context.read<WorkspaceController>();
    final er = w.erController(doc.id)!;
    final p = doc.er!;
    final refs = referencedBy(p, table.id);
    final used = [
      for (final (fromDoc, fromEl, _) in w.usagesOf(doc.id, table.id))
        if (w.workspace.documentById(fromDoc) case final src?)
          (doc: src, label: [src.name, ?noteAnchorLabel(src, fromEl)].join(' · '), el: fromEl),
    ];
    final head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.muted);
    final cell = TextStyle(fontSize: 13, color: C.text);

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            table.name,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.text),
          ),
          _CommentField(
            key: ValueKey('dict-t-${doc.id}-${table.id}'),
            value: table.comment,
            hint: tr('+ เพิ่มคำอธิบายตาราง'),
            focusNode: focusOf((docId: doc.id, tableId: table.id, columnId: null)),
            multiline: true,
            onCommit: (v) => er.setTableComment(table.id, v),
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1.6), 2: FixedColumnWidth(52), 3: FlexColumnWidth(4)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(horizontalInside: BorderSide(color: C.borderSoft)),
            children: [
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: C.border)),
                ),
                children: [
                  for (final h in [tr('คอลัมน์'), tr('ชนิด'), 'Null', tr('คำอธิบาย')])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(h, style: head),
                    ),
                ],
              ),
              for (final c in table.columns)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(c.name, style: cell.copyWith(fontWeight: FontWeight.w600)),
                          if (c.isPrimaryKey) _Badge('PK', C.pkBg, C.pkText),
                          if (fkTarget(p, table.id, c.id) != null) _Badge('FK', C.fkChip, C.text),
                        ],
                      ),
                    ),
                    Text(typeLabel(c), style: cell.copyWith(fontFamily: 'monospace', fontSize: 12)),
                    Text(c.notNull || c.isPrimaryKey ? tr('ไม่') : tr('ใช่'), style: cell),
                    _CommentField(
                      key: ValueKey('dict-c-${doc.id}-${table.id}-${c.id}'),
                      value: c.comment,
                      hint: fkTarget(p, table.id, c.id) == null
                          ? tr('+ เพิ่มคำอธิบาย')
                          : tr('+ เพิ่มคำอธิบาย (→ {0})', [fkTarget(p, table.id, c.id)!]),
                      focusNode: focusOf((docId: doc.id, tableId: table.id, columnId: c.id)),
                      onCommit: (v) => er.updateColumn(table.id, c.id, (x) => x.comment = v),
                    ),
                  ],
                ),
            ],
          ),
          if (refs.isNotEmpty || used.isNotEmpty) const SizedBox(height: 10),
          if (refs.isNotEmpty)
            _MetaRow(
              label: tr('ถูกอ้างถึงโดย'),
              child: Text(refs.join(' · '), style: cell.copyWith(fontSize: 12.5)),
            ),
          if (used.isNotEmpty)
            _MetaRow(
              label: tr('ใช้งานใน'),
              child: Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (final u in used)
                    InkWell(
                      onTap: () => gotoNoteTarget(context, u.doc.id, elementId: u.el),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DocTypeDot(u.doc.type, size: 7),
                          const SizedBox(width: 4),
                          // ชื่อยาว (เช่น ข้อความของชิ้นส่วน Wireframe) ตัดด้วย … แทนล้นแถว
                          Flexible(child: Text(u.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: cell.copyWith(fontSize: 12.5, color: C.primary))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.muted),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.bg, this.fg);
  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

/// ช่องคำอธิบายแบบแก้ในที่: ไม่มีกรอบ (ว่าง = ข้อความชวนเติม) ; บันทึกเมื่อกด Enter หรือออกจากช่อง (undo ขั้นเดียวต่อการแก้หนึ่งครั้ง)
class _CommentField extends StatefulWidget {
  const _CommentField({
    super.key,
    required this.value,
    required this.hint,
    required this.focusNode,
    required this.onCommit,
    this.multiline = false,
  });
  final String value;
  final String hint;
  final FocusNode focusNode;
  final ValueChanged<String> onCommit;
  final bool multiline;

  @override
  State<_CommentField> createState() => _CommentFieldState();
}

class _CommentFieldState extends State<_CommentField> {
  late final _ctl = TextEditingController(text: widget.value);

  /// ค่าที่บันทึกล่าสุด — Enter แล้วเสียโฟกัสในเฟรมเดียวกันต้องไม่บันทึกซ้ำ (ไม่งั้น undo สองครั้ง)
  late String _committed = widget.value;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_CommentField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    // ค่าเปลี่ยนจากที่อื่น (undo / แผงขวา) ขณะไม่ได้แก้อยู่ = แสดงค่าใหม่
    if (old.value != widget.value) _committed = widget.value;
    if (!widget.focusNode.hasFocus && _ctl.text != widget.value) _ctl.text = widget.value;
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _ctl.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!widget.focusNode.hasFocus) _commit();
  }

  void _commit() {
    final v = widget.multiline ? _ctl.text.trim() : _ctl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (v == _committed) return;
    _committed = v;
    widget.onCommit(v);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _ctl,
    focusNode: widget.focusNode,
    minLines: 1,
    maxLines: widget.multiline ? 4 : 2,
    style: TextStyle(fontSize: 13, color: C.text),
    textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done,
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      hintText: widget.hint,
      hintStyle: TextStyle(fontSize: 13, color: C.primary),
    ),
    onSubmitted: (_) => _commit(),
  );
}

class _ExportPanel extends StatefulWidget {
  const _ExportPanel();

  @override
  State<_ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<_ExportPanel> {
  DictFormat _format = DictFormat.html;
  bool _diagrams = true;
  bool _notes = true;
  Lang _lang = currentLang;

  Future<void> _export() async {
    final w = context.read<WorkspaceController>();
    final text = buildDictionaryExport(w.workspace, format: _format, diagrams: _diagrams, notes: _notes, lang: _lang);
    final ext = _format == DictFormat.html ? 'html' : 'md';
    await FileActions.saveText(context, text, '${FileActions.safeName(w.workspace.name)}-dictionary.$ext', tr('ส่งออกพจนานุกรมข้อมูล'));
  }

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.muted);
    return Material(
      key: const ValueKey('dict-export'),
      color: C.surface,
      shape: Border(left: BorderSide(color: C.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('ส่งออกเอกสาร'),
              style: TextStyle(fontWeight: FontWeight.w700, color: C.text),
            ),
            const SizedBox(height: 12),
            Text(tr('รูปแบบ'), style: small),
            const SizedBox(height: 6),
            SegmentedButton<DictFormat>(
              key: const ValueKey('dict-format'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: DictFormat.html, label: Text('HTML')),
                ButtonSegment(value: DictFormat.markdown, label: Text('Markdown')),
              ],
              selected: {_format},
              onSelectionChanged: (s) => setState(() => _format = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              tr('PDF / Word: เปิดไฟล์ HTML ในเบราว์เซอร์แล้วสั่งพิมพ์เป็น PDF หรือเปิดด้วย Word'),
              style: TextStyle(fontSize: 11, color: C.muted),
            ),
            const SizedBox(height: 14),
            Text(tr('ใส่ในเอกสาร'), style: small),
            CheckboxListTile(
              key: const ValueKey('dict-opt-diagrams'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _format == DictFormat.html && _diagrams,
              onChanged: _format == DictFormat.html ? (v) => setState(() => _diagrams = v ?? true) : null,
              title: Text(tr('แผนภาพ (HTML เท่านั้น)'), style: const TextStyle(fontSize: 13)),
            ),
            CheckboxListTile(
              key: const ValueKey('dict-opt-notes'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _notes,
              onChanged: (v) => setState(() => _notes = v ?? true),
              title: Text(tr('โน้ตและงานค้าง'), style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 8),
            Text(tr('ภาษา'), style: small),
            const SizedBox(height: 6),
            SegmentedButton<Lang>(
              key: const ValueKey('dict-lang'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: Lang.th, label: Text('ไทย')),
                ButtonSegment(value: Lang.en, label: Text('English')),
              ],
              selected: {_lang},
              onSelectionChanged: (s) => setState(() => _lang = s.first),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('dict-export-go'),
              onPressed: _export,
              child: Text(_format == DictFormat.html ? tr('ส่งออก HTML…') : tr('ส่งออก Markdown…')),
            ),
          ],
        ),
      ),
    );
  }
}
