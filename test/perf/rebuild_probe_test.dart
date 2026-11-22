// นับวิดเจ็ตที่ถูกสร้างใหม่ระหว่างแพน (หาว่าอะไรฟัง controller แล้ว rebuild ทุกเฟรม)
@Tags(['perf'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as w show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'diagrams_bench_test.dart' show build;

void main() {
  testWidgets('นับ rebuild ตอนลาก', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(initialProject: build()));
    await tester.pump(const Duration(milliseconds: 500));
    final ws = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    final dfd = ws.dfdController('dfd')!, wf = ws.wireframeController('wf')!, sf = ws.screenflowController('sf')!;
    final fc = ws.flowchartController('fc')!;
    for (final (id, ctl, sel) in <(String, dynamic, void Function())>[
      ('dfd', dfd, () => dfd.selectNode('d150')),
      ('fc', fc, () => fc.selectNode('c150')),
      ('wf', wf, () => wf.selectBox('w500')),
      ('sf', sf, () => sf.selectBox('s150')),
    ]) {
      sel();
      ctl.beginMove();
      void act(int i) => ctl.moveBy(i * 4.0, 0.0);
      ws.openDocument(id);
      await tester.pumpAndSettle();
      final counts = <String, int>{};
      final times = <String, int>{};
      w.debugOnRebuildDirtyWidget = (e, _) => counts[e.widget.runtimeType.toString()] = (counts[e.widget.runtimeType.toString()] ?? 0) + 1;
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        act(i);
        await tester.pump();
      }
      times[id] = sw.elapsedMilliseconds ~/ 5;
      w.debugOnRebuildDirtyWidget = null;
      ctl.endMove();
      final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('PROBE $id ${times[id]}ms/frame : ${top.where((e) => RegExp(r'^_?(Dfd|Fc|Flowchart|Wf|Wireframe|Sf|ScreenFlow|Status|Issue|Note|Panel|Props|Fold|Num|Color|Section|Toolbar|Body|Kind|Block|Shape|Layer|Palette|Field|Dropdown|Zoom|Minimap|Rule|Level|Right|Left)').hasMatch(e.key)).take(40).map((e) => '${e.key}=${e.value ~/ 5}').join(' ')}');
    }
  });
}
