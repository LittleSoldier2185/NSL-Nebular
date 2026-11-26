import '../models/wireframe_model.dart';

/// กรอบพิกัดจำนวนเต็ม (ปัดจากแบบ) — ใช้จำนวนเต็มเพื่อให้ผลบวกของช่องว่าง+ขนาดใน Row/Column ไม่ล้นเพราะเศษทศนิยม
class WfRect {
  const WfRect(this.left, this.top, this.right, this.bottom);
  final int left, top, right, bottom;
  int get width => right - left;
  int get height => bottom - top;

  bool covers(WfRect o) => o.left >= left && o.top >= top && o.right <= right && o.bottom <= bottom;

  @override
  String toString() => 'WfRect($left, $top, $right, $bottom)';
}

/// กรอบที่ชิ้น [c] กินพื้นที่จริง (คิดการหมุนแล้ว)
WfRect wfLayoutRect(WfComponent c) {
  final b = wfBounds(c);
  final l = b.left.round(), t = b.top.round();
  final r = b.right.round(), btm = b.bottom.round();
  return WfRect(l, t, r > l ? r : l + 1, btm > t ? btm : t + 1);
}

/// กรอบของชิ้น [c] ก่อนหมุน
WfRect wfPlainRect(WfComponent c) {
  final l = c.x.round(), t = c.y.round();
  final r = c.right.round(), btm = c.bottom.round();
  return WfRect(l, t, r > l ? r : l + 1, btm > t ? btm : t + 1);
}

/// โหนดของผังหน้าจอ ([rect] อยู่ในพิกัดหน้าจอ)
sealed class WfNode {
  const WfNode(this.rect);
  final WfRect rect;
}

/// ชิ้นส่วนหนึ่งชิ้น ; [inner] = ผังของชิ้นที่อยู่ข้างใน (เฉพาะภาชนะ ; ว่าง = null)
class WfLeafNode extends WfNode {
  const WfLeafNode(this.component, super.rect, {this.inner});
  final WfComponent component;
  final WfNode? inner;
}

/// เรียงต่อกันโดยไม่ทับกัน: [vertical] = บนลงล่าง (`Column`) ไม่ใช่ = ซ้ายไปขวา (`Row`)
class WfLineNode extends WfNode {
  const WfLineNode(super.rect, this.children, {required this.vertical});
  final List<WfNode> children;
  final bool vertical;
}

/// ชิ้นที่ทับกันจนแบ่งเป็นแถว/คอลัมน์ไม่ได้ (หรือเลยขอบพื้นที่) — วางตามตำแหน่ง เรียงตามลำดับการซ้อน
class WfStackNode extends WfNode {
  const WfStackNode(super.rect, this.children);
  final List<WfNode> children;
}

/// แบ่ง [items] ตามแกนเดียวเป็นช่วงที่ไม่ทับกัน เรียงจากน้อยไปมาก ; ในแต่ละช่วงคงลำดับเดิม (ลำดับการซ้อน)
List<List<WfNode>> _bands(List<WfNode> items, int Function(WfRect) start, int Function(WfRect) end) {
  final sorted = [...items]..sort((a, b) => start(a.rect).compareTo(start(b.rect)));
  final groups = <Set<WfNode>>[];
  var reach = 0;
  for (final n in sorted) {
    if (groups.isEmpty || start(n.rect) >= reach) {
      groups.add({n});
      reach = end(n.rect);
    } else {
      groups.last.add(n);
      if (end(n.rect) > reach) reach = end(n.rect);
    }
  }
  return [for (final g in groups) [for (final n in items) if (g.contains(n)) n]];
}

WfRect _union(List<WfNode> items) {
  var r = items.first.rect;
  for (final n in items.skip(1)) {
    final o = n.rect;
    r = WfRect(
      o.left < r.left ? o.left : r.left,
      o.top < r.top ? o.top : r.top,
      o.right > r.right ? o.right : r.right,
      o.bottom > r.bottom ? o.bottom : r.bottom,
    );
  }
  return r;
}

/// จัด [items] ภายในพื้นที่ [region] — แบ่งแถวก่อน แล้วคอลัมน์ ; แบ่งไม่ได้ = ซ้อน
WfNode _arrange(List<WfNode> items, WfRect region) {
  // เลยขอบพื้นที่: Row/Column วางไม่ได้ (ช่องว่างติดลบ / ล้น) ใช้ตำแหน่งตรง ๆ
  if (items.any((n) => !region.covers(n.rect))) return WfStackNode(region, items);
  for (final vertical in const [true, false]) {
    final bands = vertical ? _bands(items, (r) => r.top, (r) => r.bottom) : _bands(items, (r) => r.left, (r) => r.right);
    if (bands.length < 2) continue;
    return WfLineNode(region, [
      for (final band in bands)
        if (band.length == 1) band.single else _arrange(band, _union(band)),
    ], vertical: vertical);
  }
  if (items.length == 1) return WfLineNode(region, items, vertical: true);
  return WfStackNode(region, items);
}

/// ผังของหน้าจอจาก Wireframe [d] (ไม่รวมชิ้นที่ซ่อน) ; ไม่มีชิ้นให้วาง = null
WfNode? wfLayoutTree(WireframeDiagram d) {
  final parents = wfParentMap(d);
  final hidden = wfHiddenIds(d, parents);
  final shown = [for (final c in d.components) if (!hidden.contains(c.id)) c];

  WfLeafNode leaf(WfComponent c) {
    final rect = wfLayoutRect(c);
    final kids = <WfNode>[for (final k in shown) if (parents[k.id] == c.id) leaf(k)];
    // ข้างในภาชนะคิดจากกรอบก่อนหมุน (หมุนทั้งภาชนะพร้อมลูกทีเดียว)
    return WfLeafNode(c, rect, inner: kids.isEmpty ? null : _arrange(kids, wfPlainRect(c)));
  }

  final roots = <WfNode>[for (final c in shown) if (!parents.containsKey(c.id)) leaf(c)];
  if (roots.isEmpty) return null;
  return _arrange(roots, WfRect(0, 0, d.width.round(), d.height.round()));
}
