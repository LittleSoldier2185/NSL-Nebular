@Tags(['perf'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/layout/flowchart_geometry.dart';
import 'package:nsl_nebular/core/layout/ortho_route.dart';
import 'package:nsl_nebular/core/layout/screenflow_geometry.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';

import 'diagrams_bench_test.dart' show build;

void main() {
  test('เส้นทางตอนลาก: เต็ม vs ร่าง (เทียบในรอบเดียวกัน)', () {
    final w = build();
    final d = w.documentById('dfd')!.dfd!, f = w.documentById('fc')!.flowchart!, s = w.documentById('sf')!.screenflow!;
    double frames(void Function(int i) move, void Function() route, {required bool draft}) {
      clearRouteCache();
      route();
      if (draft) beginRouteDraft();
      final sw = Stopwatch()..start();
      for (var i = 1; i <= 10; i++) {
        move(i);
        route();
      }
      if (draft) endRouteDraft();
      return sw.elapsedMicroseconds / 10 / 1000;
    }

    String row(String label, void Function(int) move, void Function() route) =>
        '$label full=${frames(move, route, draft: false).toStringAsFixed(1)}ms draft=${frames(move, route, draft: true).toStringAsFixed(1)}ms';
    final dn = d.nodes[150], fn = f.nodes[150], sn = s.nodes[150];
    // ignore: avoid_print
    print('PERF drag-routes ${row('dfd', (i) => dn.x += 3, () => dfdRoutes(d))} | '
        '${row('fc', (i) => fn.x += 3, () => fcRoutes(f))} | ${row('sf', (i) => sn.x += 3, () => sfRoutes(s))}');
  });
}
