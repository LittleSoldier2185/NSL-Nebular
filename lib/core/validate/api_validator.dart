import '../l10n/l10n.dart';
import '../models/api_model.dart';
import '../models/table_model.dart';
import '../models/workspace.dart';
import 'issue.dart';

/// ตรวจเอกสาร API — [Issue.tableId] = id ของ endpoint, [Issue.columnId] = id ของฟิลด์ (ถ้าเป็นปัญหาของฟิลด์)
/// - error: method+path ซ้ำ, ชื่อฟิลด์ซ้ำ, ผูกกับตาราง/คอลัมน์ ER ที่ไม่มีแล้ว ([workspace] ต้องส่งมา)
/// - warning: ชนิดฟิลด์ไม่ตรงกับคอลัมน์, ฟิลด์บังคับแต่คอลัมน์รับ NULL, ไม่มี response, GET/DELETE มี body, ฟิลด์ไม่มีชื่อ
/// - info: ยังไม่มี endpoint, ตาราง ER ที่ยังไม่มี endpoint ใดผูก (ทั้งโปรเจกต์ — แจ้งในเอกสาร API แรกเท่านั้น)
List<Issue> validateApi(ApiDocument api, {Workspace? workspace, String? docId}) {
  final out = <Issue>[];
  if (api.endpoints.isEmpty) {
    out.add(Issue(severity: Severity.info, code: 'api_empty', title: tr('ยังไม่มี endpoint'), message: tr('เพิ่ม endpoint หรือสร้าง CRUD จากตาราง ER')));
  }
  final seen = <String, int>{};
  for (final e in api.endpoints) {
    seen[e.title] = (seen[e.title] ?? 0) + 1;
  }
  TableModel? tableOf(ApiTableRef r) => workspace?.documentById(r.docId)?.er?.tableById(r.tableId);

  for (final e in api.endpoints) {
    final name = e.title;
    if ((seen[name] ?? 0) > 1) {
      out.add(Issue(severity: Severity.error, code: 'api_dup_endpoint', title: tr('endpoint ซ้ำ'), message: tr('{0} มีมากกว่าหนึ่งอัน', [name]), tableId: e.id));
    }
    if (e.responses.isEmpty) {
      out.add(Issue(severity: Severity.warning, code: 'api_no_response', title: tr('ไม่มี response'), message: tr('{0} ยังไม่ได้กำหนด response', [name]), tableId: e.id));
    }
    if (!e.method.hasBody && e.fields.isNotEmpty) {
      out.add(Issue(
        severity: Severity.warning,
        code: 'api_body_not_allowed',
        title: tr('{0} ไม่ควรมี request body', [e.method.label]),
        message: tr('{0}: ย้ายฟิลด์ไปเป็น query/path หรือเปลี่ยน method', [name]),
        tableId: e.id,
      ));
    }
    final t = e.table;
    if (t != null && workspace != null && tableOf(t) == null) {
      out.add(Issue(
        severity: Severity.error,
        code: 'api_table_missing',
        title: tr('ผูกกับตาราง ER ที่ไม่มีแล้ว'),
        message: tr('{0} ผูกกับตารางที่ถูกลบไป — เลือกตารางใหม่หรือเลิกผูก', [name]),
        tableId: e.id,
      ));
    }
    final names = <String>{};
    for (final f in e.fields) {
      final fn = f.name.trim();
      if (fn.isEmpty) {
        out.add(Issue(severity: Severity.warning, code: 'api_field_unnamed', title: tr('ฟิลด์ไม่มีชื่อ'), message: tr('{0}: ตั้งชื่อฟิลด์', [name]), tableId: e.id, columnId: f.id));
      } else if (!names.add(fn.toLowerCase())) {
        out.add(Issue(severity: Severity.error, code: 'api_field_dup', title: tr('ชื่อฟิลด์ซ้ำ'), message: tr('{0}: ฟิลด์ {1} ซ้ำ', [name, fn]), tableId: e.id, columnId: f.id));
      }
      final ref = f.column;
      if (ref == null || workspace == null) continue;
      final col = tableOf(ref)?.columnById(ref.columnId ?? '');
      if (col == null) {
        out.add(Issue(
          severity: Severity.error,
          code: 'api_column_missing',
          title: tr('ฟิลด์ผูกกับคอลัมน์ที่ไม่มีแล้ว'),
          message: tr('{0}: ฟิลด์ {1} ผูกกับคอลัมน์ ER ที่ถูกลบไป', [name, fn]),
          tableId: e.id,
          columnId: f.id,
        ));
        continue;
      }
      final want = apiTypeOfColumn(col);
      if (f.type != want) {
        out.add(Issue(
          severity: Severity.warning,
          code: 'api_type_mismatch',
          title: tr('ชนิดข้อมูลไม่ตรงกับ ER'),
          message: tr('{0}: ฟิลด์ {1} เป็น {2} แต่คอลัมน์เป็น {3}', [name, fn, f.type.name, want.name]),
          tableId: e.id,
          columnId: f.id,
        ));
      }
      if (f.required && !(col.notNull || col.isPrimaryKey)) {
        out.add(Issue(
          severity: Severity.warning,
          code: 'api_required_nullable',
          title: tr('ฟิลด์บังคับแต่คอลัมน์รับ NULL'),
          message: tr('{0}: ฟิลด์ {1} บังคับ แต่คอลัมน์ {2} ไม่ได้เป็น NOT NULL', [name, fn, col.name]),
          tableId: e.id,
          columnId: f.id,
        ));
      }
    }
  }

  // ตารางที่ยังไม่มี endpoint ใดผูก — แจ้งครั้งเดียวในเอกสาร API แรกของโปรเจกต์
  if (workspace != null && docId != null && workspace.documentsOf(DocType.api).firstOrNull?.id == docId) {
    final covered = <String>{
      for (final d in workspace.documentsOf(DocType.api))
        for (final e in d.api!.endpoints)
          if (e.table case final t?) '${t.docId}/${t.tableId}',
    };
    for (final d in workspace.documentsOf(DocType.er)) {
      for (final t in d.er!.tables) {
        if (covered.contains('${d.id}/${t.id}')) continue;
        out.add(Issue(
          severity: Severity.info,
          code: 'api_table_uncovered',
          title: tr('ตารางยังไม่มี endpoint'),
          message: tr('ตาราง {0} ยังไม่มี endpoint — สร้าง CRUD อัตโนมัติได้', [t.name]),
          tableId: t.id,
          relationId: d.id,
        ));
      }
    }
  }
  out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return out;
}
