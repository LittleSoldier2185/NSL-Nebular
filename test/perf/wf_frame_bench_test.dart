@Tags(['perf'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/wireframe/wf_painter.dart';
import 'package:provider/provider.dart';

import 'diagrams_bench_test.dart' show build;
import 'validate_bench_test.dart' show time;

void main() {
  testWidgets('แยกต้นทุนเฟรมลาก Wireframe', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(initialProject: build()));
    await tester.pump(const Duration(milliseconds: 500));
    final ws = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    ws.openDocument('wf');
    await tester.pumpAndSettle();
    final c = ws.wireframeController('wf')!;
    c.selectBox('w500');
    final sel = c.selectedIds;
    var x = 0.0;
    final paint = time(() {
      c.diagram.components[500].x = (x += 3);
      final r = ui.PictureRecorder();
      WireframeScreenPainter(diagram: c.diagram, offset: c.offset, scale: c.scale, frameLabel: 'x', selected: sel, hidden: c.hiddenIds)
          .paint(Canvas(r), const Size(1200, 900));
      r.endRecording();
    });
    // ignore: avoid_print
    print('PERF wf-frame kind=${c.diagram.components[500].kind.name} moveSet=${time(() => c.moveSet(sel)).toStringAsFixed(2)}ms '
        'hiddenIds=${time(() => c.hiddenIds).toStringAsFixed(2)}ms painter(moved)=${paint.toStringAsFixed(2)}ms');
  });
}
