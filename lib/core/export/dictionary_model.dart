import '../models/project.dart';
import '../models/workspace.dart';

/// ช่องคำอธิบายหนึ่งช่องในพจนานุกรมข้อมูล: คำอธิบายตาราง ([columnId] = null) หรือของคอลัมน์
typedef DictSlot = ({String docId, String tableId, String? columnId});

/// ช่องคำอธิบายที่ยังว่าง (ตัดช่องว่างแล้ว) ทั้งโปรเจกต์ ตามลำดับที่แสดงในหน้า: เอกสาร ER → ตาราง → (ตาราง แล้วคอลัมน์)
List<DictSlot> missingDescriptions(Workspace w) => [
      for (final d in w.documentsOf(DocType.er))
        for (final t in d.er!.tables) ...[
          if (t.comment.trim().isEmpty) (docId: d.id, tableId: t.id, columnId: null),
          for (final c in t.columns)
            if (c.comment.trim().isEmpty) (docId: d.id, tableId: t.id, columnId: c.id),
        ],
    ];

/// จำนวนช่องคำอธิบายทั้งหมด (ตาราง + คอลัมน์) ของทุก ER
int descriptionSlotCount(Workspace w) => w.documentsOf(DocType.er).fold(
      0,
      (a, d) => a + d.er!.tables.fold<int>(0, (b, t) => b + 1 + t.columns.length),
    );

/// ช่องว่างถัดจาก [after] (วนกลับไปตัวแรกเมื่อสุดรายการ) ; ไม่มีช่องว่าง = null
DictSlot? nextMissing(Workspace w, DictSlot? after) {
  final all = missingDescriptions(w);
  if (all.isEmpty) return null;
  if (after == null) return all.first;
  final i = all.indexOf(after);
  return all[(i < 0 ? 0 : i + 1) % all.length];
}

/// คอลัมน์ของตารางอื่นที่ชี้มาที่ตาราง [tableId] ด้วย FK: "ตาราง.คอลัมน์" ตามลำดับความสัมพันธ์
List<String> referencedBy(Project p, String tableId) {
  final out = <String>[];
  for (final r in p.relations) {
    if (r.toTableId != tableId) continue;
    final t = p.tableById(r.fromTableId);
    final c = t?.columnById(r.fromColumnId);
    if (t == null || c == null) continue;
    final s = '${t.name}.${c.name}';
    if (!out.contains(s)) out.add(s);
  }
  return out;
}

/// ปลายทางของ FK ของคอลัมน์ [columnId] ในตาราง [tableId]: "ตาราง.คอลัมน์" ; ไม่ใช่ FK = null
String? fkTarget(Project p, String tableId, String columnId) {
  for (final r in p.relations) {
    if (r.fromTableId != tableId || r.fromColumnId != columnId) continue;
    final t = p.tableById(r.toTableId);
    final c = t?.columnById(r.toColumnId);
    if (t != null && c != null) return '${t.name}.${c.name}';
  }
  return null;
}
