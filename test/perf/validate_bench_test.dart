@Tags(['perf'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/layout/flowchart_geometry.dart';
import 'package:nsl_nebular/core/layout/screenflow_geometry.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/validate/dfd_validator.dart';
import 'package:nsl_nebular/core/validate/flowchart_validator.dart';
import 'package:nsl_nebular/core/validate/screenflow_validator.dart';
import 'package:nsl_nebular/core/validate/wireframe_validator.dart';

import 'diagrams_bench_test.dart' show build;

double time(void Function() f) {
  f();
  final sw = Stopwatch()..start();
  for (var i = 0; i < 5; i++) {
    f();
  }
  return sw.elapsedMicroseconds / 5 / 1000;
}

void main() {
  test('เวลาตัวตรวจ/เส้นทาง', () {
    final w = build();
    final d = w.documentById('dfd')!.dfd!, f = w.documentById('fc')!.flowchart!;
    final wf = w.documentById('wf')!.wireframe!, s = w.documentById('sf')!.screenflow!;
    // ignore: avoid_print
    print('PERF validate dfd=${time(() => validateDfd(d, workspace: w, diagramId: 'dfd')).toStringAsFixed(1)}ms '
        'fc=${time(() => validateFlowchart(f, workspace: w)).toStringAsFixed(1)}ms '
        'wf=${time(() => validateWireframe(wf, workspace: w)).toStringAsFixed(1)}ms '
        'sf=${time(() => validateScreenFlow(s, workspace: w)).toStringAsFixed(1)}ms '
        'dfdRoutes=${time(() => dfdRoutes(d)).toStringAsFixed(1)}ms fcRoutes=${time(() => fcRoutes(f)).toStringAsFixed(1)}ms sfRoutes=${time(() => sfRoutes(s)).toStringAsFixed(1)}ms');
  });
}
