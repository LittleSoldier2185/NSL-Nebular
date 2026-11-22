import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Wireframe: ช่อง X ในแผงขวาอัปเดตสดระหว่างลาก (แผงส่วนอื่นไม่สร้างใหม่ระหว่างลาก)', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ws = Workspace(name: 't', documents: [
      ProjectDocument.er(id: 'er', name: 'ER', content: Project(name: 't')),
      ProjectDocument.wireframe(
          id: 'wf', name: 'WF', content: WireframeDiagram(components: [WfComponent(id: 'b', kind: WfKind.button, text: 'OK', x: 100, y: 50)])),
    ]);
    await tester.pumpWidget(NslDevApp(initialProject: ws));
    await tester.pump(const Duration(milliseconds: 300));
    final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    w.openDocument('wf');
    await tester.pumpAndSettle();
    final c = w.wireframeController('wf')!;
    c.selectBox('b');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-x-100')), findsOneWidget);

    c.beginMove();
    c.moveBy(40, 0);
    await tester.pump();
    expect(c.gestureActive, isTrue);
    expect(find.byKey(const ValueKey('wf-x-140')), findsOneWidget);
    c.moveBy(80, 0); // สะสมจากจุดเริ่มลาก : 40 + 80
    await tester.pump();
    expect(find.byKey(const ValueKey('wf-x-220')), findsOneWidget);
    c.endMove();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-x-220')), findsOneWidget);
  });
}
