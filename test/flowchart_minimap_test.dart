import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/flowchart_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/flowchart/fc_minimap.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 4c: minimap ของ Flowchart
void main() {
  test('MinimapFrame: แปลงไป-กลับได้จุดเดิม และย่อให้พอดีกล่องโดยรักษาสัดส่วน', () {
    final f = MinimapFrame(const Rect.fromLTWH(-100, 50, 1000, 400), kFcMinimapSize);
    const p = Offset(320, 210);
    final back = f.toWorld(f.toMini(p));
    expect(back.dx, closeTo(p.dx, 1e-6));
    expect(back.dy, closeTo(p.dy, 1e-6));
    final r = f.rectToMini(f.world);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(kFcMinimapSize.width + 1e-6));
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(kFcMinimapSize.height + 1e-6));
    expect(r.width / r.height, closeTo(1000 / 400, 1e-6));
  });

  late WorkspaceController w;

  Future<FlowchartController> boot(WidgetTester tester, {Size size = const Size(1600, 950), bool content = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    final doc = w.addDocument(DocType.flowchart, name: 'Flow')!;
    if (content) {
      doc.content = FlowchartDiagram(nodes: [
        FcNode(id: 'a', shape: FcShape.start, text: 'A', x: 0, y: 0),
        FcNode(id: 'b', shape: FcShape.process, text: 'B', x: 2400, y: 1600),
      ]);
    }
    await tester.pumpAndSettle();
    return tester.element(find.byType(HomePage)).read<FlowchartController>();
  }

  final mini = find.byKey(const ValueKey('fc-minimap'));

  testWidgets('แสดงเมื่อมีสัญลักษณ์ ; คลิกที่ใด = มุมมองเลื่อนให้จุดนั้นอยู่กลางแคนวาส โดยไม่แตะเนื้อหา/การเลือก', (tester) async {
    final f = await boot(tester);
    expect(mini, findsOneWidget);
    final canvas = tester.getSize(find.byKey(const ValueKey('fc-canvas')));
    final frame = fcMinimapFrame(f, canvas)!;
    final target = frame.toMini(const Offset(2480, 1632)); // กลางสัญลักษณ์ b
    final before = f.diagram.nodes.map((n) => (n.x, n.y)).toList();
    await tester.tapAt(tester.getTopLeft(mini) + target);
    await tester.pump();
    final center = f.toWorld(canvas.center(Offset.zero));
    expect(center.dx, closeTo(2480, 2));
    expect(center.dy, closeTo(1632, 2));
    expect(f.diagram.nodes.map((n) => (n.x, n.y)).toList(), before);
    expect(f.selectedNodeIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ลากบน minimap = เลื่อนมุมมองตาม', (tester) async {
    final f = await boot(tester);
    final start = f.offset;
    final g = await tester.startGesture(tester.getCenter(mini));
    await g.moveBy(const Offset(20, 10));
    await g.moveBy(const Offset(20, 10));
    await g.up();
    await tester.pump();
    expect(f.offset, isNot(start));
  });

  testWidgets('ไม่แสดงเมื่อแผนภาพว่าง หรือแคนวาสแคบ', (tester) async {
    await boot(tester, content: false);
    expect(mini, findsNothing);
    await boot(tester, size: const Size(1000, 700)); // หน้าต่างแคบสุดของแอปคือ 980px
    expect(mini, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
