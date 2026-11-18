import '../l10n/l10n.dart';
import '../models/api_ref.dart';
import '../models/workspace.dart';
import 'issue.dart';

/// ลิงก์ไป endpoint ใช้ได้หรือไม่ ; ใช้ไม่ได้ = ข้อความบอกเหตุ (เอกสาร API ถูกลบ / endpoint ถูกลบ)
String? apiRefProblem(Workspace w, ApiRef r) {
  final doc = w.documentById(r.docId);
  if (doc?.api == null) return tr('เอกสาร API ที่ผูกไว้ถูกลบไปแล้ว');
  if (doc!.api!.endpointById(r.endpointId) == null) return tr('endpoint ที่ผูกไว้ถูกลบไปแล้ว');
  return null;
}

/// ปัญหา "เรียก endpoint ที่ไม่มีแล้ว" ของวัตถุ [what] (null = ใช้ได้ / ไม่ได้ผูก / ไม่ได้ส่ง workspace) — ปัญหาข้ามเอกสาร `api_ref_missing`
Issue? apiRefIssue(Workspace? w, ApiRef? r, String what, {String? elementId, String? edgeId}) {
  if (w == null || r == null) return null;
  final p = apiRefProblem(w, r);
  if (p == null) return null;
  return Issue(
    severity: Severity.error,
    code: 'api_ref_missing',
    title: tr('เรียก endpoint ที่ไม่มีแล้ว'),
    message: tr('{0}: {1} — เลือก endpoint ใหม่หรือเลิกผูก', [what, p]),
    tableId: elementId,
    relationId: edgeId,
  );
}
