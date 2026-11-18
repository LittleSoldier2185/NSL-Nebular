import '../validate/screenflow_validator.dart' show sfNodeTitle;
import 'dfd_model.dart';
import 'requirement.dart';
import 'workspace.dart';

/// ชนิดเอกสารที่เป็นคอลัมน์ของเมทริกซ์ ตามลำดับที่แสดง (ตามดีไซน์ `Trace`)
const kTraceColumns = [DocType.er, DocType.dfd, DocType.flowchart, DocType.wireframe, DocType.screenflow, DocType.api];

/// สถานะของช่อง
enum TraceStatus { covered, notNeeded, missing }

/// ลิงก์ [l] ยังใช้ได้กับคอลัมน์ [t]: เอกสารยังอยู่และเป็นชนิดนั้น ; ถ้าชี้วัตถุ วัตถุต้องยังอยู่
bool traceLinkValid(Workspace w, TraceLink l, DocType t) {
  final d = w.documentById(l.docId);
  if (d == null || d.type != t) return false;
  final el = l.elementId;
  if (el == null) return true;
  return switch (t) {
    DocType.er => d.er!.tableById(el) != null,
    DocType.dfd => d.dfd!.nodeById(el) != null,
    DocType.flowchart => d.flowchart!.nodeById(el) != null,
    DocType.wireframe => d.wireframe!.componentById(el) != null,
    DocType.screenflow => d.screenflow!.nodeById(el) != null,
    DocType.api => d.api!.endpointById(el) != null,
  };
}

/// ลิงก์ที่ยังใช้ได้ของช่อง [t] ใน [r]
List<TraceLink> validLinks(Workspace w, Requirement r, DocType t) =>
    [for (final l in r.cells[t]?.links ?? const <TraceLink>[]) if (traceLinkValid(w, l, t)) l];

/// สถานะช่อง: ลิงก์ที่ใช้ได้ ≥ 1 = ครอบคลุม ; ไม่จำเป็น ; ไม่งั้น (รวมลิงก์ที่ขาดหมด) = ยังไม่มี
TraceStatus traceStatus(Workspace w, Requirement r, DocType t) {
  if (validLinks(w, r, t).isNotEmpty) return TraceStatus.covered;
  if (r.cells[t]?.notNeeded ?? false) return TraceStatus.notNeeded;
  return TraceStatus.missing;
}

/// ความต้องการครอบคลุมครบ = ไม่มีช่องที่ "ยังไม่มี"
bool requirementCovered(Workspace w, Requirement r) => kTraceColumns.every((t) => traceStatus(w, r, t) != TraceStatus.missing);

/// สรุปด้านบนของหน้า
typedef TraceSummary = ({int total, int covered, int missingScreens, int missingApi, List<ProjectDocument> unlinkedDocs});

TraceSummary traceSummary(Workspace w) {
  final reqs = w.requirements;
  final linkedDocs = <String>{
    for (final r in reqs)
      for (final t in kTraceColumns)
        for (final l in validLinks(w, r, t)) l.docId,
  };
  return (
    total: reqs.length,
    covered: reqs.where((r) => requirementCovered(w, r)).length,
    missingScreens: reqs.where((r) => traceStatus(w, r, DocType.wireframe) == TraceStatus.missing).length,
    missingApi: reqs.where((r) => traceStatus(w, r, DocType.api) == TraceStatus.missing).length,
    unlinkedDocs: [for (final d in w.documents) if (d.type != null && !linkedDocs.contains(d.id)) d],
  );
}

/// ข้อความสั้นของลิงก์ (ชื่อตาราง / P2 / ชื่อหน้าจอ / POST /orders / ชื่อเอกสาร) ; ลิงก์ที่ขาด = null
String? traceLinkLabel(Workspace w, TraceLink l) {
  final d = w.documentById(l.docId);
  if (d == null) return null;
  final el = l.elementId;
  if (el == null) return d.name;
  if (d.er != null) return d.er!.tableById(el)?.name;
  if (d.dfd != null) {
    final n = d.dfd!.nodeById(el);
    if (n == null) return null;
    return n.kind == DfdKind.process && n.number.isNotEmpty ? 'P${n.number.split('.').first}${n.name.isEmpty ? '' : ' ${n.name}'}' : n.title;
  }
  if (d.screenflow != null) {
    final n = d.screenflow!.nodeById(el);
    return n == null ? null : sfNodeTitle(n);
  }
  if (d.api != null) return d.api!.endpointById(el)?.title;
  if (d.flowchart != null) return d.flowchart!.nodeById(el)?.text.trim();
  if (d.wireframe != null) return d.wireframe!.componentById(el)?.text.trim();
  return null;
}

/// สิ่งที่ผูกได้ในคอลัมน์ [t]: ER = ตาราง, DFD = กระบวนการ, Screen Flow = หน้าจอ, API = endpoint, Flowchart/Wireframe = ทั้งเอกสาร
/// (เอกสารที่ยังไม่มีวัตถุให้ผูก = ผูกทั้งเอกสารได้)
List<({TraceLink link, String label})> traceCandidates(Workspace w, DocType t) {
  final multi = w.documentsOf(t).length > 1;
  String withDoc(ProjectDocument d, String s) => multi ? '$s · ${d.name}' : s;
  final out = <({TraceLink link, String label})>[];
  for (final d in w.documentsOf(t)) {
    final before = out.length;
    switch (t) {
      case DocType.er:
        for (final x in d.er!.tables) {
          out.add((link: TraceLink(d.id, x.id), label: withDoc(d, x.name)));
        }
      case DocType.dfd:
        for (final n in d.dfd!.nodes) {
          if (n.kind == DfdKind.process) out.add((link: TraceLink(d.id, n.id), label: withDoc(d, traceLinkLabel(w, TraceLink(d.id, n.id)) ?? n.title)));
        }
      case DocType.screenflow:
        for (final n in d.screenflow!.nodes) {
          out.add((link: TraceLink(d.id, n.id), label: withDoc(d, sfNodeTitle(n))));
        }
      case DocType.api:
        for (final e in d.api!.endpoints) {
          out.add((link: TraceLink(d.id, e.id), label: withDoc(d, e.title)));
        }
      case DocType.flowchart || DocType.wireframe:
        break;
    }
    if (out.length == before) out.add((link: TraceLink(d.id), label: d.name));
  }
  return out;
}

/// รหัสถัดไปแบบ REQ-01, REQ-02… (ต่อจากเลขสูงสุดที่มี)
String nextRequirementCode(Workspace w) {
  var max = 0;
  for (final r in w.requirements) {
    final m = RegExp(r'(\d+)\s*$').firstMatch(r.code);
    if (m != null) max = (int.tryParse(m.group(1)!) ?? 0) > max ? int.parse(m.group(1)!) : max;
  }
  return 'REQ-${(max + 1).toString().padLeft(2, '0')}';
}
