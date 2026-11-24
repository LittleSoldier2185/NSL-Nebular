/// ประวัติ Undo/Redo ของข้อมูลระดับโปรเจกต์ (ความต้องการ · Use Case · ค่าตั้ง Mock) — Phase 29
///
/// เก็บสแนปช็อต (ข้อความ JSON) ของข้อมูลทั้งสามส่วนก่อนการแก้ ; ไม่เกี่ยวกับ undo ของเอกสาร (ของ `DocController`)
/// เอกสารจะเลือกว่าใช้ stack ไหนตามหน้าที่เปิดอยู่ (ดู `WorkspaceController.usesProjectHistory`)
class ProjectHistory {
  ProjectHistory({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// จำนวนขั้นสูงสุดที่เก็บ (เก่าสุดถูกทิ้ง)
  static const int maxSteps = 100;

  /// การแก้ที่มี key เดียวกันติดกันภายในช่วงนี้ถูกรวมเป็นขั้นเดียว (เช่น พิมพ์ค่าหน่วงทีละตัวเลข)
  static const Duration coalesceWindow = Duration(milliseconds: 1500);

  final DateTime Function() _now;
  final List<_Step> _undo = [];
  final List<_Step> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// ชื่อการกระทำที่จะถูกย้อน/ทำซ้ำ (null = ไม่มี)
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  /// บันทึกว่ามีการแก้ : [before] = สแนปช็อตก่อนแก้ ; ล้าง redo ; [coalesce] เหมือนขั้นบนสุดและอยู่ในช่วงเวลา = ไม่เพิ่มขั้น
  void record(String label, String before, {String? coalesce}) {
    final now = _now();
    _redo.clear();
    if (coalesce != null && _undo.isNotEmpty) {
      final top = _undo.last;
      if (top.coalesce == coalesce && now.difference(top.time) <= coalesceWindow) {
        top.time = now; // ต่ออายุ : พิมพ์ต่อเนื่องไม่ถูกตัดเป็นหลายขั้น
        return;
      }
    }
    _undo.add(_Step(label, before, now, coalesce));
    if (_undo.length > maxSteps) _undo.removeRange(0, _undo.length - maxSteps);
  }

  /// ย้อน : คืนสแนปช็อตที่ต้องกู้ ; [current] = สแนปช็อตตอนนี้ (เก็บไว้ให้ทำซ้ำ) ; ไม่มีให้ย้อน = null
  String? undo(String current) {
    if (_undo.isEmpty) return null;
    final s = _undo.removeLast();
    _redo.add(_Step(s.label, current, _now(), null));
    return s.snapshot;
  }

  /// ทำซ้ำ : คืนสแนปช็อตที่ต้องกู้ ; ไม่มี = null
  String? redo(String current) {
    if (_redo.isEmpty) return null;
    final s = _redo.removeLast();
    _undo.add(_Step(s.label, current, _now(), null));
    return s.snapshot;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}

class _Step {
  _Step(this.label, this.snapshot, this.time, this.coalesce);
  final String label;
  final String snapshot;
  DateTime time;
  final String? coalesce;
}
