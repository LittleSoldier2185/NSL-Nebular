import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/layout/diagram_geometry.dart' show relationBendHandle, relationRoutes;
import 'package:nsl_nebular/core/layout/flowchart_geometry.dart';
import 'package:nsl_nebular/core/layout/ortho_route.dart';
import 'package:nsl_nebular/core/layout/route_edit.dart';
import 'package:nsl_nebular/core/layout/screenflow_geometry.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/project_controller.dart';

import 'migration_fixtures.dart';

bool axisAligned(List<RoutePoint> r) {
  for (var i = 1; i < r.length; i++) {
    if ((r[i].$1 - r[i - 1].$1).abs() > 0.01 && (r[i].$2 - r[i - 1].$2).abs() > 0.01) return false;
  }
  return true;
}

void main() {
  group('Flowchart', () {
    FlowchartDiagram two() => FlowchartDiagram(nodes: [
          FcNode(id: 'a', shape: FcShape.process, text: 'A', x: 0, y: 0),
          FcNode(id: 'b', shape: FcShape.process, text: 'B', x: 300, y: 200),
        ], edges: [
          FcEdge(id: 'e', fromId: 'a', toId: 'b', label: 'x'),
        ]);

    test('เซฟ/โหลดค่าที่แก้เอง ; ไม่มีค่า = ไม่มีคีย์ ; ค่าผิดรูปข้าม', () {
      final e = FcEdge(id: 'e', fromId: 'a', toId: 'b')
        ..exit = const RoutePort(RouteSide.bottom, 0.25)
        ..entry = const RoutePort(RouteSide.left)
        ..hints = [40, 80]
        ..labelDx = 3
        ..labelDy = 4;
      final back = FcEdge.tryFromJson(e.toJson())!;
      expect(back.exit, const RoutePort(RouteSide.bottom, 0.25));
      expect(back.entry, const RoutePort(RouteSide.left));
      expect(back.hints, [40, 80]);
      expect((back.labelDx, back.labelDy), (3, 4));
      final plain = FcEdge(id: 'g', fromId: 'a', toId: 'b').toJson();
      for (final k in ['exit', 'entry', 'bends', 'lbl']) {
        expect(plain.containsKey(k), isFalse);
      }
      final bad = FcEdge.tryFromJson({'id': 'x', 'from': 'a', 'to': 'b', 'exit': 5, 'bends': ['a']})!;
      expect(bad.hasManualRoute, isFalse);
    });

    test('fcRoutes ใช้จุดต่อที่กำหนดเอง และเส้นยังหักมุมฉาก', () {
      final d = two();
      d.edges.single
        ..exit = const RoutePort(RouteSide.right, 0.5)
        ..entry = const RoutePort(RouteSide.top, 0.5);
      final r = fcRoutes(d)['e']!;
      expect(axisAligned(r), isTrue);
      final (s0, s1) = routeEndSides(r);
      expect((s0, s1), (RouteSide.right, RouteSide.top));
    });

    test('controller: ลากช่วงกลาง undo ขั้นเดียว ; ลากป้าย ; รีเซ็ต ; จัดวางอัตโนมัติรีเซ็ต', () {
      final pc = ProjectController(base());
      final tab = pc.addDiagram(DocType.flowchart)!.id;
      final f = pc.workspaceController.flowchartController(tab)!;
      final a = f.addNode(FcShape.process, 100, 100)!;
      final b = f.addNode(FcShape.process, 500, 300)!;
      final e = f.addEdge(a.id, b.id, label: 'x')!;
      f.selectEdge(e.id);
      final h = routeHandles(fcRoutes(f.diagram)[e.id]!).firstWhere((h) => h.kind == RouteHandleKind.segment);
      f.beginEdgeHandle(h);
      f.edgeHandleTo(Offset(h.at.$1 + 30, h.at.$2 + 30));
      f.edgeHandleTo(Offset(h.at.$1 + 50, h.at.$2 + 50));
      f.endEdgeHandle();
      expect(f.diagram.edgeById(e.id)!.hasManualRoute, isTrue);
      f.undo();
      expect(f.diagram.edgeById(e.id)!.hasManualRoute, isFalse);
      f.redo();
      f.beginEdgeLabelDrag();
      f.edgeLabelDragBy(e.id, 10, -5);
      f.endEdgeLabelDrag();
      expect((f.diagram.edgeById(e.id)!.labelDx, f.diagram.edgeById(e.id)!.labelDy), (10, -5));
      f.resetEdgeRoute(e.id);
      expect(f.diagram.edgeById(e.id)!.hasManualRoute, isFalse);
      f.resetEdgeLabelPosition(e.id);
      expect(f.diagram.edgeById(e.id)!.labelDx, 0);
      f.updateEdge(e.id, (x) => x.hints = [123]);
      f.autoLayout();
      expect(f.diagram.edgeById(e.id)!.hasManualRoute, isFalse);
    });

    test('ลากปลายเส้นไปวางบนสัญลักษณ์อื่น = ต่อใหม่', () {
      final pc = ProjectController(base());
      final tab = pc.addDiagram(DocType.flowchart)!.id;
      final f = pc.workspaceController.flowchartController(tab)!;
      final a = f.addNode(FcShape.process, 100, 100)!;
      final b = f.addNode(FcShape.process, 500, 100)!;
      final c = f.addNode(FcShape.process, 500, 400)!;
      final e = f.addEdge(a.id, b.id)!;
      f.selectEdge(e.id);
      final end = routeHandles(fcRoutes(f.diagram)[e.id]!).firstWhere((h) => h.kind == RouteHandleKind.end);
      f.beginEdgeHandle(end);
      f.edgeHandleTo(Offset(c.x + c.w / 2, c.y + 4));
      expect(f.dropNodeId, c.id);
      f.endEdgeHandle();
      expect(f.dropNodeId, isNull);
      expect(f.diagram.edgeById(e.id)!.toId, c.id);
      f.undo();
      expect(f.diagram.edgeById(e.id)!.toId, b.id);
    });
  });

  group('Screen Flow', () {
    test('เซฟ/โหลดค่าที่แก้เอง', () {
      final e = SfEdge(id: 'e', fromId: 'a', toId: 'b')
        ..exit = const RoutePort(RouteSide.right, 0.3)
        ..hints = [70]
        ..labelDx = -4;
      final back = SfEdge.tryFromJson(e.toJson())!;
      expect(back.exit, const RoutePort(RouteSide.right, 0.3));
      expect(back.hints, [70]);
      expect(back.labelDx, -4);
    });

    test('controller: ลากช่วงกลางและปลายเส้น + undo', () {
      final pc = ProjectController(base());
      final tab = pc.addDiagram(DocType.screenflow)!.id;
      final s = pc.workspaceController.screenflowController(tab)!;
      final a = s.addNode(SfKind.screen, 100, 100)!;
      final b = s.addNode(SfKind.screen, 600, 300)!;
      final c = s.addNode(SfKind.screen, 600, 600)!;
      final e = s.addEdge(a.id, b.id, label: 'go')!;
      s.selectEdge(e.id);
      final seg = routeHandles(sfRoutes(s.diagram)[e.id]!).firstWhere((h) => h.kind == RouteHandleKind.segment);
      s.beginEdgeHandle(seg);
      s.edgeHandleTo(Offset(seg.at.$1 + 40, seg.at.$2));
      s.endEdgeHandle();
      expect(s.diagram.edgeById(e.id)!.hasManualRoute, isTrue);
      s.undo();
      expect(s.diagram.edgeById(e.id)!.hasManualRoute, isFalse);

      final end = routeHandles(sfRoutes(s.diagram)[e.id]!).firstWhere((h) => h.kind == RouteHandleKind.end);
      s.beginEdgeHandle(end);
      s.edgeHandleTo(Offset(c.x + c.w / 2, c.y + c.h / 2));
      s.endEdgeHandle();
      expect(s.diagram.edgeById(e.id)!.toId, c.id);
      s.undo();
      expect(s.diagram.edgeById(e.id)!.toId, b.id);
    });
  });

  group('ER', () {
    test('เซฟ/โหลด bendX ; ไม่มีค่า = ไม่มีคีย์', () {
      final r = RelationModel(id: 'r', fromTableId: 'a', fromColumnId: 'a1', toTableId: 'b', toColumnId: 'b1')..bendX = 123.5;
      expect(RelationModel.fromJson(r.toJson()).bendX, 123.5);
      r.bendX = null;
      expect(r.toJson().containsKey('bendX'), isFalse);
    });

    test('relationRoutes ใช้ x ที่ลากเอง และจุดจับอยู่กลางช่วงแนวตั้ง', () {
      final p = base();
      final auto = relationRoutes(p)['r1']!;
      expect(axisAligned(auto), isTrue);
      p.relations.single.bendX = -50;
      final r = relationRoutes(p)['r1']!;
      expect(axisAligned(r), isTrue);
      expect(r.any((pt) => (pt.$1 + 50).abs() < 0.01), isTrue);
      final h = relationBendHandle(p, 'r1');
      expect(h, isNotNull);
      expect(h!.$1, closeTo(-50, 0.01));
    });

    test('ProjectController: ลากแล้ว undo ขั้นเดียว ; รีเซ็ต', () {
      final c = ProjectController(base());
      c.beginGesture();
      c.setRelationBendLive('r1', -20);
      c.setRelationBendLive('r1', -40);
      c.endGesture();
      expect(c.project.relations.single.bendX, -40);
      c.undo();
      expect(c.project.relations.single.bendX, isNull);
      c.redo();
      c.resetRelationBend('r1');
      expect(c.project.relations.single.bendX, isNull);
    });
  });
}
