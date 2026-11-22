@Tags(['perf'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/validate/wireframe_validator.dart';

import 'diagrams_bench_test.dart' show build;
import 'validate_bench_test.dart' show time;

void main() {
  test('ต้นทุนต่อเฟรมของ Wireframe 1,000 ชิ้น', () {
    final w = build();
    final d = w.documentById('wf')!.wireframe!;
    // ignore: avoid_print
    print('PERF wf json=${time(() => jsonEncode(d.toContentJson())).toStringAsFixed(1)}ms '
        'hidden=${time(() => wfHiddenIds(d)).toStringAsFixed(1)}ms '
        'validate=${time(() => validateWireframe(d, workspace: w)).toStringAsFixed(1)}ms');
  });
}
