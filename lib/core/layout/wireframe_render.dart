import 'dart:math' as math;

import '../models/color_utils.dart';
import '../models/wireframe_model.dart';
import 'ortho_route.dart' show RoutePoint;

/// ภาพของ Wireframe เป็นรายการ "ชิ้นวาด" กลาง (ฟังก์ชันล้วน ไม่พึ่ง Flutter) — ตัววาดบนจอ/PNG และตัวเขียน SVG
/// แปลงรายการเดียวกันนี้ จึงได้ภาพตรงกันทั้งสองรูปแบบการแสดงผล ([WfStyle.sketch] / [WfStyle.clean])

/// คำสั่งเส้น: 'M' (1 จุด), 'L' (1 จุด), 'C' (3 จุด), 'Z' — โครงเดียวกับ FcCmd ของ Flowchart
typedef WfCmd = (String op, List<RoutePoint> pts);

/// ชิ้นวาดหนึ่งชิ้น
sealed class WfPrim {
  const WfPrim();
}

/// รูปทรง/เส้น: [fill] null = ไม่เติม, [stroke] null = ไม่มีเส้น
class WfPathPrim extends WfPrim {
  const WfPathPrim(this.cmds, {this.fill, this.stroke, this.width = 1, this.dashed = false});
  final List<WfCmd> cmds;
  final int? fill;
  final int? stroke;
  final double width;
  final bool dashed;
}

/// ข้อความในกรอบ ([x],[y],[w],[h]) — ตัดคำ/ตัดบรรทัดเกินกรอบด้วย … ; [align] 0 ซ้าย 1 กลาง 2 ขวา ; [top] = ชิดบน (ไม่งั้นกึ่งกลางแนวตั้ง)
class WfTextPrim extends WfPrim {
  const WfTextPrim(this.text, this.x, this.y, this.w, this.h,
      {required this.size, required this.color, this.bold = false, this.align = 0, this.top = false, this.maxLines});
  final String text;
  final double x, y, w, h;
  final double size;
  final int color;
  final bool bold;
  final int align;
  final bool top;
  final int? maxLines;
}

/// ชิ้นวาดที่หมุนรอบจุด ([cx],[cy]) เป็นมุม [degrees] (ตามเข็มนาฬิกา) — ใช้กับชิ้นส่วนที่หมุน
class WfGroupPrim extends WfPrim {
  const WfGroupPrim(this.children, {required this.cx, required this.cy, required this.degrees});
  final List<WfPrim> children;
  final double cx, cy, degrees;
}

/// ชุดสีของการแสดงผล
class WfPalette {
  const WfPalette({
    required this.frame,
    required this.surface,
    required this.subtle,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentTint,
    required this.sketch,
  });

  final int frame, surface, subtle, border, text, muted, accent, onAccent, accentTint;
  final bool sketch;
}

int _alpha(int argb, double a) => ((a * 255).round().clamp(0, 255) << 24) | (argb & 0xFFFFFF);

/// สีเทาที่ความสว่างเท่ากัน (ใช้กับรูปแบบร่างซึ่งเป็นขาวดำ)
int wfGray(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  final v = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
  return (argb & 0xFF000000) | (v << 16) | (v << 8) | v;
}

/// ผสมสี [a] กับ [b] ด้วยสัดส่วน [t] (0 = a, 1 = b) — ทึบ
int _mix(int a, int b, double t) {
  int ch(int s) => (((a >> s) & 0xFF) * (1 - t) + ((b >> s) & 0xFF) * t).round().clamp(0, 255);
  return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

/// ชุดสีของเอกสาร [d] ตามรูปแบบที่เลือก (ไม่ขึ้นกับธีมของแอป)
WfPalette wfPalette(WireframeDiagram d) {
  if (d.style == WfStyle.sketch) {
    return const WfPalette(
      frame: 0xFFFFFFFF,
      surface: 0xFFFFFFFF,
      subtle: 0xFFF0F0F0,
      border: 0xFF3A3A3A,
      text: 0xFF2B2B2B,
      muted: 0xFF8A8A8A,
      accent: 0xFF4A4A4A,
      onAccent: 0xFFFFFFFF,
      accentTint: 0xFFE2E2E2,
      sketch: true,
    );
  }
  final a = d.accent | 0xFF000000;
  return WfPalette(
    frame: 0xFFFFFFFF,
    surface: 0xFFFFFFFF,
    subtle: 0xFFF2F4F7,
    border: 0xFFD0D5DD,
    text: 0xFF1D2939,
    muted: 0xFF667085,
    accent: a,
    onAccent: onColor(a),
    accentTint: _mix(a, 0xFFFFFFFF, 0.86),
    sketch: false,
  );
}

/// รายการชิ้นวาดของทั้งหน้าจอ (กรอบหน้าจอ + ชิ้นส่วนตามลำดับการซ้อน) ที่พิกัดหน้าจอ (กรอบเริ่ม 0,0)
List<WfPrim> wireframePrims(WireframeDiagram d, {bool frame = true}) {
  final p = wfPalette(d);
  final b = _Builder(p);
  if (frame) {
    b.rect(0, 0, d.width, d.height, fill: p.frame, stroke: p.sketch ? p.border : 0xFF98A2B3, width: p.sketch ? 1.6 : 1, seed: 7);
  }
  final hidden = wfHiddenIds(d);
  for (final c in d.components) {
    if (hidden.contains(c.id)) continue;
    if (c.rotation == 0) {
      _component(b, d, c);
      continue;
    }
    final start = b.out.length;
    _component(b, d, c);
    final kids = b.out.sublist(start);
    b.out
      ..removeRange(start, b.out.length)
      ..add(WfGroupPrim(kids, cx: c.x + c.w / 2, cy: c.y + c.h / 2, degrees: c.rotation));
  }
  return b.out;
}

/// ชิ้นวาดของชิ้น [c] ชิ้นเดียว ตามตำแหน่งของมัน (ไม่หมุน ไม่สนว่าซ่อน) — ใช้กับที่เก็บภาพของแคนวาส
List<WfPrim> wfComponentPrims(WireframeDiagram d, WfComponent c) {
  final b = _Builder(wfPalette(d));
  _component(b, d, c);
  return b.out;
}

/// ชิ้นวาดของกรอบหน้าจอเปล่า
List<WfPrim> wfFramePrims(WireframeDiagram d) {
  final p = wfPalette(d);
  final b = _Builder(p);
  b.rect(0, 0, d.width, d.height, fill: p.frame, stroke: p.sketch ? p.border : 0xFF98A2B3, width: p.sketch ? 1.6 : 1, seed: 7);
  return b.out;
}

int _seedOf(String s) {
  var h = 0x811C9DC5;
  for (final u in s.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// ตัวสร้างชิ้นวาด: รูปแบบร่างวาดเส้นแบบสั่นเล็กน้อยเหมือนวาดมือ (สุ่มแบบคงที่ตาม id ชิ้น)
class _Builder {
  _Builder(this.p);
  final WfPalette p;
  final out = <WfPrim>[];
  math.Random _rng = math.Random(1);

  void seed(String id) => _rng = math.Random(_seedOf(id));

  double _j(double amp) => (_rng.nextDouble() * 2 - 1) * amp;

  /// เส้นตรงแบบวาดมือ (แบ่งช่วง สั่นตั้งฉากกับเส้น และเลยปลายเล็กน้อย)
  List<WfCmd> _wobbly(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1, dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.01) return [];
    final ux = dx / len, uy = dy / len, nx = -uy, ny = ux;
    final over = math.min(2.0, len * 0.04);
    final steps = math.max(1, (len / 36).ceil());
    final amp = math.min(1.1, len * 0.02);
    final pts = <RoutePoint>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final along = -over + (len + 2 * over) * t;
      final off = (i == 0 || i == steps) ? _j(amp * 0.5) : _j(amp);
      pts.add((x1 + ux * along + nx * off, y1 + uy * along + ny * off));
    }
    return [('M', [pts.first]), for (final q in pts.skip(1)) ('L', [q])];
  }

  void line(double x1, double y1, double x2, double y2, {required int stroke, double width = 1, bool dashed = false}) {
    if (p.sketch && !dashed) {
      out.add(WfPathPrim(_wobbly(x1, y1, x2, y2), stroke: stroke, width: width * 1.15));
    } else {
      out.add(WfPathPrim([('M', [(x1, y1)]), ('L', [(x2, y2)])], stroke: stroke, width: width, dashed: dashed));
    }
  }

  List<WfCmd> _roundRect(double x, double y, double w, double h, double r) {
    r = math.max(0, math.min(r, math.min(w, h) / 2));
    if (r < 0.5) return [('M', [(x, y)]), ('L', [(x + w, y)]), ('L', [(x + w, y + h)]), ('L', [(x, y + h)]), ('Z', const [])];
    const k = 0.5522847498;
    final rr = r * (1 - k);
    return [
      ('M', [(x + r, y)]),
      ('L', [(x + w - r, y)]),
      ('C', [(x + w - rr, y), (x + w, y + rr), (x + w, y + r)]),
      ('L', [(x + w, y + h - r)]),
      ('C', [(x + w, y + h - rr), (x + w - rr, y + h), (x + w - r, y + h)]),
      ('L', [(x + r, y + h)]),
      ('C', [(x + rr, y + h), (x, y + h - rr), (x, y + h - r)]),
      ('L', [(x, y + r)]),
      ('C', [(x, y + rr), (x + rr, y), (x + r, y)]),
      ('Z', const []),
    ];
  }

  void rect(double x, double y, double w, double h,
      {int? fill, int? stroke, double width = 1, double r = 0, bool dashed = false, int? seed}) {
    if (seed != null) _rng = math.Random(seed);
    if (p.sketch) {
      if (fill != null) out.add(WfPathPrim(_roundRect(x, y, w, h, math.min(r, 3)), fill: fill));
      if (stroke != null) {
        if (dashed) {
          out.add(WfPathPrim(_roundRect(x, y, w, h, math.min(r, 3)), stroke: stroke, width: width, dashed: true));
        } else {
          final cmds = [
            ..._wobbly(x, y, x + w, y),
            ..._wobbly(x + w, y, x + w, y + h),
            ..._wobbly(x + w, y + h, x, y + h),
            ..._wobbly(x, y + h, x, y),
          ];
          out.add(WfPathPrim(cmds, stroke: stroke, width: width * 1.15));
        }
      }
      return;
    }
    out.add(WfPathPrim(_roundRect(x, y, w, h, r), fill: fill, stroke: stroke, width: width, dashed: dashed));
  }

  List<WfCmd> _ellipseCmds(double cx, double cy, double rx, double ry) {
    if (p.sketch) {
      final n = math.max(12, ((rx + ry) / 3).round());
      final start = _rng.nextDouble() * math.pi * 2;
      final pts = <RoutePoint>[];
      for (var i = 0; i <= n; i++) {
        final a = start + i / n * math.pi * 2 * 1.04;
        final jr = 1 + _j(0.035);
        pts.add((cx + math.cos(a) * rx * jr, cy + math.sin(a) * ry * jr));
      }
      return [('M', [pts.first]), for (final q in pts.skip(1)) ('L', [q])];
    }
    const k = 0.5522847498;
    return [
      ('M', [(cx + rx, cy)]),
      ('C', [(cx + rx, cy + ry * k), (cx + rx * k, cy + ry), (cx, cy + ry)]),
      ('C', [(cx - rx * k, cy + ry), (cx - rx, cy + ry * k), (cx - rx, cy)]),
      ('C', [(cx - rx, cy - ry * k), (cx - rx * k, cy - ry), (cx, cy - ry)]),
      ('C', [(cx + rx * k, cy - ry), (cx + rx, cy - ry * k), (cx + rx, cy)]),
      ('Z', const []),
    ];
  }

  void ellipse(double cx, double cy, double rx, double ry, {int? fill, int? stroke, double width = 1}) {
    if (fill != null) {
      final cmds = p.sketch ? [..._ellipseCmds(cx, cy, rx, ry), ('Z', const <RoutePoint>[])] : _ellipseCmds(cx, cy, rx, ry);
      out.add(WfPathPrim(cmds, fill: fill));
    }
    if (stroke != null) out.add(WfPathPrim(_ellipseCmds(cx, cy, rx, ry), stroke: stroke, width: p.sketch ? width * 1.15 : width));
  }

  void poly(List<RoutePoint> pts, {int? fill, int? stroke, double width = 1, bool close = false}) {
    out.add(WfPathPrim([
      ('M', [pts.first]),
      for (final q in pts.skip(1)) ('L', [q]),
      if (close) ('Z', const []),
    ], fill: fill, stroke: stroke, width: width));
  }

  void text(String t, double x, double y, double w, double h,
      {required double size, required int color, bool bold = false, int align = 0, bool top = false, int? maxLines}) {
    if (t.trim().isEmpty || w < 2 || h < 2) return;
    out.add(WfTextPrim(t, x, y, w, h, size: size, color: color, bold: bold, align: align, top: top, maxLines: maxLines));
  }

  /// แถบเทาแทนข้อความ (placeholder)
  void bar(double x, double y, double w, double h, int color) {
    if (w <= 1 || h <= 0) return;
    if (p.sketch) {
      line(x, y + h / 2, x + w, y + h / 2, stroke: color, width: math.max(1, h * 0.6));
    } else {
      out.add(WfPathPrim(_roundRect(x, y, w, h, h / 2), fill: color));
    }
  }
}

int _align(WfAlign a) => switch (a) { WfAlign.left => 0, WfAlign.center => 1, WfAlign.right => 2 };

void _component(_Builder b, WireframeDiagram d, WfComponent c) {
  final p = b.p;
  b.seed(c.id);
  final x = c.x, y = c.y, w = c.w, h = c.h;
  // สีของชิ้น: ค่าที่ผู้ใช้กำหนด (รูปแบบร่าง = แปลงเป็นเทา) ; ใช้งานไม่ได้ = จางลง
  int col(int? custom, int fallback) {
    var v = custom ?? fallback;
    if (p.sketch && custom != null) v = wfGray(v);
    return c.disabled ? _alpha(v, 0.45) : v;
  }

  final border = col(c.stroke, p.border);
  final surface = col(c.fill, p.surface);
  final ink = col(c.textColor, p.text);
  final muted = c.disabled ? _alpha(p.muted, 0.45) : p.muted;
  final accent = c.disabled ? _alpha(p.accent, 0.45) : p.accent;
  final fs = c.effectiveFontSize;
  final sw = p.sketch ? 1.4 : 1.0;
  final al = _align(c.align);
  final lineH = fs * 1.3;
  int lines(double hh) => math.max(1, (hh / lineH).floor());

  switch (c.kind) {
    case WfKind.container:
      b.rect(x, y, w, h, fill: c.fill == null ? null : surface, stroke: border, width: sw, r: 6, dashed: !p.sketch && c.fill == null);
      b.text(c.text, x + 8, y + 4, w - 16, math.min(h - 8, lineH), size: fs * 0.85, color: muted, align: al, top: true, maxLines: 1);
    case WfKind.heading || WfKind.label || WfKind.paragraph:
      if (c.fill != null) b.rect(x, y, w, h, fill: surface);
      b.text(c.text, x, y, w, h,
          size: fs, color: ink, bold: c.kind == WfKind.heading || c.bold, align: al, top: c.kind == WfKind.paragraph, maxLines: lines(h));
    case WfKind.button:
      final primary = !c.secondary;
      final fill = c.fill != null ? surface : (primary ? (p.sketch ? 0xFFDADADA : accent) : p.surface);
      final stroke = c.stroke != null ? border : (primary ? (p.sketch ? p.border : accent) : (p.sketch ? p.border : accent));
      final txt = c.textColor != null ? ink : (primary ? (p.sketch ? p.text : p.onAccent) : (p.sketch ? p.text : accent));
      b.rect(x, y, w, h, fill: c.disabled ? _alpha(fill, 0.5) : fill, stroke: stroke, width: primary && p.sketch ? 2 : sw, r: 6);
      b.text(c.text, x + 6, y, w - 12, h, size: fs, color: c.disabled ? _alpha(txt, 0.6) : txt, bold: true, align: al, maxLines: 1);
    case WfKind.input || WfKind.select || WfKind.search || WfKind.textarea:
      b.rect(x, y, w, h, fill: c.disabled ? col(null, p.subtle) : surface, stroke: border, width: sw, r: 4);
      var tx = x + 10;
      if (c.kind == WfKind.search) {
        final r = math.min(6.0, h / 4);
        b.ellipse(x + 12 + r, y + h / 2 - 1, r, r, stroke: muted, width: 1.4);
        b.line(x + 12 + r * 1.7, y + h / 2 - 1 + r * 0.7, x + 12 + r * 2.5, y + h / 2 - 1 + r * 1.5, stroke: muted, width: 1.4);
        tx = x + 18 + r * 2.5;
      }
      var right = x + w - 10;
      if (c.kind == WfKind.select) {
        final cx = x + w - 16, cy = y + h / 2;
        b.poly([(cx - 5, cy - 2.5), (cx, cy + 2.5), (cx + 5, cy - 2.5)], stroke: ink, width: 1.5);
        right = x + w - 28;
      }
      final top = c.kind == WfKind.textarea;
      b.text(c.text, tx, top ? y + 8 : y, right - tx, top ? h - 16 : h,
          size: fs, color: c.kind == WfKind.select ? ink : muted, align: al, top: top, maxLines: top ? lines(h - 16) : 1);
    case WfKind.checkbox || WfKind.radio:
      final s = math.min(16.0, h);
      final bx = x, by = y + (h - s) / 2;
      if (c.kind == WfKind.checkbox) {
        b.rect(bx, by, s, s, fill: c.checked && !p.sketch ? accent : surface, stroke: c.checked && !p.sketch ? accent : border, width: sw, r: 3);
        if (c.checked) {
          b.poly([(bx + s * 0.22, by + s * 0.52), (bx + s * 0.42, by + s * 0.72), (bx + s * 0.8, by + s * 0.3)],
              stroke: p.sketch ? p.text : p.onAccent, width: 2);
        }
      } else {
        b.ellipse(bx + s / 2, by + s / 2, s / 2, s / 2, fill: surface, stroke: c.checked && !p.sketch ? accent : border, width: sw);
        if (c.checked) b.ellipse(bx + s / 2, by + s / 2, s * 0.25, s * 0.25, fill: p.sketch ? p.text : accent);
      }
      b.text(c.text, x + s + 8, y, w - s - 8, h, size: fs, color: ink, align: 0, maxLines: 1);
    case WfKind.toggle:
      final th = math.min(20.0, h), tw = th * 1.8;
      final ty = y + (h - th) / 2;
      final on = c.checked;
      b.rect(x, ty, tw, th, fill: on ? (p.sketch ? 0xFF9A9A9A : accent) : col(null, p.subtle), stroke: on && !p.sketch ? accent : border, width: sw, r: th / 2);
      final kx = on ? x + tw - th / 2 : x + th / 2;
      b.ellipse(kx, ty + th / 2, th / 2 - 3, th / 2 - 3, fill: 0xFFFFFFFF, stroke: p.sketch ? p.border : null, width: 1);
      b.text(c.text, x + tw + 8, y, w - tw - 8, h, size: fs, color: ink, maxLines: 1);
    case WfKind.slider:
      final cy = y + h / 2, k = x + w * 0.4;
      b.line(x + 6, cy, x + w - 6, cy, stroke: col(null, p.sketch ? p.muted : p.border), width: 3);
      b.line(x + 6, cy, k, cy, stroke: accent, width: 3);
      b.ellipse(k, cy, math.min(8, h / 2), math.min(8, h / 2), fill: 0xFFFFFFFF, stroke: accent, width: 1.6);
    case WfKind.image:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : col(null, p.sketch ? 0xFFFFFFFF : 0xFFE4E7EC), stroke: border, width: sw);
      if (p.sketch) {
        b.line(x, y, x + w, y + h, stroke: border, width: 1);
        b.line(x + w, y, x, y + h, stroke: border, width: 1);
      } else {
        final m = math.min(w, h);
        b.poly([(x + w * 0.15, y + h * 0.8), (x + w * 0.4, y + h * 0.45), (x + w * 0.58, y + h * 0.65), (x + w * 0.7, y + h * 0.52), (x + w * 0.88, y + h * 0.8)],
            fill: 0xFFC4CAD4, close: true);
        b.ellipse(x + w * 0.7, y + h * 0.3, m * 0.08, m * 0.08, fill: 0xFFC4CAD4);
      }
    case WfKind.icon:
      final m = math.min(w, h);
      b.rect(x, y, w, h, fill: c.fill != null ? surface : col(null, p.subtle), stroke: p.sketch ? border : null, width: sw, r: m * 0.2);
      if (p.sketch) {
        b.line(x + w * 0.25, y + h * 0.25, x + w * 0.75, y + h * 0.75, stroke: border);
        b.line(x + w * 0.75, y + h * 0.25, x + w * 0.25, y + h * 0.75, stroke: border);
      } else {
        b.ellipse(x + w / 2, y + h / 2, m * 0.22, m * 0.22, stroke: col(c.stroke, p.muted), width: 1.8);
      }
    case WfKind.avatar:
      final r = math.min(w, h) / 2;
      final cx = x + w / 2, cy = y + h / 2;
      b.ellipse(cx, cy, r, r, fill: c.fill != null ? surface : col(null, p.subtle), stroke: border, width: sw);
      b.ellipse(cx, cy - r * 0.18, r * 0.32, r * 0.32, fill: p.sketch ? null : 0xFFC4CAD4, stroke: p.sketch ? border : null);
      b.poly([(cx - r * 0.6, cy + r * 0.72), (cx - r * 0.45, cy + r * 0.3), (cx + r * 0.45, cy + r * 0.3), (cx + r * 0.6, cy + r * 0.72)],
          fill: p.sketch ? null : 0xFFC4CAD4, stroke: p.sketch ? border : null, close: !p.sketch);
    case WfKind.table:
      _table(b, c, x, y, w, h, surface, border, ink, muted, fs, sw);
    case WfKind.list:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 4);
      final items = c.items;
      final n = math.max(items.length, c.rows);
      if (n == 0) break;
      final rh = math.min(44.0, h / n);
      for (var i = 0; i < n && (i + 1) * rh <= h + 0.5; i++) {
        final ry = y + i * rh;
        b.ellipse(x + 14, ry + rh / 2, 3, 3, fill: muted);
        if (i < items.length) {
          b.text(items[i], x + 26, ry, w - 36, rh, size: fs, color: ink, maxLines: 1);
        } else {
          b.bar(x + 26, ry + rh / 2 - 3, math.min(w * 0.5, w - 40), 6, col(null, p.sketch ? 0xFFBDBDBD : 0xFFE4E7EC));
        }
        if (i < n - 1) b.line(x + 8, ry + rh, x + w - 8, ry + rh, stroke: col(null, p.sketch ? 0xFFBDBDBD : p.border), width: 0.8);
      }
    case WfKind.card:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 8);
      b.text(c.text, x + 12, y + 8, w - 24, lineH, size: fs, color: ink, bold: true, align: al, top: true, maxLines: 1);
    case WfKind.tabs:
      final items = c.items.isEmpty ? [''] : c.items;
      final tw = w / items.length;
      b.line(x, y + h - 1, x + w, y + h - 1, stroke: col(null, p.sketch ? p.border : p.border), width: 1);
      for (var i = 0; i < items.length; i++) {
        final on = i == 0;
        b.text(items[i], x + i * tw + 6, y, tw - 12, h - 2, size: fs, color: on ? (p.sketch ? p.text : accent) : muted, bold: on, align: 1, maxLines: 1);
        if (on) b.line(x + i * tw + 4, y + h - 2, x + (i + 1) * tw - 4, y + h - 2, stroke: p.sketch ? p.text : accent, width: 2.5);
      }
    case WfKind.navbar:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : p.surface), stroke: border, width: sw);
      b.text(c.text, x + 16, y, w * 0.5, h, size: fs, color: ink, bold: true, maxLines: 1);
      for (var i = 0; i < 3; i++) {
        b.bar(x + w - 16 - (i + 1) * 64 + 8, y + h / 2 - 3, 48, 6, col(null, p.sketch ? 0xFFBDBDBD : 0xFFD0D5DD));
      }
    case WfKind.sidebar:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : col(null, p.subtle), stroke: border, width: sw);
      final items = c.items;
      for (var i = 0; i < items.length && 12 + (i + 1) * 36 <= h; i++) {
        final iy = y + 12 + i * 36;
        if (i == 0) b.rect(x + 8, iy, w - 16, 30, fill: p.sketch ? 0xFFE0E0E0 : p.accentTint, r: 6);
        b.text(items[i], x + 18, iy, w - 30, 30, size: fs, color: i == 0 && !p.sketch ? accent : ink, bold: i == 0, maxLines: 1);
      }
    case WfKind.modal:
      b.rect(x + 3, y + 4, w, h, fill: _alpha(0xFF000000, 0.08), r: 10);
      b.rect(x, y, w, h, fill: surface, stroke: border, width: p.sketch ? 1.8 : 1.2, r: 10);
      final th = math.min(48.0, h * 0.3);
      b.text(c.text, x + 16, y, w - 56, th, size: fs, color: ink, bold: true, maxLines: 1);
      final cx = x + w - 22, cy = y + th / 2;
      b.line(cx - 5, cy - 5, cx + 5, cy + 5, stroke: muted, width: 1.6);
      b.line(cx + 5, cy - 5, cx - 5, cy + 5, stroke: muted, width: 1.6);
      b.line(x + 1, y + th, x + w - 1, y + th, stroke: col(null, p.sketch ? p.border : p.border), width: 0.8);
    case WfKind.divider:
      if (h > w) {
        b.line(x + w / 2, y, x + w / 2, y + h, stroke: border, width: 1);
      } else {
        b.line(x, y + h / 2, x + w, y + h / 2, stroke: border, width: 1);
      }
    case WfKind.badge:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : p.accentTint), stroke: p.sketch ? border : null, width: sw, r: h / 2);
      b.text(c.text, x + 4, y, w - 8, h, size: fs, color: c.textColor != null ? ink : (p.sketch ? p.text : accent), bold: true, align: 1, maxLines: 1);
    case WfKind.pagination:
      final labels = ['‹', '1', '2', '3', '›'];
      final s = math.min(h, w / labels.length - 4);
      for (var i = 0; i < labels.length; i++) {
        final bx = x + i * (s + 4);
        final on = i == 1;
        b.rect(bx, y + (h - s) / 2, s, s, fill: on ? (p.sketch ? 0xFFDADADA : accent) : surface, stroke: on && !p.sketch ? accent : border, width: sw, r: 4);
        b.text(labels[i], bx, y + (h - s) / 2, s, s, size: fs, color: on && !p.sketch ? p.onAccent : ink, align: 1, maxLines: 1);
      }
    case WfKind.breadcrumb:
      final items = c.items;
      b.text(items.join('  /  '), x, y, w, h, size: fs, color: muted, align: al, maxLines: 1);
    case WfKind.map:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : 0xFFE6EFE3), stroke: border, width: sw);
      final road = p.sketch ? 0xFFBDBDBD : 0xFFFFFFFF;
      b.line(x, y + h * 0.35, x + w, y + h * 0.55, stroke: road, width: p.sketch ? 1.2 : 5);
      b.line(x + w * 0.3, y, x + w * 0.45, y + h, stroke: road, width: p.sketch ? 1.2 : 5);
      final px = x + w * 0.62, py = y + h * 0.42, r = math.min(10.0, math.min(w, h) * 0.08);
      b.poly([(px - r * 0.8, py + r * 0.4), (px, py + r * 2.2), (px + r * 0.8, py + r * 0.4)], fill: p.sketch ? null : 0xFFE5484D, stroke: p.sketch ? border : null, close: true);
      b.ellipse(px, py, r, r, fill: p.sketch ? 0xFFFFFFFF : 0xFFE5484D, stroke: p.sketch ? border : null);
    case WfKind.chart:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 4);
      final l = x + 24, bt = y + h - 20, tp = y + 16, r = x + w - 16;
      b.line(l, tp, l, bt, stroke: muted, width: 1);
      b.line(l, bt, r, bt, stroke: muted, width: 1);
      const vals = [0.45, 0.75, 0.55, 0.9, 0.65];
      final bw = (r - l) / (vals.length * 1.6);
      for (var i = 0; i < vals.length; i++) {
        final bx = l + bw * 0.6 + i * bw * 1.6, bh = (bt - tp) * vals[i];
        b.rect(bx, bt - bh, bw, bh, fill: p.sketch ? null : _alpha(accent, i.isEven ? 0.85 : 0.55), stroke: p.sketch ? border : null, width: 1.2);
      }
    case WfKind.link:
      b.text(c.text, x, y, w, h, size: fs, color: c.textColor != null ? ink : (p.sketch ? p.text : accent), align: al, maxLines: 1);
      final tw = math.min(w, c.text.trim().length * fs * 0.56);
      final ux = al == 1 ? x + (w - tw) / 2 : (al == 2 ? x + w - tw : x);
      b.line(ux, y + h / 2 + fs * 0.66, ux + tw, y + h / 2 + fs * 0.66, stroke: c.textColor != null ? ink : (p.sketch ? p.text : accent), width: 1);
    case WfKind.chip:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : p.subtle), stroke: border, width: sw, r: h / 2);
      b.text(c.text, x + 10, y, w - h - 6, h, size: fs, color: ink, align: al == 1 ? 0 : al, maxLines: 1);
      final cx = x + w - h / 2 - 2, cy = y + h / 2, k = h * 0.16;
      b.line(cx - k, cy - k, cx + k, cy + k, stroke: muted, width: 1.5);
      b.line(cx + k, cy - k, cx - k, cy + k, stroke: muted, width: 1.5);
    case WfKind.progress:
      final digits = RegExp(r'\d+(\.\d+)?').firstMatch(c.text)?.group(0);
      final pct = (double.tryParse(digits ?? '') ?? 60).clamp(0, 100) / 100;
      final th = math.min(10.0, h);
      final ty = y + (h - th) / 2;
      final showLabel = c.text.trim().isNotEmpty && w > 110;
      final tw = showLabel ? w - 44 : w;
      b.rect(x, ty, tw, th, fill: p.sketch ? 0xFFFFFFFF : col(null, p.subtle), stroke: p.sketch ? border : null, width: sw, r: th / 2);
      if (pct > 0) b.rect(x, ty, math.max(th, tw * pct), th, fill: p.sketch ? 0xFF9A9A9A : accent, r: th / 2);
      if (showLabel) b.text(c.text, x + tw + 8, y, 36, h, size: math.min(fs, 12), color: ink, align: 2, maxLines: 1);
    case WfKind.alert:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : p.accentTint), stroke: border, width: sw, r: 6);
      b.rect(x, y, 5, h, fill: p.sketch ? p.border : accent, r: 2);
      final r = math.min(10.0, h / 3);
      b.ellipse(x + 24, y + h / 2, r, r, fill: p.sketch ? null : accent, stroke: p.sketch ? border : null, width: 1.4);
      b.text('!', x + 24 - r, y + h / 2 - r, r * 2, r * 2, size: r * 1.4, color: p.sketch ? p.text : p.onAccent, bold: true, align: 1, maxLines: 1);
      b.text(c.text, x + 44, y, w - 56, h, size: fs, color: ink, align: al, maxLines: lines(h));
    case WfKind.datepicker:
      b.rect(x, y, w, h, fill: c.disabled ? col(null, p.subtle) : surface, stroke: border, width: sw, r: 4);
      b.text(c.text, x + 10, y, w - 44, h, size: fs, color: muted, align: al, maxLines: 1);
      final ix = x + w - 28, iy = y + h / 2 - 8;
      b.rect(ix, iy + 2, 16, 14, stroke: ink, width: 1.3, r: 2);
      b.line(ix, iy + 7, ix + 16, iy + 7, stroke: ink, width: 1.3);
      b.line(ix + 4.5, iy, ix + 4.5, iy + 4, stroke: ink, width: 1.3);
      b.line(ix + 11.5, iy, ix + 11.5, iy + 4, stroke: ink, width: 1.3);
    case WfKind.upload:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? null : p.subtle), stroke: border, width: sw, r: 8, dashed: true);
      final cx = x + w / 2, cy = y + h * 0.36, s = math.min(14.0, h * 0.14);
      b.line(cx, cy + s, cx, cy - s, stroke: muted, width: 2);
      b.poly([(cx - s * 0.7, cy - s * 0.2), (cx, cy - s), (cx + s * 0.7, cy - s * 0.2)], stroke: muted, width: 2);
      b.text(c.text, x + 12, y + h * 0.58, w - 24, h * 0.34, size: fs, color: muted, align: 1, top: true, maxLines: lines(h * 0.34));
    case WfKind.stepper:
      final items = c.items.isEmpty ? ['', '', ''] : c.items;
      final n = items.length;
      final r = math.min(11.0, h * 0.24);
      final cy = y + r + 2;
      for (var i = 0; i < n; i++) {
        final cx = x + (i + 0.5) * w / n;
        if (i < n - 1) b.line(cx + r + 2, cy, x + (i + 1.5) * w / n - r - 2, cy, stroke: i == 0 && !p.sketch ? accent : border, width: 1.5);
        final on = i == 0;
        b.ellipse(cx, cy, r, r, fill: on ? (p.sketch ? 0xFF9A9A9A : accent) : surface, stroke: on && !p.sketch ? accent : border, width: sw);
        b.text('${i + 1}', cx - r, cy - r, r * 2, r * 2, size: r * 1.15, color: on ? (p.sketch ? p.text : p.onAccent) : muted, bold: true, align: 1, maxLines: 1);
        b.text(items[i], cx - w / n / 2 + 2, cy + r + 4, w / n - 4, math.max(0, h - (cy - y) - r - 4), size: math.min(fs, 13), color: on ? ink : muted, bold: on, align: 1, top: true, maxLines: 2);
      }
    case WfKind.rating:
      final s = math.min(h, w / 5) - 2;
      for (var i = 0; i < 5; i++) {
        final cx = x + (i + 0.5) * (w / 5), cy = y + h / 2;
        final pts = <RoutePoint>[];
        for (var k = 0; k < 10; k++) {
          final ang = -math.pi / 2 + k * math.pi / 5;
          final rr = k.isEven ? s / 2 : s / 4.4;
          pts.add((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr));
        }
        final on = i < 3;
        b.poly(pts, fill: on ? (p.sketch ? 0xFFBDBDBD : 0xFFF5B301) : null, stroke: on && !p.sketch ? 0xFFF5B301 : border, width: 1.3, close: true);
      }
    case WfKind.video:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : 0xFF1D2939), stroke: border, width: sw, r: 4);
      final cx = x + w / 2, cy = y + h / 2 - 8, r = math.min(w, h) * 0.13;
      final fg = p.sketch ? border : 0xFFFFFFFF;
      b.ellipse(cx, cy, r, r, stroke: fg, width: 2);
      b.poly([(cx - r * 0.3, cy - r * 0.45), (cx + r * 0.5, cy), (cx - r * 0.3, cy + r * 0.45)], fill: p.sketch ? null : fg, stroke: p.sketch ? border : null, close: true);
      b.line(x + 14, y + h - 16, x + w - 14, y + h - 16, stroke: p.sketch ? border : 0xFF667085, width: 3);
      b.line(x + 14, y + h - 16, x + 14 + (w - 28) * 0.35, y + h - 16, stroke: p.sketch ? p.text : accent, width: 3);
    case WfKind.accordion:
      final items = c.items.isEmpty ? [''] : c.items;
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 6);
      var ay = y;
      for (var i = 0; i < items.length && ay + 36 <= y + h + 0.5; i++) {
        final open = i == 0;
        b.text(items[i], x + 14, ay, w - 44, 36, size: fs, color: ink, bold: open, maxLines: 1);
        final cx = x + w - 20, cy = ay + 18;
        if (open) {
          b.poly([(cx - 5, cy - 2.5), (cx, cy + 2.5), (cx + 5, cy - 2.5)], stroke: ink, width: 1.5);
        } else {
          b.poly([(cx - 2.5, cy - 5), (cx + 2.5, cy), (cx - 2.5, cy + 5)], stroke: ink, width: 1.5);
        }
        ay += 36;
        if (open && ay + 44 <= y + h + 0.5) {
          final grey = col(null, p.sketch ? 0xFFBDBDBD : 0xFFE4E7EC);
          b.bar(x + 14, ay + 6, w - 40, 6, grey);
          b.bar(x + 14, ay + 20, (w - 40) * 0.7, 6, grey);
          ay += 44;
        }
        if (i < items.length - 1 && ay < y + h - 1) b.line(x + 1, ay, x + w - 1, ay, stroke: border, width: 0.8);
      }
    case WfKind.footer:
      b.rect(x, y, w, h, fill: c.fill != null ? surface : col(null, p.subtle), stroke: border, width: sw);
      b.text(c.text, x + 16, y, w * 0.5, h, size: fs, color: muted, align: al == 1 ? 0 : al, maxLines: 1);
      for (var i = 0; i < 3; i++) {
        b.bar(x + w - 16 - (i + 1) * 72 + 8, y + h / 2 - 3, 56, 6, col(null, p.sketch ? 0xFFBDBDBD : 0xFFD0D5DD));
      }
    case WfKind.tooltip:
      final bh = math.max(8.0, h - 8);
      b.rect(x, y, w, bh, fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : 0xFF1D2939), stroke: border, width: sw, r: 6);
      b.poly([(x + w / 2 - 6, y + bh), (x + w / 2, y + bh + 7), (x + w / 2 + 6, y + bh)],
          fill: c.fill != null ? surface : (p.sketch ? 0xFFFFFFFF : 0xFF1D2939), stroke: p.sketch ? border : null, close: true);
      b.text(c.text, x + 8, y, w - 16, bh, size: fs, color: c.textColor != null ? ink : (p.sketch ? p.text : 0xFFFFFFFF), align: 1, maxLines: lines(bh));
    case WfKind.skeleton:
      final grey = col(null, p.sketch ? 0xFFBDBDBD : 0xFFE4E7EC);
      final r = math.min(h * 0.28, 22.0);
      b.ellipse(x + r, y + r, r, r, fill: p.sketch ? null : grey, stroke: p.sketch ? grey : null, width: 1.5);
      b.bar(x + r * 2 + 12, y + r - 8, (w - r * 2 - 12) * 0.7, 8, grey);
      b.bar(x + r * 2 + 12, y + r + 6, (w - r * 2 - 12) * 0.45, 8, grey);
      var sy = y + r * 2 + 14;
      for (final f in const [1.0, 0.92, 0.6]) {
        if (sy + 8 > y + h + 0.5) break;
        b.bar(x, sy, w * f, 8, grey);
        sy += 16;
      }
    case WfKind.calendar:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 8);
      final hh = math.min(40.0, h * 0.15);
      b.text(c.text, x + 36, y, w - 72, hh, size: fs, color: ink, bold: true, align: 1, maxLines: 1);
      b.poly([(x + 22, y + hh / 2 - 5), (x + 16, y + hh / 2), (x + 22, y + hh / 2 + 5)], stroke: muted, width: 1.5);
      b.poly([(x + w - 22, y + hh / 2 - 5), (x + w - 16, y + hh / 2), (x + w - 22, y + hh / 2 + 5)], stroke: muted, width: 1.5);
      final cw = (w - 16) / 7, rh = math.max(1.0, (h - hh - 28) / 6);
      final ds = math.min(12.0, cw * 0.42);
      const days = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];
      for (var i = 0; i < 7; i++) {
        b.text(days[i], x + 8 + i * cw, y + hh, cw, 22, size: ds * 0.9, color: muted, align: 1, maxLines: 1);
      }
      for (var n = 0; n < 30; n++) {
        final idx = n + 3; // วันที่ 1 ตรงคอลัมน์ที่ 4
        final cx = x + 8 + (idx % 7) * cw, cy = y + hh + 24 + (idx ~/ 7) * rh;
        if (cy + rh > y + h + 0.5) break;
        final today = n == 14;
        if (today) b.ellipse(cx + cw / 2, cy + rh / 2, math.min(cw, rh) * 0.4, math.min(cw, rh) * 0.4, fill: p.sketch ? 0xFFDADADA : accent, stroke: p.sketch ? border : null);
        b.text('${n + 1}', cx, cy, cw, rh, size: ds, color: today && !p.sketch ? p.onAccent : ink, bold: today, align: 1, maxLines: 1);
      }
    case WfKind.stat:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 8);
      final parts = c.items;
      final label = parts.length > 1 ? parts.first : '';
      final value = parts.isEmpty ? '' : (parts.length > 1 ? parts[1] : parts.first);
      b.text(label, x + 14, y + 10, w - 28, lineH, size: fs * 0.85, color: muted, align: al, top: true, maxLines: 1);
      b.text(value, x + 14, y + 10 + lineH, w - 28, math.max(0, h - lineH - 18), size: fs * 2.1, color: ink, bold: true, align: al, maxLines: 1);
    case WfKind.tree:
      final raw = [for (final l in c.text.split('\n')) if (l.trim().isNotEmpty) l];
      final rh = math.min(28.0, h / math.max(1, raw.length));
      int ind(String l) => (l.length - l.trimLeft().length) ~/ 2;
      for (var i = 0; i < raw.length && (i + 1) * rh <= h + 0.5; i++) {
        final d0 = ind(raw[i]);
        final ry = y + i * rh, rx = x + 6 + d0 * 18;
        final parent = i + 1 < raw.length && ind(raw[i + 1]) > d0;
        if (parent) {
          b.poly([(rx + 2, ry + rh / 2 - 3), (rx + 7, ry + rh / 2 + 2), (rx + 12, ry + rh / 2 - 3)], stroke: ink, width: 1.4);
        } else {
          b.ellipse(rx + 7, ry + rh / 2, 2.2, 2.2, fill: muted);
        }
        b.text(raw[i].trim(), rx + 18, ry, math.max(0, x + w - rx - 22), rh, size: fs, color: ink, bold: parent, maxLines: 1);
        if (d0 > 0) b.line(x + 6 + (d0 - 1) * 18 + 7, ry, x + 6 + (d0 - 1) * 18 + 7, ry + rh / 2, stroke: border, width: 0.8);
      }
    // ---- Phase 18b: มือถือ ----
    case WfKind.statusBar:
      final cy = y + h / 2, rx = x + w - 20;
      b.text(c.text, x + 20, y, w * 0.4, h, size: fs, color: ink, bold: true, maxLines: 1);
      // แบตเตอรี่ · wifi · สัญญาณ (เรียงจากขวา)
      b.rect(rx - 24, cy - 5.5, 22, 11, stroke: ink, width: 1.2, r: 3);
      b.rect(rx - 22, cy - 3.5, 15, 7, fill: ink, r: 1.5);
      b.rect(rx - 1, cy - 2.5, 2, 5, fill: ink);
      final wx = rx - 42;
      for (final r0 in const [3.5, 6.5, 9.5]) {
        b.poly([(wx - r0 * 0.7, cy + 5 - r0 * 0.7), (wx, cy + 5 - r0), (wx + r0 * 0.7, cy + 5 - r0 * 0.7)], stroke: ink, width: 1.3);
      }
      for (var i = 0; i < 4; i++) {
        final bh = 4 + i * 2.5;
        b.rect(rx - 78 + i * 5, cy + 5.5 - bh, 3, bh, fill: ink, r: 0.8);
      }
    case WfKind.appBar:
      final cy = y + h / 2;
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw);
      b.poly([(x + 26, cy - 8), (x + 18, cy), (x + 26, cy + 8)], stroke: ink, width: 1.8);
      b.text(c.text, x + 44, y, math.max(0, w - 44 - 92), h, size: fs, color: ink, bold: true, align: al == 1 ? 0 : al, maxLines: 1);
      for (final dx in const [80.0, 44.0]) {
        b.rect(x + w - dx, cy - 12, 24, 24, stroke: muted, width: 1.3, r: 7);
        b.ellipse(x + w - dx + 12, cy, 2.8, 2.8, fill: muted);
      }
    case WfKind.bottomNav:
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw);
      final tabs = c.items.isEmpty ? [''] : c.items.take(5).toList();
      final tw = w / tabs.length;
      for (var i = 0; i < tabs.length; i++) {
        final on = i == 0, cx = x + tw * i + tw / 2;
        final top = y + math.max(4.0, (h - 46) / 2);
        b.rect(cx - 11, top, 22, 22, fill: on ? (p.sketch ? 0xFFDADADA : accent) : null, stroke: on && !p.sketch ? accent : muted, width: 1.3, r: 6);
        b.text(tabs[i], x + tw * i, top + 24, tw, 18, size: fs * 0.92, color: on ? (p.sketch ? ink : accent) : muted, bold: on, align: 1, maxLines: 1);
      }
    case WfKind.fab:
      final r = math.min(w, h) / 2, cx = x + w / 2, cy = y + h / 2;
      if (!p.sketch) b.ellipse(cx, cy + 3, r, r, fill: 0x22000000);
      b.ellipse(cx, cy, r, r, fill: c.fill != null ? surface : (p.sketch ? 0xFFDADADA : accent), stroke: p.sketch ? border : null, width: sw * 1.2);
      final glyph = c.textColor != null ? ink : (p.sketch ? p.text : p.onAccent);
      final t = c.text.trim();
      if (t.isEmpty || t == '+') {
        b.line(cx - r * 0.36, cy, cx + r * 0.36, cy, stroke: glyph, width: 2.4);
        b.line(cx, cy - r * 0.36, cx, cy + r * 0.36, stroke: glyph, width: 2.4);
      } else {
        b.text(t, x, y, w, h, size: fs, color: glyph, bold: true, align: 1, maxLines: 1);
      }
    case WfKind.bottomSheet:
      final its = c.items;
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 16);
      b.bar(x + w / 2 - 18, y + 10, 36, 4, col(null, p.sketch ? 0xFFBDBDBD : 0xFFD0D5DD));
      if (its.isEmpty) break;
      b.text(its.first, x + 24, y + 24, w - 48, 30, size: fs * 1.15, color: ink, bold: true, maxLines: 1);
      for (var i = 1; i < its.length; i++) {
        final ry = y + 64 + (i - 1) * 58;
        if (ry + 58 > y + h + 0.5) break;
        b.line(x + 24, ry, x + w - 24, ry, stroke: border, width: 0.8);
        final first = i == 1;
        b.ellipse(x + 34, ry + 29, 9, 9, fill: first ? (p.sketch ? 0xFFDADADA : accent) : null, stroke: first && !p.sketch ? accent : muted, width: 1.4);
        b.text(its[i], x + 56, ry, w - 80, 58, size: fs, color: ink, bold: first, maxLines: 1);
      }
    case WfKind.drawer:
      final its = c.items;
      b.rect(x, y, w, h, fill: surface, stroke: border, width: sw);
      final hh = math.min(150.0, h * 0.25);
      b.rect(x + 1, y + 1, w - 2, hh, fill: col(null, p.subtle));
      final ar = math.min(26.0, hh * 0.17);
      b.ellipse(x + 24 + ar, y + hh * 0.3 + ar, ar, ar, fill: surface, stroke: muted, width: 1.4);
      if (its.isNotEmpty) b.text(its[0], x + 24, y + hh - 50, w - 48, 24, size: fs * 1.15, color: ink, bold: true, maxLines: 1);
      if (its.length > 1) b.text(its[1], x + 24, y + hh - 26, w - 48, 20, size: fs * 0.85, color: muted, maxLines: 1);
      for (var i = 2; i < its.length; i++) {
        final ry = y + hh + 20 + (i - 2) * 54;
        if (ry + 44 > y + h + 0.5) break;
        final on = i == 2;
        if (on) b.rect(x + 10, ry, w - 20, 44, fill: p.sketch ? 0xFFE2E2E2 : p.accentTint, r: 8);
        b.rect(x + 24, ry + 11, 22, 22, fill: on && !p.sketch ? accent : null, stroke: on && !p.sketch ? accent : muted, width: 1.3, r: 6);
        b.text(its[i], x + 58, ry, w - 76, 44, size: fs, color: on && !p.sketch ? accent : ink, bold: on, maxLines: 1);
      }
    // ---- Phase 18b: ฟอร์ม ----
    case WfKind.segmented:
      final its = c.items.isEmpty ? [''] : c.items.take(5).toList();
      b.rect(x, y, w, h, fill: col(null, p.subtle), stroke: border, width: sw, r: math.min(9.0, h / 2));
      final sgw = (w - 8) / its.length;
      b.rect(x + 4, y + 4, sgw, h - 8, fill: surface, stroke: border, width: 1.1, r: math.min(6.0, h / 2));
      for (var i = 0; i < its.length; i++) {
        b.text(its[i], x + 4 + i * sgw, y, sgw, h, size: fs * 0.92, color: i == 0 ? ink : muted, bold: i == 0, align: 1, maxLines: 1);
      }
    case WfKind.optionGroup:
      final its = c.items;
      if (its.isEmpty) break;
      b.text(its.first, x, y, w, lineH + 4, size: fs, color: ink, bold: true, top: true, maxLines: 1);
      final opts = its.skip(1).toList();
      final rh = opts.isEmpty ? 30.0 : math.min(36.0, (h - 30) / opts.length);
      for (var i = 0; i < opts.length; i++) {
        final cy = y + 30 + i * rh + rh / 2;
        if (cy + rh / 2 > y + h + 0.5) break;
        final sel = i == 0;
        if (c.secondary) {
          b.rect(x + 2, cy - 8, 16, 16, fill: sel && !p.sketch ? accent : surface, stroke: sel && !p.sketch ? accent : border, width: sw, r: 3);
          if (sel) b.poly([(x + 5, cy), (x + 9, cy + 4), (x + 15, cy - 4)], stroke: p.sketch ? p.text : p.onAccent, width: 2);
        } else {
          b.ellipse(x + 10, cy, 8, 8, fill: surface, stroke: sel && !p.sketch ? accent : border, width: sw);
          if (sel) b.ellipse(x + 10, cy, 4, 4, fill: p.sketch ? p.text : accent);
        }
        b.text(opts[i], x + 28, cy - rh / 2, w - 28, rh, size: fs, color: ink, maxLines: 1);
      }
    case WfKind.password:
      b.rect(x, y, w, h, fill: c.disabled ? col(null, p.subtle) : surface, stroke: border, width: sw, r: 4);
      final cy = y + h / 2, t = c.text.trim();
      if (t.isEmpty) {
        for (var i = 0; i < 8 && 16 + i * 10 + 20 < w - 40; i++) {
          b.ellipse(x + 18 + i * 10, cy, 3, 3, fill: ink);
        }
      } else {
        b.text(t, x + 10, y, w - 56, h, size: fs, color: muted, maxLines: 1);
      }
      b.ellipse(x + w - 24, cy, 9, 5.5, stroke: muted, width: 1.4);
      b.ellipse(x + w - 24, cy, 2.4, 2.4, fill: muted);
    case WfKind.numberInput:
      b.rect(x, y, w, h, fill: c.disabled ? col(null, p.subtle) : surface, stroke: border, width: sw, r: 6);
      final bw = math.min(40.0, w / 3), cy = y + h / 2;
      b.line(x + bw, y + 4, x + bw, y + h - 4, stroke: border, width: 0.8);
      b.line(x + w - bw, y + 4, x + w - bw, y + h - 4, stroke: border, width: 0.8);
      b.line(x + bw / 2 - 6, cy, x + bw / 2 + 6, cy, stroke: ink, width: 1.8);
      b.line(x + w - bw / 2 - 6, cy, x + w - bw / 2 + 6, cy, stroke: ink, width: 1.8);
      b.line(x + w - bw / 2, cy - 6, x + w - bw / 2, cy + 6, stroke: ink, width: 1.8);
      b.text(c.text, x + bw, y, w - 2 * bw, h, size: fs, color: ink, bold: true, align: 1, maxLines: 1);
    case WfKind.timepicker:
      b.rect(x, y, w, h, fill: c.disabled ? col(null, p.subtle) : surface, stroke: border, width: sw, r: 4);
      final cy = y + h / 2;
      b.ellipse(x + 22, cy, 9, 9, stroke: muted, width: 1.4);
      b.poly([(x + 22, cy - 5), (x + 22, cy), (x + 25.5, cy + 2.5)], stroke: muted, width: 1.4);
      b.text(c.text, x + 42, y, math.max(0, w - 80), h, size: fs, color: ink, align: al, maxLines: 1);
      b.poly([(x + w - 23, cy - 2.5), (x + w - 18, cy + 2.5), (x + w - 13, cy - 2.5)], stroke: muted, width: 1.5);
    // ---- Phase 18b: ข้อมูล / สถานะ ----
    case WfKind.emptyState:
      final its = c.items;
      final cx = x + w / 2, rr = math.min(36.0, h * 0.15), cy0 = y + 8 + rr;
      b.ellipse(cx, cy0, rr, rr, fill: c.fill != null ? surface : col(null, p.subtle), stroke: border, width: sw);
      b.rect(cx - rr * 0.38, cy0 - rr * 0.38, rr * 0.76, rr * 0.76, stroke: muted, width: 1.3, r: rr * 0.22);
      b.ellipse(cx, cy0, rr * 0.1, rr * 0.1, fill: muted);
      if (its.isNotEmpty) b.text(its[0], x + 16, cy0 + rr + 14, w - 32, 28, size: fs * 1.2, color: ink, bold: true, align: 1, maxLines: 1);
      if (its.length > 1) b.text(its[1], x + 16, cy0 + rr + 44, w - 32, 36, size: fs * 0.92, color: muted, align: 1, top: true, maxLines: 2);
      if (its.length > 2) {
        final bw = math.min(w - 48, 160.0), by = y + h - 56;
        if (by > cy0 + rr + 70 && bw > 20) {
          final fill = p.sketch ? 0xFFDADADA : accent;
          b.rect(cx - bw / 2, by, bw, 40, fill: fill, stroke: p.sketch ? p.border : accent, width: p.sketch ? 2 : sw, r: 6);
          b.text(its[2], cx - bw / 2 + 6, by, bw - 12, 40, size: fs, color: p.sketch ? p.text : p.onAccent, bold: true, align: 1, maxLines: 1);
        }
      }
    case WfKind.toast:
      final its = c.items;
      final dark = c.fill != null ? surface : (p.sketch ? 0xFF4A4A4A : 0xFF1D2939);
      final fg = c.textColor != null ? ink : 0xFFFFFFFF;
      b.rect(x, y, w, h, fill: dark, stroke: p.sketch ? border : null, width: sw, r: 10);
      final cy = y + h / 2;
      b.ellipse(x + 26, cy, 9, 9, stroke: fg, width: 1.4);
      b.poly([(x + 22, cy), (x + 25, cy + 3), (x + 30, cy - 3)], stroke: fg, width: 1.6);
      final action = its.length > 1 ? its[1] : '';
      b.text(its.isEmpty ? '' : its.first, x + 46, y, math.max(0, w - 46 - (action.isEmpty ? 16 : 92)), h, size: fs, color: fg, maxLines: 1);
      if (action.isNotEmpty) {
        b.text(action, x + w - 88, y, 72, h, size: fs * 0.95, color: p.sketch ? 0xFFD5DBE3 : 0xFF8FB4FF, bold: true, align: 2, maxLines: 1);
      }
    case WfKind.kanban:
      final cols = c.items.isEmpty ? [''] : c.items.take(6).toList();
      const gap = 15.0;
      final cw = (w - gap * (cols.length - 1)) / cols.length;
      final greyBar = col(null, p.sketch ? 0xFFBDBDBD : 0xFFD0D5DD);
      final greyLight = col(null, p.sketch ? 0xFFD8D8D8 : 0xFFE4E7EC);
      for (var i = 0; i < cols.length; i++) {
        final cx0 = x + i * (cw + gap);
        b.rect(cx0, y, cw, h, fill: col(null, p.subtle), stroke: border, width: sw, r: 10);
        final cards = math.max(1, c.rows - i);
        b.text(cols[i], cx0 + 14, y, math.max(0, cw - 50), 40, size: fs * 0.95, color: ink, bold: true, maxLines: 1);
        b.text('$cards', cx0 + cw - 44, y, 30, 40, size: fs * 0.9, color: muted, align: 2, maxLines: 1);
        for (var j = 0; j < cards; j++) {
          final cy1 = y + 44 + j * 84;
          if (cy1 + 72 > y + h + 0.5) break;
          b.rect(cx0 + 10, cy1, cw - 20, 72, fill: surface, stroke: border, width: sw, r: 8);
          b.bar(cx0 + 22, cy1 + 19, math.max(0, cw - 72), 6, greyBar);
          b.bar(cx0 + 22, cy1 + 37, math.max(0, cw - 100), 6, greyLight);
          b.rect(cx0 + 22, cy1 + 50, 44, 14, fill: p.sketch ? 0xFFE2E2E2 : p.accentTint, r: 7);
          b.ellipse(cx0 + cw - 32, cy1 + 56, 9, 9, stroke: muted, width: 1.1);
        }
      }
    case WfKind.timeline:
      final its = c.items;
      if (its.isEmpty) break;
      final step = math.min(62.0, (h - 20) / its.length);
      b.line(x + 16, y + 12, x + 16, y + h - 14, stroke: border, width: 2);
      for (var i = 0; i < its.length; i++) {
        final cy1 = y + 22 + i * step;
        if (cy1 + 16 > y + h + 0.5) break;
        final done = its.length == 1 || i < its.length - 1;
        b.ellipse(x + 16, cy1, 8, 8, fill: done ? (p.sketch ? 0xFFBDBDBD : accent) : surface, stroke: done && !p.sketch ? accent : border, width: 1.6);
        if (done) b.poly([(x + 12.5, cy1), (x + 15, cy1 + 2.5), (x + 19, cy1 - 2.5)], stroke: p.sketch ? p.text : p.onAccent, width: 1.5);
        final (title, sub) = wfSplitPipe(its[i]);
        b.text(title, x + 40, cy1 - 14, math.max(0, w - 48), 20, size: fs, color: done ? ink : muted, bold: true, maxLines: 1);
        if (sub.isNotEmpty) b.text(sub, x + 40, cy1 + 4, math.max(0, w - 48), 18, size: fs * 0.85, color: muted, maxLines: 1);
      }
  }
}

void _table(_Builder b, WfComponent c, double x, double y, double w, double h, int surface, int border, int ink, int muted,
    double fs, double sw) {
  final p = b.p;
  final cols = c.columns.isEmpty ? ['', '', ''] : c.columns;
  final rowsN = c.rows;
  final rh = math.min(40.0, h / (rowsN + 1));
  b.rect(x, y, w, h, fill: surface, stroke: border, width: sw, r: 4);
  b.rect(x, y, w, rh, fill: p.sketch ? 0xFFEDEDED : p.subtle);
  b.line(x, y + rh, x + w, y + rh, stroke: border, width: 1);
  final cw = w / cols.length;
  final placeholder = p.sketch ? 0xFFC8C8C8 : 0xFFE4E7EC;
  for (var i = 0; i < cols.length; i++) {
    b.text(cols[i], x + i * cw + 8, y, cw - 16, rh, size: fs, color: ink, bold: true, maxLines: 1);
    if (i > 0) b.line(x + i * cw, y, x + i * cw, y + math.min(h, rh * (rowsN + 1)), stroke: p.sketch ? 0xFFBDBDBD : p.border, width: 0.8);
  }
  for (var r = 1; r <= rowsN && (r + 1) * rh <= h + 0.5; r++) {
    final ry = y + r * rh;
    if (r > 1) b.line(x, ry, x + w, ry, stroke: p.sketch ? 0xFFBDBDBD : p.border, width: 0.8);
    for (var i = 0; i < cols.length; i++) {
      final len = (cw - 16) * (0.45 + 0.35 * (((r * 7 + i * 3) % 5) / 4));
      b.bar(x + i * cw + 8, ry + rh / 2 - 3, len, 6, placeholder);
    }
  }
}
