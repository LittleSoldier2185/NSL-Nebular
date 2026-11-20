import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/wireframe_model.dart';

/// หมวดของคลังชิ้นส่วน Wireframe (Phase 18, ดีไซน์แบบ A): ทุกชนิดอยู่ในหมวดเดียวพอดี (เทสต์ตรวจ)
class WfCategory {
  const WfCategory(this.id, this.kinds);
  final String id;
  final List<WfKind> kinds;

  String get label => switch (id) {
        'layout' => tr('โครงหน้า'),
        'text' => tr('ข้อความ'),
        'form' => tr('ฟอร์ม'),
        'data' => tr('ข้อมูล'),
        'media' => tr('สื่อ'),
        _ => tr('สถานะ'),
      };
}

const List<WfCategory> kWfCategories = [
  WfCategory('layout', [
    WfKind.container, WfKind.card, WfKind.navbar, WfKind.sidebar, WfKind.footer,
    WfKind.modal, WfKind.tabs, WfKind.accordion, WfKind.divider,
  ]),
  WfCategory('text', [WfKind.heading, WfKind.label, WfKind.paragraph, WfKind.link, WfKind.breadcrumb]),
  WfCategory('form', [
    WfKind.button, WfKind.input, WfKind.textarea, WfKind.checkbox, WfKind.radio, WfKind.toggle,
    WfKind.select, WfKind.slider, WfKind.search, WfKind.datepicker, WfKind.upload, WfKind.rating,
  ]),
  WfCategory('data', [
    WfKind.table, WfKind.list, WfKind.tree, WfKind.chart, WfKind.stat, WfKind.calendar, WfKind.pagination,
  ]),
  WfCategory('media', [WfKind.image, WfKind.icon, WfKind.avatar, WfKind.video, WfKind.map]),
  WfCategory('status', [
    WfKind.badge, WfKind.chip, WfKind.progress, WfKind.alert, WfKind.stepper, WfKind.tooltip, WfKind.skeleton,
  ]),
];

/// รูปย่อของชิ้นส่วน (ภาพเส้นขนาด 44×28 หน่วย ย่อ/ขยายตามกล่อง) — ใช้ในคลังและแถบเครื่องมือ
class WfKindThumb extends StatelessWidget {
  const WfKindThumb(this.kind, {super.key, this.color, this.width = 30, this.height = 20});
  final WfKind kind;
  final Color? color;
  final double width, height;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, height),
        painter: _ThumbPainter(kind, color ?? IconTheme.of(context).color ?? Colors.grey),
      );
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.kind, this.color);
  final WfKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 44;
    canvas.save();
    canvas.scale(s, size.height / 28);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final soft = Paint()..color = color.withValues(alpha: 0.22);
    final solid = Paint()..color = color;

    void r(double x, double y, double w, double h, {double rad = 2, bool fill = false, bool dash = false}) {
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rad));
      if (fill) canvas.drawRRect(rr, soft);
      if (dash) {
        final path = Path()..addRRect(rr);
        for (final m in path.computeMetrics()) {
          for (double d = 0; d < m.length; d += 5) {
            canvas.drawPath(m.extractPath(d, (d + 3).clamp(0, m.length)), line);
          }
        }
      } else {
        canvas.drawRRect(rr, line);
      }
    }

    void l(double x1, double y1, double x2, double y2, [double w = 1.3]) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), w == 1.3 ? line : (Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round));
    void c(double x, double y, double rad, {bool fill = false}) => canvas.drawCircle(Offset(x, y), rad, fill ? solid : line);
    void poly(List<double> pts, {bool close = false}) {
      final p = Path()..moveTo(pts[0], pts[1]);
      for (var i = 2; i < pts.length; i += 2) {
        p.lineTo(pts[i], pts[i + 1]);
      }
      if (close) p.close();
      canvas.drawPath(p, line);
    }

    switch (kind) {
      case WfKind.container:
        r(3, 3, 38, 22, dash: true);
      case WfKind.heading:
        l(5, 12, 32, 12, 3.4);
        l(5, 19, 20, 19);
      case WfKind.label:
        l(5, 14, 28, 14);
      case WfKind.paragraph:
        l(5, 8, 38, 8);
        l(5, 14, 38, 14);
        l(5, 20, 26, 20);
      case WfKind.button:
        r(8, 8, 28, 12, rad: 6, fill: true);
      case WfKind.input:
        r(3, 8, 38, 12, rad: 3);
        l(7, 14, 18, 14);
      case WfKind.textarea:
        r(3, 3, 38, 22, rad: 3);
        l(7, 9, 30, 9);
        l(7, 14, 24, 14);
      case WfKind.checkbox:
        r(5, 9, 10, 10);
        poly([7, 14, 9, 16, 13, 12]);
        l(20, 14, 38, 14);
      case WfKind.radio:
        c(10, 14, 5);
        c(10, 14, 2, fill: true);
        l(20, 14, 38, 14);
      case WfKind.toggle:
        r(8, 9, 28, 10, rad: 5, fill: true);
        c(30, 14, 3.4, fill: true);
      case WfKind.select:
        r(3, 8, 38, 12, rad: 3);
        poly([30, 12, 33, 15, 36, 12]);
      case WfKind.slider:
        l(4, 14, 40, 14);
        c(20, 14, 4, fill: true);
      case WfKind.search:
        r(3, 8, 38, 12, rad: 6);
        c(12, 14, 3);
        l(14, 16, 17, 19);
      case WfKind.image:
        r(3, 3, 38, 22);
        poly([3, 21, 13, 13, 21, 19, 27, 15, 41, 23]);
        c(12, 9, 2);
      case WfKind.icon:
        poly([22, 6, 25, 13, 32, 13.6, 26.6, 18.2, 28.4, 25.2, 22, 21, 15.6, 25.2, 17.4, 18.2, 12, 13.6, 19, 13], close: true);
      case WfKind.avatar:
        c(22, 14, 11);
        c(22, 11, 3.4);
        canvas.drawPath(Path()..moveTo(14, 22)..relativeCubicTo(2, -5, 14, -5, 16, 0), line);
      case WfKind.table:
        r(3, 3, 38, 22);
        l(3, 10, 41, 10);
        l(3, 17, 41, 17);
        l(16, 3, 16, 25);
      case WfKind.list:
        for (final y in [8.0, 14.0, 20.0]) {
          c(7, y, 1.6, fill: true);
          l(12, y, 38, y);
        }
      case WfKind.card:
        r(3, 3, 38, 22, rad: 3);
        r(3, 3, 38, 9, rad: 3, fill: true);
        l(8, 18, 30, 18);
      case WfKind.tabs:
        l(3, 12, 41, 12);
        r(5, 5, 12, 7, fill: true);
        l(22, 8, 30, 8);
        l(34, 8, 40, 8);
      case WfKind.navbar:
        r(2, 3, 40, 8, fill: true);
        l(6, 7, 12, 7);
        l(26, 7, 32, 7);
        l(35, 7, 40, 7);
      case WfKind.sidebar:
        r(2, 2, 40, 24);
        r(2, 2, 12, 24, fill: true);
      case WfKind.modal:
        r(2, 2, 40, 24, dash: true);
        r(9, 6, 26, 16, rad: 3);
        l(13, 11, 30, 11);
      case WfKind.divider:
        l(3, 14, 41, 14);
      case WfKind.badge:
        r(12, 9, 20, 10, rad: 5, fill: true);
      case WfKind.pagination:
        r(4, 9, 8, 10);
        r(15, 9, 8, 10, fill: true);
        r(26, 9, 8, 10);
        l(36, 14, 40, 14);
      case WfKind.breadcrumb:
        l(4, 14, 12, 14);
        poly([15, 11, 18, 14, 15, 17]);
        l(21, 14, 29, 14);
        poly([32, 11, 35, 14, 32, 17]);
        l(37, 14, 40, 14);
      case WfKind.map:
        final pin = Path()
          ..moveTo(22, 24)
          ..relativeCubicTo(0, 0, -8, -7, -8, -13)
          ..arcToPoint(const Offset(30, 11), radius: const Radius.circular(8))
          ..relativeCubicTo(0, 6, -8, 13, -8, 13)
          ..close();
        canvas.drawPath(pin, line);
        c(22, 11, 2.6);
      case WfKind.chart:
        r(5, 14, 6, 10, rad: 1, fill: true);
        r(15, 8, 6, 16, rad: 1, fill: true);
        r(25, 12, 6, 12, rad: 1, fill: true);
        l(3, 25, 41, 25);
      case WfKind.link:
        l(6, 16, 32, 16);
        l(6, 11, 26, 11);
      case WfKind.chip:
        r(8, 9, 28, 10, rad: 5);
        c(14, 14, 2, fill: true);
        l(19, 14, 31, 14);
      case WfKind.progress:
        r(3, 11, 38, 6, rad: 3);
        r(3, 11, 22, 6, rad: 3, fill: true);
      case WfKind.alert:
        r(3, 6, 38, 16, rad: 3);
        c(9, 14, 2, fill: true);
        l(15, 14, 36, 14);
      case WfKind.datepicker:
        r(3, 8, 38, 12, rad: 3);
        r(29, 10, 8, 8);
        l(29, 13, 37, 13);
      case WfKind.upload:
        r(3, 4, 38, 20, rad: 3, dash: true);
        l(22, 19, 22, 11);
        poly([18, 14, 22, 10, 26, 14]);
      case WfKind.stepper:
        c(8, 14, 3.4, fill: true);
        l(11, 14, 19, 14);
        c(22, 14, 3.4);
        l(25, 14, 33, 14);
        c(36, 14, 3.4);
      case WfKind.rating:
        for (final x in [8.0, 17.0, 26.0, 35.0]) {
          c(x, 14, 3, fill: x < 20);
        }
      case WfKind.video:
        r(3, 3, 38, 22, rad: 3);
        poly([19, 9, 28, 14, 19, 19], close: true);
      case WfKind.accordion:
        r(3, 3, 38, 7);
        r(3, 12, 38, 13);
        poly([33, 5, 35, 7, 37, 5]);
        l(7, 18, 30, 18);
      case WfKind.footer:
        r(2, 3, 40, 22);
        r(2, 19, 40, 6, rad: 1, fill: true);
      case WfKind.tooltip:
        r(5, 4, 34, 14, rad: 3, fill: true);
        poly([19, 18, 22, 22, 25, 18]);
        l(10, 11, 34, 11);
      case WfKind.skeleton:
        r(4, 5, 12, 12, rad: 6, fill: true);
        l(20, 8, 38, 8, 3);
        l(20, 14, 32, 14, 3);
        l(4, 22, 38, 22, 3);
      case WfKind.calendar:
        r(3, 3, 38, 22);
        l(3, 9, 41, 9);
        for (final x in [11.0, 18.0, 25.0, 32.0]) {
          c(x, 15, 1, fill: true);
        }
        for (final x in [11.0, 18.0]) {
          c(x, 20, 1, fill: true);
        }
      case WfKind.stat:
        r(3, 3, 38, 22, rad: 3);
        l(8, 12, 24, 12, 4);
        l(8, 19, 20, 19);
      case WfKind.tree:
        c(6, 6, 1.6, fill: true);
        l(10, 6, 26, 6);
        l(12, 12, 12, 20);
        l(12, 13, 16, 13);
        l(16, 13, 32, 13);
        l(12, 20, 16, 20);
        l(16, 20, 30, 20);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.kind != kind || old.color != color;
}
