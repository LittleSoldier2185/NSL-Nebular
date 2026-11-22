// วัดเวลาฝั่ง CPU ต่อเฟรมของกระดาน DFD / Flowchart / Wireframe / Screen Flow ที่มีของเยอะ (ดูหมายเหตุใน er_canvas_bench_test.dart)
@Tags(['perf'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'er_canvas_bench_test.dart' show measure;

const n = 300;
double gx(int i) => (i % 15) * 220.0;
double gy(int i) => (i ~/ 15) * 160.0;

Workspace build() {
  final dfd = DfdDiagram(
    nodes: [
      for (var i = 0; i < n; i++)
        DfdNode(id: 'd$i', kind: DfdKind.values[i % 3], name: 'node $i', number: '$i', x: gx(i), y: gy(i)),
    ],
    flows: [for (var i = 1; i < n; i++) DfdFlow(id: 'df$i', fromId: 'd${(i - 1) ~/ 2}', toId: 'd$i', label: 'data $i')],
  );
  final fc = FlowchartDiagram(
    nodes: [for (var i = 0; i < n; i++) FcNode(id: 'c$i', shape: FcShape.values[i % FcShape.values.length], text: 'step $i', x: gx(i), y: gy(i))],
    edges: [for (var i = 1; i < n; i++) FcEdge(id: 'ce$i', fromId: 'c${(i - 1) ~/ 2}', toId: 'c$i', label: 'e$i')],
  );
  final wf = WireframeDiagram(
    width: 3400,
    height: 3400,
    components: [
      for (var i = 0; i < 1000; i++)
        WfComponent(id: 'w$i', kind: WfKind.values[i % WfKind.values.length], text: 'item $i', x: (i % 25) * 130.0, y: (i ~/ 25) * 80.0),
    ],
  );
  final sf = ScreenFlowDiagram(
    nodes: [for (var i = 0; i < n; i++) SfNode(id: 's$i', kind: SfKind.screen, title: 'screen $i', x: gx(i), y: gy(i))],
    edges: [for (var i = 1; i < n; i++) SfEdge(id: 'se$i', fromId: 's${(i - 1) ~/ 2}', toId: 's$i', label: 't$i')],
  );
  return Workspace(name: 'bench', documents: [
    ProjectDocument.er(id: 'er', name: 'ER', content: Project(name: 'bench')),
    ProjectDocument.dfd(id: 'dfd', name: 'DFD', content: dfd),
    ProjectDocument.flowchart(id: 'fc', name: 'FC', content: fc),
    ProjectDocument.wireframe(id: 'wf', name: 'WF', content: wf),
    ProjectDocument.screenflow(id: 'sf', name: 'SF', content: sf),
  ]);
}

void main() {
  testWidgets('DFD / Flowchart / Wireframe / Screen Flow : แพน / ซูม / ลาก / เลือก', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(initialProject: build()));
    await tester.pump(const Duration(milliseconds: 500));
    final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();

    Future<void> bench(String label, String id, dynamic ctl, void Function(int i) select, int count) async {
      w.openDocument(id);
      await tester.pumpAndSettle();
      final pan = await measure(tester, 30, (i) => ctl.panBy(Offset(i.isEven ? 6 : -6, 3)));
      final zoom = await measure(tester, 30, (i) => ctl.zoomAt(const Offset(500, 400), i.isEven ? 1.05 : 1 / 1.05));
      select(count ~/ 2);
      await tester.pump();
      ctl.beginMove();
      final drag = await measure(tester, 30, (i) => ctl.moveBy(i * 4.0, 0.0));
      ctl.endMove();
      final sel = await measure(tester, 20, (i) => select(i * 7 % count));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('PERF $label  pan=${pan.toStringAsFixed(2)}ms  zoom=${zoom.toStringAsFixed(2)}ms  '
          'drag=${drag.toStringAsFixed(2)}ms  select=${sel.toStringAsFixed(2)}ms');
    }

    final d = w.dfdController('dfd')!;
    await bench('DFD n=$n', 'dfd', d, (i) => d.selectNode('d$i'), n);
    final f = w.flowchartController('fc')!;
    await bench('FC n=$n', 'fc', f, (i) => f.selectNode('c$i'), n);
    final wf = w.wireframeController('wf')!;
    await bench('WF n=1000', 'wf', wf, (i) => wf.selectBox('w$i'), 1000);
    final s = w.screenflowController('sf')!;
    await bench('SF n=$n', 'sf', s, (i) => s.selectBox('s$i'), n);
  });
}
