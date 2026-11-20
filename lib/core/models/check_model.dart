/// CHECK constraint ระดับตาราง (Phase 19): ชื่อ + นิพจน์ SQL ที่ทุกแถวต้องเป็นจริง เช่น `check_out > check_in`
/// นิพจน์เก็บตามที่ผู้ใช้พิมพ์ (ไม่ครอบชื่อคอลัมน์ด้วยเครื่องหมายอ้าง) — ตัวตรวจ ER เตือนเมื่ออ้างคอลัมน์ที่ไม่มี
class CheckModel {
  CheckModel({required this.id, required this.name, required this.expr});

  String id;
  String name;
  String expr;

  CheckModel copy() => CheckModel(id: id, name: name, expr: expr);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'expr': expr};

  /// อ่านจากไฟล์ — รายการเสีย (ไม่ใช่ Map / ชนิดผิด) = null เพื่อข้ามแทนที่จะพังทั้งไฟล์
  static CheckModel? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], expr = j['expr'];
    if (id is! String || id.isEmpty || name is! String || expr is! String) return null;
    return CheckModel(id: id, name: name, expr: expr);
  }
}
