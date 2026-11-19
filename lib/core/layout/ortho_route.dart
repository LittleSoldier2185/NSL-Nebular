import 'dart:math' as math;

/// เรขาคณิตของเส้นหักมุมฉากที่ใช้ร่วมกันระหว่างแผนภาพ (DFD, Flowchart, …) — ฟังก์ชันล้วน ไม่ขึ้นกับโมเดลของแผนภาพใด

typedef RoutePoint = (double x, double y);

/// กล่องที่เส้นต่อได้ (พิกัดแผนภาพ)
class RouteBox {
  const RouteBox(this.id, this.x, this.y, this.w, this.h, {this.inset = 8});
  final String id;
  final double x, y, w, h;

  /// ระยะจากมุมกล่องที่เส้นไม่ควรต่อ (กล่องมุมมนมีขอบตรงเฉพาะช่วงกลาง — ต่อที่มุมแล้วหัวลูกศรจะลอยห่างจากกล่อง)
  final double inset;
  double get cx => x + w / 2;
  double get cy => y + h / 2;
  double get right => x + w;
  double get bottom => y + h;
}

enum RouteSide { left, right, top, bottom }

bool isHorizontalSide(RouteSide s) => s == RouteSide.left || s == RouteSide.right;

/// ทิศ "ออกนอกกล่อง" ของด้าน (+1 = ไปทาง x/y เพิ่ม) : ขวา/ล่าง = +1, ซ้าย/บน = −1
int routeSideSign(RouteSide s) => (s == RouteSide.right || s == RouteSide.bottom) ? 1 : -1;

/// จุดต่อที่ผู้ใช้กำหนดบนขอบกล่อง : [side] + ตำแหน่งตามขอบ [t] (0..1 จากซ้าย→ขวา หรือ บน→ล่าง) — แบบ draw.io (exitX/entryX)
class RoutePort {
  const RoutePort(this.side, [this.t = 0.5]);
  final RouteSide side;
  final double t;

  @override
  bool operator ==(Object other) => other is RoutePort && other.side == side && other.t == t;

  @override
  int get hashCode => Object.hash(side, t);
}

/// จุดบนขอบกล่อง [b] ของ [p]
RoutePoint routePortPoint(RouteBox b, RoutePort p) {
  final len = isHorizontalSide(p.side) ? b.h : b.w;
  final lo = math.min(0.5, b.inset / len);
  final t = p.t.clamp(lo, 1 - lo);
  return switch (p.side) {
    RouteSide.left => (b.x, b.y + b.h * t),
    RouteSide.right => (b.right, b.y + b.h * t),
    RouteSide.top => (b.x + b.w * t, b.y),
    RouteSide.bottom => (b.x + b.w * t, b.bottom),
  };
}

/// เส้นหนึ่งเส้นจากกล่อง [from] ไปกล่อง [to]
///
/// ค่าที่ผู้ใช้แก้เอง (ไม่ระบุ = จัดอัตโนมัติ) : [exit]/[entry] = จุดต่อที่ปลายต้น/ปลายทาง,
/// [hints] = พิกัดของช่วงกลางทุกช่วง (ช่วงที่ 1..n−2 ; แนวนอน = y, แนวตั้ง = x) — ดู [routeFromHints]
class RouteLink {
  const RouteLink(this.id, this.from, this.to, {this.exit, this.entry, this.hints});
  final String id, from, to;
  final RoutePort? exit, entry;
  final List<double>? hints;

  bool get hasHints => hints != null && hints!.isNotEmpty;
  bool get hasManualPorts => exit != null || entry != null;
  bool get isManual => hasManualPorts || hasHints;
}

/// เส้นทางหักมุมฉากจากจุดต่อ [p0] (ออกด้าน [s0]) ไป [p1] (เข้าด้าน [s1]) ที่ช่วงกลางทุกช่วงกำหนดโดย [hints]
///
/// เส้นมี n = hints.length + 2 ช่วง วางแนวนอน/แนวตั้งสลับกัน เริ่มจากแนวของ [s0] ; ช่วงแรก/ช่วงสุดท้ายยึดกับ p0/p1
/// ช่วงอื่นใช้ค่าจาก [hints] (ช่วงที่ติดกล่องถูกดันให้ห่างขอบอย่างน้อย 12 px เพื่อให้เส้นออก/เข้าตั้งฉากกับขอบ)
/// คืน null ถ้าจำนวนช่วงขัดกับแนวของ [s0]/[s1] (n คู่ ⇔ แนวของสองด้านต่างกัน)
List<RoutePoint>? routeFromHints(RoutePoint p0, RouteSide s0, RoutePoint p1, RouteSide s1, List<double> hints) {
  final h0 = isHorizontalSide(s0), h1 = isHorizontalSide(s1);
  final n = hints.length + 2;
  if (n.isOdd != (h0 == h1)) return null;
  bool horizontalSeg(int i) => i.isEven ? h0 : !h0;

  final c = <double>[h0 ? p0.$2 : p0.$1, ...hints, h1 ? p1.$2 : p1.$1];
  const margin = 12.0;
  if (n >= 3) {
    // ช่วงที่ 1 ตั้งฉากกับช่วงแรก : ต้องอยู่นอกกล่องต้นทางอย่างน้อย margin
    final o0 = routeSideSign(s0);
    final a0 = h0 ? p0.$1 : p0.$2;
    if ((c[1] - a0) * o0 < margin) c[1] = a0 + o0 * margin;
    // ช่วงที่ n−2 ตั้งฉากกับช่วงสุดท้าย : ต้องอยู่นอกกล่องปลายทางอย่างน้อย margin
    final o1 = routeSideSign(s1);
    final a1 = h1 ? p1.$1 : p1.$2;
    if ((c[n - 2] - a1) * o1 < margin) c[n - 2] = a1 + o1 * margin;
  }
  final pts = <RoutePoint>[p0];
  for (var k = 1; k < n; k++) {
    pts.add(horizontalSeg(k - 1) ? (c[k], c[k - 1]) : (c[k - 1], c[k]));
  }
  pts.add(p1);
  return pts;
}

/// เส้นทางอัตโนมัติระหว่างจุดต่อ [p0]/[p1] บนด้าน [s0]/[s1] ใด ๆ (ใช้เมื่อผู้ใช้เลือกด้านเอง) — ตรง / ตัว L / ตัว Z / ตัว C / อ้อม
List<RoutePoint> routeBetweenSides(RoutePoint p0, RouteSide s0, RoutePoint p1, RouteSide s1) {
  const stub = 20.0;
  final h0 = isHorizontalSide(s0), h1 = isHorizontalSide(s1);
  final o0 = routeSideSign(s0), o1 = routeSideSign(s1);
  final a0 = h0 ? p0.$1 : p0.$2, q0 = h0 ? p0.$2 : p0.$1; // แกนออก / แกนขวาง ของต้นทาง
  final a1 = h1 ? p1.$1 : p1.$2, q1 = h1 ? p1.$2 : p1.$1;

  List<double> hints;
  if (h0 == h1) {
    final facing = o0 == -o1 && (a1 - a0) * o0 > 2 * stub;
    if (facing) {
      if ((q0 - q1).abs() < 0.5) return [p0, p1];
      hints = [(a0 + a1) / 2];
    } else if (o0 == o1) {
      // ออก/เข้าด้านเดียวกัน (ตัว C)
      hints = [(o0 > 0 ? math.max(a0, a1) : math.min(a0, a1)) + o0 * stub];
    } else {
      // เข้าด้านตรงข้ามแต่ปลายทางอยู่ข้างหลัง : ออก ข้ามไปกลาง กลับมาเข้า
      final qm = (q0 - q1).abs() >= 2 * stub ? (q0 + q1) / 2 : math.max(q0, q1) + 2 * stub;
      hints = [a0 + o0 * stub, qm, a1 + o1 * stub];
    }
  } else {
    // ตั้งฉากกัน : ตัว L ถ้ามุมอยู่นอกกล่องทั้งสอง ไม่งั้นอ้อมด้วย 4 ช่วง
    final corner = h0 ? (p1.$1, p0.$2) : (p0.$1, p1.$2);
    final cA0 = h0 ? corner.$1 : corner.$2; // พิกัดมุมตามแกนออกของต้นทาง
    final cA1 = h1 ? corner.$1 : corner.$2; // พิกัดมุมตามแกนเข้าของปลายทาง
    if ((cA0 - a0) * o0 >= 12 && (cA1 - a1) * o1 >= 12) return [p0, corner, p1];
    hints = [a0 + o0 * stub, (h0 ? p1.$2 : p1.$1) + o1 * stub];
  }
  return routeFromHints(p0, s0, p1, s1, hints) ?? [p0, p1];
}

/// เส้นทางหักมุมฉากของทุกเส้น (key = id): ออกด้านที่หันหาอีกกล่อง กระจายช่องตามด้านของกล่อง
/// เส้นที่ออก/เข้าด้านเดียวกันของกล่องเดียวกันถูกเรียงเป็นช่องคนละระดับ จึงไม่ซ้อนกัน
/// เส้นที่วิ่งทับกันในช่องว่างเดียวกันถูกดันห่างกัน — ลำดับของ [links] มีผลต่อการดัน (ผลลัพธ์คงที่)
/// [gutter] = ระยะห่างขั้นต่ำระหว่างขอบที่ถือว่าอยู่คนละฝั่ง, [slotGap] = ระยะระหว่างช่องบนด้านเดียวกัน
/// [preferVertical] = กล่องเฉียงกันให้ออกแนวตั้งก่อน (Flowchart บนลงล่าง) ; false = ออกตามแกนที่ห่างกว่า (DFD)
/// [avoidBoxes] = เส้นที่วิ่งทะลุกล่องอื่นจะถูกอ้อมขึ้น/ลงไปวิ่งในช่องทางเหนือ/ใต้กลุ่มกล่อง (ดู [_detourRoute])
Map<String, List<RoutePoint>> orthogonalRoutes(
  Map<String, RouteBox> boxes,
  List<RouteLink> links, {
  double gutter = 28,
  double slotGap = 18,
  bool preferVertical = false,
  bool avoidBoxes = false,
}) {
  final routes = _orthogonalRoutes(boxes, links, gutter: gutter, slotGap: slotGap, preferVertical: preferVertical);
  if (!avoidBoxes) return routes;

  final blocked = <RouteLink>[
    for (final f in links)
      if (!f.isManual)
        if (routes[f.id] case final r? when _routeHitsBox(r, boxes, f.from, f.to)) f,
  ];
  if (blocked.isEmpty) return routes;

  // จัดเส้นที่เหลือใหม่โดยไม่นับเส้นที่ต้องอ้อม (ช่องที่เคยจองไว้ให้เส้นพวกนั้นจะว่างคืน)
  final blockedIds = {for (final f in blocked) f.id};
  final result = _orthogonalRoutes(
    boxes,
    [for (final f in links) if (!blockedIds.contains(f.id)) f],
    gutter: gutter,
    slotGap: slotGap,
    preferVertical: preferVertical,
  );

  // เส้นสั้นอ้อมก่อน จะได้อยู่ช่องทางใกล้กล่อง ; เส้นยาวอยู่วงนอก
  final order = [...blocked]..sort((p, q) {
      final c = _spanX(boxes, p).compareTo(_spanX(boxes, q));
      return c != 0 ? c : p.id.compareTo(q.id);
    });
  final used = <({bool top, double lo, double hi, int lane})>[];
  final attach = <(String, bool), Set<double>>{};
  for (final f in order) {
    final a = boxes[f.from]!, b = boxes[f.to]!;
    final lo = math.min(a.cx, b.cx), hi = math.max(a.cx, b.cx);
    final spanning = [
      for (final n in boxes.values)
        if (n.right > math.min(a.x, b.x) - 8 && n.x < math.max(a.right, b.right) + 8) n
    ];
    final topY = spanning.map((n) => n.y).reduce(math.min);
    final bottomY = spanning.map((n) => n.bottom).reduce(math.max);

    // ทางจากกล่อง [n] ไปถึงช่องทางที่ [laneY] โดยไม่ชนกล่องอื่น : เส้นดิ่งจากด้านบน/ล่าง (ไล่จุดต่อจากกลางออกไปทีละ 14)
    // ถ้าด้านนั้นถูกกล่องอื่นบังหมด ให้เข้าทางด้านข้างของกล่องแทน ; ไม่มีทางโล่ง = null
    ({List<RoutePoint> path, double? x})? endPath(RouteBox n, bool top, double laneY) {
      final taken = attach.putIfAbsent((n.id, top), () => {});
      final y0 = top ? n.y : n.bottom;
      final maxOff = n.w / 2 - 10;
      for (var k = 0; k < 40; k++) {
        final off = ((k + 1) ~/ 2) * 14.0 * (k.isOdd ? 1 : -1);
        if (off.abs() > maxOff) break;
        final x = n.cx + off;
        if (taken.contains(x)) continue;
        final path = <RoutePoint>[(x, y0), (x, laneY)];
        if (!_routeHitsBox(path, boxes, n.id, n.id)) return (path: path, x: x);
      }
      for (final left in [true, false]) {
        final wall = left ? n.x : n.right;
        final sx = left ? n.x - 20 : n.right + 20;
        for (final dy in const [0.0, -12.0, 12.0, -20.0, 20.0]) {
          final y = n.cy + dy;
          if (y < n.y + 8 || y > n.bottom - 8) continue;
          if (result.values.any((r) => r.any((p) => (p.$1 - wall).abs() < 0.5 && (p.$2 - y).abs() < 10))) continue;
          final path = <RoutePoint>[(wall, y), (sx, y), (sx, laneY)];
          if (!_routeHitsBox(path, boxes, n.id, n.id)) return (path: path, x: null);
        }
      }
      return null;
    }

    int laneFor(bool top) {
      var lane = 0;
      while (used.any((u) => u.top == top && u.lane == lane && u.hi > lo - 8 && u.lo < hi + 8)) {
        lane++;
      }
      return lane;
    }

    // ไม่แก้ [attach] ที่นี่ — เทียบสองด้านก่อนแล้วค่อยจองจุดต่อของด้านที่เลือก
    ({List<RoutePoint> route, double? ax, double? bx, int lane, double cost})? tryRoute(bool top) {
      final lane = laneFor(top);
      final laneY = top ? topY - 24 - lane * 14 : bottomY + 24 + lane * 14;
      final pa = endPath(a, top, laneY), pb = endPath(b, top, laneY);
      if (pa == null || pb == null) return null;
      final route = [...pa.path, ...pb.path.reversed];
      var cost = 0.0;
      for (var i = 1; i < route.length; i++) {
        cost += (route[i].$1 - route[i - 1].$1).abs() + (route[i].$2 - route[i - 1].$2).abs();
      }
      if (pa.x == null) cost += 40; // เข้าทางด้านข้าง = รองจากเส้นดิ่งตรง
      if (pb.x == null) cost += 40;
      return (route: route, ax: pa.x, bx: pb.x, lane: lane, cost: cost);
    }

    final t = tryRoute(true), bt = tryRoute(false);
    final top = t != null && (bt == null || t.cost <= bt.cost);
    final pick = top ? t : bt;
    if (pick == null) continue; // ไม่มีทางอ้อมที่โล่ง: คงเส้นตรงเดิมไว้
    used.add((top: top, lo: lo, hi: hi, lane: pick.lane));
    if (pick.ax != null) attach[(a.id, top)]!.add(pick.ax!);
    if (pick.bx != null) attach[(b.id, top)]!.add(pick.bx!);
    result[f.id] = pick.route;
  }
  // คืนตามลำดับ links เดิม (ผลลัพธ์คงที่)
  return {for (final f in links) f.id: ?(result[f.id] ?? routes[f.id])};
}

double _spanX(Map<String, RouteBox> boxes, RouteLink f) => (boxes[f.from]!.cx - boxes[f.to]!.cx).abs();

/// เส้นทางวิ่งผ่านกล่องอื่นที่ไม่ใช่ปลายทั้งสองหรือไม่
bool _routeHitsBox(List<RoutePoint> r, Map<String, RouteBox> boxes, String from, String to) {
  for (final n in boxes.values) {
    if (n.id == from || n.id == to) continue;
    for (var i = 1; i < r.length; i++) {
      final l = math.min(r[i - 1].$1, r[i].$1), rr = math.max(r[i - 1].$1, r[i].$1);
      final t = math.min(r[i - 1].$2, r[i].$2), bb = math.max(r[i - 1].$2, r[i].$2);
      if (rr > n.x + 1 && l < n.right - 1 && bb > n.y + 1 && t < n.bottom - 1) return true;
    }
  }
  return false;
}

Map<String, List<RoutePoint>> _orthogonalRoutes(
  Map<String, RouteBox> boxes,
  List<RouteLink> links, {
  required double gutter,
  required double slotGap,
  required bool preferVertical,
}) {
  final sides = <String, (RouteSide, RouteSide)>{};
  // (boxId, side) -> [(linkId, isStart, ตำแหน่งอ้างอิงตามแนวขนานขอบ)]
  final slots = <(String, RouteSide), List<(String, bool, double)>>{};

  for (final f in links) {
    final a = boxes[f.from], b = boxes[f.to];
    if (a == null || b == null) continue;
    final auto = routeSidesFor(a, b, gutter: gutter, preferVertical: preferVertical);
    final s = (f.exit?.side ?? auto.$1, f.entry?.side ?? auto.$2);
    sides[f.id] = s;
    // จุดต่อที่ผู้ใช้กำหนดเองไม่เข้าคิวช่อง (ตำแหน่งตายตัวตามสัดส่วนของขอบ)
    if (f.exit == null) {
      slots.putIfAbsent((a.id, s.$1), () => []).add((f.id, true, isHorizontalSide(s.$1) ? b.cy : b.cx));
    }
    if (f.entry == null) {
      slots.putIfAbsent((b.id, s.$2), () => []).add((f.id, false, isHorizontalSide(s.$2) ? a.cy : a.cx));
    }
  }
  final linkById = {for (final f in links) f.id: f};

  // ตำแหน่งปลายเส้น: จุดกึ่งกลางด้าน + ระยะช่อง
  final start = <String, RoutePoint>{}, end = <String, RoutePoint>{};
  slots.forEach((key, list) {
    final n = boxes[key.$1]!;
    list.sort((p, q) {
      final c = p.$3.compareTo(q.$3);
      return c != 0 ? c : p.$1.compareTo(q.$1);
    });
    final horizontal = isHorizontalSide(key.$2);
    final extent = horizontal ? n.h : n.w;
    final gap = list.length <= 1 ? 0.0 : math.min(slotGap, (extent - 2 * n.inset) / (list.length - 1));
    for (var i = 0; i < list.length; i++) {
      final off = (i - (list.length - 1) / 2) * gap;
      final RoutePoint p = switch (key.$2) {
        RouteSide.left => (n.x, n.cy + off),
        RouteSide.right => (n.right, n.cy + off),
        RouteSide.top => (n.cx + off, n.y),
        RouteSide.bottom => (n.cx + off, n.bottom),
      };
      (list[i].$2 ? start : end)[list[i].$1] = p;
    }
  });

  for (final f in links) {
    if (!sides.containsKey(f.id)) continue;
    if (f.exit != null) start[f.id] = routePortPoint(boxes[f.from]!, f.exit!);
    if (f.entry != null) end[f.id] = routePortPoint(boxes[f.to]!, f.entry!);
  }

  List<RoutePoint> build(String id, double shift) {
    final s = sides[id]!;
    final p0 = start[id]!, p1 = end[id]!;
    final link = linkById[id]!;
    if (link.hasHints) {
      final r = routeFromHints(p0, s.$1, p1, s.$2, link.hints!);
      if (r != null) return r;
    }
    if (link.hasManualPorts) return routeBetweenSides(p0, s.$1, p1, s.$2);
    final horizontal = isHorizontalSide(s.$1);
    if (horizontal) {
      if ((p0.$2 - p1.$2).abs() < 0.5) return [p0, (p1.$1, p0.$2)];
      final mx = (p0.$1 + p1.$1) / 2 + shift;
      return [p0, (mx, p0.$2), (mx, p1.$2), p1];
    }
    if ((p0.$1 - p1.$1).abs() < 0.5) return [p0, (p0.$1, p1.$2)];
    final my = (p0.$2 + p1.$2) / 2 + shift;
    return [p0, (p0.$1, my), (p1.$1, my), p1];
  }

  final ids = [for (final f in links) if (sides.containsKey(f.id)) f.id];
  final shifts = {for (final id in ids) id: 0.0};
  final routes = {for (final id in ids) id: build(id, 0)};

  // เส้นที่ช่วงกลาง (ตั้งฉากกับทิศออก) ทับกัน: ดันเส้นหลังออกไปทีละ 12 px
  for (var pass = 0; pass < 6; pass++) {
    var changed = false;
    for (var j = 1; j < ids.length; j++) {
      if (linkById[ids[j]]!.isManual) continue; // เส้นที่ผู้ใช้จัดเองไม่ถูกดัน
      for (var i = 0; i < j; i++) {
        // เฉพาะช่วงกลาง (ไม่นับช่วงที่เริ่ม/จบที่กล่อง) ที่อยู่ในช่องว่างร่วมกัน
        if (routes[ids[j]]!.length > 2 &&
            routes[ids[i]]!.length > 2 &&
            routeSegmentsOverlap(routes[ids[i]]!.sublist(1, routes[ids[i]]!.length - 1),
                routes[ids[j]]!.sublist(1, routes[ids[j]]!.length - 1))) {
          shifts[ids[j]] = shifts[ids[j]]! + 12;
          routes[ids[j]] = build(ids[j], shifts[ids[j]]!);
          changed = true;
          break;
        }
      }
    }
    if (!changed) break;
  }
  return routes;
}

/// สองเส้นทางมีช่วงตรงที่วิ่งซ้อนทับกัน (แนวเดียวกัน ห่างกันไม่ถึง 6 px และทับกันเกิน 4 px) หรือไม่
bool routeSegmentsOverlap(List<RoutePoint> a, List<RoutePoint> b) {
  for (var i = 1; i < a.length; i++) {
    for (var j = 1; j < b.length; j++) {
      final av = (a[i - 1].$1 - a[i].$1).abs() < 0.001 && (a[i - 1].$2 - a[i].$2).abs() > 2;
      final bv = (b[j - 1].$1 - b[j].$1).abs() < 0.001 && (b[j - 1].$2 - b[j].$2).abs() > 2;
      final ah = (a[i - 1].$2 - a[i].$2).abs() < 0.001 && (a[i - 1].$1 - a[i].$1).abs() > 2;
      final bh = (b[j - 1].$2 - b[j].$2).abs() < 0.001 && (b[j - 1].$1 - b[j].$1).abs() > 2;
      if (av && bv && (a[i].$1 - b[j].$1).abs() < 6) {
        final lo = math.max(math.min(a[i - 1].$2, a[i].$2), math.min(b[j - 1].$2, b[j].$2));
        final hi = math.min(math.max(a[i - 1].$2, a[i].$2), math.max(b[j - 1].$2, b[j].$2));
        if (hi - lo > 4) return true;
      }
      if (ah && bh && (a[i].$2 - b[j].$2).abs() < 6) {
        final lo = math.max(math.min(a[i - 1].$1, a[i].$1), math.min(b[j - 1].$1, b[j].$1));
        final hi = math.min(math.max(a[i - 1].$1, a[i].$1), math.max(b[j - 1].$1, b[j].$1));
        if (hi - lo > 4) return true;
      }
    }
  }
  return false;
}

RouteSide _sideAxis(RouteBox a, RouteBox b, bool horizontal) {
  if (horizontal) return a.cx <= b.cx ? RouteSide.right : RouteSide.left;
  return a.cy <= b.cy ? RouteSide.bottom : RouteSide.top;
}

/// ด้านที่เส้นออกจาก [a] และเข้า [b]
(RouteSide, RouteSide) routeSidesFor(RouteBox a, RouteBox b, {double gutter = 28, bool preferVertical = false}) {
  final gapX = math.max(a.x - b.right, b.x - a.right); // บวก = มีช่องว่างแนวนอน
  final gapY = math.max(a.y - b.bottom, b.y - a.bottom);
  final bool horizontal;
  if (gapX >= gutter && gapY >= gutter) {
    horizontal = preferVertical ? false : gapX >= gapY; // เฉียง
  } else if (gapX >= gutter) {
    horizontal = true;
  } else if (gapY >= gutter) {
    horizontal = false;
  } else {
    // ซ้อน/ชิดกัน: ใช้แกนที่ศูนย์กลางห่างกว่า
    horizontal = (a.cx - b.cx).abs() >= (a.cy - b.cy).abs();
  }
  return (_sideAxis(a, b, horizontal), _sideAxis(b, a, horizontal));
}

/// จุดวางป้ายชื่อ: กึ่งกลางช่วงที่ยาวที่สุดของเส้น
RoutePoint routeLabelAnchor(List<RoutePoint> pts) {
  var best = 0, bestLen = -1.0;
  for (var i = 1; i < pts.length; i++) {
    final len = (pts[i].$1 - pts[i - 1].$1).abs() + (pts[i].$2 - pts[i - 1].$2).abs();
    if (len > bestLen) {
      bestLen = len;
      best = i;
    }
  }
  final a = pts[best - 1], b = pts[best];
  return ((a.$1 + b.$1) / 2, (a.$2 + b.$2) / 2);
}

/// จุดที่สัดส่วน [t] (0..1) ของความยาวเส้นทาง
RoutePoint routePointAt(List<RoutePoint> pts, double t) {
  if (pts.length == 1) return pts.first;
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += _len(pts[i - 1], pts[i]);
  }
  if (total == 0) return pts.first;
  var want = t.clamp(0.0, 1.0) * total;
  for (var i = 1; i < pts.length; i++) {
    final l = _len(pts[i - 1], pts[i]);
    if (want <= l || i == pts.length - 1) {
      final k = l == 0 ? 0.0 : (want / l).clamp(0.0, 1.0);
      return (pts[i - 1].$1 + (pts[i].$1 - pts[i - 1].$1) * k, pts[i - 1].$2 + (pts[i].$2 - pts[i - 1].$2) * k);
    }
    want -= l;
  }
  return pts.last;
}

/// สัดส่วน (0..1) ตามความยาวเส้นทางของจุดบนเส้นที่ใกล้ ([x],[y]) ที่สุด
double routeParamAt(List<RoutePoint> pts, double x, double y) {
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += _len(pts[i - 1], pts[i]);
  }
  if (total == 0) return 0.5;
  var best = double.infinity, bestT = 0.5, acc = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final (ax, ay) = pts[i - 1];
    final (bx, by) = pts[i];
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final k = len2 == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / len2).clamp(0.0, 1.0);
    final px = ax + k * dx - x, py = ay + k * dy - y;
    final d = px * px + py * py;
    final l = math.sqrt(len2);
    if (d < best) {
      best = d;
      bestT = (acc + k * l) / total;
    }
    acc += l;
  }
  return bestT;
}

double _len(RoutePoint a, RoutePoint b) {
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
  return math.sqrt(dx * dx + dy * dy);
}

/// ระยะจากจุดถึงเส้นทาง (ช่วงสั้นสุด)
double distanceToRoute(List<RoutePoint> pts, double x, double y) {
  var best = double.infinity;
  for (var i = 1; i < pts.length; i++) {
    final (ax, ay) = pts[i - 1];
    final (bx, by) = pts[i];
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / len2).clamp(0.0, 1.0);
    final px = ax + t * dx - x, py = ay + t * dy - y;
    best = math.min(best, math.sqrt(px * px + py * py));
  }
  return best;
}
