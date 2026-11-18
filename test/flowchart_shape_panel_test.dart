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

/// บั๊กเดิม: ช่อง "รูปทรง" ในแผงขวาของ Flowchart ใช้รายการของคลัง (10 รูปทรง) จึงพัง
/// ("There should be exactly one item with [DropdownButton]'s value: FcShape.cylinder")
/// ตอนเลือกสัญลักษณ์ทรงกระบอก / หกเหลี่ยม / เอกสาร / ข้อความ — ต้องรองรับทุกรูปทรงของ [FcShape]
void main() {
  for (final s in FcShape.values) {
    testWidgets('เลือกสัญลักษณ์ ${s.name}: แผงขวาแสดงช่องรูปทรงได้ ไม่มี exception', (tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
      final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      await tester.pump();

      final doc = w.addDocument(DocType.flowchart, name: 'Shapes')!;
      doc.content = FlowchartDiagram(nodes: [FcNode(id: 'n', shape: s, text: 'x', x: 100, y: 100)]);
      await tester.pump();
      final f = tester.element(find.byType(HomePage)).read<FlowchartController>();
      f.selectNode('n');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('fc-shape')), findsOneWidget);
    });
  }

  testWidgets('เปลี่ยนรูปทรงจากช่อง: เป็นทรงกระบอกได้ แล้วเปลี่ยนกลับได้', (tester) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
    final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    await tester.pump();
    final doc = w.addDocument(DocType.flowchart, name: 'Shapes')!;
    doc.content = FlowchartDiagram(nodes: [FcNode(id: 'n', shape: FcShape.process, text: 'x', x: 100, y: 100)]);
    await tester.pump();
    final f = tester.element(find.byType(HomePage)).read<FlowchartController>();
    f.selectNode('n');
    await tester.pumpAndSettle();

    f.setShape(['n'], FcShape.cylinder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(f.diagram.nodeById('n')!.shape, FcShape.cylinder);

    f.setShape(['n'], FcShape.process);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
