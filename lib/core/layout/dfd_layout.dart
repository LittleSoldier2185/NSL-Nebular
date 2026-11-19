import 'dart:math' as math;

import '../models/dfd_model.dart';

/// ระยะห่างขั้นต่ำระหว่างคอลัมน์ (แนวนอน) และระหว่างวัตถุในคอลัมน์เดียวกัน (แนวตั้ง) ตอนจัดวางอัตโนมัติ
const double kDfdLayerGap = 140;
const double kDfdRowGap = 50;

/// ผลจัดวางอัตโนมัติ : มุมซ้ายบนใหม่ของทุกวัตถุ + ความสูงใหม่ของวัตถุที่ต้องขยาย (ขยายอย่างเดียว ไม่หด)
class DfdLayoutPlan {
  const DfdLayoutPlan(this.positions, this.heights);
  final Map<String, ({double x, double y})> positions;

  /// เฉพาะวัตถุที่สูงกว่าเดิม (เพื่อให้ช่องของเส้นที่ออก/เข้าด้านเดียวกันห่างพอไม่ให้ป้ายชนกัน)
  final Map<String, double> heights;
}

Map<String, ({double x, double y})> dfdAutoLayout(DfdDiagram d) => dfdLayoutPlan(d).positions;

/// จัดวาง DFD ตามบทบาทของวัตถุ (ไม่แก้แผนภาพ) — ผลเหมือนเดิมทุกครั้ง และมุมซ้ายบนของทั้งชุดอยู่ที่เดิม
///
/// 1. **คอลัมน์ของ process** = ลำดับตามทิศทางข้อมูลของเส้น process→process โดยตรง (เส้นที่ทำให้วนกลับไม่นับ) ;
///    process ที่ไม่ส่งข้อมูลถึงกันโดยตรงอยู่คอลัมน์เดียวกัน (ซ้อนกันในแนวตั้ง) ไม่ยืดแผนภาพออกด้านข้าง
/// 2. **entity** = ข้อมูลออกมากกว่าเข้า → ซ้าย (ต้นทางข้อมูล), เข้ามากกว่าออก → ขวา (ปลายทาง) ;
///    เท่ากัน → ดูว่าต่อกับ process ต้นหรือปลายสาย ; ถ้ากลางพอดีก็แจกให้ซ้าย/ขวาน้ำหนักเส้นเท่ากันที่สุด
/// 3. **data store** แทรกเป็นคอลัมน์คั่นระหว่าง process : ถัดจากผู้เขียนก่อน (ผู้อ่านอยู่ถัดไป)
///    ; อ่านอย่างเดียวอยู่หลังผู้อ่านคนแรก (ไม่ขวางเส้นจาก entity ฝั่งซ้าย) ; เขียนอย่างเดียวอยู่หลังผู้เขียนคนสุดท้าย
/// 4. **แนวตั้ง** = วนซ้ำ: วางแต่ละคอลัมน์ให้ตรงกับค่าเฉลี่ยตำแหน่งของเพื่อนบ้าน (ถ่วงด้วยจำนวนเส้น)
///    แล้วเรียงใหม่ตามค่านั้น (ลดเส้นตัดกัน) และดันห่างไม่ให้ซ้อน → เส้นระหว่างคู่วัตถุเรียงตรงขนานกัน
/// 5. **ระยะ** : ช่องระหว่างคอลัมน์กว้างพอให้ป้ายชื่อเส้นที่ผ่านช่องนั้นไม่ทับกล่อง ;
///    วัตถุที่มีเส้นออก/เข้าด้านเดียวกันหลายเส้นถูกขยายความสูงให้ช่องของเส้นห่างกัน [kDfdSlotGap]
DfdLayoutPlan dfdLayoutPlan(DfdDiagram d) {
  final nodes = <String, DfdNode>{};
  for (final n in d.nodes) {
    nodes.putIfAbsent(n.id, () => n);
  }
  if (nodes.isEmpty) return const DfdLayoutPlan({}, {});
  final ids = nodes.keys.toList();
  final index = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  final flows = [
    for (final f in d.flows)
      if (nodes.containsKey(f.fromId) && nodes.containsKey(f.toId) && f.fromId != f.toId) f,
  ];
  bool isKind(String id, DfdKind k) => nodes[id]!.kind == k;

  // เพื่อนบ้านถ่วงน้ำหนัก (จำนวนเส้นระหว่างสองวัตถุ ไม่สนทิศทาง)
  final nbr = <String, Map<String, int>>{for (final id in ids) id: {}};
  for (final f in flows) {
    nbr[f.fromId]![f.toId] = (nbr[f.fromId]![f.toId] ?? 0) + 1;
    nbr[f.toId]![f.fromId] = (nbr[f.toId]![f.fromId] ?? 0) + 1;
  }

  // ---- 1. คอลัมน์ของ process ----
  final procs = [for (final id in ids) if (isKind(id, DfdKind.process)) id];
  final edges = <(String, String)>[];
  final seenEdge = <(String, String)>{};
  void addEdge(String a, String b) {
    if (a != b && seenEdge.add((a, b))) edges.add((a, b));
  }

  for (final f in flows) {
    if (isKind(f.fromId, DfdKind.process) && isKind(f.toId, DfdKind.process)) addEdge(f.fromId, f.toId);
  }
  final pcol = _longestLayers(procs, edges);
  final maxC = pcol.values.fold<int>(0, math.max);

  final key = <String, double>{}; // คอลัมน์ของวัตถุ (ตัวเลขน้อย = ซ้าย)
  pcol.forEach((id, c) => key[id] = c.toDouble());

  // ---- 3. data store ----
  for (final s in ids.where((i) => isKind(i, DfdKind.store))) {
    final w = [for (final f in flows) if (f.toId == s && isKind(f.fromId, DfdKind.process)) pcol[f.fromId]!];
    final r = [for (final f in flows) if (f.fromId == s && isKind(f.toId, DfdKind.process)) pcol[f.toId]!];
    key[s] = switch ((w.isEmpty, r.isEmpty)) {
      (false, false) => math.min(w.reduce(math.min), r.reduce(math.min)) + 0.5,
      (false, true) => w.reduce(math.max) + 0.5,
      (true, false) => r.reduce(math.min) + 0.5,
      _ => 0.5,
    };
  }

  // ---- 2. entity ----
  final entities = [for (final id in ids) if (isKind(id, DfdKind.entity)) id];
  const leftKey = -1.0;
  final rightKey = maxC + 1.0;
  double weight(String id) => nbr[id]!.values.fold<int>(0, (a, b) => a + b).toDouble();
  var leftW = 0.0, rightW = 0.0;
  final tied = <String>[];
  for (final e in entities) {
    final out = flows.where((f) => f.fromId == e).length;
    final inn = flows.where((f) => f.toId == e).length;
    if (out > inn) {
      key[e] = leftKey;
      leftW += weight(e);
    } else if (inn > out) {
      key[e] = rightKey;
      rightW += weight(e);
    } else {
      final cols = [for (final n in nbr[e]!.keys) if (pcol.containsKey(n)) pcol[n]!];
      final avg = cols.isEmpty ? maxC / 2 : cols.reduce((a, b) => a + b) / cols.length;
      if (avg < maxC / 2 - 1e-9) {
        key[e] = leftKey;
        leftW += weight(e);
      } else if (avg > maxC / 2 + 1e-9) {
        key[e] = rightKey;
        rightW += weight(e);
      } else {
        tied.add(e);
      }
    }
  }
  tied.sort((a, b) {
    final c = weight(b).compareTo(weight(a));
    return c != 0 ? c : index[a]!.compareTo(index[b]!);
  });
  for (final e in tied) {
    if (leftW <= rightW) {
      key[e] = leftKey;
      leftW += weight(e);
    } else {
      key[e] = rightKey;
      rightW += weight(e);
    }
  }

  final keys = key.values.toSet().toList()..sort();
  final colOf = {for (final id in ids) id: keys.indexOf(key[id]!)};
  final cols = <List<String>>[for (final _ in keys) []];
  for (final id in ids) {
    cols[colOf[id]!].add(id);
  }

  // ---- ความสูง: ให้ช่องของเส้นที่ออก/เข้าด้านเดียวกันห่างกัน kDfdSlotGap ----
  final left = {for (final id in ids) id: 0}, right = {for (final id in ids) id: 0};
  for (final f in flows) {
    final a = colOf[f.fromId]!, b = colOf[f.toId]!;
    if (a < b) {
      right[f.fromId] = right[f.fromId]! + 1;
      left[f.toId] = left[f.toId]! + 1;
    } else if (a > b) {
      left[f.fromId] = left[f.fromId]! + 1;
      right[f.toId] = right[f.toId]! + 1;
    }
  }
  final hh = <String, double>{}, grown = <String, double>{};
  for (final id in ids) {
    final n = nodes[id]!;
    final m = math.max(left[id]!, right[id]!);
    final need = m > 1 ? math.min(kDfdMaxSide, 2 * dfdPortInset(n.kind) + kDfdSlotGap * (m - 1)) : 0.0;
    hh[id] = math.max(n.h, need);
    if (hh[id]! > n.h) grown[id] = hh[id]!;
  }

  // ---- 4. แนวตั้ง ----
  final cy = <String, double>{};
  for (final list in cols) {
    final total = list.fold<double>(0, (s, id) => s + hh[id]!) + kDfdRowGap * (list.length - 1);
    var top = -total / 2;
    for (final id in list) {
      cy[id] = top + hh[id]! / 2;
      top += hh[id]! + kDfdRowGap;
    }
  }
  void settle(int ci) {
    final list = cols[ci];
    final want = <String, double>{};
    for (final id in list) {
      var sum = 0.0, ws = 0.0;
      nbr[id]!.forEach((o, c) {
        final dc = (colOf[o]! - ci).abs();
        if (dc == 0) return;
        final w = dc == 1 ? c.toDouble() : c * 0.5;
        sum += w * cy[o]!;
        ws += w;
      });
      want[id] = ws == 0 ? cy[id]! : sum / ws;
    }
    list.sort((a, b) {
      final c = want[a]!.compareTo(want[b]!);
      if (c != 0) return c;
      final c2 = cy[a]!.compareTo(cy[b]!);
      return c2 != 0 ? c2 : index[a]!.compareTo(index[b]!);
    });
    // วางจากบนลงล่างและล่างขึ้นบน แล้วเฉลี่ย (ยังเว้นระยะครบทั้งสองแบบ จึงเฉลี่ยแล้วก็ครบ)
    final fwd = <double>[], bwd = List<double>.filled(list.length, 0);
    var edge = -double.infinity;
    for (final id in list) {
      final t = math.max(want[id]! - hh[id]! / 2, edge);
      fwd.add(t);
      edge = t + hh[id]! + kDfdRowGap;
    }
    edge = double.infinity;
    for (var i = list.length - 1; i >= 0; i--) {
      final id = list[i];
      final bottom = math.min(want[id]! + hh[id]! / 2, edge);
      bwd[i] = bottom - hh[id]!;
      edge = bwd[i] - kDfdRowGap;
    }
    for (var i = 0; i < list.length; i++) {
      cy[list[i]] = (fwd[i] + bwd[i]) / 2 + hh[list[i]]! / 2;
    }
  }

  for (var pass = 0; pass < 8; pass++) {
    for (var c = 0; c < cols.length; c++) {
      settle(c);
    }
    for (var c = cols.length - 1; c >= 0; c--) {
      settle(c);
    }
  }

  // ---- 5. แนวนอน: ช่องระหว่างคอลัมน์กว้างพอให้ป้ายชื่อเส้นที่ผ่านช่องนั้น ----
  final colW = [for (final list in cols) list.map((id) => nodes[id]!.w).reduce(math.max)];
  final gap = List<double>.filled(math.max(0, cols.length - 1), kDfdLayerGap);
  for (final f in flows) {
    final a = colOf[f.fromId]!, b = colOf[f.toId]!;
    if ((a - b).abs() != 1) continue;
    final g = math.min(a, b);
    final labelW = f.label.trim().isEmpty ? 0.0 : math.min(260.0, f.label.trim().runes.length * 7.0 + 12);
    gap[g] = math.max(gap[g], labelW + 44);
  }
  final colX = <double>[];
  var x = 0.0;
  for (var c = 0; c < cols.length; c++) {
    colX.add(x);
    x += colW[c] + (c < gap.length ? gap[c] : 0);
  }

  final raw = <String, ({double x, double y})>{};
  for (var c = 0; c < cols.length; c++) {
    for (final id in cols[c]) {
      raw[id] = (x: colX[c] + (colW[c] - nodes[id]!.w) / 2, y: cy[id]! - hh[id]! / 2);
    }
  }
  final minX = raw.values.map((p) => p.x).reduce(math.min);
  final minY = raw.values.map((p) => p.y).reduce(math.min);
  final ox = nodes.values.map((n) => n.x).reduce(math.min);
  final oy = nodes.values.map((n) => n.y).reduce(math.min);
  return DfdLayoutPlan(
    {for (final e in raw.entries) e.key: (x: e.value.x - minX + ox, y: e.value.y - minY + oy)},
    grown,
  );
}

/// ชั้นของแต่ละ id ด้วยเส้นทางยาวสุดจากต้นทาง (ไม่มีเส้นเข้า = ชั้น 0) ; เส้นย้อนกลับที่ทำให้วนถูกข้าม
Map<String, int> _longestLayers(List<String> ids, List<(String, String)> edges) {
  final set = ids.toSet();
  final out = <String, List<String>>{for (final id in ids) id: []};
  for (final (a, b) in edges) {
    if (set.contains(a) && set.contains(b)) out[a]!.add(b);
  }
  final hasIn = <String>{for (final e in out.values) ...e};
  final dag = <String, List<String>>{for (final id in ids) id: []};
  final state = <String, int>{};
  void dfs(String u) {
    state[u] = 1;
    for (final v in out[u]!) {
      if (state[v] == 1) continue;
      dag[u]!.add(v);
      if (state[v] == null) dfs(v);
    }
    state[u] = 2;
  }

  for (final id in ids.where((i) => !hasIn.contains(i))) {
    if (state[id] == null) dfs(id);
  }
  for (final id in ids) {
    if (state[id] == null) dfs(id);
  }
  final layer = {for (final id in ids) id: 0};
  final indeg = {for (final id in ids) id: 0};
  for (final vs in dag.values) {
    for (final v in vs) {
      indeg[v] = indeg[v]! + 1;
    }
  }
  final queue = [for (final id in ids) if (indeg[id] == 0) id];
  for (var i = 0; i < queue.length; i++) {
    final u = queue[i];
    for (final v in dag[u]!) {
      layer[v] = math.max(layer[v]!, layer[u]! + 1);
      indeg[v] = indeg[v]! - 1;
      if (indeg[v] == 0) queue.add(v);
    }
  }
  return layer;
}
