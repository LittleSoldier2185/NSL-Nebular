@Tags(['perf'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/ui/dfd/dfd_painter.dart';
import 'package:nsl_nebular/ui/flowchart/fc_painter.dart';
import 'package:nsl_nebular/ui/screenflow/sf_painter.dart';
import 'package:nsl_nebular/ui/wireframe/wf_painter.dart';

import 'diagrams_bench_test.dart' show build;
import 'validate_bench_test.dart' show time;

void main() {
  testWidgets('เวลาบันทึกภาพทั้งแผนภาพ', (tester) async {
    final w = build();
    final d = w.documentById('dfd')!.dfd!, f = w.documentById('fc')!.flowchart!;
    final wf = w.documentById('wf')!.wireframe!, s = w.documentById('sf')!.screenflow!;
    double rec(void Function(ui.Canvas c) draw) => time(() {
          final r = ui.PictureRecorder();
          draw(ui.Canvas(r));
          r.endRecording();
        });
    // ignore: avoid_print
    print('PERF paint dfd=${rec((c) => paintDfd(c, d)).toStringAsFixed(1)}ms '
        'fc=${rec((c) => paintFlowchart(c, f)).toStringAsFixed(1)}ms '
        'wf=${rec((c) => paintWireframe(c, wf)).toStringAsFixed(1)}ms '
        'sf=${rec((c) => paintScreenFlow(c, s)).toStringAsFixed(1)}ms');
  });
}
