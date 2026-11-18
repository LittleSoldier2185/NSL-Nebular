import 'workspace.dart';

/// ความสำคัญของความต้องการ
enum ReqPriority { high, medium, low }

/// ลิงก์จากความต้องการไปยังเอกสาร [docId] (และวัตถุ [elementId] ในเอกสารนั้น ถ้ามี)
class TraceLink {
  const TraceLink(this.docId, [this.elementId]);
  final String docId;
  final String? elementId;

  Map<String, dynamic> toJson() => {'doc': docId, if (elementId != null) 'el': elementId};

  static TraceLink? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['doc'], e = j['el'];
    if (d is! String || d.isEmpty) return null;
    return TraceLink(d, e is String && e.isNotEmpty ? e : null);
  }

  @override
  bool operator ==(Object other) => other is TraceLink && other.docId == docId && other.elementId == elementId;

  @override
  int get hashCode => Object.hash(docId, elementId);
}

/// ช่องหนึ่งของเมทริกซ์ (ความต้องการ × ชนิดเอกสาร): ไม่จำเป็น หรือรายการลิงก์
class TraceCell {
  TraceCell({this.notNeeded = false, List<TraceLink>? links}) : links = links ?? [];
  bool notNeeded;
  final List<TraceLink> links;

  bool get isEmpty => !notNeeded && links.isEmpty;

  Map<String, dynamic> toJson() => {
        if (notNeeded) 'na': true,
        if (links.isNotEmpty) 'links': [for (final l in links) l.toJson()],
      };

  static TraceCell fromJson(Object? j) {
    if (j is! Map) return TraceCell();
    final seen = <TraceLink>{};
    return TraceCell(
      notNeeded: j['na'] == true,
      links: [
        for (final l in (j['links'] is List ? j['links'] as List : const []))
          if (TraceLink.tryFromJson(l) case final x? when seen.add(x)) x,
      ],
    );
  }
}

/// ความต้องการหนึ่งข้อ
class Requirement {
  Requirement({
    required this.id,
    this.code = '',
    this.text = '',
    this.priority = ReqPriority.medium,
    Map<DocType, TraceCell>? cells,
    Map<String, dynamic>? extra,
  })  : cells = cells ?? {},
        extra = extra ?? {};

  final String id;

  /// รหัสที่แสดง เช่น REQ-01
  String code;
  String text;
  ReqPriority priority;

  /// ช่องตามชนิดเอกสาร (ไม่มีคีย์ = ยังไม่มี)
  final Map<DocType, TraceCell> cells;

  /// คีย์ที่รุ่นนี้ไม่รู้จัก (รวมชนิดเอกสารที่ไม่รู้จัก) — เขียนกลับเหมือนเดิม
  final Map<String, dynamic> extra;

  TraceCell cell(DocType t) => cells.putIfAbsent(t, TraceCell.new);

  static const _keys = {'id', 'code', 'text', 'priority', 'cells'};

  Map<String, dynamic> toJson() {
    final unknownCells = extra['cells'] is Map ? Map<String, dynamic>.from(extra['cells'] as Map) : <String, dynamic>{};
    return {
      for (final e in extra.entries)
        if (e.key != 'cells') e.key: e.value,
      'id': id,
      'code': code,
      'text': text,
      'priority': priority.name,
      'cells': {
        ...unknownCells,
        for (final e in cells.entries)
          if (!e.value.isEmpty) e.key.name: e.value.toJson(),
      },
    };
  }

  static Requirement? tryFromJson(Object? j) {
    if (j is! Map || j['id'] is! String || (j['id'] as String).isEmpty) return null;
    final cells = <DocType, TraceCell>{};
    final unknownCells = <String, dynamic>{};
    if (j['cells'] is Map) {
      for (final e in (j['cells'] as Map).entries) {
        final t = DocType.values.asNameMap()[e.key];
        if (t != null) {
          cells[t] = TraceCell.fromJson(e.value);
        } else if (e.key is String) {
          unknownCells[e.key as String] = e.value;
        }
      }
    }
    return Requirement(
      id: j['id'] as String,
      code: j['code'] is String ? j['code'] as String : '',
      text: j['text'] is String ? j['text'] as String : '',
      priority: ReqPriority.values.asNameMap()[j['priority']] ?? ReqPriority.medium,
      cells: cells,
      extra: {
        for (final e in j.entries)
          if (e.key is String && !_keys.contains(e.key)) e.key as String: e.value,
        if (unknownCells.isNotEmpty) 'cells': unknownCells,
      },
    );
  }
}

/// อ่านรายการความต้องการ (ข้อมูลเสียทีละข้อถูกข้าม ; id ซ้ำ = ใช้ตัวแรก)
List<Requirement> decodeRequirements(Object? j) {
  if (j is! List) return [];
  final ids = <String>{};
  return [
    for (final e in j)
      if (Requirement.tryFromJson(e) case final r? when ids.add(r.id)) r,
  ];
}
