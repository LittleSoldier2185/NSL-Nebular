import 'dart:math' as math;

import '../models/use_case.dart';
import '../models/workspace.dart';

/// ขนาดของโหนดในแผนภาพ Use Case (หน่วยพิกเซลของแคนวาส)
const double kUcW = 200, kUcH = 72, kActorW = 84, kActorH = 100;

/// ระยะห่างของช่องจัดวาง (กว้าง × สูง) และขอบของกรอบระบบ
const double kUcCellW = 270, kUcCellH = 116, kUcBoundaryPad = 30, kUcBoundaryTitle = 44;

/// โหนดหนึ่งในแผนภาพ : ผู้กระทำ (`actor:<ชื่อ>`) หรือ Use Case (`uc:<id>`) ; x,y = มุมซ้ายบน
class UcNode {
  const UcNode({required this.key, required this.label, required this.x, required this.y, required this.w, required this.h, this.ucId, this.sub = ''});

  final String key;
  final String label;

  /// ข้อความรอง : รหัส Use Case (UC-01)
  final String sub;
  final double x, y, w, h;
  final String? ucId;

  bool get isActor => ucId == null;
  double get cx => x + w / 2;
  double get cy => y + h / 2;
  double get right => x + w;
  double get bottom => y + h;

  UcNode movedTo(double nx, double ny) => UcNode(key: key, label: label, sub: sub, x: nx, y: ny, w: w, h: h, ucId: ucId);
}

enum UcEdgeKind { association, include, extend }

class UcEdge {
  const UcEdge({required this.kind, required this.fromKey, required this.toKey, this.condition = ''});
  final UcEdgeKind kind;
  final String fromKey, toKey;

  /// เงื่อนไขของ extend (ว่าง = ไม่มี)
  final String condition;
}

/// แผนภาพ Use Case ที่จัดวางแล้ว : โหนด · เส้น · กรอบระบบ ([boundary] = ล้อมเฉพาะ Use Case) · ขอบเขตทั้งภาพ ([bounds])
class UcDiagram {
  const UcDiagram({required this.nodes, required this.edges, required this.boundary, required this.bounds, required this.systemName});
  final List<UcNode> nodes;
  final List<UcEdge> edges;
  final ({double x, double y, double w, double h})? boundary;
  final ({double left, double top, double right, double bottom})? bounds;
  final String systemName;

  UcNode? node(String key) {
    for (final n in nodes) {
      if (n.key == key) return n;
    }
    return null;
  }

  bool get isEmpty => nodes.isEmpty;
}

String ucActorKey(String name) => 'actor:$name';
String ucNodeKey(String ucId) => 'uc:$ucId';

/// จัดวางแผนภาพจากสเปก Use Case ของ [w] (ฟังก์ชันล้วน ผลคงที่)
/// ผู้กระทำหลักอยู่ซ้าย ผู้กระทำรอง/ระบบภายนอกอยู่ขวา Use Case เรียงเป็นตารางในกรอบระบบ (จัดกลุ่มตามผู้กระทำหลัก)
/// [overrides] = ตำแหน่งที่ผู้ใช้ลาก (คีย์โหนด -> มุมซ้ายบน) ทับตำแหน่งอัตโนมัติ ; กรอบระบบคำนวณใหม่ตาม Use Case ที่ย้ายแล้ว
UcDiagram layoutUseCaseDiagram(Workspace w, {Map<String, (double, double)> overrides = const {}}) {
  final ucs = w.useCases;
  final systemName = w.name.trim().isEmpty ? 'System' : w.name.trim();
  if (ucs.isEmpty) return UcDiagram(nodes: const [], edges: const [], boundary: null, bounds: null, systemName: systemName);

  // ---- ผู้กระทำ ----
  final primary = <String>[];
  for (final u in ucs) {
    final a = u.actor.trim();
    if (a.isNotEmpty && !primary.contains(a)) primary.add(a);
  }
  final secondary = <String>[];
  for (final u in ucs) {
    for (final a in u.secondaryActors) {
      if (!primary.contains(a) && !secondary.contains(a)) secondary.add(a);
    }
  }

  // ---- ลำดับ Use Case : จัดกลุ่มตามผู้กระทำหลัก (ตามลำดับที่เจอ) ข้อที่ไม่มีผู้กระทำอยู่ท้าย ----
  final ordered = <UseCase>[
    for (final a in primary)
      for (final u in ucs)
        if (u.actor.trim() == a) u,
    for (final u in ucs)
      if (u.actor.trim().isEmpty) u,
  ];
  final n = ordered.length;
  final cols = n <= 4 ? 1 : (n <= 12 ? 2 : 3);
  final rows = (n / cols).ceil();

  const bx = 190.0, by = 30.0;
  final nodes = <String, UcNode>{};
  for (var i = 0; i < n; i++) {
    final col = i ~/ rows, row = i % rows; // เรียงลงทีละคอลัมน์ : ผู้กระทำคนเดียวกันอยู่ใกล้กัน
    final u = ordered[i];
    nodes[ucNodeKey(u.id)] = UcNode(
      key: ucNodeKey(u.id),
      label: u.name.trim().isEmpty ? u.code : u.name.trim(),
      sub: u.code,
      ucId: u.id,
      x: bx + kUcBoundaryPad + col * kUcCellW,
      y: by + kUcBoundaryTitle + row * kUcCellH,
      w: kUcW,
      h: kUcH,
    );
  }
  final autoRight = bx + kUcBoundaryPad * 2 + (cols - 1) * kUcCellW + kUcW;

  // ---- ตำแหน่งผู้กระทำ : กึ่งกลางแนวตั้งของ Use Case ที่เกี่ยวข้อง แล้วเลี่ยงการทับกัน ----
  List<UcNode> actorsOf(List<String> names, double x, bool Function(UseCase u, String a) related) {
    final pref = <(String, double)>[];
    for (final a in names) {
      final ys = [for (final u in ucs) if (related(u, a)) nodes[ucNodeKey(u.id)]!.cy];
      pref.add((a, ys.isEmpty ? by + kUcBoundaryTitle + kActorH / 2 : ys.reduce((p, q) => p + q) / ys.length));
    }
    pref.sort((p, q) => p.$2.compareTo(q.$2));
    final out = <UcNode>[];
    var minY = by + kUcBoundaryTitle - 10;
    for (final (a, cy) in pref) {
      final y = (cy - kActorH / 2) < minY ? minY : cy - kActorH / 2;
      out.add(UcNode(key: ucActorKey(a), label: a, x: x, y: y, w: kActorW, h: kActorH));
      minY = y + kActorH + 24;
    }
    return out;
  }

  for (final a in actorsOf(primary, 50, (u, a) => u.actor.trim() == a)) {
    nodes[a.key] = a;
  }
  for (final a in actorsOf(secondary, autoRight + 70, (u, a) => u.secondaryActors.contains(a))) {
    nodes[a.key] = a;
  }

  // ---- ตำแหน่งที่ผู้ใช้ลาก ----
  for (final e in overrides.entries) {
    final cur = nodes[e.key];
    if (cur != null) nodes[e.key] = cur.movedTo(e.value.$1, e.value.$2);
  }

  // ---- เส้น ----
  final byId = {for (final u in ucs) u.id: u};
  final edges = <UcEdge>[];
  for (final u in ucs) {
    final a = u.actor.trim();
    if (a.isNotEmpty) edges.add(UcEdge(kind: UcEdgeKind.association, fromKey: ucActorKey(a), toKey: ucNodeKey(u.id)));
    for (final s in u.secondaryActors) {
      edges.add(UcEdge(kind: UcEdgeKind.association, fromKey: ucActorKey(s), toKey: ucNodeKey(u.id)));
    }
    for (final id in u.includes) {
      if (id != u.id && byId.containsKey(id)) edges.add(UcEdge(kind: UcEdgeKind.include, fromKey: ucNodeKey(u.id), toKey: ucNodeKey(id)));
    }
    for (final e in u.extendsFrom) {
      if (e.baseId != u.id && byId.containsKey(e.baseId)) {
        edges.add(UcEdge(kind: UcEdgeKind.extend, fromKey: ucNodeKey(u.id), toKey: ucNodeKey(e.baseId), condition: e.condition.trim()));
      }
    }
  }

  // ---- กรอบระบบ (ล้อม Use Case) + ขอบเขตทั้งภาพ ----
  final ucNodes = [for (final x in nodes.values) if (!x.isActor) x];
  var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  for (final x in ucNodes) {
    if (x.x < l) l = x.x;
    if (x.y < t) t = x.y;
    if (x.right > r) r = x.right;
    if (x.bottom > b) b = x.bottom;
  }
  final boundary = (x: l - kUcBoundaryPad, y: t - kUcBoundaryTitle, w: r - l + kUcBoundaryPad * 2, h: b - t + kUcBoundaryTitle + kUcBoundaryPad);
  var bl = boundary.x, bt = boundary.y, br = boundary.x + boundary.w, bb = boundary.y + boundary.h;
  for (final x in nodes.values) {
    if (x.x < bl) bl = x.x;
    if (x.y < bt) bt = x.y;
    if (x.right > br) br = x.right;
    if (x.bottom > bb) bb = x.bottom;
  }
  return UcDiagram(
    nodes: nodes.values.toList(),
    edges: edges,
    boundary: boundary,
    bounds: (left: bl - 30, top: bt - 20, right: br + 30, bottom: bb + 30),
    systemName: systemName,
  );
}

/// จุดบนขอบวงรีของ [n] ที่เส้นจากกึ่งกลางไปทาง ([tx], [ty]) ตัดผ่าน
(double, double) ucOnEllipse(UcNode n, double tx, double ty) {
  final dx = tx - n.cx, dy = ty - n.cy;
  if (dx == 0 && dy == 0) return (n.cx, n.cy);
  final rx = n.w / 2, ry = n.h / 2;
  final t = 1 / math.sqrt((dx / rx) * (dx / rx) + (dy / ry) * (dy / ry));
  return (n.cx + dx * t, n.cy + dy * t);
}

/// จุดบนขอบของผู้กระทำ (ประมาณเป็นวงกลมรอบตัวคน ไม่รวมป้ายชื่อ)
(double, double) ucOnActor(UcNode n, double tx, double ty) {
  final cx = n.cx, cy = n.y + 42;
  final dx = tx - cx, dy = ty - cy;
  final d = math.sqrt(dx * dx + dy * dy);
  if (d == 0) return (cx, cy);
  const r = 34.0;
  return (cx + dx / d * r, cy + dy / d * r);
}

/// ปลายทั้งสองของเส้น [e] (ตัดที่ขอบโหนด) ; โหนดปลายทางหาย = null
({double x1, double y1, double x2, double y2})? ucEdgeLine(UcDiagram d, UcEdge e) {
  final a = d.node(e.fromKey), b = d.node(e.toKey);
  if (a == null || b == null) return null;
  final (x1, y1) = a.isActor ? ucOnActor(a, b.cx, b.cy) : ucOnEllipse(a, b.cx, b.cy);
  final (x2, y2) = b.isActor ? ucOnActor(b, a.cx, a.cy) : ucOnEllipse(b, a.cx, a.cy);
  return (x1: x1, y1: y1, x2: x2, y2: y2);
}

/// โหนดที่อยู่ใต้จุด ([wx], [wy]) ในพิกัดแคนวาส (โหนดที่อยู่ท้ายรายการอยู่บนสุด) ; ไม่มี = null
UcNode? ucHitTest(UcDiagram d, double wx, double wy) {
  for (final n in d.nodes.reversed) {
    if (n.isActor) {
      if (wx >= n.x && wx <= n.right && wy >= n.y && wy <= n.bottom) return n;
    } else {
      final dx = (wx - n.cx) / (n.w / 2), dy = (wy - n.cy) / (n.h / 2);
      if (dx * dx + dy * dy <= 1) return n;
    }
  }
  return null;
}

/// สเกลและตำแหน่งที่ทำให้ [bounds] พอดีกับพื้นที่ [viewW]×[viewH] (กึ่งกลาง ; ไม่ขยายเกิน [maxScale])
({double scale, double dx, double dy}) ucFitTransform(({double left, double top, double right, double bottom}) bounds, double viewW, double viewH, {double maxScale = 1.2}) {
  final bw = bounds.right - bounds.left, bh = bounds.bottom - bounds.top;
  if (bw <= 0 || bh <= 0 || viewW <= 0 || viewH <= 0) return (scale: 1, dx: 0, dy: 0);
  final s = math.min(math.min(viewW / bw, viewH / bh), maxScale).clamp(0.1, maxScale).toDouble();
  return (scale: s, dx: (viewW - bw * s) / 2 - bounds.left * s, dy: (viewH - bh * s) / 2 - bounds.top * s);
}
