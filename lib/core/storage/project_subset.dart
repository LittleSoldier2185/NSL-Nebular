import '../models/doc_ref.dart';
import '../models/workspace.dart';
import 'project_codec.dart';

/// ผลของการตัดโปรเจกต์ย่อย ([extractSubset])
class SubsetResult {
  SubsetResult(this.workspace, {required this.documentCount, required this.brokenRefs, required this.droppedTraceLinks});

  /// โปรเจกต์ย่อย — เขียนเป็น `.nsln` ได้ทันที
  final Workspace workspace;
  final int documentCount;

  /// การอ้างอิงข้ามเอกสารที่ชี้ไปเอกสารนอกชุด (คงไว้ตามเดิม เหมือนตอนลบเอกสาร — ตัวตรวจจะแจ้งเป็นปัญหา)
  final int brokenRefs;

  /// ลิงก์ไล่ตามความต้องการที่ชี้ไปเอกสารนอกชุดและถูกตัดออก
  final int droppedTraceLinks;
}

/// ตัดโปรเจกต์ [w] ให้เหลือเฉพาะเอกสาร [docIds] และทุกเอกสารในโฟลเดอร์ [folderIds] (รวมโฟลเดอร์ย่อย)
/// - ไม่แก้ [w] (ทำงานบนสำเนา)
/// - เก็บโครงโฟลเดอร์ของเอกสารที่เลือก (โฟลเดอร์แม่ทุกชั้น) ; โฟลเดอร์ที่ไม่มีเอกสารเหลือถูกตัดทิ้ง ยกเว้นโฟลเดอร์ที่เลือกเอง
/// - ความต้องการทุกข้อคงไว้ แต่ตัดลิงก์ไล่ตามที่ชี้ไปเอกสารนอกชุด
/// - คืน null ถ้าไม่มีเอกสารเหลือเลย
SubsetResult? extractSubset(Workspace w, {Set<String> docIds = const {}, Set<String> folderIds = const {}}) {
  final copy = copyWorkspace(w);

  // โฟลเดอร์ที่เลือก + ลูกหลานทุกชั้น
  final selFolders = <String>{...folderIds.where((id) => copy.folderById(id) != null)};
  for (var grew = true; grew;) {
    grew = false;
    for (final f in copy.folders) {
      final p = f.parentId;
      if (p != null && selFolders.contains(p) && selFolders.add(f.id)) grew = true;
    }
  }

  final keep = {
    for (final d in copy.documents)
      if (docIds.contains(d.id) || (d.folderId != null && selFolders.contains(d.folderId))) d.id,
  };
  if (keep.isEmpty) return null;

  final index = WorkspaceIndex(copy);
  // นับเฉพาะอ้างอิง "ออก" จากเอกสารที่เก็บ ไปยังเอกสารนอกชุด
  var brokenRefs = 0;
  for (final d in copy.documents) {
    if (!keep.contains(d.id)) continue;
    for (final other in copy.documents) {
      if (keep.contains(other.id)) continue;
      brokenRefs += index.backlinks(other.id).where((e) => e.$1 == d.id).length;
    }
  }

  copy.documents.removeWhere((d) => !keep.contains(d.id));

  // โฟลเดอร์ที่ต้องเก็บ = โฟลเดอร์ของเอกสารที่เหลือ + แม่ทุกชั้น + โฟลเดอร์ที่เลือกเอง
  final folderKeep = <String>{...selFolders};
  for (final d in copy.documents) {
    for (var f = d.folderId; f != null && folderKeep.add(f);) {
      f = copy.folderById(f)?.parentId;
    }
  }
  // แม่ของโฟลเดอร์ที่เลือกก็ต้องเก็บ
  for (final id in [...folderKeep]) {
    for (var p = copy.folderById(id)?.parentId; p != null && folderKeep.add(p);) {
      p = copy.folderById(p)?.parentId;
    }
  }
  copy.folders.removeWhere((f) => !folderKeep.contains(f.id));

  var dropped = 0;
  for (final r in copy.requirements) {
    for (final cell in r.cells.values) {
      final before = cell.links.length;
      cell.links.removeWhere((l) => !keep.contains(l.docId));
      dropped += before - cell.links.length;
    }
  }

  // ขั้นตอนของ Use Case ที่ลิงก์ไปเอกสารที่ไม่ได้เลือก = ตัดลิงก์ออก (นับรวมกับลิงก์ไล่ตาม)
  for (final u in copy.useCases) {
    for (final s in u.steps) {
      final before = s.links.length;
      s.links.removeWhere((l) => !keep.contains(l.docId));
      dropped += before - s.links.length;
    }
  }

  return SubsetResult(copy, documentCount: keep.length, brokenRefs: brokenRefs, droppedTraceLinks: dropped);
}
