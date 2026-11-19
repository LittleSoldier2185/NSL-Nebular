import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/layout/ortho_route.dart';
import 'package:nsl_nebular/core/layout/route_edit.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/project_controller.dart';

import 'migration_fixtures.dart';
import 'support/project_helpers.dart';


DfdDiagram twoBoxes() => DfdDiagram(nodes: [
      DfdNode(id: 'a', kind: DfdKind.process, name: 'A', number: '1', x: 0, y: 0, w: 100, h: 60),
      DfdNode(id: 'b', kind: DfdKind.process, name: 'B', number: '2', x: 300, y: 200, w: 100, h: 60),
    ], flows: [
      DfdFlow(id: 'f', fromId: 'a', toId: 'b', label: 'x'),
    ]);

bool axisAligned(List<RoutePoint> r) {
  for (var i = 1; i < r.length; i++) {
    if ((r[i].$1 - r[i - 1].$1).abs() > 0.01 && (r[i].$2 - r[i - 1].$2).abs() > 0.01) return false;
  }
  return true;
}

void main() {
  trimTests();
  group('routeFromHints', () {
    test('Z (3 ช่วง): hint เดียว = พิกัด x ของช่วงกลาง', () {
      final r = routeFromHints((100, 30), RouteSide.right, (300, 230), RouteSide.left, [180]);
      expect(r, [(100.0, 30.0), (180.0, 30.0), (180.0, 230.0), (300.0, 230.0)]);
    });

    test('จำนวนช่วงขัดกับด้านที่ออก/เข้า = null', () {
      // ออกแนวนอน เข้าแนวนอน ต้องเป็นจำนวนช่วงคี่ ; hint 2 ตัว = 4 ช่วง
      expect(routeFromHints((100, 30), RouteSide.right, (300, 230), RouteSide.left, [150, 100]), isNull);
    });

    test('hint ที่เข้าไปในกล่องถูกดันออกอย่างน้อย 12 px', () {
      final r = routeFromHints((100, 30), RouteSide.right, (300, 230), RouteSide.left, [50])!;
      expect(r[1].$1, 112);
    });

    test('ตัว L ตั้งฉากกัน: ออกด้านขวา เข้าด้านบน', () {
      final r = routeBetweenSides((100, 30), RouteSide.right, (350, 200), RouteSide.top);
      expect(r, [(100.0, 30.0), (350.0, 30.0), (350.0, 200.0)]);
    });

    test('ทุกคู่ด้านให้เส้นหักมุมฉากเสมอ และออก/เข้าตั้งฉากกับขอบ', () {
      const boxA = RouteBox('a', 0, 0, 100, 60), boxB = RouteBox('b', 300, 200, 100, 60);
      for (final s0 in RouteSide.values) {
        for (final s1 in RouteSide.values) {
          final p0 = routePortPoint(boxA, RoutePort(s0));
          final p1 = routePortPoint(boxB, RoutePort(s1));
          final r = routeBetweenSides(p0, s0, p1, s1);
          expect(axisAligned(r), isTrue, reason: '$s0→$s1 $r');
          expect(r.first, p0);
          expect(r.last, p1);
          final (e0, e1) = routeEndSides(r);
          expect(e0, s0, reason: '$s0→$s1 $r');
          expect(e1, s1, reason: '$s0→$s1 $r');
        }
      }
    });
  });

  group('orthogonalRoutes กับค่าที่แก้เอง', () {
    test('exit/entry ที่กำหนดเองถูกใช้ และเส้นอื่นไม่ถูกกระทบ', () {
      const boxes = {
        'a': RouteBox('a', 0, 0, 100, 60),
        'b': RouteBox('b', 300, 200, 100, 60),
      };
      final r = orthogonalRoutes(boxes, [
        const RouteLink('f', 'a', 'b', exit: RoutePort(RouteSide.bottom, 0.25), entry: RoutePort(RouteSide.left, 0.5)),
      ]);
      expect(r['f']!.first, (25.0, 60.0));
      expect(r['f']!.last, (300.0, 230.0));
      expect(axisAligned(r['f']!), isTrue);
    });

    test('hints ที่กำหนดเองไม่ถูกดันห่างจากเส้นอื่น และไม่ถูก avoidBoxes อ้อม', () {
      const boxes = {
        'a': RouteBox('a', 0, 0, 100, 60),
        'b': RouteBox('b', 300, 0, 100, 60),
        'c': RouteBox('c', 600, 0, 100, 60),
      };
      final r = orthogonalRoutes(boxes, [const RouteLink('f', 'a', 'c', hints: [150, 100, 500])], avoidBoxes: true);
      expect(r['f'], isNotNull);
      expect(routeHintsOf(r['f']!), [150, 100, 500]);
    });
  });

  group('แก้เส้น', () {
    test('ลากช่วงกลางของเส้น Z = เลื่อน hint', () {
      final r = routeFromHints((100, 30), RouteSide.right, (300, 230), RouteSide.left, [180])!;
      expect(dragRouteSegment(r, 1, 220), [220]);
    });

    test('ลากช่วงแรกของเส้น Z = แตกช่วง (5 ช่วง) และยังหักมุมฉาก', () {
      final r = routeFromHints((100, 30), RouteSide.right, (300, 230), RouteSide.left, [180])!;
      final h = dragRouteSegment(r, 0, -40);
      expect(h.length, 3);
      final r2 = routeFromHints((100, 30), RouteSide.right, (300, 230), RouteSide.left, h)!;
      expect(axisAligned(r2), isTrue);
      expect(r2.length, 6);
      expect(r2.any((p) => p.$2 == -40), isTrue);
    });

    test('ลากช่วงของตัว L = เส้น 4 ช่วง ; ปลายเดิมยังอยู่', () {
      final r = routeBetweenSides((100, 30), RouteSide.right, (350, 200), RouteSide.top);
      final h = dragRouteSegment(r, 0, -30);
      final r2 = routeFromHints(r.first, RouteSide.right, r.last, RouteSide.top, h)!;
      expect(axisAligned(r2), isTrue);
      expect(r2.first, r.first);
      expect(r2.last, r.last);
    });

    test('ลากแล้วกลับเข้าแนวเดิม = รวมช่วงจนไม่เหลือ hint ที่ซ้ำ', () {
      // ช่วงแรกถูกลากไปที่ y เดิมของ p0 → ช่วงที่แตกออกมารวมกลับ
      final r = routeFromHints((100, 30), RouteSide.right, (300, 230), RouteSide.left, [180])!;
      final h = dragRouteSegment(r, 0, 30);
      expect(normalizeRouteHints(h, 30, 230), [180]);
    });

    test('เส้นตรงช่วงเดียว: ลากแล้วเป็น 5 ช่วง', () {
      final h = dragRouteSegment([(100.0, 30.0), (300.0, 30.0)], 0, 90);
      expect(h.length, 3);
      expect(h[1], 90);
    });

    test('nearestRoutePort: เลือกด้านที่ใกล้สุด และปัดเข้ากลางด้าน', () {
      const b = RouteBox('b', 0, 0, 100, 60);
      expect(nearestRoutePort(b, (50, -10)).side, RouteSide.top);
      expect(nearestRoutePort(b, (50, -10)).t, 0.5);
      expect(nearestRoutePort(b, (110, 15)), const RoutePort(RouteSide.right, 0.25));
      expect(nearestRoutePort(b, (-5, 59)).side, RouteSide.left);
    });

    test('routeHandleAt: ปลายเส้นมาก่อนกลางช่วง', () {
      final r = routeFromHints((100, 30), RouteSide.right, (300, 230), RouteSide.left, [180])!;
      expect(routeHandleAt(r, (101, 31), 8)!.kind, RouteHandleKind.start);
      expect(routeHandleAt(r, (180, 130), 8)!.kind, RouteHandleKind.segment);
      expect(routeHandleAt(r, (500, 500), 8), isNull);
    });
  });

  group('โมเดล DFD', () {
    test('เซฟ/โหลด: exit, entry, bends, ป้าย ; ไม่มีค่า = ไม่มีคีย์', () {
      final f = DfdFlow(
        id: 'f',
        fromId: 'a',
        toId: 'b',
        exit: const RoutePort(RouteSide.bottom, 0.3),
        entry: const RoutePort(RouteSide.left),
        hints: [10, 20.5],
        labelDx: 5,
        labelDy: -7,
      );
      final back = DfdFlow.tryFromJson(f.toJson())!;
      expect(back.exit, const RoutePort(RouteSide.bottom, 0.3));
      expect(back.entry, const RoutePort(RouteSide.left, 0.5));
      expect(back.hints, [10, 20.5]);
      expect((back.labelDx, back.labelDy), (5, -7));
      final plain = DfdFlow(id: 'g', fromId: 'a', toId: 'b').toJson();
      for (final k in ['exit', 'entry', 'bends', 'lbl']) {
        expect(plain.containsKey(k), isFalse);
      }
    });

    test('ไฟล์ที่ค่าผิดรูป: ข้ามค่านั้น ไม่พัง', () {
      final f = DfdFlow.tryFromJson({
        'id': 'f',
        'from': 'a',
        'to': 'b',
        'exit': {'s': 'nowhere', 't': 0.5},
        'entry': 'x',
        'bends': [1, 'two'],
        'lbl': [double.nan, 'x'],
      })!;
      expect(f.exit, isNull);
      expect(f.entry, isNull);
      expect(f.hints, isNull);
      expect((f.labelDx, f.labelDy), (0, 0));
    });

    test('dfdRoutes ใช้ค่าที่แก้เอง และป้ายตามระยะที่ลาก', () {
      final d = twoBoxes();
      final auto = dfdRoutes(d)['f']!;
      final f = d.flows.single..labelDx = 30..labelDy = -10;
      final (ax, ay) = dfdLabelAnchor(auto);
      expect(dfdFlowLabelCenter(f, auto), (ax + 30, ay - 10));
      f.hints = [200];
      expect(routeHintsOf(dfdRoutes(d)['f']!), [200]);
    });
  });

  group('DfdController', () {
    test('ลากช่วงกลาง: undo ขั้นเดียว ; รีเซ็ตกลับอัตโนมัติ', () {
      final pc = ProjectController(base());
      final tab = pc.addDiagram(DocType.dfd)!.id;
      final d = dfdCtl(pc, tab);
      final a = d.addNode(DfdKind.process, 0, 0)!;
      final b = d.addNode(DfdKind.process, 400, 200)!;
      final f = d.addFlow(a.id, b.id, label: 'x')!;
      d.selectFlow(f.id);
      final seg = d.edgeHandleAt(const Offset(0, 0), tolPx: 1e9); // ใกล้สุดก็ได้ แค่ต้องมีจุดจับ
      expect(seg, isNotNull);
      final h = routeHandles(dfdRoutes(pc.dfdOf(tab))[f.id]!).firstWhere((h) => h.kind == RouteHandleKind.segment);
      d.beginEdgeHandle(h);
      d.edgeHandleTo(Offset(h.at.$1 + 40, h.at.$2));
      d.edgeHandleTo(Offset(h.at.$1 + 60, h.at.$2));
      d.endEdgeHandle();
      expect(pc.dfdOf(tab).flowById(f.id)!.hints, isNotNull);
      d.undo();
      expect(pc.dfdOf(tab).flowById(f.id)!.hints, isNull);
      d.redo();
      expect(pc.dfdOf(tab).flowById(f.id)!.hasManualRoute, isTrue);
      d.resetEdgeRoute(f.id);
      expect(pc.dfdOf(tab).flowById(f.id)!.hasManualRoute, isFalse);
    });

    test('ลากปลายเส้นไปวางบนกล่องอื่น = ต่อใหม่ ; วางนอกกล่อง = ไม่เปลี่ยน', () {
      final pc = ProjectController(base());
      final tab = pc.addDiagram(DocType.dfd)!.id;
      final d = dfdCtl(pc, tab);
      final a = d.addNode(DfdKind.process, 0, 0)!;
      final b = d.addNode(DfdKind.process, 400, 0)!;
      final c = d.addNode(DfdKind.process, 400, 300)!;
      final f = d.addFlow(a.id, b.id, label: 'x')!;
      d.selectFlow(f.id);
      final end = routeHandles(dfdRoutes(pc.dfdOf(tab))[f.id]!).firstWhere((h) => h.kind == RouteHandleKind.end);
      d.beginEdgeHandle(end);
      d.edgeHandleTo(const Offset(1000, 1000)); // นอกกล่อง
      expect(pc.dfdOf(tab).flowById(f.id)!.toId, b.id);
      d.edgeHandleTo(Offset(c.x + c.w / 2, c.y + 5)); // บนกล่อง c
      d.endEdgeHandle();
      final nf = pc.dfdOf(tab).flowById(f.id)!;
      expect(nf.toId, c.id);
      expect(nf.entry!.side, RouteSide.top);
      d.undo();
      expect(pc.dfdOf(tab).flowById(f.id)!.toId, b.id);
      expect(pc.dfdOf(tab).flowById(f.id)!.entry, isNull);
    });

    test('ลากป้าย: เก็บระยะ ; จัดวางอัตโนมัติรีเซ็ตเส้นและป้าย', () {
      final pc = ProjectController(base());
      final tab = pc.addDiagram(DocType.dfd)!.id;
      final d = dfdCtl(pc, tab);
      final a = d.addNode(DfdKind.entity, 0, 0)!;
      final b = d.addNode(DfdKind.process, 400, 0)!;
      final f = d.addFlow(a.id, b.id, label: 'x')!;
      d.beginEdgeLabelDrag();
      d.edgeLabelDragBy(f.id, 10, 5);
      d.edgeLabelDragBy(f.id, 5, 5);
      d.endEdgeLabelDrag();
      expect((pc.dfdOf(tab).flowById(f.id)!.labelDx, pc.dfdOf(tab).flowById(f.id)!.labelDy), (15, 10));
      d.undo();
      expect(pc.dfdOf(tab).flowById(f.id)!.labelDx, 0);
      d.redo();
      d.updateFlow(f.id, (x) => x.hints = [123]);
      d.autoLayout();
      final nf = pc.dfdOf(tab).flowById(f.id)!;
      expect((nf.hasManualRoute, nf.labelDx, nf.labelDy), (false, 0, 0));
    });
  });
}

void trimTests() {
  test('dfdTrimRoute ตัดปลายเส้นตามแนวเส้น ไม่ให้ทะลุหัวลูกศร', () {
    final r = dfdTrimRoute([(0.0, 0.0), (100.0, 0.0), (100.0, 50.0)], end: 9);
    expect(r.last, (100.0, 41.0));
    // ช่วงสุดท้ายสั้นกว่าที่ตัด: ตัดข้ามมุม
    final r2 = dfdTrimRoute([(0.0, 0.0), (100.0, 0.0), (100.0, 5.0)], end: 9);
    expect(r2.last.$2, 0);
    expect(r2.last.$1, closeTo(96, 0.01));
    // ตัดต้นด้วย
    final r3 = dfdTrimRoute([(0.0, 0.0), (100.0, 0.0)], start: 9, end: 9);
    expect(r3, [(9.0, 0.0), (91.0, 0.0)]);
  });
}
