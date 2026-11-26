@Tags(['codegen-analyze'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/cli/nebular_api.dart';
import 'package:nsl_nebular/core/codegen/wireframe_code.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';

/// Phase 35: โค้ดหน้าจอ Flutter ที่สร้างต้องผ่าน `dart analyze` แบบไม่มีข้อความใดเลย
/// (Wireframe ทุกหน้าของตัวอย่างโรงแรม + ชิ้นส่วนทุกชนิด + ชิ้นหมุน/ซ่อน/ซ้อนในภาชนะ)
void main() {
  test('dart analyze ผ่าน', () async {
    final hotel = await loadProject('samples/hotel_booking.nsln');
    final screens = <String, WireframeDiagram>{
      for (final (i, d) in hotel.documentsOf(DocType.wireframe).indexed) 'hotel_$i': d.wireframe!,
      'every_kind': WireframeDiagram(components: [
        for (final (i, k) in WfKind.values.indexed)
          WfComponent(id: k.name, kind: k, x: (i % 4) * 340, y: (i ~/ 4) * 320, w: wfDefaultSize(k).$1, h: wfDefaultSize(k).$2),
      ]),
      'mixed': WireframeDiagram(components: [
        WfComponent(id: 'card', kind: WfKind.card, x: 20, y: 20, w: 400, h: 300),
        WfComponent(id: 'in', kind: WfKind.input, x: 40, y: 60, w: 200, h: 48),
        WfComponent(id: 'turn', kind: WfKind.label, x: 500, y: 100, w: 120, h: 30, rotation: 30),
        WfComponent(id: 'hid', kind: WfKind.button, x: 600, y: 600, w: 100, h: 40, hidden: true),
      ]),
      'empty': WireframeDiagram(),
    };
    expect(screens.length, greaterThan(3));
    // ต้องอยู่ในแพ็กเกจเพื่อให้ analyzer หา package:flutter เจอ
    final dir = Directory('test/_codegen_analyze_tmp')..createSync(recursive: true);
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final e in screens.entries) {
      File('${dir.path}/${e.key}.dart').writeAsStringSync(flutterScreen(e.key, e.value));
    }
    final r = await Process.run('dart', ['analyze', '--fatal-infos', dir.path], runInShell: true);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
