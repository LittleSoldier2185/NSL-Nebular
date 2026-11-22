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
  testWidgets('นับ rebuild ตอนเลือก', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(initialProject: build()));
    await tester.pump(const Duration(milliseconds: 500));
    final ws = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    final dfd = ws.dfdController('dfd')!, wf = ws.wireframeController('wf')!, sf = ws.screenflowController('sf')!;
    final fc = ws.flowchartController('fc')!;
    for (final (id, act) in <(String, void Function(int))>[
      ('dfd', (i) => dfd.selectNode('d${i * 7}')),
      ('fc', (i) => fc.selectNode('c${i * 7}')),
      ('wf', (i) => wf.selectBox('w${i * 7}')),
      ('sf', (i) => sf.selectBox('s${i * 7}')),
    ]) {
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
      final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      // ignore: avoid_print
      print('PROBE $id ${times[id]}ms/frame : ${top.where((e) => !e.key.startsWith('_Inherited')).take(30).map((e) => '${e.key}=${e.value ~/ 5}').join(' ')}');
    }
  });
}
