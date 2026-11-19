import 'package:flutter/material.dart';

import '../core/parser/sql_importer.dart';
import 'theme.dart';
import '../core/l10n/l10n.dart';

/// ปลายทางของการนำเข้า .sql/ฐานข้อมูล
enum ImportTarget {
  /// เพิ่มเป็นเอกสาร ER ใหม่ในโปรเจกต์ที่เปิดอยู่ (ค่าเริ่มต้น)
  newEr,

  /// แทนเนื้อหา ER ที่เปิดอยู่ — undo ได้
  replaceEr,

  /// ปิดโปรเจกต์ที่เปิดอยู่แล้วเปิดผลนำเข้าเป็นโปรเจกต์ใหม่ (พฤติกรรมเดิม)
  newProject,
}

/// พรีวิวผลการ import: จำนวนที่อ่านได้ + รายการที่ข้าม/ไม่แน่ใจ + เลือกปลายทาง ก่อนยืนยัน
/// คืน [ImportTarget] ที่เลือกเมื่อผู้ใช้กด "นำเข้า" ; ยกเลิก = null
///
/// [currentErName] = ชื่อ ER ที่จะถูกแทนถ้าเลือก "แทนที่" ; null = ไม่มีตัวเลือก (นำเข้าเป็นโปรเจกต์ใหม่เท่านั้น)
class ImportPreviewDialog extends StatefulWidget {
  const ImportPreviewDialog({
    super.key,
    required this.result,
    required this.fileName,
    this.currentErName,
    this.initial = ImportTarget.newEr,
  });
  final ImportResult result;
  final String fileName;
  final String? currentErName;
  final ImportTarget initial;

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  late ImportTarget _target =
      widget.currentErName == null ? ImportTarget.newProject : widget.initial;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final p = result.project;
    final cols = p.tables.fold<int>(0, (s, t) => s + t.columns.length);
    final warnings = result.notes.where((n) => n.warning).toList();
    final infos = result.notes.where((n) => !n.warning).toList();
    final empty = p.tables.isEmpty;
    final erName = widget.currentErName;

    return AlertDialog(
      title: Text(tr('นำเข้า {0}', [widget.fileName])),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            empty
                ? tr('ไม่พบ CREATE TABLE ในไฟล์นี้')
                : tr('พบ {0} ตาราง · {1} คอลัมน์ · {2} ความสัมพันธ์ FK\nตรวจพบ dialect: {3}',
                    [p.tables.length, cols, p.relations.length, result.detected.label]),
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
          if (!empty && erName == null) ...[
            const SizedBox(height: 6),
            Text(tr('การนำเข้าจะแทนที่โปรเจกต์ที่เปิดอยู่'),
                style: TextStyle(fontSize: 12.5, color: C.muted)),
          ],
          if (!empty && erName != null) ...[
            const SizedBox(height: 12),
            Text(tr('นำเข้าไปที่'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            _option(ImportTarget.newEr, tr('เอกสาร ER ใหม่ในโปรเจกต์นี้'),
                tr('เอกสารอื่นไม่ถูกแตะ')),
            _option(ImportTarget.replaceEr, tr('แทนที่ ER ที่เปิดอยู่: {0}', [erName]),
                tr('เลิกทำ (Ctrl+Z) ได้ ; ลิงก์จาก DFD/Wireframe ที่ชี้ตารางเดิมอาจขาด')),
            _option(ImportTarget.newProject, tr('เปิดเป็นโปรเจกต์ใหม่'),
                tr('ปิดโปรเจกต์ที่เปิดอยู่ (ถามก่อนถ้ายังไม่บันทึก)')),
          ],
          if (warnings.isNotEmpty || infos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(warnings.isEmpty ? tr('ข้อมูลเพิ่มเติม') : tr('สิ่งที่ควรตรวจ ({0})', [warnings.length]),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: C.field,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(10),
                  children: [
                    for (final n in warnings) _line(n, C.warnText, Icons.warning_amber_rounded),
                    for (final n in infos) _line(n, C.muted, Icons.info_outline),
                  ],
                ),
              ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        FilledButton(
          onPressed: empty ? null : () => Navigator.pop(context, _target),
          child: Text(tr('นำเข้า')),
        ),
      ],
    );
  }

  Widget _option(ImportTarget t, String title, String hint) {
    final on = _target == t;
    return InkWell(
      key: ValueKey('import-target-${t.name}'),
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _target = t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18, color: on ? Theme.of(context).colorScheme.primary : C.muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
              Text(hint, style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _line(ImportNote n, Color color, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              n.line > 0 ? tr('บรรทัด {0}: {1}', [n.line, n.message]) : n.message,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ]),
      );
}
