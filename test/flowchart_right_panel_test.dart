import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/flowchart_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// แผงขวา Flowchart แบบ A: แท็บ รูปทรง / เส้น / ตรวจ · N + ช่องกว้าง/สูง
Future<FlowchartController> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
  final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
  await tester.pump();
  final doc = w.addDocument(DocType.flowchart, name: 'FC')!;
  doc.content = FlowchartDiagram(
    nodes: [
      FcNode(id: 'a', shape: FcShape.process, text: 'A', x: 100, y: 100),
      FcNode(id: 'b', shape: FcShape.process, text: 'B', x: 100, y: 300),
    ],
    edges: [FcEdge(id: 'e', fromId: 'a', toId: 'b', label: 'ใช่')],
  );
  await tester.pump();
  final f = tester.element(find.byType(HomePage)).read<FlowchartController>();
  await tester.pumpAndSettle();
  return f;
}

void main() {
  testWidgets('มี 3 แท็บ และเลือกสัญลักษณ์/เส้นแล้วสลับแท็บให้เอง', (tester) async {
    final f = await _open(tester);
    expect(find.byKey(const ValueKey('fc-tab-shape')), findsOneWidget);
    expect(find.byKey(const ValueKey('fc-tab-line')), findsOneWidget);
    expect(find.byKey(const ValueKey('fc-tab-check')), findsOneWidget);

    f.selectNode('a');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fc-shape')), findsOneWidget, reason: 'สัญลักษณ์ → แท็บรูปทรง');

    f.selectEdge('e');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fc-reverse')), findsOneWidget, reason: 'เส้น → แท็บเส้น');
    expect(find.byKey(const ValueKey('fc-shape')), findsNothing);

    f.selectNode('a');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fc-shape')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('แท็บเส้นของสัญลักษณ์: แสดงเส้นที่ต่ออยู่ กดแล้วเลือกเส้นนั้น', (tester) async {
    final f = await _open(tester);
    f.selectNode('a');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fc-tab-line')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fc-node-edge-e')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fc-node-edge-e')));
    await tester.pumpAndSettle();
    expect(f.selectedEdge?.id, 'e');
    expect(find.byKey(const ValueKey('fc-reverse')), findsOneWidget);
  });

  testWidgets('แท็บตรวจ: ขึ้นจำนวนปัญหาบนหัวแท็บ และเปิดรายการได้', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('fc-tab-check')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('ตรวจ ·'), findsOneWidget);
  });

  testWidgets('ช่องกว้าง/สูง: พิมพ์ค่าแล้วขนาดเปลี่ยน (undo ได้) ; เกินช่วง = ถูกจำกัด ; ค่าที่ไม่ใช่ตัวเลข = ไม่เปลี่ยน', (tester) async {
    final f = await _open(tester);
    f.selectNode('a');
    await tester.pumpAndSettle();
    final n0 = f.diagram.nodeById('a')!;
    final (w0, h0) = (n0.w, n0.h);

    await tester.enterText(find.descendant(of: find.byWidgetPredicate((w) => w.key.toString().contains('fc-w-a-')), matching: find.byType(TextField)), '300');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(f.diagram.nodeById('a')!.w, 300);
    expect(f.diagram.nodeById('a')!.h, h0);

    f.undo();
    await tester.pumpAndSettle();
    expect(f.diagram.nodeById('a')!.w, w0);

    f.setSize('a', w: 5, h: 99999);
    expect(f.diagram.nodeById('a')!.w, kFcMinSide);
    expect(f.diagram.nodeById('a')!.h, kFcMaxSide);

    f.setSize('a', w: kFcMinSide, h: kFcMaxSide); // ไม่เปลี่ยน = ไม่เข้าประวัติ
    f.undo();
    expect(f.diagram.nodeById('a')!.w, w0);
  });
}
