import '../validate/screenflow_validator.dart' show sfNodeTitle;
import '../validate/wireframe_validator.dart' show wfComponentTitle;
import 'workspace.dart';

/// ชื่อที่อ่านได้ของวัตถุ [id] ในเอกสาร [doc] (ตาราง / วัตถุ DFD / สัญลักษณ์ / ชิ้นส่วน / หน้าจอ) ; ไม่พบ = null
String? noteAnchorLabel(ProjectDocument doc, String? id) {
  if (id == null) return null;
  final er = doc.er;
  if (er != null) {
    for (final t in er.tables) {
      if (t.id == id) return t.name;
    }
    return null;
  }
  final dfd = doc.dfd;
  if (dfd != null) {
    for (final n in dfd.nodes) {
      if (n.id == id) return n.name.trim().isEmpty ? n.number : n.name;
    }
    return null;
  }
  final fc = doc.flowchart;
  if (fc != null) {
    for (final n in fc.nodes) {
      if (n.id == id) return n.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    return null;
  }
  final wf = doc.wireframe;
  if (wf != null) {
    for (final c in wf.components) {
      if (c.id == id) return wfComponentTitle(c);
    }
    return null;
  }
  final sf = doc.screenflow;
  if (sf != null) {
    for (final n in sf.nodes) {
      if (n.id == id) return sfNodeTitle(n);
    }
  }
  return null;
}

/// ปลายทางของคำอ้างอิง `#ชื่อ` ในโน้ต: เอกสาร หรือ ตารางในเอกสาร ER
typedef NoteRefTarget = ({String docId, String? tableId});

/// หาปลายทางของ `#[ref]` (ไม่สนตัวพิมพ์ ; ช่องว่างในชื่อเอกสารพิมพ์เป็น _): ชื่อเอกสารก่อน แล้วจึงชื่อตาราง ER (เอกสาร [preferDocId] ก่อน ถ้ามีตารางชื่อนั้น) ; ไม่พบ = null
NoteRefTarget? resolveNoteRef(Workspace w, String ref, {String? preferDocId}) {
  final key = ref.toLowerCase();
  for (final d in w.documents) {
    // ชื่อเอกสารที่มีช่องว่าง อ้างด้วย _ แทนช่องว่างได้ (#หน้า_ตะกร้า)
    final n = d.name.trim().toLowerCase();
    if (d.type != null && (n == key || n.replaceAll(RegExp(r'\s+'), '_') == key)) return (docId: d.id, tableId: null);
  }
  NoteRefTarget? first;
  for (final d in w.documents) {
    final er = d.er;
    if (er == null) continue;
    for (final t in er.tables) {
      if (t.name.toLowerCase() != key) continue;
      if (d.id == preferDocId) return (docId: d.id, tableId: t.id);
      first ??= (docId: d.id, tableId: t.id);
    }
  }
  return first;
}
