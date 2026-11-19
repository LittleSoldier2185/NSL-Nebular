import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/dfd_model.dart';
import '../../core/models/workspace.dart';
import '../../state/dfd_controller.dart';
import '../flowchart/fc_minimap.dart' show MinimapFrame, kFcMinimapSize, kFcMinimapMinCanvasWidth;
import '../theme.dart';

/// แคนวาส DFD แคบกว่านี้ไม่แสดง minimap (ค่าเดียวกับ Flowchart)
const double kDfdMinimapMinCanvasWidth = kFcMinimapMinCanvasWidth;

/// กรอบของ minimap: ครอบทุกวัตถุ/ขอบเขตระบบและส่วนที่มองเห็นอยู่ (ไม่มีวัตถุ = null)
MinimapFrame? dfdMinimapFrame(DfdController d, Size canvas, {Size box = kFcMinimapSize}) {
  final dg = d.diagram;
  if (dg.nodes.isEmpty || canvas.isEmpty) return null;
  Rect? b;
  for (final n in dg.nodes) {
    final r = Rect.fromLTWH(n.x, n.y, n.w, n.h);
    b = b == null ? r : b.expandToInclude(r);
  }
  for (final x in dg.boundaries) {
    b = b!.expandToInclude(Rect.fromLTWH(x.x, x.y, x.w, x.h));
  }
  final visible = Rect.fromPoints(d.toWorld(Offset.zero), d.toWorld(Offset(canvas.width, canvas.height)));
  return MinimapFrame(b!.inflate(20).expandToInclude(visible), box);
}

/// minimap มุมขวาล่างของแคนวาส DFD (ตามดีไซน์ Phase 15) : วัตถุย่อ + กรอบส่วนที่มองเห็น ; คลิก/ลาก = เลื่อนมุมมอง
class DfdMinimap extends StatelessWidget {
  const DfdMinimap({super.key, required this.canvas});
  final Size canvas;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DfdController>();
    final frame = dfdMinimapFrame(d, canvas);
    if (frame == null) return const SizedBox.shrink();
    void go(Offset local) => d.revealPoint(frame.toWorld(local), canvas);
    return Semantics(
      label: tr('แผนที่ย่อ'),
      child: Tooltip(
        message: tr('แผนที่ย่อ — คลิกหรือลากเพื่อเลื่อนมุมมอง'),
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          key: const ValueKey('dfd-minimap'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) => go(e.localPosition),
          onPanStart: (e) => go(e.localPosition),
          onPanUpdate: (e) => go(e.localPosition),
          child: Container(
            width: kFcMinimapSize.width,
            height: kFcMinimapSize.height,
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: C.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(painter: _DfdMinimapPainter(d, frame, canvas)),
          ),
        ),
      ),
    );
  }
}

class _DfdMinimapPainter extends CustomPainter {
  _DfdMinimapPainter(this.d, this.frame, this.canvasSize);
  final DfdController d;
  final MinimapFrame frame;
  final Size canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    final col = C.doc(DocType.dfd).main;
    canvas.save();
    canvas.translate(frame.origin.dx - frame.world.left * frame.k, frame.origin.dy - frame.world.top * frame.k);
    canvas.scale(frame.k);
    final fill = Paint()..color = col.withValues(alpha: 0.35);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / frame.k
      ..color = col;
    for (final n in d.diagram.nodes) {
      final r = Rect.fromLTWH(n.x, n.y, n.w, n.h);
      switch (n.kind) {
        case DfdKind.process:
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(r.shortestSide / 4, 12))), fill);
        case DfdKind.store:
          canvas.drawRect(r, fill);
        case DfdKind.entity:
          canvas.drawRect(r, line);
      }
    }
    canvas.restore();

    final view = frame.rectToMini(Rect.fromPoints(d.toWorld(Offset.zero), d.toWorld(Offset(canvasSize.width, canvasSize.height))));
    canvas.drawRect(view, Paint()..color = col.withValues(alpha: 0.08));
    canvas.drawRect(view, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = col);
  }

  @override
  bool shouldRepaint(_DfdMinimapPainter old) => true;
}
