/// โน้ตและงานค้างของเอกสาร (Phase 5) — ใช้คนเดียว ออฟไลน์ ; เก็บในไฟล์ `.nsln` ใต้คีย์ `notes` ของเอกสาร
/// (แยกจากโน้ตบนแคนวาส ER และรูปทรง "โน้ต" ของ Flowchart ซึ่งเป็นเนื้อหาของแผนภาพ)
library;

/// ชนิดของโน้ต
enum NoteKind {
  /// ต้องทำ (มีสถานะเสร็จ/ยังไม่เสร็จ)
  todo,

  /// คำถาม (ปิดได้เมื่อได้คำตอบ)
  question,

  /// บันทึกทั่วไป
  memo,
}

class ReviewNote {
  ReviewNote({
    required this.id,
    this.kind = NoteKind.todo,
    this.text = '',
    this.done = false,
    this.x,
    this.y,
    this.anchorId,
    DateTime? created,
    Map<String, dynamic>? extra,
  })  : created = created ?? DateTime.now(),
        extra = extra ?? {};

  final String id;
  NoteKind kind;
  String text;

  /// ทำเสร็จ / ได้คำตอบแล้ว
  bool done;

  /// ตำแหน่งหมุดบนแคนวาส (พิกัดแผนภาพ) ; null = ไม่ได้ปักหมุด (โน้ตของทั้งเอกสาร)
  double? x, y;

  /// id ของวัตถุในเอกสารที่โน้ตนี้พูดถึง (ตาราง / สัญลักษณ์ / ชิ้นส่วน) ; null = ไม่ผูก
  String? anchorId;

  final DateTime created;

  /// คีย์อื่นที่รุ่นนี้ไม่รู้จัก (เขียนกลับเหมือนเดิม)
  final Map<String, dynamic> extra;

  bool get pinned => x != null && y != null;

  /// ยังค้างอยู่ (ต้องทำ/คำถามที่ยังไม่เสร็จ)
  bool get open => !done && kind != NoteKind.memo;

  static const _keys = {'id', 'kind', 'text', 'done', 'x', 'y', 'anchor', 'created'};

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'kind': kind.name,
        'text': text,
        if (done) 'done': true,
        if (x != null && y != null) ...{'x': x, 'y': y},
        if (anchorId != null) 'anchor': anchorId,
        'created': created.toUtc().toIso8601String(),
      };

  /// อ่านโน้ตหนึ่งรายการ ; ข้อมูลเสีย = null (ข้ามรายการเดียว ไม่ทำให้เปิดไฟล์ไม่ได้)
  static ReviewNote? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    final x = j['x'], y = j['y'];
    final hasPos = x is num && y is num && x.isFinite && y.isFinite;
    final c = j['created'];
    return ReviewNote(
      id: id,
      kind: NoteKind.values.asNameMap()[j['kind']] ?? NoteKind.memo,
      text: j['text'] is String ? j['text'] as String : '',
      done: j['done'] == true,
      x: hasPos ? x.toDouble() : null,
      y: hasPos ? y.toDouble() : null,
      anchorId: j['anchor'] is String ? j['anchor'] as String : null,
      created: c is String ? DateTime.tryParse(c)?.toLocal() : null,
      extra: {
        for (final e in j.entries)
          if (e.key is String && !_keys.contains(e.key)) e.key as String: e.value,
      },
    );
  }
}

/// อ่านรายการโน้ตจาก JSON (ไม่ใช่ list = ว่าง ; id ซ้ำ = ใช้ตัวแรก)
List<ReviewNote> decodeNotes(Object? j) {
  if (j is! List) return [];
  final ids = <String>{};
  return [
    for (final e in j)
      if (ReviewNote.tryFromJson(e) case final n? when ids.add(n.id)) n,
  ];
}

List<Object?> encodeNotes(List<ReviewNote> notes) => [for (final n in notes) n.toJson()];

/// คำอ้างอิงแบบ `#ชื่อ` ในข้อความโน้ต (ตัวอักษร/ตัวเลข/_/./- และอักษรไทย ; ไม่รวม # ที่ติดกับตัวอักษรข้างหน้า)
final RegExp kNoteRefPattern = RegExp(r'(?<![\w#])#([\w฀-๿][\w฀-๿.\-/]*)');

/// ชื่อที่อ้างถึงด้วย `#` ในข้อความ ตามลำดับที่เจอ (ไม่ซ้ำ)
List<String> noteRefs(String text) {
  final out = <String>[];
  for (final m in kNoteRefPattern.allMatches(text)) {
    final r = m.group(1)!.replaceAll(RegExp(r'[.\-/]+$'), '');
    if (r.isNotEmpty && !out.contains(r)) out.add(r);
  }
  return out;
}
