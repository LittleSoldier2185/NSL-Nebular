import 'package:flutter/material.dart';

import '../core/layout/ortho_route.dart';
import '../core/layout/route_edit.dart';
import 'doc_controller.dart';

/// การลากแก้เส้นเชื่อมด้วยมือ (แบบ draw.io) ที่ controller ของแผนภาพทุกชนิดใช้ร่วมกัน :
/// ลากกลางช่วง / ลากปลายไปต่อกล่องหรือด้านอื่น / ลากป้ายชื่อ / รีเซ็ต — ทุกการลากเป็น undo ขั้นเดียว
///
/// controller ที่ใช้ต้องบอก 6 อย่างผ่าน hook ด้านล่าง (เส้นที่เลือก, เส้นทางที่วาดอยู่, กล่องที่จุดนั้น, ฯลฯ)
mixin RouteEditing on DocController {
  // ---- hook ที่ controller ต้องให้ ----

  /// เส้นตาม id ; ไม่มี = null
  RouteEditable? routeEdgeById(String id);

  /// เส้นที่เลือกอยู่ (เลือกเส้นเดียว)
  RouteEditable? get routeSelectedEdge;

  /// เส้นทางที่วาดอยู่ของทุกเส้น (key = id)
  Map<String, List<RoutePoint>> routeRoutes();

  /// id ของกล่องที่อยู่ที่จุด (พิกัดแผนภาพ) ; ไม่มี = null
  String? routeNodeAt(double x, double y);

  /// ขอบเขตของกล่อง (ใช้หาจุดต่อบนขอบ)
  RouteBox? routeBoxOf(String id);

  /// แก้สดระหว่างลาก (ต้องอยู่ในช่วง beginGesture/endGesture)
  void routeLive(void Function() change);

  /// แก้เส้น [id] แบบมีประวัติ (undo ขั้นเดียว)
  void routeEditEdge(String id, void Function(RouteEditable e) change);

  double get scale;

  // ---- สถานะการลาก ----

  RouteDragSession? _routeDrag;
  String? _routeDragEdge;

  /// กล่อง/จุดต่อที่ปลายเส้นที่กำลังลากจะไปวาง (ให้ตัววาดไฮไลต์) ; null = ไม่ได้ลากปลายเส้น
  String? get dropNodeId => _routeDrag?.dropNode;
  RoutePort? get dropPort => _routeDrag?.dropPort;

  bool get draggingEdgeHandle => _routeDrag != null;

  /// จุดจับของเส้นที่เลือก ณ [world] (รัศมี [tolPx] พิกเซลจอ) ; ไม่ได้เลือกเส้น/ไม่โดน = null
  RouteHandle? edgeHandleAt(Offset world, {double tolPx = 8}) {
    final e = routeSelectedEdge;
    if (e == null) return null;
    final r = routeRoutes()[routeEdgeIdOf(e)];
    return r == null ? null : routeHandleAt(r, (world.dx, world.dy), tolPx / scale);
  }

  /// id ของเส้นจากตัวเส้นเอง
  String routeEdgeIdOf(RouteEditable e);

  void beginEdgeHandle(RouteHandle h) {
    final e = routeSelectedEdge;
    if (e == null) return;
    final id = routeEdgeIdOf(e);
    final r = routeRoutes()[id];
    if (r == null) return;
    beginGesture();
    _routeDrag = RouteDragSession(h, e, r);
    _routeDragEdge = id;
  }

  /// ลากจุดจับไปที่ [world] — ช่วงกลาง: เลื่อนช่วงนั้น ; ปลายเส้น: ย้ายไปต่อกล่อง/ด้านอื่น (วางนอกกล่อง = ไม่เปลี่ยน)
  void edgeHandleTo(Offset world, {double? grid}) {
    final s = _routeDrag;
    if (s == null) return;
    routeLive(() => s.update(
          (world.dx, world.dy),
          grid: grid,
          scale: scale,
          nodeIdAt: routeNodeAt,
          boxOf: routeBoxOf,
        ));
  }

  void endEdgeHandle() {
    final s = _routeDrag, id = _routeDragEdge;
    if (s == null || id == null) return;
    routeLive(() => s.finish(routeRoutes()[id]));
    _routeDrag = null;
    _routeDragEdge = null;
    endGesture();
  }

  /// ลากป้ายชื่อของเส้น (undo ขั้นเดียวต่อการลาก)
  void beginEdgeLabelDrag() => beginGesture();

  void edgeLabelDragBy(String id, double dx, double dy) => routeLive(() {
        final e = routeEdgeById(id);
        if (e == null) return;
        e
          ..labelDx += dx
          ..labelDy += dy;
      });

  void endEdgeLabelDrag() => endGesture();

  /// ล้างเส้นที่ลากเอง (กลับเป็นอัตโนมัติ)
  void resetEdgeRoute(String id) {
    final e = routeEdgeById(id);
    if (e == null || !routeEditableIsManual(e)) return;
    routeEditEdge(id, routeEditableReset);
  }

  /// ย้ายป้ายชื่อกลับตำแหน่งปกติ
  void resetEdgeLabelPosition(String id) {
    final e = routeEdgeById(id);
    if (e == null || (e.labelDx == 0 && e.labelDy == 0)) return;
    routeEditEdge(id, (e) {
      e.labelDx = 0;
      e.labelDy = 0;
    });
  }
}
