import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/layout/flowchart_geometry.dart';
import '../../core/models/workspace.dart';
import '../../state/flowchart_controller.dart';
import '../theme.dart';
import 'fc_painter.dart' show fcPath;

/// ขนาดของ minimap (ตามดีไซน์ `Flowchart`)
const Size kFcMinimapSize = Size(150, 96);

/// แคนวาสแคบกว่านี้ไม่แสดง minimap (กันบังพื้นที่ทำงาน)
const double kFcMinimapMinCanvasWidth = 640;

/// การแปลงพิกัดระหว่างแผนภาพกับ minimap: ย่อ [world] ให้พอดีกล่อง [box] (เว้นขอบ [pad]) และอยู่กลางกล่อง
class MinimapFrame {
  MinimapFrame(this.world, Size box, {double pad = 6}) {
    final w = math.max(world.width, 1.0), h = math.max(world.height, 1.0);
    k = math.min((box.width - pad * 2) / w, (box.height - pad * 2) / h);
    origin = Offset((box.width - w * k) / 2, (box.height - h * k) / 2);
  }

  /// ขอบเขตในพิกัดแผนภาพที่ minimap ครอบ
  final Rect world;
  late final double k;
  late final Offset origin;

  Offset toMini(Offset p) => origin + (p - world.topLeft) * k;
  Offset toWorld(Offset m) => world.topLeft + (m - origin) / k;
  Rect rectToMini(Rect r) => Rect.fromPoints(toMini(r.topLeft), toMini(r.bottomRight));
}

/// กรอบของ minimap: ครอบทั้งแผนภาพและส่วนที่มองเห็นอยู่ (ไม่มีสัญลักษณ์ = null)
MinimapFrame? fcMinimapFrame(FlowchartController f, Size canvas, {Size box = kFcMinimapSize}) {
  final b = fcBounds(f.diagram, pad: 20);
  if (b == null || canvas.isEmpty) return null;
  final visible = Rect.fromPoints(f.toWorld(Offset.zero), f.toWorld(Offset(canvas.width, canvas.height)));
  return MinimapFrame(Rect.fromLTRB(b.left, b.top, b.right, b.bottom).expandToInclude(visible), box);
}

/// minimap มุมขวาล่างของแคนวาส Flowchart: รูปทรงย่อ + กรอบประของส่วนที่มองเห็น ; คลิก/ลาก = เลื่อนมุมมองไปตรงนั้น
class FcMinimap extends StatelessWidget {
  const FcMinimap({super.key, required this.canvas});

  /// ขนาดพื้นที่แคนวาส (ใช้คำนวณส่วนที่มองเห็น)
  final Size canvas;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<FlowchartController>();
    final frame = fcMinimapFrame(f, canvas);
    if (frame == null) return const SizedBox.shrink();
    void go(Offset local) => f.revealPoint(frame.toWorld(local), canvas);
    return Semantics(
      label: tr('แผนที่ย่อ'),
      child: Tooltip(
        message: tr('แผนที่ย่อ — คลิกหรือลากเพื่อเลื่อนมุมมอง'),
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          key: const ValueKey('fc-minimap'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => go(d.localPosition),
          onPanStart: (d) => go(d.localPosition),
          onPanUpdate: (d) => go(d.localPosition),
          child: Container(
            width: kFcMinimapSize.width,
            height: kFcMinimapSize.height,
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: C.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(painter: _MinimapPainter(f, frame, canvas)),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.f, this.frame, this.canvasSize);
  final FlowchartController f;
  final MinimapFrame frame;
  final Size canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    final col = C.doc(DocType.flowchart);
    canvas.save();
    canvas.translate(frame.origin.dx - frame.world.left * frame.k, frame.origin.dy - frame.world.top * frame.k);
    canvas.scale(frame.k);
    final fill = Paint()..color = col.main.withValues(alpha: 0.35);
    for (final n in f.diagram.nodes) {
      canvas.drawPath(fcPath(fcShapeGeom(n).outline), fill);
    }
    canvas.restore();

    final view = frame.rectToMini(Rect.fromPoints(f.toWorld(Offset.zero), f.toWorld(Offset(canvasSize.width, canvasSize.height))));
    canvas.drawRect(view, Paint()..color = col.main.withValues(alpha: 0.08));
    _dashedRect(canvas, view, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = col.main);
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const dash = 4.0, gap = 3.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len == 0) return;
      final dir = (b - a) / len;
      for (var t = 0.0; t < len; t += dash + gap) {
        canvas.drawLine(a + dir * t, a + dir * math.min(t + dash, len), p);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => true;
}
