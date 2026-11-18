import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/doc_ref.dart';
import '../core/models/workspace.dart';
import '../core/validate/screenflow_validator.dart' show sfNodeTitle;
import '../core/validate/wireframe_validator.dart' show wfComponentTitle;
import '../state/workspace_controller.dart';
import 'prompt_dialog.dart';
import 'theme.dart';

/// ไอคอนประจำชนิดเอกสาร (แท็บ / ตัวสำรวจ / Project Home / หน้าต่างปัญหา)
IconData docTypeIcon(DocType? t) => switch (t) {
      DocType.er => Icons.table_chart_outlined,
      DocType.flowchart => Icons.schema_outlined,
      DocType.wireframe => Icons.web_outlined,
      DocType.screenflow => Icons.alt_route_rounded,
      _ => Icons.account_tree_outlined,
    };

/// ชื่อของวัตถุต้นทางของลิงก์ข้ามเอกสาร ([fromElement] ในเอกสาร [src]) : ชิ้นส่วน Wireframe / หน้าจอ Screen Flow / วัตถุ DFD
String linkOriginTitle(ProjectDocument? src, String fromElement) {
  if (src?.wireframe != null) {
    final comp = src!.wireframe!.componentById(fromElement);
    return comp == null ? tr('(ไม่มีชื่อ)') : wfComponentTitle(comp);
  }
  if (src?.screenflow != null) {
    final n = src!.screenflow!.nodeById(fromElement);
    return n == null ? tr('(ไม่มีชื่อ)') : sfNodeTitle(n);
  }
  final node = src?.dfd?.nodeById(fromElement);
  return node == null || node.title.isEmpty ? tr('(ไม่มีชื่อ)') : node.title;
}

/// จุดสีประจำชนิดเอกสาร (ตามดีไซน์: DFD = วงกลม, Flowchart = ข้าวหลามตัด, ชนิดอื่น = สี่เหลี่ยมมน) — ตกแต่งอย่างเดียว ไม่อ่านออกเสียง
class DocTypeDot extends StatelessWidget {
  const DocTypeDot(this.type, {super.key, this.size = 9});

  final DocType? type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = C.doc(type).main;
    final dot = switch (type) {
      DocType.dfd => DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      DocType.flowchart => Transform.rotate(
          angle: 0.7853981633974483,
          child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
        ),
      _ => DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.5))),
    };
    // ข้าวหลามตัดวาดเล็กลงให้ดูขนาดเท่ากับรูปอื่น
    final inner = type == DocType.flowchart ? size * 0.78 : size;
    return ExcludeSemantics(
      child: SizedBox(width: size, height: size, child: Center(child: SizedBox(width: inner, height: inner, child: dot))),
    );
  }
}

/// กล่องเปลี่ยนชื่อเอกสาร (ใช้ร่วมกันระหว่างแท็บแผนภาพและ Project Explorer): ชื่อว่าง/ซ้ำ = แจ้งเตือนและไม่เปลี่ยน
Future<void> renameDocumentDialog(BuildContext context, String docId) async {
  final c = context.read<WorkspaceController>();
  final doc = c.documentById(docId);
  if (doc == null) return;
  final r = await showDialog<PromptResult>(
    context: context,
    builder: (_) => TextPromptDialog(
      title: tr('เปลี่ยนชื่อแผนภาพ'),
      initial: doc.name,
      label: tr('ชื่อ'),
    ),
  );
  if (r == null || !context.mounted) return;
  if (!c.renameDocument(docId, r.text)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('ชื่อว่างหรือซ้ำกับแผนภาพอื่น'))),
    );
  }
}

/// กล่องยืนยันลบเอกสาร (แสดงลิงก์ข้ามเอกสารที่จะขาด) แล้วลบถ้ายืนยัน ; ลบไม่ได้ (ER อันสุดท้าย) = ไม่ทำอะไร
Future<void> deleteDocumentDialog(BuildContext context, String docId) async {
  final c = context.read<WorkspaceController>();
  final doc = c.documentById(docId);
  if (doc == null || !c.canDeleteDocument(docId)) return;
  final broken = brokenLinkLines(c, docId);
  const maxLines = 8;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('ลบแผนภาพ "{0}"', [doc.name])),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('เนื้อหาในแผนภาพนี้จะหายไปและย้อนกลับด้วย Ctrl+Z ไม่ได้')),
            if (broken.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                tr('ลิงก์จากแผนภาพอื่น {0} รายการจะใช้ไม่ได้:', [broken.length]),
                key: const ValueKey('delete-broken-links'),
                style: TextStyle(color: C.danger, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              for (final line in broken.take(maxLines))
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text('• $line', style: const TextStyle(fontSize: 12.5)),
                ),
              if (broken.length > maxLines)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    tr('และอีก {0} รายการ', [broken.length - maxLines]),
                    style: TextStyle(fontSize: 12.5, color: C.muted),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('ยกเลิก')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('ลบ')),
        ),
      ],
    ),
  );
  if (ok == true) c.deleteDocument(docId);
}

/// รายการลิงก์จากเอกสารอื่นที่จะใช้ไม่ได้ถ้าลบเอกสาร [docId] (ข้อความหนึ่งบรรทัดต่อหนึ่งลิงก์ ใช้ในกล่องยืนยันการลบ)
List<String> brokenLinkLines(WorkspaceController c, String docId) {
  final target = c.documentById(docId);
  final out = <String>[];
  for (final (fromDoc, fromElement, ref) in c.backlinksOf(docId)) {
    final src = c.documentById(fromDoc);
    final from = '${src?.name ?? fromDoc} · ${linkOriginTitle(src, fromElement)}';
    final table = target?.er?.tableById(ref.elementId ?? '');
    out.add(switch (ref.kind) {
      DocRefKind.storeTable => tr('{0} → ตาราง {1}', [
          from,
          table?.name ?? ref.elementId ?? '?',
        ]),
      DocRefKind.dfdChild => tr('{0} → แผนภาพย่อย', [from]),
      DocRefKind.wireframeTable => tr('{0} → ตาราง {1}', [
          from,
          '${table?.name ?? ref.elementId ?? '?'}'
              '${ref.subElementId == null ? '' : '.${table?.columnById(ref.subElementId!)?.name ?? ref.subElementId}'}',
        ]),
      DocRefKind.screenWireframe => tr('{0} → หน้าจอ Wireframe', [from]),
    });
  }
  return out;
}
