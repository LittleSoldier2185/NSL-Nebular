import 'color_utils.dart';
import 'enums.dart';

/// FK: fromTable.fromColumn (ลูก) -> toTable.toColumn (แม่)
class RelationModel {
  RelationModel({
    required this.id,
    required this.fromTableId,
    required this.fromColumnId,
    required this.toTableId,
    required this.toColumnId,
    this.onDelete = RefAction.noAction,
    this.onUpdate = RefAction.noAction,
    this.name,
    this.color,
  });

  /// สีเส้นของความสัมพันธ์นี้ (ARGB) — null = ใช้สีเส้นเริ่มต้นของโปรเจกต์/ธีม
  int? color;

  /// สัญลักษณ์ปลายเส้นที่ผู้ใช้กำหนดเอง (Phase 17b) — null = อนุมานจากสคีมา ; เป็นเอกสารล้วน ไม่มีผลกับ DDL
  ParentCard? parentCard;
  ChildMax? childMax;
  ChildMin? childMin;

  /// ตำแหน่ง x (พิกัดแผนภาพ) ของช่วงแนวตั้งกลางเส้นที่ผู้ใช้ลากเอง — null = จัดอัตโนมัติ
  /// (ปลายเส้นผูกกับคอลัมน์ จึงปรับได้แค่ช่วงกลาง ต่างจาก DFD/Flowchart ที่ย้ายปลายได้)
  double? bendX;

  String id;
  String fromTableId;
  String fromColumnId;
  String toTableId;
  String toColumnId;
  RefAction onDelete;
  RefAction onUpdate;
  String? name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromTable': fromTableId,
        'fromColumn': fromColumnId,
        'toTable': toTableId,
        'toColumn': toColumnId,
        'onDelete': onDelete.name,
        'onUpdate': onUpdate.name,
        if (name != null) 'name': name,
        if (color != null) 'color': color,
        if (parentCard != null) 'parentCard': parentCard!.name,
        if (childMax != null) 'childMax': childMax!.name,
        if (childMin != null) 'childMin': childMin!.name,
        if (bendX != null) 'bendX': bendX,
      };

  factory RelationModel.fromJson(Map<String, dynamic> j) => RelationModel(
        id: j['id'] as String,
        fromTableId: j['fromTable'] as String,
        fromColumnId: j['fromColumn'] as String,
        toTableId: j['toTable'] as String,
        toColumnId: j['toColumn'] as String,
        onDelete: RefAction.values.byName(j['onDelete'] as String? ?? 'noAction'),
        onUpdate: RefAction.values.byName(j['onUpdate'] as String? ?? 'noAction'),
        name: j['name'] as String?,
        color: parseArgb(j['color']),
      )
        ..bendX = j['bendX'] is num && (j['bendX'] as num).isFinite ? (j['bendX'] as num).toDouble() : null
        ..parentCard = _enumOrNull(ParentCard.values, j['parentCard'])
        ..childMax = _enumOrNull(ChildMax.values, j['childMax'])
        ..childMin = _enumOrNull(ChildMin.values, j['childMin']);
}

/// ค่า enum จากชื่อในไฟล์ — ไม่รู้จัก/ไม่ใช่ข้อความ = null (อัตโนมัติ) เพื่อให้ไฟล์ที่แก้มือหรือจากรุ่นใหม่กว่าไม่พัง
T? _enumOrNull<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
