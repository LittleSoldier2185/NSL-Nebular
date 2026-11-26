import 'dart:math' as math;

import '../models/flowchart_model.dart';
import 'ortho_route.dart';

/// เรขาคณิตของ Flowchart (ใช้ร่วมกันทั้งบนจอ / PNG / SVG / การคลิก) — ฟังก์ชันล้วน

/// คำสั่งวาดเส้นแบบกลาง: 'M' (1 จุด), 'L' (1 จุด), 'C' (3 จุด: ควบคุม 2 + ปลาย), 'Z' (ไม่มีจุด)
typedef FcCmd = (String op, List<RoutePoint> pts);

/// ส่วนประกอบของรูปทรงหนึ่งรูป: เส้นรอบรูป (เติมสีได้) + เส้นตกแต่งด้านใน (เส้นอย่างเดียว)
class FcShapeGeom {
  const FcShapeGeom(this.outline, this.details);
  final List<FcCmd> outline;
  final List<FcCmd> details;
}

const double _k = 0.5522847498;

/// ความเอียงของสี่เหลี่ยมด้านขนาน (Input/Output)
double fcIoSkew(FcNode n) => math.min(n.w * 0.25, n.h * 0.45);

/// ระยะเข้าของมุมหกเหลี่ยม
double fcHexInset(FcNode n) => math.min(n.w * 0.2, n.h * 0.5);

/// ความสูงครึ่งวงรีของฝาทรงกระบอก
double fcCylinderCap(FcNode n) => math.min(n.h * 0.14, 14);

/// แอมพลิจูดคลื่นขอบล่างของเอกสาร
double fcDocWave(FcNode n) => math.min(10, n.h * 0.15);

/// ขนาดมุมพับของโน้ต
double fcNoteFold(FcNode n) => math.min(16, math.min(n.w, n.h) * 0.3);

/// ความสูงส่วนปลายแหลมของจุดต่อข้ามหน้า
double fcOffPageTip(FcNode n) => math.min(n.h * 0.375, n.w * 0.5);

/// ระยะเหลื่อมของแผ่นหลังในหลายเอกสาร
double fcMultiDocStep(FcNode n) => math.min(8, math.min(n.w * 0.08, n.h * 0.1));

/// รัศมีแนวนอนของปลายโค้ง (ทรงกระบอกนอน / ข้อมูลที่จัดเก็บ / แสดงผล)
double fcSideCurve(FcNode n) => math.min(n.w * 0.15, n.h / 2);

/// ระยะเส้นแบ่งของหน่วยความจำภายใน
double fcStorageInset(FcNode n) => math.min(14, math.min(n.w * 0.15, n.h * 0.2));

/// ขนาดมุมที่ตัด (บัตร / ขอบเขตลูป)
double fcCornerCut(FcNode n) => math.min(18, math.min(n.w, n.h) * 0.25);

/// ความเอียงขอบบนของการป้อนข้อมูลด้วยมือ
double fcManualSlope(FcNode n) => n.h * 0.3;

/// ความกว้างวงเล็บของคำอธิบายประกอบ
double fcBracket(FcNode n) => math.min(16, n.w * 0.2);

/// ส่วนโค้งด้านขวาแบบครึ่งวงรี (กว้าง [rx]) : ปกติจาก (r - rx, y) โค้งออกขวาถึง (r - rx, b) ;
/// [inward] = จาก (r, y) โค้งเข้าทางซ้ายถึง (r, b)
List<FcCmd> _rightCap(double r, double y, double b, double rx, {bool inward = false}) {
  final cy = (y + b) / 2, ry = (b - y) / 2;
  if (inward) {
    return [
      ('C', [(r - rx * _k, y), (r - rx, cy - ry * _k), (r - rx, cy)]),
      ('C', [(r - rx, cy + ry * _k), (r - rx * _k, b), (r, b)]),
    ];
  }
  final x0 = r - rx;
  return [
    ('C', [(x0 + rx * _k, y), (r, cy - ry * _k), (r, cy)]),
    ('C', [(r, cy + ry * _k), (x0 + rx * _k, b), (x0, b)]),
  ];
}

/// ส่วนโค้งด้านซ้ายแบบครึ่งวงรี จาก (x + rx, b) โค้งออกซ้ายขึ้นไปถึง (x + rx, y)
List<FcCmd> _leftCap(double x, double y, double b, double rx) {
  final cy = (y + b) / 2, ry = (b - y) / 2, x0 = x + rx;
  return [
    ('C', [(x0 - rx * _k, b), (x, cy + ry * _k), (x, cy)]),
    ('C', [(x, cy - ry * _k), (x0 - rx * _k, y), (x0, y)]),
  ];
}

List<FcCmd> _ellipse(double x, double y, double w, double h) {
  final rx = w / 2, ry = h / 2, cx = x + rx, cy = y + ry;
  return [
    ('M', [(cx + rx, cy)]),
    ('C', [(cx + rx, cy + ry * _k), (cx + rx * _k, cy + ry), (cx, cy + ry)]),
    ('C', [(cx - rx * _k, cy + ry), (cx - rx, cy + ry * _k), (cx - rx, cy)]),
    ('C', [(cx - rx, cy - ry * _k), (cx - rx * _k, cy - ry), (cx, cy - ry)]),
    ('C', [(cx + rx * _k, cy - ry), (cx + rx, cy - ry * _k), (cx + rx, cy)]),
    ('Z', const []),
  ];
}

List<FcCmd> _roundRect(double x, double y, double w, double h, double r) {
  r = math.min(r, math.min(w, h) / 2);
  final rr = r * (1 - _k);
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

List<FcCmd> _poly(List<RoutePoint> pts) => [
      ('M', [pts.first]),
      for (final p in pts.skip(1)) ('L', [p]),
      ('Z', const []),
    ];

/// รูปทรงของสัญลักษณ์ [n] ในพิกัดแผนภาพ
FcShapeGeom fcShapeGeom(FcNode n) {
  final x = n.x, y = n.y, w = n.w, h = n.h, r = n.right, b = n.bottom;
  switch (n.shape) {
    case FcShape.start || FcShape.end:
      return FcShapeGeom(_roundRect(x, y, w, h, math.min(w, h) / 2), const []);
    case FcShape.process:
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b), (x, b)]), const []);
    case FcShape.rounded:
      return FcShapeGeom(_roundRect(x, y, w, h, math.min(12, math.min(w, h) / 4)), const []);
    case FcShape.decision:
      return FcShapeGeom(_poly([(n.cx, y), (r, n.cy), (n.cx, b), (x, n.cy)]), const []);
    case FcShape.io:
      final s = fcIoSkew(n);
      return FcShapeGeom(_poly([(x + s, y), (r, y), (r - s, b), (x, b)]), const []);
    case FcShape.subroutine:
      final i = math.min(12.0, w * 0.1);
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b), (x, b)]), [
        ('M', [(x + i, y)]),
        ('L', [(x + i, b)]),
        ('M', [(r - i, y)]),
        ('L', [(r - i, b)]),
      ]);
    case FcShape.connector || FcShape.ellipse:
      return FcShapeGeom(_ellipse(x, y, w, h), const []);
    case FcShape.text:
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b), (x, b)]), const []);
    case FcShape.hexagon:
      final i = fcHexInset(n);
      return FcShapeGeom(_poly([(x + i, y), (r - i, y), (r, n.cy), (r - i, b), (x + i, b), (x, n.cy)]), const []);
    case FcShape.cylinder:
      final rx = w / 2, ry = fcCylinderCap(n), cx = n.cx;
      return FcShapeGeom([
        ('M', [(x, y + ry)]),
        ('C', [(x, y + ry - ry * _k), (cx - rx * _k, y), (cx, y)]),
        ('C', [(cx + rx * _k, y), (r, y + ry - ry * _k), (r, y + ry)]),
        ('L', [(r, b - ry)]),
        ('C', [(r, b - ry + ry * _k), (cx + rx * _k, b), (cx, b)]),
        ('C', [(cx - rx * _k, b), (x, b - ry + ry * _k), (x, b - ry)]),
        ('Z', const []),
      ], [
        ('M', [(x, y + ry)]),
        ('C', [(x, y + ry + ry * _k), (cx - rx * _k, y + 2 * ry), (cx, y + 2 * ry)]),
        ('C', [(cx + rx * _k, y + 2 * ry), (r, y + ry + ry * _k), (r, y + ry)]),
      ]);
    case FcShape.document:
      final a = fcDocWave(n);
      return FcShapeGeom([
        ('M', [(x, y)]),
        ('L', [(r, y)]),
        ('L', [(r, b - a)]),
        ('C', [(r - w * 0.33, b - a * 3), (x + w * 0.33, b + a), (x, b - a)]),
        ('Z', const []),
      ], const []);
    case FcShape.note:
      final f = fcNoteFold(n);
      return FcShapeGeom(_poly([(x, y), (r - f, y), (r, y + f), (r, b), (x, b)]), [
        ('M', [(r - f, y)]),
        ('L', [(r - f, y + f)]),
        ('L', [(r, y + f)]),
      ]);
    case FcShape.offPage:
      final t = fcOffPageTip(n);
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b - t), (n.cx, b), (x, b - t)]), const []);
    case FcShape.annotation:
      final k = fcBracket(n);
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b), (x, b)]), [
        ('M', [(x + k, y)]),
        ('L', [(x, y)]),
        ('L', [(x, b)]),
        ('L', [(x + k, b)]),
      ]);
    case FcShape.multiDocument:
      final o = fcMultiDocStep(n), a = math.min(fcDocWave(n), (h - 2 * o) * 0.15), fw = w - 2 * o;
      return FcShapeGeom([
        ('M', [(x + 2 * o, y)]),
        ('L', [(r, y)]),
        ('L', [(r, b - 2 * o)]),
        ('L', [(r - o, b - 2 * o)]),
        ('L', [(r - o, b - o)]),
        ('L', [(r - 2 * o, b - o)]),
        ('L', [(r - 2 * o, b - a)]),
        ('C', [(r - 2 * o - fw * 0.33, b - a * 3), (x + fw * 0.33, b + a), (x, b - a)]),
        ('L', [(x, y + 2 * o)]),
        ('L', [(x + o, y + 2 * o)]),
        ('L', [(x + o, y + o)]),
        ('L', [(x + 2 * o, y + o)]),
        ('Z', const []),
      ], [
        ('M', [(x, y + 2 * o)]),
        ('L', [(r - 2 * o, y + 2 * o)]),
        ('L', [(r - 2 * o, b - o)]),
        ('M', [(x + o, y + o)]),
        ('L', [(r - o, y + o)]),
        ('L', [(r - o, b - 2 * o)]),
      ]);
    case FcShape.directData:
      final c = fcSideCurve(n);
      return FcShapeGeom([
        ('M', [(x + c, y)]),
        ('L', [(r - c, y)]),
        ..._rightCap(r, y, b, c),
        ('L', [(x + c, b)]),
        ..._leftCap(x, y, b, c),
        ('Z', const []),
      ], [
        ('M', [(r - c, y)]),
        ..._rightCap(r - c, y, b, c, inward: true),
      ]);
    case FcShape.storedData:
      final c = fcSideCurve(n);
      return FcShapeGeom([
        ('M', [(x + c, y)]),
        ('L', [(r, y)]),
        ..._rightCap(r, y, b, c, inward: true),
        ('L', [(x + c, b)]),
        ..._leftCap(x, y, b, c),
        ('Z', const []),
      ], const []);
    case FcShape.internalStorage:
      final i = fcStorageInset(n);
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b), (x, b)]), [
        ('M', [(x + i, y)]),
        ('L', [(x + i, b)]),
        ('M', [(x, y + i)]),
        ('L', [(r, y + i)]),
      ]);
    case FcShape.sequentialData:
      final d = math.min(w, h);
      return FcShapeGeom(_ellipse(n.cx - d / 2, n.cy - d / 2, d, d), [
        ('M', [(n.cx, n.cy + d / 2)]),
        ('L', [(r, n.cy + d / 2)]),
      ]);
    case FcShape.paperTape:
      final a = fcDocWave(n);
      return FcShapeGeom([
        ('M', [(x, y + a)]),
        ('C', [(x + w * 0.33, y + a * 3), (x + w * 0.67, y - a), (r, y + a)]),
        ('L', [(r, b - a)]),
        ('C', [(r - w * 0.33, b - a * 3), (x + w * 0.33, b + a), (x, b - a)]),
        ('Z', const []),
      ], const []);
    case FcShape.card:
      final c = fcCornerCut(n);
      return FcShapeGeom(_poly([(x + c, y), (r, y), (r, b), (x, b), (x, y + c)]), const []);
    case FcShape.manualInput:
      return FcShapeGeom(_poly([(x, y + fcManualSlope(n)), (r, y), (r, b), (x, b)]), const []);
    case FcShape.manualOperation:
      final s = fcIoSkew(n);
      return FcShapeGeom(_poly([(x, y), (r, y), (r - s, b), (x + s, b)]), const []);
    case FcShape.delay:
      final c = math.min(w / 2, h / 2);
      return FcShapeGeom([
        ('M', [(x, y)]),
        ('L', [(r - c, y)]),
        ..._rightCap(r, y, b, c),
        ('L', [(x, b)]),
        ('Z', const []),
      ], const []);
    case FcShape.display:
      final c = fcSideCurve(n), p = math.min(w * 0.15, h * 0.5);
      return FcShapeGeom([
        ('M', [(x, n.cy)]),
        ('L', [(x + p, y)]),
        ('L', [(r - c, y)]),
        ..._rightCap(r, y, b, c),
        ('L', [(x + p, b)]),
        ('Z', const []),
      ], const []);
    case FcShape.loopLimit:
      final c = fcCornerCut(n);
      return FcShapeGeom(_poly([(x + c, y), (r - c, y), (r, y + c), (r, b), (x, b), (x, y + c)]), const []);
    case FcShape.parallelMode:
      return FcShapeGeom(_poly([(x, y), (r, y), (r, b), (x, b)]), [
        ('M', [(x, y)]),
        ('L', [(r, y)]),
        ('M', [(x, b)]),
        ('L', [(r, b)]),
      ]);
    case FcShape.collate:
      return FcShapeGeom([
        ..._poly([(x, y), (r, y), (n.cx, n.cy)]),
        ..._poly([(n.cx, n.cy), (r, b), (x, b)]),
      ], const []);
    case FcShape.sort:
      return FcShapeGeom(_poly([(n.cx, y), (r, n.cy), (n.cx, b), (x, n.cy)]), [
        ('M', [(x, n.cy)]),
        ('L', [(r, n.cy)]),
      ]);
    case FcShape.extract:
      return FcShapeGeom(_poly([(n.cx, y), (r, b), (x, b)]), const []);
    case FcShape.merge:
      return FcShapeGeom(_poly([(x, y), (r, y), (n.cx, b)]), const []);
    case FcShape.summingJunction:
      final dx = w / 2 * 0.7071, dy = h / 2 * 0.7071;
      return FcShapeGeom(_ellipse(x, y, w, h), [
        ('M', [(n.cx - dx, n.cy - dy)]),
        ('L', [(n.cx + dx, n.cy + dy)]),
        ('M', [(n.cx + dx, n.cy - dy)]),
        ('L', [(n.cx - dx, n.cy + dy)]),
      ]);
    case FcShape.or:
      return FcShapeGeom(_ellipse(x, y, w, h), [
        ('M', [(n.cx, y)]),
        ('L', [(n.cx, b)]),
        ('M', [(x, n.cy)]),
        ('L', [(r, n.cy)]),
      ]);
    case FcShape.transfer:
      final head = math.min(w * 0.4, h * 0.6), band = h * 0.2;
      return FcShapeGeom(
          _poly([(x, y + band), (r - head, y + band), (r - head, y), (r, n.cy), (r - head, b), (r - head, b - band), (x, b - band)]),
          const []);
  }
}

/// กรอบวางข้อความภายในสัญลักษณ์ (left, top, width, height)
({double left, double top, double width, double height}) fcTextBox(FcNode n) {
  final (l, t, rr, bb) = switch (n.shape) {
    FcShape.decision => (n.w * 0.2, n.h * 0.18, n.w * 0.2, n.h * 0.18),
    FcShape.io => (fcIoSkew(n) * 0.75 + 4, 4.0, fcIoSkew(n) * 0.75 + 4, 4.0),
    FcShape.subroutine => (math.min(12.0, n.w * 0.1) + 6, 4.0, math.min(12.0, n.w * 0.1) + 6, 4.0),
    FcShape.start || FcShape.end => (math.min(n.w, n.h) / 4 + 4, 4.0, math.min(n.w, n.h) / 4 + 4, 4.0),
    FcShape.ellipse || FcShape.connector => (n.w * 0.14, n.h * 0.14, n.w * 0.14, n.h * 0.14),
    FcShape.note => (10.0, 8.0, fcNoteFold(n) + 4, 8.0),
    FcShape.hexagon => (fcHexInset(n) * 0.7 + 4, 4.0, fcHexInset(n) * 0.7 + 4, 4.0),
    FcShape.cylinder => (8.0, fcCylinderCap(n) * 2 + 2, 8.0, fcCylinderCap(n) + 4),
    FcShape.document => (10.0, 6.0, 10.0, fcDocWave(n) * 2 + 4),
    FcShape.text => (4.0, 2.0, 4.0, 2.0),
    FcShape.offPage => (6.0, 4.0, 6.0, fcOffPageTip(n) * 0.7),
    FcShape.annotation => (fcBracket(n) * 0.5 + 6, 4.0, 4.0, 4.0),
    FcShape.multiDocument => (8.0, fcMultiDocStep(n) * 2 + 4, fcMultiDocStep(n) * 2 + 8, fcDocWave(n) * 2 + 4),
    FcShape.directData => (fcSideCurve(n) + 4, 4.0, fcSideCurve(n) * 1.6 + 4, 4.0),
    FcShape.storedData || FcShape.display => (fcSideCurve(n) + 4, 4.0, fcSideCurve(n) + 4, 4.0),
    FcShape.delay => (8.0, 4.0, math.min(n.w, n.h) / 4 + 4, 4.0),
    FcShape.internalStorage => (fcStorageInset(n) + 6, fcStorageInset(n) + 4, 6.0, 4.0),
    FcShape.sequentialData => (n.w * 0.18, n.h * 0.18, n.w * 0.18, n.h * 0.18),
    FcShape.paperTape => (8.0, fcDocWave(n) * 2 + 2, 8.0, fcDocWave(n) * 2 + 2),
    FcShape.manualInput => (8.0, fcManualSlope(n) * 0.6 + 2, 8.0, 4.0),
    FcShape.manualOperation => (fcIoSkew(n) * 0.75 + 4, 4.0, fcIoSkew(n) * 0.75 + 4, 4.0),
    FcShape.sort => (n.w * 0.2, n.h * 0.18, n.w * 0.2, n.h * 0.18),
    FcShape.extract => (n.w * 0.25, n.h * 0.4, n.w * 0.25, 4.0),
    FcShape.merge => (n.w * 0.25, 4.0, n.w * 0.25, n.h * 0.4),
    FcShape.summingJunction || FcShape.or => (n.w * 0.14, n.h * 0.14, n.w * 0.14, n.h * 0.14),
    FcShape.transfer => (8.0, n.h * 0.2 + 2, math.min(n.w * 0.4, n.h * 0.6) * 0.5 + 4, n.h * 0.2 + 2),
    _ => (10.0, 6.0, 10.0, 6.0),
  };
  return (left: n.x + l, top: n.y + t, width: math.max(4, n.w - l - rr), height: math.max(4, n.h - t - bb));
}

/// จุด ([x],[y]) อยู่ในรูปทรงของ [n] หรือไม่ (เผื่อขอบ [tol])
bool fcNodeContains(FcNode n, double x, double y, {double tol = 0}) {
  if (x < n.x - tol || x > n.right + tol || y < n.y - tol || y > n.bottom + tol) return false;
  switch (n.shape) {
    case FcShape.decision:
      final dx = (x - n.cx).abs() / (n.w / 2 + tol), dy = (y - n.cy).abs() / (n.h / 2 + tol);
      return dx + dy <= 1;
    case FcShape.ellipse || FcShape.connector || FcShape.summingJunction || FcShape.or:
      final dx = (x - n.cx) / (n.w / 2 + tol), dy = (y - n.cy) / (n.h / 2 + tol);
      return dx * dx + dy * dy <= 1;
    case FcShape.sort:
      final dx = (x - n.cx).abs() / (n.w / 2 + tol), dy = (y - n.cy).abs() / (n.h / 2 + tol);
      return dx + dy <= 1;
    default:
      return true;
  }
}

/// เลื่อนปลายเส้น [p] ที่อยู่บนด้าน [side] ของกรอบ เข้าไปแตะเส้นรอบรูปจริง (เลื่อนตามแกนที่ออกเท่านั้น เส้นยังตั้งฉาก)
RoutePoint fcSnapToOutline(FcNode n, RouteSide side, RoutePoint p) {
  final horizontal = isHorizontalSide(side);
  final sign = (side == RouteSide.left || side == RouteSide.top) ? 1.0 : -1.0;
  double inset; // ระยะจากขอบกรอบเข้าไปถึงเส้นรอบรูป
  switch (n.shape) {
    case FcShape.decision || FcShape.sort:
      final f = horizontal ? ((p.$2 - n.cy).abs() / (n.h / 2)) : ((p.$1 - n.cx).abs() / (n.w / 2));
      inset = (horizontal ? n.w / 2 : n.h / 2) * f.clamp(0.0, 1.0);
    case FcShape.ellipse || FcShape.connector || FcShape.summingJunction || FcShape.or:
      final a = horizontal ? n.w / 2 : n.h / 2, bb = horizontal ? n.h / 2 : n.w / 2;
      final d = horizontal ? (p.$2 - n.cy) : (p.$1 - n.cx);
      final q = (d / bb).clamp(-1.0, 1.0);
      inset = a - a * math.sqrt(1 - q * q);
    case FcShape.start || FcShape.end:
      final rad = math.min(n.w, n.h) / 2;
      if (horizontal && n.w >= n.h || !horizontal && n.h > n.w) {
        final d = horizontal ? (p.$2 - n.cy) : (p.$1 - n.cx);
        final q = d.abs().clamp(0.0, rad);
        inset = rad - math.sqrt(rad * rad - q * q);
      } else {
        inset = 0;
      }
    case FcShape.io:
      if (!horizontal) {
        inset = 0;
      } else {
        final s = fcIoSkew(n);
        final t = ((p.$2 - n.y) / n.h).clamp(0.0, 1.0);
        inset = side == RouteSide.left ? s * (1 - t) : s * t;
      }
    default:
      inset = 0;
  }
  return horizontal ? (p.$1 + sign * inset, p.$2) : (p.$1, p.$2 + sign * inset);
}

/// เส้นทางของเส้นเชื่อมทุกเส้น (key = id) — หักมุมฉาก ชอบออกแนวตั้ง (บนลงล่าง) ปลายเส้นแตะเส้นรอบรูปจริง
/// เส้นวนเข้าตัวเองวาดเป็นห่วงเล็กทางขวาของสัญลักษณ์
Map<String, List<RoutePoint>> fcRoutes(FlowchartDiagram d) {
  final boxes = <String, RouteBox>{};
  final byId = <String, FcNode>{};
  for (final n in d.nodes) {
    boxes.putIfAbsent(n.id, () => RouteBox(n.id, n.x, n.y, n.w, n.h));
    byId.putIfAbsent(n.id, () => n);
  }
  final links = [for (final e in d.edges) if (e.fromId != e.toId) RouteLink(e.id, e.fromId, e.toId, exit: e.exit, entry: e.entry, hints: e.hints)];
  final raw = orthogonalRoutes(boxes, links, gutter: 24, slotGap: 16, preferVertical: true);
  final out = <String, List<RoutePoint>>{};
  for (final e in d.edges) {
    final a = byId[e.fromId], b = byId[e.toId];
    if (a == null || b == null) continue;
    if (e.fromId == e.toId) {
      final r = a.right, y0 = a.cy - math.min(12, a.h / 4), y1 = a.cy + math.min(12, a.h / 4);
      out[e.id] = [(r, y0), (r + 28, y0), (r + 28, y1), (r, y1)];
      continue;
    }
    final pts = raw[e.id];
    if (pts == null || pts.length < 2) continue;
    final route = List.of(pts);
    route[0] = fcSnapToOutline(a, _sideOf(a, pts.first), pts.first);
    route[route.length - 1] = fcSnapToOutline(b, _sideOf(b, pts.last), pts.last);
    out[e.id] = fcRoomForArrows(e, route);
  }
  return out;
}

RouteSide _sideOf(FcNode n, RoutePoint p) {
  final dl = (p.$1 - n.x).abs(), dr = (p.$1 - n.right).abs(), dt = (p.$2 - n.y).abs(), db = (p.$2 - n.bottom).abs();
  final m = [dl, dr, dt, db].reduce(math.min);
  if (m == dt) return RouteSide.top;
  if (m == db) return RouteSide.bottom;
  if (m == dl) return RouteSide.left;
  return RouteSide.right;
}

/// สัญลักษณ์บนสุดที่ ([x],[y]) อยู่ในรูปทรง (ท้ายรายการก่อน)
FcNode? fcNodeAt(FlowchartDiagram d, double x, double y, {double tol = 0}) {
  for (final n in d.nodes.reversed) {
    if (fcNodeContains(n, x, y, tol: tol)) return n;
  }
  return null;
}

/// เส้นที่อยู่ใกล้จุดภายใน [tolerance] (ใกล้สุดก่อน) ; ไม่มี = null
String? fcEdgeAt(FlowchartDiagram d, double x, double y, {double tolerance = 7, Map<String, List<RoutePoint>>? routes}) {
  String? best;
  var bestD = tolerance;
  (routes ?? fcRoutes(d)).forEach((id, pts) {
    final dist = distanceToRoute(pts, x, y);
    if (dist <= bestD) {
      bestD = dist;
      best = id;
    }
  });
  return best;
}

/// ขอบเขตของแผนภาพ (สัญลักษณ์ + เส้น) เผื่อขอบ [pad] ; ว่าง = null
({double left, double top, double right, double bottom})? fcBounds(FlowchartDiagram d, {double pad = 40, Set<String>? only}) {
  final nodes = only == null ? d.nodes : d.nodes.where((n) => only.contains(n.id)).toList();
  if (nodes.isEmpty) return null;
  var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  for (final n in nodes) {
    l = math.min(l, n.x);
    t = math.min(t, n.y);
    r = math.max(r, n.right);
    b = math.max(b, n.bottom);
  }
  if (only == null) {
    for (final pts in fcRoutes(d).values) {
      for (final (x, y) in pts) {
        l = math.min(l, x);
        t = math.min(t, y);
        r = math.max(r, x);
        b = math.max(b, y);
      }
    }
  }
  return (left: l - pad, top: t - pad, right: r + pad, bottom: b + pad);
}

/// ความยาวหัวลูกศรของเส้นหนา [width]
double fcArrowSize(double width) => 9 + width;

/// ระยะที่ต้องมีบนท่อนปลายเส้นที่มีหัวลูกศร: หัวลูกศร + รัศมีมุมโค้ง — สั้นกว่านี้มุมหักจะเข้าไปอยู่ในหัวลูกศร
double fcArrowStub(FcEdge e, FcArrow a) => a == FcArrow.none ? 0 : fcArrowSize(e.width) + 6;

/// ยืดท่อนสุดท้ายให้ยาวอย่างน้อย [need] โดยเลื่อนท่อนขวางก่อนถึงปลายถอยหลัง (จุดปลายทั้งสองอยู่ที่เดิม)
/// ทำได้เฉพาะเส้นที่ท่อนก่อนท่อนขวางวิ่งทางเดียวกับท่อนปลาย ; เหลือท่อนนั้นไว้อย่างน้อย [keep] ; ที่ไม่พอ = ยืดเท่าที่มี
List<RoutePoint> _stretchEnd(List<RoutePoint> pts, double need, double keep) {
  final n = pts.length;
  if (n < 4) return pts;
  final a = pts[n - 4], b = pts[n - 3], c = pts[n - 2], d = pts[n - 1];
  final dx = d.$1 - c.$1, dy = d.$2 - c.$2;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 0.001 || len >= need) return pts;
  final ux = dx / len, uy = dy / len;
  final lead = (b.$1 - a.$1) * ux + (b.$2 - a.$2) * uy;
  final across = (c.$1 - b.$1) * ux + (c.$2 - b.$2) * uy;
  if (across.abs() > 0.5) return pts;
  final shift = math.min(need - len, lead - keep);
  if (shift <= 0) return pts;
  return [...pts.take(n - 3), (b.$1 - ux * shift, b.$2 - uy * shift), (c.$1 - ux * shift, c.$2 - uy * shift), d];
}

/// เผื่อที่ให้หัวลูกศรทั้งสองปลาย (ปลายทางก่อน เพราะมีหัวลูกศรเป็นปกติ) ; stub 0 = ปลายนั้นไม่มีหัว
List<RoutePoint> routeRoomForArrows(List<RoutePoint> pts, {required double endStub, double startStub = 0}) {
  var out = _stretchEnd(pts, endStub, math.max(2, startStub));
  if (startStub > 0) {
    // เส้น 4 จุด ท่อนที่ยอมให้หดตอนยืดต้นทางคือท่อนปลายทาง จึงต้องเหลือที่ของหัวลูกศรปลายทางไว้
    out = _stretchEnd(out.reversed.toList(), startStub, out.length == 4 ? math.max(2, endStub) : 2).reversed.toList();
  }
  return out;
}

/// ตัดปลายท้ายเส้นออก [cut] (ไม่เกินความยาวท่อนสุดท้าย)
List<RoutePoint> _trimEnd(List<RoutePoint> pts, double cut) {
  final a = pts[pts.length - 2], b = pts.last;
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 0.001) return pts;
  final k = math.min(cut, len) / len;
  return [...pts.take(pts.length - 1), (b.$1 - dx * k, b.$2 - dy * k)];
}

/// [routeRoomForArrows] ของเส้น Flowchart [e]
List<RoutePoint> fcRoomForArrows(FcEdge e, List<RoutePoint> pts) =>
    routeRoomForArrows(pts, endStub: fcArrowStub(e, e.endArrow), startStub: fcArrowStub(e, e.startArrow));

/// ตัดตัวเส้นที่ปลาย [endCut] / ต้น [startCut] (0 = ไม่ตัด)
List<RoutePoint> routeTrimForArrows(List<RoutePoint> pts, {double endCut = 0, double startCut = 0}) {
  var out = pts;
  if (endCut > 0) out = _trimEnd(out, endCut);
  if (startCut > 0) out = _trimEnd(out.reversed.toList(), startCut).reversed.toList();
  return out;
}

/// เส้นทางสำหรับ "วาดตัวเส้น": ปลายที่เป็นหัวลูกศรทึบจบที่ฐานหัวลูกศร ตัวเส้นจึงไม่ทะลุหัว/โผล่เลยปลายแหลม
/// (ซ้อนไว้ครึ่งพิกเซลกันรอยต่อ) ; ตัวหัวลูกศรยังคิดจากเส้นทางเต็ม
List<RoutePoint> fcLineRoute(FcEdge e, List<RoutePoint> route) {
  final cut = fcArrowSize(e.width) - 0.5;
  return routeTrimForArrows(route, endCut: e.endArrow == FcArrow.arrow ? cut : 0, startCut: e.startArrow == FcArrow.arrow ? cut : 0);
}

/// รูปหัวลูกศรที่ปลาย [to] ของช่วง [from]→[to] : (เส้นปิดเติมสี?, จุด) — none = ว่าง
(bool filled, List<RoutePoint>) fcArrowHead(FcArrow a, RoutePoint from, RoutePoint to, {double size = 10}) {
  if (a == FcArrow.none) return (false, const []);
  final dx = to.$1 - from.$1, dy = to.$2 - from.$2;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 0.001) return (false, const []);
  final ux = dx / len, uy = dy / len;
  final bx = to.$1 - ux * size, by = to.$2 - uy * size;
  final nx = -uy, ny = ux;
  final p1 = (bx + nx * size * 0.45, by + ny * size * 0.45), p2 = (bx - nx * size * 0.45, by - ny * size * 0.45);
  return a == FcArrow.arrow ? (true, [to, p1, p2]) : (false, [p1, to, p2]);
}

// ---------- จุดต่อเส้นที่โผล่ตอนชี้สัญลักษณ์ (แบบ draw.io) ----------

/// ระยะจากขอบสัญลักษณ์ถึงจุดต่อเส้น และรัศมีของจุด (หน่วยพิกเซลจอ — ผู้เรียกหารด้วยสเกลเอง)
const double kFcLinkGapPx = 18;
const double kFcLinkRadiusPx = 9;

/// ระยะ (พิกเซลจอ) ที่สัญลักษณ์ที่ลากอยู่จะดูดเข้าแนวสัญลักษณ์อื่น
const double kFcGuideTolPx = 6;

/// ศูนย์กลางจุดต่อเส้นด้าน [side] ของ [n] ซึ่งอยู่นอกขอบเป็นระยะ [gap]
(double, double) fcLinkHandlePos(FcNode n, RouteSide side, double gap) => switch (side) {
      RouteSide.top => (n.cx, n.y - gap),
      RouteSide.bottom => (n.cx, n.bottom + gap),
      RouteSide.left => (n.x - gap, n.cy),
      RouteSide.right => (n.right + gap, n.cy),
    };

/// ด้านของจุดต่อเส้นที่ ([x],[y]) ชี้อยู่ ; ไม่ได้ชี้จุดไหน = null
RouteSide? fcLinkHandleAt(FcNode n, double x, double y, {required double gap, required double radius}) {
  for (final s in RouteSide.values) {
    final (hx, hy) = fcLinkHandlePos(n, s, gap);
    final dx = x - hx, dy = y - hy;
    if (dx * dx + dy * dy <= radius * radius) return s;
  }
  return null;
}

/// สัญลักษณ์ที่ควรแสดงจุดต่อเส้น เมื่อเมาส์อยู่ที่ ([x],[y]): อยู่ในตัวสัญลักษณ์ หรือในแถบรอบที่ครอบจุดต่อเส้นทั้งหมด
/// (ชั้นบนสุดก่อน) ; ไม่มี = null
FcNode? fcLinkHoverNode(FlowchartDiagram d, double x, double y, {required double gap, required double radius}) {
  final reach = gap + radius;
  for (final n in d.nodes.reversed) {
    if (fcNodeContains(n, x, y)) return n;
    if (fcLinkHandleAt(n, x, y, gap: gap, radius: radius) != null) return n;
    // ช่องว่างระหว่างตัวสัญลักษณ์กับจุด: ให้จุดไม่หายตอนเมาส์ข้ามผ่าน
    final inBand = x >= n.x && x <= n.right ? (y >= n.y - reach && y <= n.bottom + reach) : false;
    final inBandSide = y >= n.y && y <= n.bottom ? (x >= n.x - reach && x <= n.right + reach) : false;
    if (inBand || inBandSide) return n;
  }
  return null;
}

/// จุดศูนย์กลางของสัญลักษณ์ใหม่ที่จะโผล่ต่อจาก [from] ทางด้าน [side] (ห่างพอดี [spacing])
(double, double) fcNextNodeCenter(FcNode from, RouteSide side, FcShape shape, {double spacing = 60}) {
  final (w, h) = fcDefaultSize(shape);
  return switch (side) {
    RouteSide.bottom => (from.cx, from.bottom + spacing + h / 2),
    RouteSide.top => (from.cx, from.y - spacing - h / 2),
    RouteSide.right => (from.right + spacing + w / 2, from.cy),
    RouteSide.left => (from.x - spacing - w / 2, from.cy),
  };
}
