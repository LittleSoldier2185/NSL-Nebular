import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/export/diagram_text_export.dart';
import '../../core/export/markdown_export.dart';
import '../../core/export/html_doc_export.dart';
import '../../core/export/sample_data.dart';
import '../../core/export/sql_export.dart';
import '../../core/models/project.dart';
import '../../core/models/workspace.dart';
import '../dictionary_view.dart' show buildDictionaryDocx;
import '../file_actions.dart';
import '../sql_view.dart';
import '../theme.dart';
import '../../core/l10n/l10n.dart';

enum TextExportKind { dictionary, mermaid, dbml, sample, html, word, sqlAll }

extension on TextExportKind {
  String get label => switch (this) {
        TextExportKind.dictionary => 'Data dictionary',
        TextExportKind.mermaid => 'Mermaid',
        TextExportKind.dbml => 'DBML',
        TextExportKind.sample => tr('ข้อมูลตัวอย่าง'),
        TextExportKind.html => 'HTML',
        TextExportKind.word => 'Word',
        TextExportKind.sqlAll => tr('SQL ทั้งโปรเจกต์'),
      };

  IconData get icon => switch (this) {
        TextExportKind.dictionary => Icons.menu_book_outlined,
        TextExportKind.mermaid => Icons.account_tree_outlined,
        TextExportKind.dbml => Icons.schema_outlined,
        TextExportKind.sample => Icons.dataset_outlined,
        TextExportKind.html => Icons.code_rounded,
        TextExportKind.word => Icons.description_outlined,
        TextExportKind.sqlAll => Icons.storage_rounded,
      };

  String get ext => switch (this) {
        TextExportKind.dictionary => '.md',
        TextExportKind.mermaid => '.mmd',
        TextExportKind.dbml => '.dbml',
        TextExportKind.sample => '.sql',
        TextExportKind.html => '.html',
        TextExportKind.word => '.docx',
        TextExportKind.sqlAll => '.sql',
      };

  /// ใช้ข้อมูลของ ER ที่เปิดอยู่ ER เดียว (ต่างจากแบบทั้งโปรเจกต์)
  bool get perEr => this == TextExportKind.mermaid || this == TextExportKind.dbml || this == TextExportKind.sample;

  String get hint => switch (this) {
        TextExportKind.dictionary => tr('เอกสาร Markdown อธิบายตาราง/คอลัมน์/ความสัมพันธ์ ใช้ส่งงานหรือแปะ README'),
        TextExportKind.mermaid => tr('แปะในบล็อก ```mermaid ของ GitHub / GitLab / Notion เพื่อแสดงแผนภาพ ER'),
        TextExportKind.dbml => tr('นำเข้า dbdiagram.io หรือเครื่องมือที่รองรับ DBML'),
        TextExportKind.sample => tr('INSERT ข้อมูลสุ่มไว้ทดสอบ ตามตัวเลือก dialect ปัจจุบัน (ตารางแม่ก่อนลูก, FK ถูกต้อง)'),
        TextExportKind.html => tr('เอกสาร HTML ไฟล์เดียวทั้งโปรเจกต์ (ภาพแผนภาพ ER/DFD ฝังในไฟล์ พิมพ์เป็น PDF ได้) — ตัวอย่างแสดงเฉพาะส่วนต้น'),
        TextExportKind.word => tr('ไฟล์ Word (.docx) ทั้งโปรเจกต์ พร้อมภาพแผนภาพ — ตัวอย่างแสดงเนื้อหาแบบข้อความ ส่วนภาพจะอยู่ในไฟล์ที่บันทึก'),
        TextExportKind.sqlAll => tr('SQL ของทุก ER รวมเป็นไฟล์เดียว แยกหัวคอมเมนต์ต่อ ER และใช้ dialect ของแต่ละ ER (ไม่รวมข้อมูลตั้งต้น)'),
      };
}

/// Export ข้อความ 4 แบบ: Data dictionary (Markdown) / Mermaid / DBML / INSERT ข้อมูลตัวอย่าง
class TextExportDialog extends StatefulWidget {
  const TextExportDialog({super.key, required this.project, this.workspace, this.erName, this.initial = TextExportKind.dictionary});

  /// ER ที่ใช้กับ Mermaid / DBML / ข้อมูลตัวอย่าง (ER ที่เปิดอยู่)
  final Project project;

  /// ทั้งโปรเจกต์ (Data dictionary / HTML / SQL ทั้งโปรเจกต์) — null = มีเฉพาะ [project] ER เดียว
  final Workspace? workspace;

  /// ชื่อเอกสารของ [project] (แสดงเมื่อโปรเจกต์มีหลาย ER)
  final String? erName;
  final TextExportKind initial;

  @override
  State<TextExportDialog> createState() => _TextExportDialogState();
}

class _TextExportDialogState extends State<TextExportDialog> {
  late TextExportKind _kind = widget.initial;
  int _rows = 10;
  bool _copied = false;
  Timer? _timer;
  final _cache = <TextExportKind, String>{};

  Workspace get _ws => widget.workspace ?? Workspace.single(widget.project);

  static const rowChoices = [5, 10, 25, 50, 100];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get text {
    final p = widget.project;
    return switch (_kind) {
      TextExportKind.dictionary || TextExportKind.word => exportWorkspaceDictionary(_ws),
      TextExportKind.html => _cache.putIfAbsent(_kind, () => exportHtmlDocument(_ws)),
      TextExportKind.sqlAll => _cache.putIfAbsent(_kind, () => buildWorkspaceSql(_ws)),
      TextExportKind.mermaid => exportMermaid(p),
      TextExportKind.dbml => exportDbml(p),
      TextExportKind.sample => exportSampleData(p, rows: _rows),
    };
  }

  String get fileName {
    final base = FileActions.safeName(_kind.perEr ? widget.project.name : _ws.name);
    return switch (_kind) {
      TextExportKind.dictionary => '${base}_dictionary.md',
      TextExportKind.html => '$base.html',
      TextExportKind.word => '${base}_dictionary.docx',
      TextExportKind.sqlAll => '${base}_all.sql',
      TextExportKind.mermaid => '$base.mmd',
      TextExportKind.dbml => '$base.dbml',
      TextExportKind.sample => '${base}_sample_${widget.project.dialect.name}.sql',
    };
  }

  Future<void> _copy(String t) async {
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  bool _busy = false;

  Future<void> _save(String t) async {
    if (_kind != TextExportKind.word) {
      return FileActions.saveText(context, t, fileName, tr('บันทึก {0}', [_kind.label]));
    }
    setState(() => _busy = true);
    try {
      final bytes = await buildDictionaryDocx(_ws);
      if (!mounted) return;
      await FileActions.saveBytes(context, bytes, fileName, tr('บันทึก {0}', [_kind.label]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = text;
    // HTML ยาวมาก (SVG ฝัง) : ตัวอย่างแสดงแค่ส่วนต้น แต่คัดลอก/บันทึกได้ครบ
    final preview = _kind == TextExportKind.html ? t.split(RegExp(r'\r?\n')).take(200).join('\n') : t;
    final lines = SqlCodeView.splitLines(preview);
    final multiEr = _ws.documentsOf(DocType.er).length > 1;
    final isWord = _kind == TextExportKind.word;

    Widget main() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
            Icon(_kind.icon, size: 20, color: C.primaryDark),
            Text(_kind.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.text)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(6)),
              child: Text(fileName, style: TextStyle(fontSize: 11.5, color: C.muted, fontFamily: kMono, fontFamilyFallback: const ['Consolas'])),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                [
                  _kind.hint,
                  if (multiEr && _kind.perEr && widget.erName != null) tr('ใช้เฉพาะ ER: {0}', [widget.erName]),
                ].join('  ·  '),
                key: const ValueKey('export-hint'),
                style: TextStyle(fontSize: 12.5, color: C.muted, height: 1.4),
              ),
            ),
            if (_kind == TextExportKind.sample) ...[
              const SizedBox(width: 12),
              Text(tr('แถวต่อตาราง'), style: TextStyle(fontSize: 12.5, color: C.muted)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _rows,
                isDense: true,
                items: [for (final n in rowChoices) DropdownMenuItem(value: n, child: Text('$n'))],
                onChanged: (v) => setState(() => _rows = v ?? _rows),
              ),
            ],
          ]),
          if (isWord)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 14, color: C.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(tr('ตัวอย่างด้านล่างเป็นข้อความ — ภาพแผนภาพจะอยู่ในไฟล์ที่บันทึก'), style: TextStyle(fontSize: 12, color: C.muted))),
              ]),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: const Color(0xFF0F172A),
                child: SqlCodeView(lines: lines, highlight: _kind == TextExportKind.sample || _kind == TextExportKind.sqlAll),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
              onPressed: isWord ? null : () => _copy(t), // Word เป็นไฟล์ไบนารี คัดลอกเป็นข้อความไม่ได้
              child: Text(_copied ? tr('คัดลอกแล้ว ✓') : tr('คัดลอก')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('export-save'),
              onPressed: _busy ? null : () => _save(t),
              icon: Icon(_busy ? Icons.hourglass_top_rounded : Icons.save_alt_rounded, size: 17),
              label: Text(_busy ? tr('กำลังสร้างไฟล์…') : tr('บันทึกเป็นไฟล์')),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ปิด'))),
          ]),
        ]);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 700),
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 720;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Export เอกสาร / ข้อมูล'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 12),
              Flexible(child: SizedBox(
                height: 520,
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(width: 210, child: _sidebar()),
                        VerticalDivider(width: 24, color: C.borderSoft),
                        Expanded(child: main()),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _chips(),
                        const SizedBox(height: 12),
                        Expanded(child: main()),
                      ]),
              )),
            ]),
          );
        }),
      ),
    );
  }

  /// รายการรูปแบบทางซ้าย จัดเป็นกลุ่ม (จอกว้าง)
  Widget _sidebar() => ListView(children: [
        for (final g in _groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Text(g.$1(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: C.muted)),
          ),
          for (final k in g.$2) _item(k),
          const SizedBox(height: 8),
        ],
      ]);

  Widget _item(TextExportKind k) {
    final on = k == _kind;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        key: ValueKey('export-kind-${k.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _kind = k),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: on ? C.primaryTint : null, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(k.icon, size: 18, color: on ? C.primaryDark : C.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(k.label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? C.primaryDark : C.text)),
            ),
            Text(k.ext, style: TextStyle(fontSize: 11, color: C.muted, fontFamily: kMono, fontFamilyFallback: const ['Consolas'])),
          ]),
        ),
      ),
    );
  }

  /// จอแคบ : ชิปเรียงบรรทัด
  Widget _chips() => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final k in TextExportKind.values)
          ChoiceChip(
            key: ValueKey('export-kind-${k.name}'),
            label: Text(k.label),
            selected: k == _kind,
            onSelected: (_) => setState(() => _kind = k),
          ),
      ]);
}

/// กลุ่มของรูปแบบในรายการซ้าย
final List<(String Function(), List<TextExportKind>)> _groups = [
  (() => tr('เอกสาร'), [TextExportKind.dictionary, TextExportKind.html, TextExportKind.word]),
  (() => tr('แผนภาพ / สคีมา'), [TextExportKind.mermaid, TextExportKind.dbml, TextExportKind.sqlAll]),
  (() => tr('ข้อมูล'), [TextExportKind.sample]),
];
