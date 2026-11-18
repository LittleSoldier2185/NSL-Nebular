import 'dart:convert';

import '../l10n/l10n.dart';
import '../models/project.dart';
import '../models/workspace.dart';
import 'schema_diff.dart';

/// สถานะของตาราง/คอลัมน์ในภาพ diff
enum DiffMark { same, added, dropped, changed }

class VisualColumn {
  const VisualColumn(this.name, this.mark, {this.detail});
  final String name;
  final DiffMark mark;

  /// รายละเอียดที่เปลี่ยน เช่น "VARCHAR(10) → VARCHAR(20)" หรือ "เดิมชื่อ x"
  final String? detail;
}

class VisualTable {
  const VisualTable(this.name, this.mark, this.columns, {this.oldName});
  final String name;
  final DiffMark mark;
  final List<VisualColumn> columns;

  /// ชื่อเดิม (เมื่อเปลี่ยนชื่อตาราง)
  final String? oldName;
}

/// ภาพ diff ของ ER [old] → [neu] สร้างจาก [d] (ผลของ [diffProjects]) เท่านั้น — สถานะจึงตรงกับรายการความเปลี่ยนแปลงเสมอ
/// ลำดับ: ตารางตามลำดับใน [neu] (รวมที่เพิ่มใหม่) แล้วต่อด้วยตารางที่ถูกลบ ; ในตารางที่แก้ คอลัมน์ที่ถูกลบต่อท้าย
List<VisualTable> visualDiff(Project old, Project neu, SchemaDiff d) {
  final added = {for (final t in d.addedTables) t.id};
  final modifiedByNew = {for (final m in d.modified) m.neu.id: m};
  final out = <VisualTable>[];
  for (final t in neu.tables) {
    if (added.contains(t.id)) {
      out.add(VisualTable(t.name, DiffMark.added, [for (final c in t.columns) VisualColumn(c.name, DiffMark.added)]));
      continue;
    }
    final m = modifiedByNew[t.id];
    if (m == null) {
      out.add(VisualTable(t.name, DiffMark.same, [for (final c in t.columns) VisualColumn(c.name, DiffMark.same)]));
      continue;
    }
    final addedCols = {for (final c in m.addedColumns) c.id};
    final changed = {for (final c in m.changedColumns) c.neu.id: c};
    out.add(VisualTable(
      t.name,
      m.hasChanges ? DiffMark.changed : DiffMark.same,
      [
        for (final c in t.columns)
          if (addedCols.contains(c.id))
            VisualColumn(c.name, DiffMark.added)
          else if (changed[c.id] case final ch?)
            VisualColumn(c.name, DiffMark.changed, detail: _columnDetail(ch))
          else
            VisualColumn(c.name, DiffMark.same),
        for (final c in m.droppedColumns) VisualColumn(c.name, DiffMark.dropped),
      ],
      oldName: m.renamed ? m.old.name : null,
    ));
  }
  for (final t in d.droppedTables) {
    out.add(VisualTable(t.name, DiffMark.dropped, [for (final c in t.columns) VisualColumn(c.name, DiffMark.dropped)]));
  }
  return out;
}

String _columnDetail(ColumnChange c) {
  final parts = <String>[
    if (c.renamed) tr('เดิมชื่อ {0}', [c.old.name]),
    if (c.typeChanged) '${ColumnChange.typeText(c.old)} → ${ColumnChange.typeText(c.neu)}',
    if (c.nullChanged) (c.neu.notNull || c.neu.isPrimaryKey) ? 'NOT NULL' : 'NULL',
    if (c.defaultChanged) 'DEFAULT',
    if (c.uniqueChanged) 'UNIQUE',
    if (c.autoIncrementChanged) 'AUTO INCREMENT',
    if (c.commentChanged) tr('หมายเหตุ'),
  ];
  return parts.join(' · ');
}

/// ความเปลี่ยนแปลงของเอกสารที่ไม่ใช่ ER ระหว่าง [old] กับ [cur] (เทียบด้วย id เอกสาร): เพิ่ม / ลบ / แก้เนื้อหาหรือชื่อ
List<ChangeLine> documentChanges(Workspace old, Workspace cur) {
  String typeName(ProjectDocument d) => switch (d.type) {
        DocType.dfd => 'DFD',
        DocType.flowchart => 'Flowchart',
        DocType.wireframe => 'Wireframe',
        DocType.screenflow => 'Screen Flow',
        DocType.api => 'API',
        DocType.er => 'ER',
        null => d.typeName,
      };
  String body(ProjectDocument d) => jsonEncode(d.content.toContentJson());
  final out = <ChangeLine>[];
  final oldById = {for (final d in old.documents) d.id: d};
  final curIds = {for (final d in cur.documents) d.id};
  for (final d in cur.documents) {
    if (d.type == DocType.er) continue;
    final o = oldById[d.id];
    if (o == null) {
      out.add(ChangeLine(ChangeKind.add, tr('{0}: เพิ่มเอกสาร {1}', [typeName(d), d.name])));
    } else if (o.name != d.name || body(o) != body(d)) {
      out.add(ChangeLine(ChangeKind.change, tr('{0}: แก้เอกสาร {1}', [typeName(d), d.name])));
    }
  }
  for (final d in old.documents) {
    if (d.type == DocType.er || curIds.contains(d.id)) continue;
    out.add(ChangeLine(ChangeKind.drop, tr('{0}: ลบเอกสาร {1}', [typeName(d), d.name]), destructive: true));
  }
  // ER ทั้งเอกสารที่เพิ่ม/ลบ (การแก้ข้างใน ER ดูจากภาพ diff ของ ER นั้น)
  for (final d in cur.documents) {
    if (d.type == DocType.er && !oldById.containsKey(d.id)) out.add(ChangeLine(ChangeKind.add, tr('ER: เพิ่มเอกสาร {0}', [d.name])));
  }
  for (final d in old.documents) {
    if (d.type == DocType.er && !curIds.contains(d.id)) {
      out.add(ChangeLine(ChangeKind.drop, tr('ER: ลบเอกสาร {0}', [d.name]), destructive: true));
    }
  }
  return out;
}
