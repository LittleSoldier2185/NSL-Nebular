/// การอ้างถึง endpoint หนึ่งในเอกสาร API (Phase 8e) — ใช้กับชิ้นส่วน Wireframe, เส้น Screen Flow, กระบวนการ DFD, สัญลักษณ์ Flowchart
/// เก็บในไฟล์เป็น `"api": {"doc": ..., "endpoint": ...}` (ไม่มี = ไม่เขียนคีย์)
class ApiRef {
  const ApiRef({required this.docId, required this.endpointId});
  final String docId;
  final String endpointId;

  Map<String, dynamic> toJson() => {'doc': docId, 'endpoint': endpointId};

  static ApiRef? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['doc'], e = j['endpoint'];
    if (d is! String || d.isEmpty || e is! String || e.isEmpty) return null;
    return ApiRef(docId: d, endpointId: e);
  }

  @override
  bool operator ==(Object other) => other is ApiRef && other.docId == docId && other.endpointId == endpointId;

  @override
  int get hashCode => Object.hash(docId, endpointId);
}
