import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/flowchart_svg.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/layout/flowchart_geometry.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/validate/flowchart_validator.dart';
import 'package:nsl_nebular/ui/flowchart/fc_painter.dart';
import 'package:nsl_nebular/ui/flowchart/fc_view.dart' show fcShapeIcon;

/// Phase 4: ทุกรูปทรงของ Flowchart (ชุด draw.io) — เรขาคณิต กรอบข้อความ การคลิก ไฟล์ SVG การวาด ตัวตรวจ
void main() {
  FcNode node(FcShape s, {String text = 'ทดสอบ'}) {
    final (w, h) = fcDefaultSize(s);
    return FcNode(id: 'n', shape: s, text: text, x: 100, y: 200, w: w, h: h);
  }

  test('มีครบ 36 รูปทรง (14 เดิม + 21 ที่ดีไซน์เพิ่ม + Transfer ของ draw.io)', () {
    expect(FcShape.values.length, 36);
    // ชื่อในไฟล์ของรูปทรงเดิมต้องไม่เปลี่ยน (ไฟล์เก่าเปิดได้)
    expect(FcShape.values.take(14).map((s) => s.name).toList(), [
      'start', 'end', 'process', 'decision', 'io', 'subroutine', 'connector', //
      'note', 'rounded', 'ellipse', 'text', 'hexagon', 'cylinder', 'document',
    ]);
  });

  for (final s in FcShape.values) {
    group(s.name, () {
      test('เส้นรอบรูปปิด ทุกจุดปลายอยู่ในกรอบ', () {
        final n = node(s);
        final g = fcShapeGeom(n);
        expect(g.outline.first.$1, 'M');
        expect(g.outline.last.$1, 'Z');
        for (final (op, pts) in [...g.outline, ...g.details]) {
          if (op == 'Z') continue;
          final ends = op == 'C' ? [pts.last] : pts;
          for (final p in ends) {
            expect(p.$1, inInclusiveRange(n.x - 0.001, n.right + 0.001), reason: '$op x');
            expect(p.$2, inInclusiveRange(n.y - 0.001, n.bottom + 0.001), reason: '$op y');
          }
        }
      });

      test('กรอบข้อความอยู่ในตัวสัญลักษณ์และมีที่ว่าง', () {
        final n = node(s);
        final b = fcTextBox(n);
        expect(b.width, greaterThan(20));
        expect(b.height, greaterThan(10));
        expect(b.left, greaterThanOrEqualTo(n.x));
        expect(b.top, greaterThanOrEqualTo(n.y));
        expect(b.left + b.width, lessThanOrEqualTo(n.right + 0.001));
        expect(b.top + b.height, lessThanOrEqualTo(n.bottom + 0.001));
      });

      test('คลิกกลางรูป = โดน ; นอกกรอบ = ไม่โดน', () {
        final n = node(s);
        expect(fcNodeContains(n, n.cx, n.cy), isTrue);
        expect(fcNodeContains(n, n.right + 5, n.bottom + 5), isFalse);
      });

      test('ขนาดเริ่มต้น สี ป้ายชื่อ ชื่อมาตรฐาน ไอคอน', () {
        final (w, h) = fcDefaultSize(s);
        expect(w, greaterThanOrEqualTo(kFcMinSide));
        expect(h, greaterThanOrEqualTo(kFcMinSide));
        expect(kFcShapeColors[s], isNotNull);
        expect(fcShapeLabel(s), isNotEmpty);
        expect(fcShapeStdName(s), matches(RegExp(r'^[A-Z][A-Za-z\- ]+$')));
        fcShapeIcon(s);
      });

      test('ป้ายชื่อภาษาอังกฤษไม่มีอักษรไทย', () {
        currentLang = Lang.en;
        addTearDown(() => currentLang = Lang.th);
        expect(fcShapeLabel(s), isNot(matches(RegExp(r'[฀-๿]'))));
      });

      test('บันทึก/เปิด JSON ได้รูปทรงเดิม', () {
        final n = node(s);
        expect(FcNode.tryFromJson(n.toJson())!.shape, s);
      });

      test('SVG และการวาดบนแคนวาสไม่พัง ; ปลายเส้นเชื่อมแตะในกรอบ', () {
        final a = node(s);
        final b = FcNode(id: 'm', shape: FcShape.process, text: 'ต่อ', x: 100, y: 500);
        final d = FlowchartDiagram(nodes: [a, b], edges: [FcEdge(id: 'e', fromId: 'n', toId: 'm')]);
        final svg = exportFlowchartSvg(d)!;
        expect(svg, contains('<path'));
        final rec = ui.PictureRecorder();
        paintFlowchart(ui.Canvas(rec), d);
        rec.endRecording().dispose();
        final r = fcRoutes(d)['e']!;
        expect(r.first.$1, inInclusiveRange(a.x - 0.5, a.right + 0.5));
        expect(r.first.$2, inInclusiveRange(a.y - 0.5, a.bottom + 0.5));
      });
    });
  }

  group('รูปทรงพิเศษ', () {
    test('คำอธิบายประกอบเป็นคำอธิบาย: ไม่นับในกฎการไหล', () {
      expect(fcIsAnnotation(FcShape.annotation), isTrue);
      final d = FlowchartDiagram(nodes: [node(FcShape.annotation)]);
      expect(validateFlowchart(d).where((i) => i.code == 'fc_dead_end' || i.code == 'fc_unreachable'), isEmpty);
    });

    test('ไม่มีพื้น/กรอบ: ข้อความลอย คำอธิบายประกอบ ทำงานขนาน — แต่เส้นตกแต่งยังอยู่ใน SVG', () {
      for (final s in [FcShape.annotation, FcShape.parallelMode]) {
        expect(fcIsBare(s), isTrue);
        expect(fcShapeGeom(node(s)).details, isNotEmpty);
        final svg = exportFlowchartSvg(FlowchartDiagram(nodes: [node(s)]))!;
        expect(svg, contains('fill="none"'));
      }
      expect(fcIsBare(FcShape.process), isFalse);
    });

    test('จุดต่อข้ามหน้าเป็นทางตันได้ ; สัญลักษณ์ล้วนไม่ต้องมีข้อความ', () {
      final start = FcNode(id: 's', shape: FcShape.start, text: 'เริ่ม', x: 0, y: 0);
      final off = FcNode(id: 'o', shape: FcShape.offPage, text: 'A', x: 0, y: 200);
      final or = FcNode(id: 'r', shape: FcShape.or, text: '', x: 200, y: 0);
      final d = FlowchartDiagram(nodes: [start, off, or], edges: [
        FcEdge(id: 'e1', fromId: 's', toId: 'r'),
        FcEdge(id: 'e2', fromId: 'r', toId: 'o'),
      ]);
      final issues = validateFlowchart(d);
      expect(issues.where((i) => i.tableId == 'o' && i.code == 'fc_dead_end'), isEmpty);
      expect(issues.where((i) => i.tableId == 'r' && i.code == 'fc_empty_text'), isEmpty);
      expect(fcTextOptional(FcShape.summingJunction), isTrue);
      expect(fcTextOptional(FcShape.process), isFalse);
    });

    test('รูปวงกลม (จุดรวมผล/หรือ): มุมกรอบไม่นับว่าโดน', () {
      for (final s in [FcShape.summingJunction, FcShape.or]) {
        final n = node(s);
        expect(fcNodeContains(n, n.x + 1, n.y + 1), isFalse);
      }
    });

    test('เรียงลำดับ: เป็นข้าวหลามตัด มุมกรอบไม่นับว่าโดน และมีเส้นกลางแนวนอน', () {
      final n = node(FcShape.sort);
      expect(fcNodeContains(n, n.x + 2, n.y + 2), isFalse);
      final det = fcShapeGeom(n).details;
      expect(det.map((c) => c.$2.first.$2).toSet(), {n.cy});
    });
  });
}
