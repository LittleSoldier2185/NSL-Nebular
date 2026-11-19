import 'dart:math' as math;

import 'ortho_route.dart';

/// การแก้เส้นหักมุมฉากด้วยมือ (แบบ draw.io) ใช้ร่วมกันทุกแผนภาพ — ฟังก์ชันล้วน
///
/// แนวคิด : เส้นที่แก้เองเก็บแค่ "จุดบังคับ" ได้แก่ [RoutePort] ของปลายทั้งสอง และ hints = พิกัดของช่วงกลางทุกช่วง
/// (ดู [routeFromHints]) ปลายเส้นคำนวณใหม่จากกล่องเสมอ จึงตามกล่องที่ย้ายไปเอง

/// ด้านที่เส้นออกจากต้นทาง และด้านที่เข้าปลายทาง อ่านจากเส้นทางที่วาดอยู่
(RouteSide, RouteSide) routeEndSides(List<RoutePoint> pts) {
  if (pts.length < 2) return (RouteSide.right, RouteSide.left);
  final a = pts[0], b = pts[1];
  final dx0 = b.$1 - a.$1, dy0 = b.$2 - a.$2;
  final RouteSide s0 = dx0.abs() >= dy0.abs()
      ? (dx0 >= 0 ? RouteSide.right : RouteSide.left)
      : (dy0 >= 0 ? RouteSide.bottom : RouteSide.top);
  final c = pts[pts.length - 2], d = pts.last;
  final dx1 = d.$1 - c.$1, dy1 = d.$2 - c.$2;
  final RouteSide s1 = dx1.abs() >= dy1.abs()
      ? (dx1 >= 0 ? RouteSide.left : RouteSide.right) // วิ่งไปทางขวา = เข้าด้านซ้ายของกล่อง
      : (dy1 >= 0 ? RouteSide.top : RouteSide.bottom);
  return (s0, s1);
}

/// ช่วงที่ [i] (จาก pts[i] ถึง pts[i+1]) เป็นแนวนอนหรือไม่ — ช่วงสลับแนวกันเริ่มจากแนวของด้านที่ออก
bool routeSegmentHorizontal(List<RoutePoint> pts, int i) {
  final h0 = isHorizontalSide(routeEndSides(pts).$1);
  return i.isEven ? h0 : !h0;
}

/// hints ของเส้นทางที่วาดอยู่ : พิกัดคงที่ของช่วงที่ 1..n−2 (แนวนอน = y, แนวตั้ง = x)
List<double> routeHintsOf(List<RoutePoint> pts) {
  final n = pts.length - 1;
  return [
    for (var i = 1; i <= n - 2; i++) routeSegmentHorizontal(pts, i) ? pts[i].$2 : pts[i].$1,
  ];
}

/// จุดจับของเส้นที่เลือก : ปลายต้น/ปลายทาง และกึ่งกลางของแต่ละช่วงที่ยาวพอ (ช่วงสั้นเกินไปไม่มีจุดจับ)
class RouteHandle {
  const RouteHandle.start(this.at)
      : kind = RouteHandleKind.start,
        segment = -1;
  const RouteHandle.end(this.at)
      : kind = RouteHandleKind.end,
        segment = -1;
  const RouteHandle.segment(this.segment, this.at) : kind = RouteHandleKind.segment;
  final RouteHandleKind kind;
  final int segment;
  final RoutePoint at;
}

enum RouteHandleKind { start, end, segment }

List<RouteHandle> routeHandles(List<RoutePoint> pts, {double minSegment = 18}) {
  if (pts.length < 2) return const [];
  final out = <RouteHandle>[RouteHandle.start(pts.first), RouteHandle.end(pts.last)];
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    if ((a.$1 - b.$1).abs() + (a.$2 - b.$2).abs() >= minSegment) {
      out.add(RouteHandle.segment(i, ((a.$1 + b.$1) / 2, (a.$2 + b.$2) / 2)));
    }
  }
  return out;
}

/// จุดจับของ [pts] ที่ใกล้ [p] ภายใน [tol] (ปลายมาก่อนกลางช่วง) ; ไม่มี = null
RouteHandle? routeHandleAt(List<RoutePoint> pts, RoutePoint p, double tol) {
  RouteHandle? best;
  var bestD = tol;
  for (final h in routeHandles(pts)) {
    final d = math.sqrt(math.pow(h.at.$1 - p.$1, 2) + math.pow(h.at.$2 - p.$2, 2));
    // ปลายเส้นชนะช่วงกลางถ้าเกือบเท่ากัน
    final bias = h.kind == RouteHandleKind.segment ? 0.0 : 2.0;
    if (d - bias <= bestD) {
      bestD = d - bias;
      best = h;
    }
  }
  return best;
}

/// hints ใหม่เมื่อลากช่วงที่ [segment] ของเส้น [pts] ไปที่พิกัด [c] (ช่วงแนวนอน = y, แนวตั้ง = x)
///
/// ช่วงกลาง = เลื่อนช่วงนั้น ; ช่วงที่ติดกล่อง (ช่วงแรก/สุดท้าย) = แตกเป็นช่วงสั้น ๆ ออกจากกล่องแล้วเบี่ยงไปที่ [c]
/// (เส้นตรงช่วงเดียวถูกเบี่ยงทั้งสองปลาย) — ผลยังไม่ผ่าน [normalizeRouteHints]
List<double> dragRouteSegment(List<RoutePoint> pts, int segment, double c) {
  final n = pts.length - 1;
  final (s0, s1) = routeEndSides(pts);
  final h0 = isHorizontalSide(s0), h1 = isHorizontalSide(s1);
  final o0 = routeSideSign(s0), o1 = routeSideSign(s1);
  final p0 = pts.first, p1 = pts.last;
  final a0 = h0 ? p0.$1 : p0.$2, a1 = h1 ? p1.$1 : p1.$2;
  final old = routeHintsOf(pts);
  const stub = 20.0;
  if (n <= 1) {
    final st = math.min(stub, (a1 - a0).abs() / 3);
    return [a0 + o0 * st, c, a1 + o1 * st];
  }
  if (segment <= 0) return [a0 + o0 * stub, c, ...old];
  if (segment >= n - 1) return [...old, c, a1 + o1 * stub];
  return [...old]..[segment - 1] = c;
}

/// รวมช่วงที่ซ้อนเป็นแนวเดียวกัน (ช่วงที่ยาว 0) ออกจาก hints : [cFirst]/[cLast] = พิกัดคงที่ของช่วงแรก/ช่วงสุดท้าย
/// จำนวนที่ตัดทิ้งเป็นคู่เสมอ จึงยังตรงกับแนวของด้านที่ออก/เข้า
List<double> normalizeRouteHints(List<double> hints, double cFirst, double cLast, {double eps = 1}) {
  final c = [cFirst, ...hints, cLast];
  var changed = true;
  while (changed && c.length > 2) {
    changed = false;
    for (var i = 1; i <= c.length - 2; i++) {
      if ((c[i - 1] - c[i + 1]).abs() >= eps) continue;
      if (c.length == 3) return const []; // ตรงเป็นเส้นเดียว
      if (i + 1 <= c.length - 2) {
        c
          ..removeAt(i + 1)
          ..removeAt(i);
      } else {
        c
          ..removeAt(i)
          ..removeAt(i - 1);
      }
      changed = true;
      break;
    }
  }
  return c.sublist(1, c.length - 1);
}

/// จุดต่อบนขอบกล่อง [b] ที่ใกล้จุด [p] ที่สุด (ด้าน + สัดส่วนตามขอบ ปัดเข้ากลางด้านถ้าใกล้) — ใช้ตอนลากปลายเส้นมาวาง
RoutePort nearestRoutePort(RouteBox b, RoutePoint p) {
  double distToSeg(double ax, double ay, double bx, double by) {
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((p.$1 - ax) * dx + (p.$2 - ay) * dy) / len2).clamp(0.0, 1.0);
    final qx = ax + t * dx - p.$1, qy = ay + t * dy - p.$2;
    return math.sqrt(qx * qx + qy * qy);
  }

  final cand = <(RouteSide, double)>[
    (RouteSide.left, distToSeg(b.x, b.y, b.x, b.bottom)),
    (RouteSide.right, distToSeg(b.right, b.y, b.right, b.bottom)),
    (RouteSide.top, distToSeg(b.x, b.y, b.right, b.y)),
    (RouteSide.bottom, distToSeg(b.x, b.bottom, b.right, b.bottom)),
  ];
  var best = cand.first;
  for (final c in cand) {
    if (c.$2 < best.$2 - 1e-9) best = c;
  }
  final side = best.$1;
  var t = isHorizontalSide(side) ? (p.$2 - b.y) / b.h : (p.$1 - b.x) / b.w;
  final lo = math.min(0.5, b.inset / (isHorizontalSide(side) ? b.h : b.w));
  t = t.clamp(lo, 1 - lo);
  if ((t - 0.5).abs() < 0.04) t = 0.5;
  return RoutePort(side, (t * 100).roundToDouble() / 100);
}

// ---- JSON (ใช้ร่วมกันทุกแผนภาพ) ----

Map<String, dynamic> routePortToJson(RoutePort p) => {'s': p.side.name, 't': p.t};

RoutePort? routePortFromJson(Object? j) {
  if (j is! Map) return null;
  final side = RouteSide.values.where((s) => s.name == j['s']).firstOrNull;
  final t = j['t'];
  if (side == null || t is! num || !t.isFinite) return null;
  return RoutePort(side, t.toDouble().clamp(0.0, 1.0));
}

/// hints จาก JSON : ตัวเลขจำกัดค่าเท่านั้น ไม่เกิน 40 ช่วง ; ว่าง/ผิดรูป = null
List<double>? routeHintsFromJson(Object? j) {
  if (j is! List) return null;
  final out = <double>[for (final v in j) if (v is num && v.isFinite) v.toDouble()];
  if (out.isEmpty || out.length != j.length || out.length > 40) return null;
  return out;
}

// ---- เส้นที่แก้ได้ (ใช้ร่วมกันทุกแผนภาพ) ----

/// เส้นเชื่อมที่ผู้ใช้ลากแก้ได้ : ปลายต่อกล่อง [fromId]→[toId], จุดต่อ [exit]/[entry], ช่วงกลาง [hints], ป้าย [labelDx]/[labelDy]
abstract interface class RouteEditable {
  String get fromId;
  set fromId(String v);
  String get toId;
  set toId(String v);
  RoutePort? get exit;
  set exit(RoutePort? v);
  RoutePort? get entry;
  set entry(RoutePort? v);
  List<double>? get hints;
  set hints(List<double>? v);
  double get labelDx;
  set labelDx(double v);
  double get labelDy;
  set labelDy(double v);
}

bool routeEditableIsManual(RouteEditable e) => e.exit != null || e.entry != null || (e.hints?.isNotEmpty ?? false);

/// ล้างเส้นที่ลากเอง (จุดต่อ + ช่วงกลาง) กลับเป็นอัตโนมัติ ; ตำแหน่งป้ายไม่แตะ
void routeEditableReset(RouteEditable e) {
  e.exit = null;
  e.entry = null;
  e.hints = null;
}

/// เขียนค่าที่แก้เองลง JSON (เฉพาะที่มีค่า)
void writeRouteJson(RouteEditable e, Map<String, dynamic> j) {
  if (e.exit != null) j['exit'] = routePortToJson(e.exit!);
  if (e.entry != null) j['entry'] = routePortToJson(e.entry!);
  if (e.hints != null && e.hints!.isNotEmpty) j['bends'] = e.hints;
  if (e.labelDx != 0 || e.labelDy != 0) j['lbl'] = [e.labelDx, e.labelDy];
}

/// อ่านค่าที่แก้เองจาก JSON (ค่าผิดรูปข้ามไป)
void readRouteJson(RouteEditable e, Map j) {
  e.exit = routePortFromJson(j['exit']);
  e.entry = routePortFromJson(j['entry']);
  e.hints = routeHintsFromJson(j['bends']);
  final l = j['lbl'];
  double fin(Object? v) => v is num && v.isFinite ? v.toDouble() : 0;
  if (l is List && l.length == 2) {
    e.labelDx = fin(l[0]);
    e.labelDy = fin(l[1]);
  }
}

/// การลากจุดจับของเส้น 1 ครั้ง (ตั้งแต่กดจนปล่อย) — ไม่ผูกกับแผนภาพใด ตัว controller เรียก [update] ในช่วงแก้สด
/// แล้วเรียก [finish] ตอนปล่อย ; ผลทั้งหมดเขียนลง [edge] โดยตรง
class RouteDragSession {
  RouteDragSession(this.handle, this.edge, this.route)
      : _from = edge.fromId,
        _to = edge.toId,
        _exit = edge.exit,
        _entry = edge.entry,
        _hints = edge.hints == null ? null : [...edge.hints!];

  final RouteHandle handle;
  final RouteEditable edge;

  /// เส้นทางตอนเริ่มลาก
  final List<RoutePoint> route;
  final String _from, _to;
  final RoutePort? _exit, _entry;
  final List<double>? _hints;

  /// กล่อง/จุดต่อที่ปลายเส้นกำลังจะไปวาง (null = ไม่ได้ลากปลาย หรืออยู่นอกกล่อง)
  String? dropNode;
  RoutePort? dropPort;

  /// ลากไปที่ [world] — ช่วงกลาง: เลื่อนช่วง (ดูดเข้า [grid] และเข้าแนวปลายทั้งสอง) ; ปลาย: ต่อกล่องที่อยู่ใต้เมาส์
  /// [nodeIdAt]/[boxOf] ให้ผู้เรียกบอกว่ากล่องไหนอยู่ที่จุดนั้น/ขอบเขตของกล่อง ; [scale] ใช้แปลงระยะดูดจากพิกเซลจอ
  void update(
    RoutePoint world, {
    double? grid,
    required double scale,
    required String? Function(double x, double y) nodeIdAt,
    required RouteBox? Function(String id) boxOf,
  }) {
    switch (handle.kind) {
      case RouteHandleKind.segment:
        final horizontal = routeSegmentHorizontal(route, handle.segment);
        var c = horizontal ? world.$2 : world.$1;
        if (grid != null) c = (c / grid).round() * grid;
        for (final p in [route.first, route.last]) {
          final pc = horizontal ? p.$2 : p.$1;
          if ((pc - c).abs() < 6 / scale) c = pc;
        }
        edge.hints = dragRouteSegment(route, handle.segment, c);
      case RouteHandleKind.start || RouteHandleKind.end:
        final isStart = handle.kind == RouteHandleKind.start;
        final id = nodeIdAt(world.$1, world.$2);
        final box = id == null ? null : boxOf(id);
        final other = isStart ? _to : _from;
        if (id == null || box == null || id == other) {
          dropNode = null;
          dropPort = null;
          edge
            ..fromId = _from
            ..toId = _to
            ..exit = _exit
            ..entry = _entry
            ..hints = _hints;
          return;
        }
        final port = nearestRoutePort(box, world);
        dropNode = id;
        dropPort = port;
        if (isStart) {
          edge
            ..fromId = id
            ..exit = port
            ..entry = _entry;
        } else {
          edge
            ..toId = id
            ..entry = port
            ..exit = _exit;
        }
        edge.hints = null; // ต่อปลายใหม่แล้ว เส้นกลางจัดใหม่
    }
  }

  /// ปล่อยเมาส์ : ช่วงกลาง = เก็บค่าที่ถูกดันเข้าแนวแล้วและรวมช่วงที่ซ้อนกัน ([currentRoute] = เส้นทางที่วาดอยู่ตอนนี้)
  void finish(List<RoutePoint>? currentRoute) {
    dropNode = null;
    dropPort = null;
    if (handle.kind != RouteHandleKind.segment || currentRoute == null || currentRoute.length < 2) return;
    final (s0, s1) = routeEndSides(currentRoute);
    final p0 = currentRoute.first, p1 = currentRoute.last;
    final h = normalizeRouteHints(
      routeHintsOf(currentRoute),
      isHorizontalSide(s0) ? p0.$2 : p0.$1,
      isHorizontalSide(s1) ? p1.$2 : p1.$1,
    );
    edge.hints = h.isEmpty ? null : h;
  }
}

/// จุดกึ่งกลางป้ายชื่อของเส้นที่แก้ได้ [e] = กึ่งกลางช่วงที่ยาวที่สุดของ [pts] + ระยะที่ผู้ใช้ลากป้าย
RoutePoint routeLabelPoint(List<RoutePoint> pts, RouteEditable e) {
  final (ax, ay) = routeLabelAnchor(pts);
  return (ax + e.labelDx, ay + e.labelDy);
}
