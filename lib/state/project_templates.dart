import '../core/models/workspace.dart';
import 'workspace_controller.dart';

/// จุดเริ่มต้นสำเร็จรูปของโปรเจกต์ใหม่ (หน้า Start / กล่องสร้างโปรเจกต์)
/// กำหนดแค่ "มีเอกสารชนิดไหนบ้าง" — ยังไม่ใส่เนื้อหาตัวอย่างในเอกสาร
enum ProjectTemplate {
  /// โปรเจกต์ว่าง: มี ER อันเดียว เลือกเอกสารเพิ่มเองได้
  blank,

  /// ฐานข้อมูลอย่างเดียว: ER + สร้าง SQL
  database,

  /// วิเคราะห์ระบบ: ER + DFD + Flowchart
  analysis,

  /// ออกแบบแอป: ER + Wireframe + Screen Flow
  appDesign,

  /// ขั้นตอนงาน: Flowchart เป็นหลัก
  flow,

  /// ครบทุกชนิด
  full,
}

extension ProjectTemplateDocs on ProjectTemplate {
  /// เอกสารที่ต้องเพิ่มต่อจาก ER (ER มีเสมอ: โปรเจกต์ต้องมี ER อย่างน้อยหนึ่งอัน)
  List<DocType> get extraDocs => switch (this) {
        ProjectTemplate.blank || ProjectTemplate.database => const [],
        ProjectTemplate.analysis => const [DocType.dfd, DocType.flowchart],
        ProjectTemplate.appDesign => const [DocType.wireframe, DocType.screenflow],
        ProjectTemplate.flow => const [DocType.flowchart],
        ProjectTemplate.full => const [DocType.dfd, DocType.flowchart, DocType.wireframe, DocType.screenflow],
      };
}

/// ลำดับที่ใช้เลือกเอกสารที่เปิดอยู่ตอนสร้างเสร็จ (เอกสารแรกที่เลือกตามลำดับนี้ ไม่มี = ER)
const _openOrder = [DocType.flowchart, DocType.wireframe, DocType.screenflow, DocType.dfd];

/// สร้างโปรเจกต์ใหม่ใน [w] (แทนที่โปรเจกต์ที่เปิดอยู่ — ผู้เรียกต้องถามบันทึกก่อน) ด้วยเอกสารชนิด [docs] ต่อจาก ER
/// ตั้งชื่อโปรเจกต์เป็น [name] ถ้าให้มา ; คืนเอกสารที่เปิดอยู่หลังสร้าง
ProjectDocument createProject(
  WorkspaceController w, {
  Iterable<DocType> docs = const [],
  String? name,
  double? boardWidth,
  double? boardHeight,
}) {
  if (boardWidth != null && boardHeight != null) {
    w.newProject(boardWidth: boardWidth, boardHeight: boardHeight);
  } else {
    w.newProject();
  }
  final wanted = docs.toSet()..remove(DocType.er);
  final trimmed = name?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    w.mainEr.project.name = trimmed;
    w.workspace.name = trimmed;
  }
  // เพิ่มตามลำดับคงที่ (ไม่ขึ้นกับลำดับที่ส่งมา) เพื่อให้ผลเหมือนกันทุกครั้ง
  for (final t in [DocType.dfd, DocType.flowchart, DocType.wireframe, DocType.screenflow]) {
    if (wanted.contains(t)) w.addDocument(t);
  }
  final first = _openOrder.where(wanted.contains).firstOrNull;
  if (first == null) {
    w.openDocument(w.mainEr.docId);
  } else {
    w.openDocument(w.documents.firstWhere((d) => d.type == first).id);
  }
  return w.activeDocument;
}

/// สร้างจากจุดเริ่มต้นสำเร็จรูป
ProjectDocument createProjectFromTemplate(WorkspaceController w, ProjectTemplate t, {String? name}) =>
    createProject(w, docs: t.extraDocs, name: name);
