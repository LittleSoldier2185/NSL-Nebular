import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/layout/wireframe_render.dart';
import '../../core/models/wireframe_model.dart';
import '../canvas/box_canvas.dart' show paintMarquee, paintResizeHandles;
import '../flowchart/fc_painter.dart' show fcPath;
import '../theme.dart';
import '../canvas/scene_cache.dart';

/// สีสำเร็จรูปให้เลือกในแผงขวาของ Wireframe
const List<int> kWfPalette = [
  0xFF2563EB,
  0xFF16A34A,
  0xFFDC2626,
  0xFFD97706,
  0xFF0D9488,
  0xFF7C3AED,
  0xFFDB2777,
  0xFF475569,
  0xFFFFFFFF,
  0xFF000000,
];

/// ระยะจุดจับหมุนเหนือขอบบนของชิ้น (พิกเซลจอ)
const double kWfRotateHandleGap = 26;

void _strokeDashed(Canvas canvas, Path path, Paint paint) {
  for (final m in path.computeMetrics()) {
    var dist = 0.0;
    var on = true;
    while (dist < m.length) {
      final len = on ? 6.0 : 4.0;
      if (on) canvas.drawPath(m.extractPath(dist, math.min(m.length, dist + len)), paint);
      dist += len;
      on = !on;
    }
  }
}

/// วาดชิ้นวาดกลางของ Wireframe ลงใน [canvas] (พิกัดหน้าจอ ผู้เรียกจัดการ translate/scale เอง)
void paintWfPrims(Canvas canvas, List<WfPrim> prims) {
  for (final p in prims) {
    switch (p) {
      case WfGroupPrim():
        canvas.save();
        canvas.translate(p.cx, p.cy);
        canvas.rotate(p.degrees * math.pi / 180);
        canvas.translate(-p.cx, -p.cy);
        paintWfPrims(canvas, p.children);
        canvas.restore();
      case WfPathPrim():
        final path = fcPath(p.cmds);
        if (p.fill != null) canvas.drawPath(path, Paint()..color = Color(p.fill!));
        if (p.stroke != null) {
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = p.width
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..color = Color(p.stroke!);
          if (p.dashed) {
            _strokeDashed(canvas, path, paint);
          } else {
            canvas.drawPath(path, paint);
          }
        }
      case WfTextPrim():
        final lineH = p.size * 1.3;
        final maxLines = p.maxLines ?? math.max(1, (p.h / lineH).floor());
        final tp = TextPainter(
          text: TextSpan(
            text: p.text,
            style: TextStyle(
              fontFamily: kThai,
              fontFamilyFallback: kFontFallback,
              fontSize: p.size,
              color: Color(p.color),
              fontWeight: p.bold ? FontWeight.w700 : FontWeight.w400,
              height: 1.3,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: switch (p.align) { 1 => TextAlign.center, 2 => TextAlign.right, _ => TextAlign.left },
          maxLines: maxLines,
          ellipsis: '…',
        )..layout(maxWidth: math.max(4, p.w));
        final dx = switch (p.align) { 1 => p.x + (p.w - tp.width) / 2, 2 => p.x + p.w - tp.width, _ => p.x };
        final dy = p.top ? p.y : p.y + (p.h - tp.height) / 2;
        tp.paint(canvas, Offset(dx, dy));
        tp.dispose();
    }
  }
}

/// ที่เก็บภาพที่วาดแล้วของแต่ละชิ้น (วาดที่มุม 0,0 ของชิ้น) — กุญแจ = รูปแบบการแสดงผล + ค่าทุกอย่างของชิ้นยกเว้นตำแหน่ง/การหมุน
/// ลาก/ย้าย/หมุน/เลื่อน/ซูม จึงไม่ต้องสร้างชิ้นวาดและวัดข้อความใหม่ ; เก็บสูงสุด [_max] ภาพ (ใช้ล่าสุดอยู่ท้าย)
class WfPictureCache {
  WfPictureCache._();

  static const _max = 4000;
  static final LinkedHashMap<String, ui.Picture> _pics = LinkedHashMap();

  static int get length => _pics.length;
  static void clear() => _pics.clear();

  static ui.Picture _get(String key, void Function(Canvas c) draw) {
    final hit = _pics.remove(key);
    if (hit != null) {
      _pics[key] = hit;
      return hit;
    }
    final rec = ui.PictureRecorder();
    draw(Canvas(rec));
    final pic = rec.endRecording();
    _pics[key] = pic;
    // ภาพเก่าที่ถูกตัดออกปล่อยให้ระบบเก็บกวาดเอง (อาจยังถูกอ้างในเฟรมที่กำลังวาด)
    if (_pics.length > _max) _pics.remove(_pics.keys.first);
    return pic;
  }

  static String _styleKey(WireframeDiagram d) => '${d.style.name}|${d.accent}';

  static ui.Picture frame(WireframeDiagram d) =>
      _get('F|${_styleKey(d)}|${d.width}|${d.height}', (c) => paintWfPrims(c, wfFramePrims(d)));

  static ui.Picture component(WireframeDiagram d, WfComponent comp, {bool noText = false}) {
    final j = comp.toJson()
      ..remove('x')
      ..remove('y')
      ..remove('rotation')
      ..remove('hidden')
      ..remove('locked')
      ..remove('group')
      ..remove('ref')
      ..remove('api');
    if (noText) j['text'] = '';
    return _get('C|${_styleKey(d)}|${jsonEncode(j)}', (c) {
      final local = WfComponent.tryFromJson({...j, 'x': 0, 'y': 0})!;
      paintWfPrims(c, wfComponentPrims(d, local));
    });
  }
}

/// วาดหน้าจอ Wireframe ทั้งกรอบจากภาพที่เก็บไว้ ([hideTextOf] = ชิ้นที่กำลังพิมพ์บนแคนวาส ไม่วาดข้อความซ้อน) ; ชิ้นที่ซ่อนไม่ถูกวาด
void paintWireframe(Canvas canvas, WireframeDiagram d, {String? hideTextOf, Set<String>? hidden}) {
  canvas.drawPicture(WfPictureCache.frame(d));
  final hide = hidden ?? wfHiddenIds(d);
  for (final c in d.components) {
    if (hide.contains(c.id)) continue;
    final pic = WfPictureCache.component(d, c, noText: c.id == hideTextOf);
    canvas.save();
    if (c.rotation == 0) {
      canvas.translate(c.x, c.y);
    } else {
      canvas.translate(c.x + c.w / 2, c.y + c.h / 2);
      canvas.rotate(c.rotation * math.pi / 180);
      canvas.translate(-c.w / 2, -c.h / 2);
    }
    canvas.drawPicture(pic);
    canvas.restore();
  }
}

/// ทำงานในพิกัดของชิ้น [c] (มุมบนซ้าย 0,0 ก่อนหมุน)
void _inLocal(Canvas canvas, WfComponent c, void Function() draw) {
  canvas.save();
  canvas.translate(c.x + c.w / 2, c.y + c.h / 2);
  canvas.rotate(c.rotation * math.pi / 180);
  canvas.translate(-c.w / 2, -c.h / 2);
  draw();
  canvas.restore();
}

/// ตัวพิมพ์บนจอ: เลื่อน/ซูม แล้ววาดหน้าจอ + ป้ายขนาดหน้าจอ + ชิปข้อมูล ER + กรอบเลือก/จุดจับ/จุดหมุน + กรอบลากเลือก
class WireframeScreenPainter extends CustomPainter {
  WireframeScreenPainter({
    required this.diagram,
    required this.offset,
    required this.scale,
    required this.frameLabel,
    this.selected = const {},
    this.children = const {},
    this.chips = const {},
    this.hidden = const {},
    this.marquee,
    this.hideTextOf,
  });

  final WireframeDiagram diagram;
  final Offset offset;
  final double scale;
  final String frameLabel;
  final Set<String> selected;

  /// ลูกในภาชนะของชิ้นที่เลือก (ไฮไลต์จาง ๆ ว่าจะย้ายตาม)
  final Set<String> children;

  /// ชิปข้อมูล ER: id ชิ้น -> (ข้อความ, ผูกขาด?)
  final Map<String, (String, bool)> chips;

  /// ชิ้นที่มองไม่เห็น (ซ่อนเอง/อยู่ในภาชนะที่ซ่อน)
  final Set<String> hidden;
  final Rect? marquee;
  final String? hideTextOf;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    // เงาใต้กรอบหน้าจอ
    canvas.drawRect(
      Rect.fromLTWH(0, 4, diagram.width, diagram.height),
      Paint()
        ..color = Colors.black.withValues(alpha: C.isDark ? 0.35 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    drawCachedScene(canvas, diagram, '${jsonEncode(diagram.toContentJson())}|$hideTextOf|${setKey(hidden)}',
        (c) => paintWireframe(c, diagram, hideTextOf: hideTextOf, hidden: hidden));

    final label = TextPainter(
      text: TextSpan(text: frameLabel, style: TextStyle(fontFamily: kThai, fontSize: 12 / scale, color: C.muted)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    label.paint(canvas, Offset(0, -label.height - 4 / scale));

    for (final c in diagram.components) {
      final chip = chips[c.id];
      if (chip == null || hidden.contains(c.id)) continue;
      final (text, broken) = chip;
      final color = broken ? C.danger : const Color(0xFF0D9488);
      final tp = TextPainter(
        text: TextSpan(text: '⛁ $text', style: TextStyle(fontFamily: kThai, fontFamilyFallback: kFontFallback, fontSize: 10.5 / scale, color: Colors.white, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(40 / scale, c.w));
      final bb = wfBounds(c);
      final r = Rect.fromLTWH(bb.right - tp.width - 8 / scale, bb.top - tp.height - 2 / scale, tp.width + 8 / scale, tp.height + 2 / scale);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(4 / scale)), Paint()..color = color);
      tp.paint(canvas, Offset(r.left + 4 / scale, r.top + 1 / scale));
    }

    for (final c in diagram.components) {
      final isSel = selected.contains(c.id);
      if (!isSel && !children.contains(c.id)) continue;
      _inLocal(canvas, c, () {
        final rect = Rect.fromLTWH(0, 0, c.w, c.h);
        if (!isSel) {
          canvas.drawRect(
            rect.inflate(2 / scale),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1 / scale
              ..color = C.primary.withValues(alpha: 0.45),
          );
          return;
        }
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 / scale
          ..color = c.locked ? C.muted : C.primary;
        if (hidden.contains(c.id)) {
          _strokeDashed(canvas, Path()..addRect(rect.inflate(3 / scale)), paint);
        } else {
          canvas.drawRect(rect.inflate(3 / scale), paint);
        }
      });
    }
    if (selected.length == 1) {
      final c = diagram.componentById(selected.first);
      if (c != null && !c.locked) {
        _inLocal(canvas, c, () {
          paintResizeHandles(canvas, Rect.fromLTWH(0, 0, c.w, c.h), scale);
          // จุดหมุน: วงกลมเหนือกึ่งกลางขอบบน + เส้นต่อ
          final top = Offset(c.w / 2, 0);
          final knob = Offset(c.w / 2, -kWfRotateHandleGap / scale);
          canvas.drawLine(
            top,
            knob,
            Paint()
              ..strokeWidth = 1.2 / scale
              ..color = C.primary,
          );
          canvas.drawCircle(knob, 5 / scale, Paint()..color = C.surface);
          canvas.drawCircle(
            knob,
            5 / scale,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4 / scale
              ..color = C.primary,
          );
        });
      }
    }
    canvas.restore();
    paintMarquee(canvas, marquee);
  }

  @override
  bool shouldRepaint(WireframeScreenPainter old) => true;
}
