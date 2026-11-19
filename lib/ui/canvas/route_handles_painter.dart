import 'package:flutter/material.dart';

import '../../core/layout/ortho_route.dart';
import '../../core/layout/route_edit.dart';
import '../theme.dart';

/// จุดจับของเส้นที่เลือก (ทุกแผนภาพใช้ร่วมกัน) : ปลายทั้งสอง = วงกลมขอบสี, กึ่งกลางแต่ละช่วง = จุดเล็ก — ขนาดคงที่บนจอ
/// เรียกในพิกัดแผนภาพ (หลัง translate/scale) ; [scale] = ซูมปัจจุบัน
void paintRouteHandles(Canvas canvas, List<RoutePoint> route, Color accent, double scale) {
  for (final h in routeHandles(route)) {
    final c = Offset(h.at.$1, h.at.$2);
    if (h.kind == RouteHandleKind.segment) {
      canvas.drawCircle(c, 3.6 / scale, Paint()..color = accent.withValues(alpha: 0.55));
    } else {
      canvas.drawCircle(c, 5.5 / scale, Paint()..color = C.surface);
      canvas.drawCircle(
        c,
        5.5 / scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 / scale
          ..color = accent,
      );
    }
  }
}

/// ปลายเส้นที่กำลังลากมาวางบนกล่อง [box] : ไฮไลต์กล่องและจุดต่อ [port] ที่จะใช้
void paintRouteDrop(Canvas canvas, RouteBox box, RoutePort? port, double scale) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(box.x, box.y, box.w, box.h).inflate(3), const Radius.circular(10)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / scale
      ..color = C.primary.withValues(alpha: 0.8),
  );
  if (port != null) {
    final (px, py) = routePortPoint(box, port);
    canvas.drawCircle(Offset(px, py), 6 / scale, Paint()..color = C.primary);
  }
}
