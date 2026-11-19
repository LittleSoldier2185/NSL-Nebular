import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/layout/box_ops.dart';
import '../core/layout/dfd_resize.dart' show DfdHandle, dfdHandleAtRect, resizeDfdRect;
import '../core/layout/diagram_geometry.dart' show snapToGrid;
import '../core/models/workspace.dart';
import 'diagram_viewport.dart';
import 'doc_controller.dart';
import 'workspace_controller.dart';

/// ฐานร่วมของ controller เอกสารแบบ "กล่องบนแคนวาส" (Wireframe, Screen Flow): เนื้อหา [C] ที่มีรายการกล่อง [B]
/// + ประวัติ undo/redo + สถานะหน้าจอ (การเลือก ข้อความที่กำลังพิมพ์ ลากย้าย ปรับขนาด จัดแนว มุมมอง)
///
/// ชนิดย่อยบอกว่าเนื้อหาแปลงเป็น/จาก JSON อย่างไร และกล่องอยู่ที่ไหน — ส่วนที่เหลือ (เลือก/ย้าย/จัดแนว/ลำดับการซ้อน)
/// ทำงานเหมือนกันทุกชนิด ; สถานะหน้าจอแยกต่อแท็บ ไม่ถูกบันทึกในไฟล์
abstract class BoxDiagramController<C extends DocContent, B extends EditableBox> extends DocController with DiagramViewport {
  BoxDiagramController(super.doc, this.workspace);

  final WorkspaceController workspace;

  /// เอกสารนี้ยังอยู่ในโปรเจกต์ (ตัวแทน/เอกสารที่ถูกลบ = false แก้ไขไม่ได้)
  bool get active => !disposed && identical(workspace.documentById(docId), doc);

  /// เนื้อหาปัจจุบัน
  C get content => doc.content as C;

  /// เนื้อหา -> JSON / JSON -> เนื้อหาใหม่ (ซ่อมค่าผิดปกติ)
  @protected
  Object? encodeContent(C c);
  @protected
  C decodeContent(Object? j);

  /// กล่องทั้งหมดของ [c] ตามลำดับการซ้อน (ท้ายรายการอยู่บนสุด)
  @protected
  List<B> boxesOf(C c);

  /// ขนาดต่ำสุด/สูงสุดของกล่องตอนปรับขนาด
  @protected
  double get minSide;
  @protected
  double get maxSide;

  List<B> get boxes => boxesOf(content);

  B? boxById(String id) {
    for (final b in boxes) {
      if (b.id == id) return b;
    }
    return null;
  }

  B? _boxIn(C c, String id) {
    for (final b in boxesOf(c)) {
      if (b.id == id) return b;
    }
    return null;
  }

  @override
  @protected
  String snapshot() => jsonEncode(encodeContent(content));

  @override
  @protected
  void restoreSnapshot(String snap) => doc.content = decodeContent(jsonDecode(snap));

  @override
  @protected
  void afterRestore() => prune();

  /// แก้เนื้อหาแบบมีประวัติ (undo ขั้นเดียว) — เอกสารที่ไม่อยู่ในโปรเจกต์แล้วแก้ไม่ได้
  @protected
  void edit(void Function(C c) change) {
    if (!active) return;
    editWithHistory(() => change(content));
  }

  /// แก้สดระหว่างลาก (ยังไม่เข้าประวัติ — ปิดด้วย [endGesture])
  @protected
  void live(void Function(C c) change) {
    if (!active) return;
    change(content);
    markLive();
    notifyListeners();
  }

  /// แก้แบบมีประวัติเฉพาะเมื่อเนื้อหาเปลี่ยนจริง (ลองกับสำเนาก่อน — ไม่ให้มี Ctrl+Z ว่าง ๆ) ; คืน true ถ้าเปลี่ยน
  @protected
  bool editIfChanged(void Function(C c) change) {
    if (!active) return false;
    final before = snapshot();
    final probe = decodeContent(jsonDecode(before));
    change(probe);
    if (jsonEncode(encodeContent(probe)) == before) return false;
    edit(change);
    return true;
  }

  @override
  void beginGesture() {
    if (!active) return;
    super.beginGesture();
  }

  // ---------- ล็อก / ซ่อน / กลุ่ม / หมุน (ชนิดย่อยเปิดใช้เอง) ----------

  /// กล่องที่ล็อก: คลิก/ลากเลือกบนแคนวาสไม่โดน ย้าย/ปรับขนาด/หมุน/ลบ/จัดแนวไม่ได้ (ยังเลือกได้จากแผงเลเยอร์)
  bool isLocked(B b) => false;

  /// เลือกได้ด้วยการคลิก/ลากกรอบ/Ctrl+A บนแคนวาส (ค่าเริ่มต้น = ไม่ล็อก)
  bool selectableOnCanvas(B b) => !isLocked(b);

  /// กล่องทั้งหมดที่ถูกเลือกพร้อมกันเมื่อเลือก [id] (กลุ่ม) — ค่าเริ่มต้น = ตัวมันเอง
  @protected
  Set<String> withGroup(String id) => {id};

  /// มุมหมุน (องศา) ของกล่อง — ชนิดที่ไม่รองรับการหมุน = 0
  double rotationOf(B b) => 0;

  /// ตั้งมุมหมุน (เรียกภายใน [edit]/[live] เท่านั้น)
  @protected
  void setRotationOf(B b, double degrees) {}

  /// ชนิดนี้หมุนกล่องได้
  bool get canRotate => false;

  /// ระยะจุดจับหมุนเหนือขอบบน (พิกเซลจอ)
  double get rotateHandleGap => 26;

  bool _unlocked(String id) {
    final b = boxById(id);
    return b != null && !isLocked(b);
  }

  /// [p] (พิกัดแผนภาพ) -> พิกัดของกล่อง [b] ก่อนหมุน
  Offset toBoxLocal(B b, Offset p) {
    final r = rotationOf(b);
    if (r == 0) return p;
    final c = Offset(b.x + b.w / 2, b.y + b.h / 2);
    final a = -r * math.pi / 180;
    final d = p - c;
    return c + Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a));
  }

  static Offset _rotate(Offset v, double degrees) {
    final a = degrees * math.pi / 180;
    return Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
  }

  /// ตำแหน่งจุดจับหมุนของกล่อง [b] (พิกัดแผนภาพ)
  Offset rotateHandlePos(B b) {
    final c = Offset(b.x + b.w / 2, b.y + b.h / 2);
    return c + _rotate(Offset(0, -b.h / 2 - rotateHandleGap / scale), rotationOf(b));
  }

  /// [world] ชี้ที่จุดจับหมุนของกล่องที่เลือกอยู่ใบเดียว
  bool rotateHandleAt(Offset world, {double tolPx = 9}) {
    final b = selectedBox;
    if (!canRotate || b == null || isLocked(b)) return false;
    return (world - rotateHandlePos(b)).distance <= tolPx / scale;
  }

  String? _rotId;

  void beginRotate() {
    final b = selectedBox;
    if (!canRotate || b == null || isLocked(b)) return;
    beginGesture();
    _rotId = b.id;
  }

  /// หมุนให้จุดจับชี้ไปที่ [world] ; [snap] = ปัดทีละ 15 องศา
  void rotateToward(Offset world, {bool snap = false}) {
    final id = _rotId;
    final b = id == null ? null : boxById(id);
    if (b == null) return;
    final c = Offset(b.x + b.w / 2, b.y + b.h / 2);
    var deg = math.atan2(world.dy - c.dy, world.dx - c.dx) * 180 / math.pi + 90;
    if (snap) deg = (deg / 15).round() * 15.0;
    live((content) {
      final x = _boxIn(content, id!);
      if (x != null) setRotationOf(x, deg);
    });
  }

  void endRotate() {
    _rotId = null;
    endGesture();
  }

  /// ตั้งมุมหมุนของกล่อง [ids] (ข้ามที่ล็อก) — undo ขั้นเดียว ; [relative] = บวกเพิ่มจากมุมเดิม
  void setRotation(Iterable<String> ids, double degrees, {bool relative = false}) {
    if (!canRotate) return;
    final set = {for (final id in ids) if (_unlocked(id)) id};
    if (set.isEmpty) return;
    editIfChanged((c) {
      for (final b in boxesOf(c)) {
        if (set.contains(b.id)) setRotationOf(b, relative ? rotationOf(b) + degrees : degrees);
      }
    });
  }

  // ---------- การเลือก ----------

  final Set<String> _sel = {};

  Set<String> get selectedIds => Set.unmodifiable(_sel);
  B? get selectedBox => _sel.length == 1 ? boxById(_sel.first) : null;
  List<B> get selectedBoxes => [for (final b in boxes) if (_sel.contains(b.id)) b];

  /// ล้างการเลือกอื่นนอกจากกล่อง (เช่น เส้น) — คืน true ถ้ามีอะไรเปลี่ยน
  @protected
  bool clearOtherSelection() => false;

  /// มีอะไรเลือกนอกจากกล่อง
  @protected
  bool get hasOtherSelection => false;

  void clearSelection() {
    final other = clearOtherSelection();
    if (_sel.isEmpty && !other) return;
    _sel.clear();
    notifyListeners();
  }

  /// เลือกกล่อง [id] (อยู่ในกลุ่ม = เลือกทั้งกลุ่ม เว้นแต่ [exact]) ; [add] = สลับเข้า/ออกจากที่เลือกอยู่
  void selectBox(String id, {bool add = false, bool exact = false}) {
    if (boxById(id) == null) return;
    clearOtherSelection();
    final members = exact ? {id} : withGroup(id);
    if (add) {
      if (_sel.contains(id)) {
        _sel.removeAll(members);
      } else {
        _sel.addAll(members);
      }
    } else {
      _sel
        ..clear()
        ..addAll(members);
    }
    notifyListeners();
  }

  /// เลือกกล่อง [ids] (สมาชิกกลุ่มของแต่ละใบถูกเลือกด้วย เว้นแต่ [exact])
  void setSelection(Iterable<String> ids, {bool exact = false}) {
    final next = {
      for (final id in ids)
        if (boxById(id) != null) ...(exact ? {id} : withGroup(id)),
    };
    if (next.length == _sel.length && next.containsAll(_sel) && !hasOtherSelection) return;
    clearOtherSelection();
    _sel
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// Ctrl+A: เลือกทุกกล่องที่เลือกได้บนแคนวาส (ไม่รวมที่ล็อก/ซ่อน)
  void selectAll() {
    clearOtherSelection();
    _sel
      ..clear()
      ..addAll([for (final b in boxes) if (selectableOnCanvas(b)) b.id]);
    notifyListeners();
  }

  /// กล่องที่กรอบลากเลือก [r] (พิกัดแผนภาพ) แตะ — เฉพาะที่เลือกได้บนแคนวาส
  Set<String> marqueeHits(Rect r) => {
        for (final b in boxes)
          if (selectableOnCanvas(b) && r.overlaps(boundsOf(b))) b.id,
      };

  /// กรอบตั้งฉากที่ครอบกล่อง [b] หลังหมุน
  Rect boundsOf(B b) {
    final r = rotationOf(b);
    if (r == 0) return Rect.fromLTWH(b.x, b.y, b.w, b.h);
    final a = r * math.pi / 180;
    final hw = (b.w / 2 * math.cos(a)).abs() + (b.h / 2 * math.sin(a)).abs();
    final hh = (b.w / 2 * math.sin(a)).abs() + (b.h / 2 * math.cos(a)).abs();
    return Rect.fromCenter(center: Offset(b.x + b.w / 2, b.y + b.h / 2), width: hw * 2, height: hh * 2);
  }

  /// ล้างการเลือกกล่องเงียบ ๆ (ให้ชนิดย่อยใช้ตอนเลือกอย่างอื่น)
  @protected
  void dropBoxSelection() => _sel.clear();

  /// ตัดสิ่งที่ไม่มีแล้วออกจากการเลือก/การพิมพ์ (หลัง undo/redo)
  @protected
  void prune() {
    _sel.removeWhere((id) => boxById(id) == null);
    final e = _editing;
    if (e != null && !editTargetExists(e)) _editing = null;
  }

  // ---------- พิมพ์ข้อความบนแคนวาส ----------

  ({String id, bool isEdge})? _editing;

  /// กล่อง/เส้นที่กำลังพิมพ์ข้อความบนแคนวาส (null = ไม่ได้แก้)
  ({String id, bool isEdge})? get editing => _editing;

  @protected
  bool editTargetExists(({String id, bool isEdge}) t) => !t.isEdge && boxById(t.id) != null;

  /// ใส่ข้อความที่พิมพ์เสร็จ (undo ขั้นเดียว ; ไม่เปลี่ยน = ไม่เข้าประวัติ)
  @protected
  void applyEditedText(({String id, bool isEdge}) t, String text);

  void beginEdit(String id, {bool isEdge = false}) {
    final t = (id: id, isEdge: isEdge);
    if (!active || !editTargetExists(t)) return;
    if (!isEdge) {
      clearOtherSelection();
      _sel
        ..clear()
        ..add(id);
    }
    _editing = t;
    notifyListeners();
  }

  void commitEditing(String text) {
    final e = _editing;
    _editing = null;
    if (e == null) return;
    applyEditedText(e, text);
    notifyListeners();
  }

  void cancelEditing() {
    if (_editing == null) return;
    _editing = null;
    notifyListeners();
  }

  /// Esc ขณะพิมพ์ = ยกเลิก ; คืน true ถ้าใช้ไป
  @protected
  bool escapeEditing() {
    if (_editing == null) return false;
    cancelEditing();
    return true;
  }

  // ---------- ลบ ----------

  /// ลบกล่อง [ids] ออกจาก [c] (ชนิดย่อยลบของที่เกี่ยวข้องด้วย เช่น เส้น/ลูก)
  @protected
  void removeBoxes(C c, Set<String> ids);

  /// ลบกล่องที่เลือก — คืนจำนวนที่ลบ
  int deleteSelectedBoxes() {
    final ids = _sel.where(_unlocked).toSet();
    if (ids.isEmpty) return 0;
    edit((c) => removeBoxes(c, ids));
    _sel.removeAll(ids);
    notifyListeners();
    return ids.length;
  }

  // ---------- ย้าย / ขยับ ----------

  /// กล่องที่ย้ายตามเมื่อย้ายกล่อง [ids] (ค่าเริ่มต้น = ตัวเอง ; Wireframe เพิ่มลูกในภาชนะ)
  @protected
  Set<String> moveSet(Set<String> ids) => ids;

  Map<String, (double, double)>? _origin;
  double _rawDx = 0, _rawDy = 0;
  String? _anchor;

  /// กล่องที่ย้ายจริงเมื่อย้ายที่เลือกอยู่ (รวมที่ย้ายตาม ไม่รวมที่ล็อก)
  Set<String> _movingIds() => moveSet({for (final b in selectedBoxes) if (!isLocked(b)) b.id}).where(_unlocked).toSet();

  void beginMove() {
    beginGesture();
    final ids = _movingIds();
    _origin = {for (final b in boxes) if (ids.contains(b.id)) b.id: (b.x, b.y)};
    _anchor = selectedBoxes.firstOrNull?.id;
    _rawDx = 0;
    _rawDy = 0;
  }

  /// ย้ายกล่องที่เลือกแบบสด ([grid] != null = ปัดเข้าช่องตามกล่องแรกที่เลือก ทุกชิ้นเลื่อนเท่ากัน)
  void moveBy(double dx, double dy, {double? grid}) {
    final o = _origin;
    if (o == null || o.isEmpty) return;
    _rawDx += dx;
    _rawDy += dy;
    var sx = _rawDx, sy = _rawDy;
    if (grid != null) {
      final ref = o[_anchor] ?? o.values.first;
      sx = snapToGrid(ref.$1 + _rawDx, grid) - ref.$1;
      sy = snapToGrid(ref.$2 + _rawDy, grid) - ref.$2;
    }
    live((c) {
      for (final e in o.entries) {
        final b = _boxIn(c, e.key);
        if (b == null) continue;
        b.x = (e.value.$1 + sx).clamp(-19600, 19600).toDouble();
        b.y = (e.value.$2 + sy).clamp(-19600, 19600).toDouble();
      }
    });
  }

  void endMove() {
    _origin = null;
    endGesture();
  }

  /// ขยับกล่องที่เลือก (และที่ย้ายตาม) ด้วยปุ่มลูกศร (undo ต่อการกด)
  bool nudge(double dx, double dy) {
    final ids = _movingIds();
    if (ids.isEmpty) return false;
    edit((c) {
      for (final b in boxesOf(c)) {
        if (!ids.contains(b.id)) continue;
        b.x += dx;
        b.y += dy;
      }
    });
    return true;
  }

  // ---------- ปรับขนาด ----------

  String? _resizeId;
  DfdHandle? _resizeHandle;
  Rect? _resizeStart;
  double _resizeDx = 0, _resizeDy = 0;

  /// จุดจับของกล่องที่เลือกอยู่ใบเดียวที่ [world] ชี้อยู่ ; รัศมีเป็นพิกเซลจอ
  DfdHandle? handleAt(Offset world, {double tolPx = 8}) {
    final b = selectedBox;
    if (b == null || isLocked(b)) return null;
    return dfdHandleAtRect(Rect.fromLTWH(b.x, b.y, b.w, b.h), toBoxLocal(b, world), tolPx / scale);
  }

  double _resizeAngle = 0;

  void beginResize(DfdHandle h) {
    final b = selectedBox;
    if (b == null || isLocked(b)) return;
    _resizeAngle = rotationOf(b);
    beginGesture();
    _resizeId = b.id;
    _resizeHandle = h;
    _resizeStart = Rect.fromLTWH(b.x, b.y, b.w, b.h);
    _resizeDx = 0;
    _resizeDy = 0;
  }

  void resizeBy(double dx, double dy, {double? grid}) {
    final id = _resizeId, h = _resizeHandle, r0 = _resizeStart;
    if (id == null || h == null || r0 == null) return;
    _resizeDx += dx;
    _resizeDy += dy;
    var r = resizeDfdRect(r0, h, _resizeDx, _resizeDy, grid: grid, minW: minSide, minH: minSide, maxSide: maxSide);
    if (_resizeAngle != 0) {
      // กล่องที่หมุน: ปรับขนาดในพิกัดของกล่อง แล้วเลื่อนจุดกึ่งกลางตามแนวที่หมุน (ขอบฝั่งตรงข้ามอยู่กับที่)
      final local = _rotate(Offset(_resizeDx, _resizeDy), -_resizeAngle);
      final lr = resizeDfdRect(r0, h, local.dx, local.dy, minW: minSide, minH: minSide, maxSide: maxSide);
      final center = r0.center + _rotate(lr.center - r0.center, _resizeAngle);
      r = Rect.fromCenter(center: center, width: lr.width, height: lr.height);
    }
    live((c) {
      final b = _boxIn(c, id);
      if (b == null) return;
      b
        ..x = r.left
        ..y = r.top
        ..w = r.width
        ..h = r.height;
    });
  }

  void endResize() {
    _resizeId = null;
    _resizeHandle = null;
    _resizeStart = null;
    endGesture();
  }

  // ---------- จัดแนว / กระจาย / ขนาดเท่ากัน / ลำดับการซ้อน ----------

  void _place(Map<String, (double, double)> pos) {
    if (pos.isEmpty) return;
    // กล่องที่ขยับพาลูกไปด้วยเท่ากัน
    final delta = <String, (double, double)>{};
    for (final b in boxes) {
      final p = pos[b.id];
      if (p == null || isLocked(b)) continue;
      final d = (p.$1 - b.x, p.$2 - b.y);
      for (final id in moveSet({b.id})) {
        delta.putIfAbsent(id, () => d);
      }
    }
    editIfChanged((c) {
      for (final b in boxesOf(c)) {
        final d = delta[b.id];
        if (d == null) continue;
        b.x += d.$1;
        b.y += d.$2;
      }
    });
  }

  /// จัดแนวกล่องที่เลือก (อย่างน้อย 2 ใบ) — คืน false ถ้าไม่ได้ทำ
  bool align(BoxAlign k) {
    final sel = selectedBoxes;
    if (sel.length < 2) return false;
    _place(alignBoxes(sel, k));
    return true;
  }

  /// กระจายกล่องที่เลือก (อย่างน้อย 3 ใบ) ให้ช่องว่างเท่ากัน
  bool distribute({required bool horizontal}) {
    final sel = selectedBoxes;
    if (sel.length < 3) return false;
    _place(distributeBoxes(sel, horizontal: horizontal));
    return true;
  }

  /// ให้กล่องที่เลือกกว้าง/สูงเท่ากับใบแรกที่เลือก
  bool sameSize({bool width = true, bool height = true}) {
    if (_sel.length < 2) return false;
    final ref = boxById(_sel.first);
    if (ref == null) return false;
    final ids = _sel.where(_unlocked).toSet();
    editIfChanged((c) {
      for (final b in boxesOf(c)) {
        if (!ids.contains(b.id)) continue;
        if (width) b.w = ref.w;
        if (height) b.h = ref.h;
      }
    });
    return true;
  }

  /// ยกกล่องที่เลือก (และที่ย้ายตาม) ขึ้นบนสุด ([front]) หรือลงล่างสุด — ลำดับภายในกลุ่มคงเดิม
  bool reorder({required bool front}) {
    if (selectedBoxes.isEmpty) return false;
    final ids = moveSet({for (final b in selectedBoxes) b.id});
    editIfChanged((c) {
      final list = boxesOf(c);
      final moving = [for (final b in list) if (ids.contains(b.id)) b];
      list.removeWhere((b) => ids.contains(b.id));
      if (front) {
        list.addAll(moving);
      } else {
        list.insertAll(0, moving);
      }
    });
    return true;
  }

  // ---------- มุมมอง ----------

  /// ขอบเขตของเนื้อหา (เฉพาะ [only] ถ้าระบุ) ; ว่าง = null
  @protected
  ({double left, double top, double right, double bottom})? contentBounds({Set<String>? only});

  /// ปรับให้เห็นทั้งแผนภาพ (ซูมไม่เกิน 1.2 เท่า) ; ว่าง = กลับมุมมองเริ่มต้น
  void fit(Size viewport) => fitRect(contentBounds(), viewport);

  /// ปรับให้เห็นเฉพาะที่เลือก (ไม่ได้เลือก = ทั้งแผนภาพ)
  void fitSelection(Size viewport) {
    final ids = {for (final b in selectedBoxes) b.id};
    if (ids.isEmpty) return fit(viewport);
    fitRect(contentBounds(only: ids), viewport, maxZoom: 2);
  }

  /// เลื่อนมุมมองให้กล่อง [id] อยู่กลางจอ
  void reveal(String id, Size viewport) {
    final b = boxById(id);
    if (b == null) return;
    revealPoint(Offset(b.x + b.w / 2, b.y + b.h / 2), viewport);
  }
}
