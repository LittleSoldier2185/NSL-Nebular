@Tags(['perf'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/layout/diagram_geometry.dart';

import 'er_canvas_bench_test.dart' show bigEr;

void main() {
  test('เวลา relationRoutes', () {
    for (final n in [40, 150]) {
      final p = bigEr(n);
      relationRoutes(p);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        relationRoutes(p);
      }
      // ignore: avoid_print
      print('PERF routes n=$n ${(sw.elapsedMicroseconds / 10 / 1000).toStringAsFixed(2)}ms');
    }
  });
}
