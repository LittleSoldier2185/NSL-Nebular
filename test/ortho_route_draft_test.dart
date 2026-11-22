import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/layout/diagram_geometry.dart';
import 'package:nsl_nebular/core/layout/ortho_route.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

import 'perf/er_canvas_bench_test.dart' show bigEr;

Map<String, RouteBox> grid({double dx = 0}) => {
      for (var i = 0; i < 12; i++)
        'b$i': RouteBox('b$i', (i % 4) * 200.0 + (i == 5 ? dx : 0), (i ~/ 4) * 150.0, 120, 60),
    };
final links = [for (var i = 1; i < 12; i++) RouteLink('l$i', 'b${(i - 1) ~/ 2}', 'b$i')];

void main() {
  tearDown(() {
    while (routeDraftActive) {
      endRouteDraft();
    }
  });

  test('เรียกซ้ำได้ผลจากแคช และเท่ากับคำนวณใหม่', () {
    final a = orthogonalRoutes(grid(), links);
    final b = orthogonalRoutes(grid(), links);
    expect(identical(a, b), isTrue);
    clearRouteCache();
    expect(orthogonalRoutes(grid(), links), a);
  });

  test('ระหว่างลาก: เส้นที่ไม่แตะกล่องที่ขยับใช้ทางเดิม ; เส้นที่แตะถูกคำนวณใหม่', () {
    final before = orthogonalRoutes(grid(), links);
    beginRouteDraft();
    final during = orthogonalRoutes(grid(dx: 37), links);
    // b5 ขยับ : เส้นที่ต่อกับ b5 คือ l5 (b2->b5), l10 (b5->b10), l11 (b5->b11)
    for (final f in links) {
      final touches = f.from == 'b5' || f.to == 'b5';
      if (!touches) expect(during[f.id], before[f.id], reason: f.id);
    }
    expect(during['l5'], isNot(equals(before['l5'])));
    endRouteDraft();
  });

  test('หลังปล่อย: ได้ผลเต็มเท่ากับคำนวณโดยไม่ผ่านโหมดร่าง', () {
    beginRouteDraft();
    orthogonalRoutes(grid(), links);
    orthogonalRoutes(grid(dx: 20), links);
    orthogonalRoutes(grid(dx: 60), links);
    endRouteDraft();
    final after = orthogonalRoutes(grid(dx: 60), links);
    // คำนวณใหม่จริง (ล้างแคชก่อน) ต้องเท่ากับผลหลังปล่อย
    clearRouteCache();
    final fresh = orthogonalRoutes(grid(dx: 60), links);
    expect(identical(after, fresh), isFalse);
    expect(after, fresh);
    expect(routeDraftActive, isFalse);
  });

  test('ER: ระหว่างลากใช้ทางเดิมของเส้นที่ไม่ขยับ ; ปล่อยแล้วเท่ากับคำนวณเต็ม', () {
    final p = bigEr(40);
    final before = relationRoutes(p);
    final t = p.tables[10];
    beginRouteDraft();
    t.x += 45;
    final during = relationRoutes(p);
    for (final r in p.relations) {
      if (r.fromTableId != t.id && r.toTableId != t.id) expect(during[r.id], before[r.id], reason: r.id);
    }
    endRouteDraft();
    final after = relationRoutes(p);
    clearRelationRouteCache();
    expect(relationRoutes(p), after);
  });

  test('controller: ลากแล้วปล่อย = ออกจากโหมดร่างเสมอ (ER และ DFD)', () {
    final ws = Workspace(documents: [
      ProjectDocument.er(id: 'er', name: 'ER', content: bigEr(3)),
      ProjectDocument.dfd(id: 'd', name: 'DFD', content: DfdDiagram()),
    ]);
    final w = WorkspaceController(ws);
    final er = w.erController('er')!;
    er.beginGesture();
    expect(routeDraftActive, isTrue);
    er.endGesture();
    expect(routeDraftActive, isFalse);
    final d = w.dfdController('d')!;
    d.beginGesture();
    d.beginGesture(); // ซ้ำไม่นับเพิ่ม
    expect(routeDraftActive, isTrue);
    d.endGesture();
    expect(routeDraftActive, isFalse);
  });
}
