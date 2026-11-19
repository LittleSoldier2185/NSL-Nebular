import 'dart:math' as math;

import '../layout/box_ops.dart';
import 'color_utils.dart';
import 'workspace.dart';
import 'api_ref.dart';

/// ชนิดของชิ้นส่วนบนหน้าจอ Wireframe (ลำดับ = ลำดับในคลังชิ้นส่วน)
enum WfKind {
  container,
  heading,
  label,
  paragraph,
  button,
  input,
  textarea,
  checkbox,
  radio,
  toggle,
  select,
  slider,
  search,
  image,
  icon,
  avatar,
  table,
  list,
  card,
  tabs,
  navbar,
  sidebar,
  modal,
  divider,
  badge,
  pagination,
  breadcrumb,
  map,
  chart,
}

/// ชิ้นส่วนที่เป็น "ภาชนะ" — ชิ้นอื่นที่อยู่ข้างในทั้งใบ (และอยู่เหนือมันในลำดับการซ้อน) เป็นลูก ย้ายตามกัน
const Set<WfKind> kWfContainerKinds = {WfKind.container, WfKind.card, WfKind.modal, WfKind.sidebar, WfKind.navbar};

/// ชิ้นส่วนที่ผูกกับตาราง/คอลัมน์ใน ER ได้ (data binding อย่างง่าย)
const Set<WfKind> kWfBindableKinds = {
  WfKind.input,
  WfKind.textarea,
  WfKind.select,
  WfKind.checkbox,
  WfKind.toggle,
  WfKind.label,
  WfKind.table,
  WfKind.list,
};

/// ชิ้นส่วนที่มีสถานะ "เลือกอยู่" (checked/on)
const Set<WfKind> kWfCheckableKinds = {WfKind.checkbox, WfKind.radio, WfKind.toggle};

/// ขนาดเริ่มต้นของแต่ละชนิด
(double, double) wfDefaultSize(WfKind k) => switch (k) {
      WfKind.container => (320, 200),
      WfKind.heading => (280, 40),
      WfKind.label => (160, 24),
      WfKind.paragraph => (320, 72),
      WfKind.button => (120, 40),
      WfKind.input || WfKind.select || WfKind.search => (240, 40),
      WfKind.textarea => (280, 100),
      WfKind.checkbox || WfKind.radio => (160, 24),
      WfKind.toggle => (130, 28),
      WfKind.slider => (200, 28),
      WfKind.image => (200, 140),
      WfKind.icon => (32, 32),
      WfKind.avatar => (48, 48),
      WfKind.table => (480, 200),
      WfKind.list => (260, 180),
      WfKind.card => (260, 180),
      WfKind.tabs => (360, 40),
      WfKind.navbar => (640, 56),
      WfKind.sidebar => (220, 480),
      WfKind.modal => (420, 280),
      WfKind.divider => (300, 12),
      WfKind.badge => (72, 24),
      WfKind.pagination => (240, 36),
      WfKind.breadcrumb => (300, 24),
      WfKind.map => (320, 220),
      WfKind.chart => (320, 200),
    };

/// ขนาดตัวอักษรเริ่มต้นของแต่ละชนิด
double wfDefaultFontSize(WfKind k) => switch (k) {
      WfKind.heading => 22,
      WfKind.navbar || WfKind.modal || WfKind.card => 15,
      WfKind.badge || WfKind.breadcrumb => 12,
      _ => 14,
    };

const double kWfMinSide = 4;
const double kWfMaxSide = 8000;

/// แนวข้อความ
enum WfAlign { left, center, right }

/// รูปแบบการแสดงผลของ Wireframe ทั้งเอกสาร (มีผลกับการวาดเท่านั้น ไม่เปลี่ยนเนื้อหา)
enum WfStyle {
  /// ร่าง / low-fidelity: ขาวดำ เส้นเหมือนวาดมือ รูปภาพเป็นกากบาท
  sketch,

  /// เรียบร้อย / medium-fidelity: UI แบน สีสว่างกลาง ๆ + สีเน้น (accent)
  clean,
}

/// ขนาดหน้าจอสำเร็จรูป
enum WfDevice {
  desktop(1440, 900),
  laptop(1280, 800),
  tablet(768, 1024),
  tabletLandscape(1024, 768),
  mobile(390, 844),
  mobileSmall(360, 800),
  custom(0, 0);

  const WfDevice(this.width, this.height);
  final double width, height;
}

/// สีเน้นเริ่มต้น
const int kWfDefaultAccent = 0xFF2563EB;

/// การผูกชิ้นส่วนกับตาราง (และคอลัมน์) ในเอกสาร ER — เก็บเป็น id ล้วน
class WfDataRef {
  const WfDataRef({required this.docId, required this.tableId, this.columnId});

  final String docId;
  final String tableId;
  final String? columnId;

  Map<String, dynamic> toJson() => {'doc': docId, 'table': tableId, if (columnId != null) 'column': columnId};

  static WfDataRef? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['doc'], t = j['table'], c = j['column'];
    if (d is! String || d.isEmpty || t is! String || t.isEmpty) return null;
    return WfDataRef(docId: d, tableId: t, columnId: c is String && c.isNotEmpty ? c : null);
  }

  @override
  bool operator ==(Object other) =>
      other is WfDataRef && other.docId == docId && other.tableId == tableId && other.columnId == columnId;

  @override
  int get hashCode => Object.hash(docId, tableId, columnId);
}

/// ชิ้นส่วนหนึ่งชิ้นบนหน้าจอ (พิกัดเทียบมุมซ้ายบนของกรอบหน้าจอ)
class WfComponent implements EditableBox {
  WfComponent({
    required this.id,
    required this.kind,
    this.text = '',
    this.x = 0,
    this.y = 0,
    double? w,
    double? h,
    List<String>? columns,
    this.rows = 3,
    this.fill,
    this.stroke,
    this.textColor,
    this.fontSize,
    this.bold = false,
    this.align = WfAlign.left,
    this.disabled = false,
    this.checked = false,
    this.secondary = false,
    this.ref,
    this.hidden = false,
    this.locked = false,
    this.group,
    double rotation = 0,
  })  : w = w ?? wfDefaultSize(kind).$1,
        h = h ?? wfDefaultSize(kind).$2,
        columns = columns ?? [],
        rotation = wfNormAngle(rotation);

  @override
  final String id;
  WfKind kind;

  /// ข้อความ (ปุ่ม/ป้าย/หัวข้อ/placeholder) — แท็บ/breadcrumb/dropdown/รายการ ใช้บรรทัดละรายการ
  String text;
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;

  /// หัวคอลัมน์ของตาราง
  final List<String> columns;

  /// จำนวนแถวตัวอย่างของตาราง/รายการ
  int rows;

  /// สีพื้น/สีเส้นขอบ/สีตัวอักษร (ARGB) — null = ค่าเริ่มต้นตามรูปแบบการแสดงผล
  int? fill, stroke, textColor;

  /// ขนาดตัวอักษร — null = ค่าเริ่มต้นของชนิด
  double? fontSize;
  bool bold;
  WfAlign align;

  /// สถานะ: ใช้งานไม่ได้ (disabled) / เลือกอยู่ (checkbox, radio, switch) / ปุ่มรอง (secondary)
  bool disabled, checked, secondary;

  /// ผูกกับตาราง/คอลัมน์ใน ER (null = ไม่ผูก)
  WfDataRef? ref;

  /// ซ่อน (ไม่วาดบนแคนวาส/ภาพย่อ/Export ; ซ่อนภาชนะ = ลูกซ่อนตาม) — เหมือนปิดตาในแผงเลเยอร์
  bool hidden;

  /// ล็อก: คลิก/ลากเลือกบนแคนวาสไม่โดน ย้าย/ปรับขนาด/หมุน/ลบไม่ได้ (เลือกจากแผงเลเยอร์ได้)
  bool locked;

  /// รหัสกลุ่ม (null = ไม่อยู่กลุ่ม) — สมาชิกกลุ่มเดียวกันถูกเลือก/ย้ายพร้อมกัน
  String? group;

  /// มุมหมุนรอบจุดกึ่งกลาง (องศา ตามเข็มนาฬิกา, 0 ถึง <360)
  double rotation;

  double get right => x + w;
  double get bottom => y + h;
  double get effectiveFontSize => fontSize ?? wfDefaultFontSize(kind);

  /// รายการ (บรรทัดที่ไม่ว่าง) ของข้อความ
  List<String> get items => [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()];

  /// endpoint ในเอกสาร API ที่วัตถุนี้เรียกใช้ (null = ไม่ผูก)
  ApiRef? api;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'text': text,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (columns.isNotEmpty) 'columns': columns,
        if (rows != 3) 'rows': rows,
        if (fill != null) 'fill': fill,
        if (stroke != null) 'stroke': stroke,
        if (textColor != null) 'textColor': textColor,
        if (fontSize != null) 'fontSize': fontSize,
        if (bold) 'bold': true,
        if (align != WfAlign.left) 'align': align.name,
        if (disabled) 'disabled': true,
        if (checked) 'checked': true,
        if (secondary) 'secondary': true,
        if (ref != null) 'ref': ref!.toJson(),
        if (api != null) 'api': api!.toJson(),
        if (hidden) 'hidden': true,
        if (locked) 'locked': true,
        if (group != null) 'group': group,
        if (rotation != 0) 'rotation': rotation,
      };

  /// ค่าผิดปกติ = null (ข้ามชิ้นนั้น) หรือใช้ค่าปลอดภัย
  static WfComponent? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final kind = WfKind.values.asNameMap()[j['kind']];
    if (id is! String || id.isEmpty || kind == null) return null;
    double num0(Object? v, double fb) => v is num && v.isFinite ? v.toDouble() : fb;
    final d = wfDefaultSize(kind);
    double side(Object? v, double fb) {
      final n = num0(v, fb);
      return n < kWfMinSide ? fb : math.min(n, kWfMaxSide);
    }

    final fs = j['fontSize'];
    final rows = j['rows'];
    final cols = j['columns'];
    return WfComponent(
      id: id,
      kind: kind,
      text: j['text'] is String ? j['text'] as String : '',
      x: num0(j['x'], 0).clamp(-20000, 20000).toDouble(),
      y: num0(j['y'], 0).clamp(-20000, 20000).toDouble(),
      w: side(j['w'], d.$1),
      h: side(j['h'], d.$2),
      columns: [
        if (cols is List)
          for (final c in cols.take(30)) if (c is String) c,
      ],
      rows: rows is int ? rows.clamp(0, 50) : 3,
      fill: parseArgb(j['fill']),
      stroke: parseArgb(j['stroke']),
      textColor: parseArgb(j['textColor']),
      fontSize: fs is num && fs.isFinite && fs >= 6 && fs <= 96 ? fs.toDouble() : null,
      bold: j['bold'] == true,
      align: WfAlign.values.asNameMap()[j['align']] ?? WfAlign.left,
      disabled: j['disabled'] == true,
      checked: j['checked'] == true,
      secondary: j['secondary'] == true,
      ref: WfDataRef.tryFromJson(j['ref']),
      hidden: j['hidden'] == true,
      locked: j['locked'] == true,
      group: j['group'] is String && (j['group'] as String).isNotEmpty ? j['group'] as String : null,
      rotation: j['rotation'] is num && (j['rotation'] as num).isFinite ? (j['rotation'] as num).toDouble() : 0,
    )..api = ApiRef.tryFromJson(j['api']);
  }
}

/// เนื้อหาของเอกสาร Wireframe หนึ่งชิ้น = หน้าจอหนึ่งหน้า
/// กรอบหน้าจอเริ่มที่ (0,0) ขนาด [width]×[height] ; ลำดับใน [components] = ลำดับการซ้อน (ท้ายรายการอยู่บนสุด)
class WireframeDiagram implements DocContent {
  WireframeDiagram({
    this.device = WfDevice.desktop,
    double? width,
    double? height,
    this.style = WfStyle.sketch,
    this.accent = kWfDefaultAccent,
    List<WfComponent>? components,
    List<WfGroup>? groups,
  })  : groups = groups ?? [],
        width = width ?? (device == WfDevice.custom ? WfDevice.desktop.width : device.width),
        height = height ?? (device == WfDevice.custom ? WfDevice.desktop.height : device.height),
        components = components ?? [];

  WfDevice device;
  double width, height;
  WfStyle style;

  /// สีเน้นของเอกสาร (ARGB ทึบ) — ใช้กับปุ่มหลัก/สวิตช์/แท็บที่เลือก ในรูปแบบ "เรียบร้อย"
  int accent;
  final List<WfComponent> components;

  /// กลุ่มในแผงเลเยอร์ (ชื่อ + ตำแหน่งตอนว่าง) — กลุ่มอยู่ได้แม้ไม่มีสมาชิก ; สมาชิกคือชิ้นที่ [WfComponent.group] ตรงกับ id
  final List<WfGroup> groups;

  WfGroup? groupById(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// ชื่อกลุ่มถัดไปที่ยังไม่ซ้ำ ("กลุ่ม 1", "กลุ่ม 2", …) — [prefix] คือคำว่า "กลุ่ม" ตามภาษาของโปรแกรม
  String nextGroupName(String prefix) {
    final used = {for (final g in groups) g.name};
    var n = groups.length + 1;
    while (used.contains('$prefix $n')) {
      n++;
    }
    return '$prefix $n';
  }

  static const double minFrame = 120, maxFrame = 8000;

  WfComponent? componentById(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'device': device.name,
        'width': width,
        'height': height,
        'style': style.name,
        'accent': accent,
        'components': components.map((c) => c.toJson()).toList(),
        if (groups.isNotEmpty) 'groups': [for (final g in groups) g.toJson()],
      };

  @override
  Map<String, dynamic> toContentJson() => toJson();

  /// ซ่อมข้อมูลผิดปกติ: ข้ามชิ้นที่อ่านไม่ได้/id ซ้ำ ; ขนาดกรอบนอกช่วง = ขนาดของอุปกรณ์ (หรือ desktop)
  factory WireframeDiagram.fromJson(Object? j) {
    if (j is! Map) return WireframeDiagram();
    final device = WfDevice.values.asNameMap()[j['device']] ?? WfDevice.desktop;
    final fb = device == WfDevice.custom ? WfDevice.desktop : device;
    double frame(Object? v, double fallback) =>
        v is num && v.isFinite && v >= minFrame && v <= maxFrame ? v.toDouble() : fallback;
    final ids = <String>{};
    final accent = parseArgb(j['accent']);
    return WireframeDiagram(
      device: device,
      width: frame(j['width'], fb.width),
      height: frame(j['height'], fb.height),
      style: WfStyle.values.asNameMap()[j['style']] ?? WfStyle.sketch,
      accent: accent == null ? kWfDefaultAccent : (accent | 0xFF000000),
      components: [
        for (final e in (j['components'] is List ? j['components'] as List : const []))
          if (WfComponent.tryFromJson(e) case final c? when ids.add(c.id)) c,
      ],
      groups: [
        for (final e in (j['groups'] is List ? j['groups'] as List : const []))
          if (WfGroup.tryFromJson(e) case final g? when ids.add('group:${g.id}')) g,
      ],
    )..syncGroups();
  }

  /// ให้ทุกกลุ่มที่ชิ้นส่วนอ้างถึงมีรายการใน [groups] (ไฟล์เก่า/ข้อมูลที่วางมา = เพิ่มให้ ชื่อว่าง)
  void syncGroups() {
    final known = {for (final g in groups) g.id};
    for (final c in components) {
      final g = c.group;
      if (g != null && known.add(g)) groups.add(WfGroup(id: g));
    }
  }
}

/// กลุ่มในแผงเลเยอร์ (แบบ Adobe): มีชื่อ และอยู่ได้แม้ยังไม่มีสมาชิก
/// [at] = จำนวนชิ้นที่อยู่ใต้กลุ่มนี้ในลำดับการซ้อน — ใช้วางตำแหน่งเฉพาะตอนกลุ่มว่าง (มีสมาชิกแล้วอยู่ที่สมาชิกบนสุด)
class WfGroup {
  WfGroup({required this.id, this.name = '', this.at = 0});
  final String id;

  /// ชื่อ (ว่าง = ใช้คำว่า "กลุ่ม")
  String name;
  int at;

  Map<String, dynamic> toJson() => {'id': id, if (name.isNotEmpty) 'name': name, if (at != 0) 'at': at};

  static WfGroup? tryFromJson(Object? j) {
    if (j is! Map || j['id'] is! String || (j['id'] as String).isEmpty) return null;
    final at = j['at'];
    return WfGroup(
      id: j['id'] as String,
      name: j['name'] is String ? (j['name'] as String).trim() : '',
      at: at is int && at >= 0 ? at : 0,
    );
  }
}

/// พ่อของแต่ละชิ้น (id ลูก -> id พ่อ): ภาชนะที่เล็กที่สุดซึ่งอยู่ใต้ลูกในลำดับการซ้อนและครอบลูกทั้งใบ
/// (คำนวณจากตำแหน่งเสมอ จึงไม่มีลิงก์พ่อ-ลูกที่ขาด)
Map<String, String> wfParentMap(WireframeDiagram d) {
  final out = <String, String>{};
  final list = d.components;
  for (var i = 0; i < list.length; i++) {
    final c = list[i];
    WfComponent? best;
    for (var j = 0; j < i; j++) {
      final p = list[j];
      if (!kWfContainerKinds.contains(p.kind) || !boxInside(c, p)) continue;
      if (best == null || p.w * p.h <= best.w * best.h) best = p;
    }
    if (best != null) out[c.id] = best.id;
  }
  return out;
}

/// ลูกหลานทั้งหมดของชิ้น [ids] (ไม่รวมตัวเอง) ตามลำดับการซ้อน
Set<String> wfDescendants(WireframeDiagram d, Set<String> ids, [Map<String, String>? parents]) {
  final p = parents ?? wfParentMap(d);
  final out = <String>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final c in d.components) {
      final par = p[c.id];
      if (par != null && (ids.contains(par) || out.contains(par)) && !ids.contains(c.id) && out.add(c.id)) changed = true;
    }
  }
  return out;
}

/// มุมในช่วง 0 ถึง <360 (ปัดละเอียด 0.001 องศา) ; ค่าที่ไม่ใช่ตัวเลข = 0
double wfNormAngle(double a) {
  if (!a.isFinite) return 0;
  var r = a % 360;
  if (r < 0) r += 360;
  r = (r * 1000).round() / 1000;
  return r >= 360 ? 0 : r;
}

/// จุด ([x],[y]) ในพิกัดหน้าจอ -> พิกัดของชิ้น [c] ก่อนหมุน (หมุนกลับรอบจุดกึ่งกลาง)
(double, double) wfToLocal(WfComponent c, double x, double y) {
  if (c.rotation == 0) return (x, y);
  final cx = c.x + c.w / 2, cy = c.y + c.h / 2;
  final a = -c.rotation * math.pi / 180;
  final dx = x - cx, dy = y - cy;
  return (cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a));
}

/// จุด ([x],[y]) อยู่บนชิ้น [c] (คิดการหมุนแล้ว ; [tol] = ระยะเผื่อ)
bool wfContains(WfComponent c, double x, double y, {double tol = 0}) {
  final (lx, ly) = wfToLocal(c, x, y);
  return lx >= c.x - tol && lx <= c.right + tol && ly >= c.y - tol && ly <= c.bottom + tol;
}

/// กรอบตั้งฉากที่ครอบชิ้น [c] หลังหมุน
({double left, double top, double right, double bottom}) wfBounds(WfComponent c) {
  if (c.rotation == 0) return (left: c.x, top: c.y, right: c.right, bottom: c.bottom);
  final a = c.rotation * math.pi / 180;
  final hw = (c.w / 2 * math.cos(a)).abs() + (c.h / 2 * math.sin(a)).abs();
  final hh = (c.w / 2 * math.sin(a)).abs() + (c.h / 2 * math.cos(a)).abs();
  final cx = c.x + c.w / 2, cy = c.y + c.h / 2;
  return (left: cx - hw, top: cy - hh, right: cx + hw, bottom: cy + hh);
}

/// ชิ้นที่มองไม่เห็น: ชิ้นที่ซ่อน + ลูกหลานในภาชนะที่ซ่อน
Set<String> wfHiddenIds(WireframeDiagram d, [Map<String, String>? parents]) {
  final own = {for (final c in d.components) if (c.hidden) c.id};
  if (own.isEmpty) return own;
  return {...own, ...wfDescendants(d, own, parents)};
}

/// สมาชิกของกลุ่ม [group] ตามลำดับการซ้อน
List<WfComponent> wfGroupMembers(WireframeDiagram d, String group) => [for (final c in d.components) if (c.group == group) c];

/// ขอบเขตของภาพทั้งหน้าจอ: กรอบหน้าจอ + ชิ้นที่มองเห็น (ชิ้นที่ล้นออกนอกกรอบก็นับ ; คิดการหมุนแล้ว)
({double left, double top, double right, double bottom}) wfContentBounds(WireframeDiagram d) {
  var l = 0.0, t = 0.0, r = d.width, b = d.height;
  final hidden = wfHiddenIds(d);
  for (final c in d.components) {
    if (hidden.contains(c.id)) continue;
    final bb = wfBounds(c);
    l = math.min(l, bb.left);
    t = math.min(t, bb.top);
    r = math.max(r, bb.right);
    b = math.max(b, bb.bottom);
  }
  return (left: l, top: t, right: r, bottom: b);
}
