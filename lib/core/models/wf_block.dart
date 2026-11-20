import 'wireframe_model.dart';

/// บล็อกของ Wireframe (Phase 18b): ชุดชิ้นส่วนสำเร็จรูปที่วางทีเดียวทั้งก้อนเป็นกลุ่ม
/// ใช้ทั้ง "แม่แบบ" ที่โปรแกรมมีให้ ([isTemplate]) และ "ของฉัน" ที่ผู้ใช้บันทึกจากชิ้นที่เลือก (เก็บในไฟล์ตั้งค่าของเครื่อง ไม่ลงไฟล์โปรเจกต์)
/// ชิ้นส่วนใน [parts] อยู่ที่พิกัดสัมพัทธ์ (มุมซ้ายบนของบล็อก = 0,0) ; id/กลุ่มเดิมไม่สำคัญ (ตอนวางจะสร้างใหม่ทั้งหมด)
class WfBlock {
  WfBlock({required this.id, required this.name, required this.w, required this.h, required this.parts, this.isTemplate = false});

  final String id;
  String name;
  final double w, h;
  final List<WfComponent> parts;

  /// แม่แบบของโปรแกรม (แก้/ลบไม่ได้)
  final bool isTemplate;

  /// ขนาดและชิ้นส่วนเหมือนเดิม ชื่อใหม่ (ไม่ใช้กับแม่แบบ)
  WfBlock renamed(String newName) => WfBlock(id: id, name: newName, w: w, h: h, parts: parts);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'w': w,
        'h': h,
        'parts': [for (final p in parts) p.toJson()],
      };

  /// อ่านจากไฟล์ตั้งค่า — ข้อมูลเสีย (ชนิด/ค่าผิด, ไม่มีชิ้นส่วน) = null แทนที่จะพังทั้งไฟล์ ; ชิ้นที่อ่านไม่ได้ถูกข้าม
  static WfBlock? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], w = j['w'], h = j['h'], parts = j['parts'];
    if (id is! String || id.isEmpty || name is! String || w is! num || h is! num || parts is! List) return null;
    if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return null;
    final list = [for (final p in parts) ?WfComponent.tryFromJson(p)];
    if (list.isEmpty) return null;
    return WfBlock(id: id, name: name, w: w.toDouble(), h: h.toDouble(), parts: list);
  }

  /// สร้างบล็อกจากชิ้นที่เลือก (รวมลูกในภาชนะ) — พิกัดย้ายให้มุมซ้ายบนของกรอบรวมเป็น 0,0 ; กลุ่ม/ล็อก/ซ่อนเดิมไม่ติดไป
  /// คืน null ถ้า [source] ว่าง
  static WfBlock? fromComponents(String id, String name, Iterable<WfComponent> source) {
    final src = source.toList();
    if (src.isEmpty) return null;
    var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
    for (final c in src) {
      if (c.x < left) left = c.x;
      if (c.y < top) top = c.y;
      if (c.x + c.w > right) right = c.x + c.w;
      if (c.y + c.h > bottom) bottom = c.y + c.h;
    }
    final parts = [
      for (final c in src)
        WfComponent.tryFromJson({...c.toJson(), 'x': c.x - left, 'y': c.y - top, 'group': null, 'locked': false, 'hidden': false})!,
    ];
    return WfBlock(id: id, name: name, w: right - left, h: bottom - top, parts: parts);
  }

  /// เอกสารจำลองสำหรับวาดรูปย่อของบล็อก (กรอบพอดีเนื้อหา)
  WireframeDiagram previewDiagram({WfStyle style = WfStyle.clean}) =>
      WireframeDiagram(style: style, width: w + 8, height: h + 8, components: [
        for (final p in parts) WfComponent.tryFromJson({...p.toJson(), 'x': p.x + 4, 'y': p.y + 4})!,
      ]);
}
