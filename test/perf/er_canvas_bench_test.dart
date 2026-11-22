// วัดเวลาฝั่ง CPU (build + layout + บันทึกคำสั่งวาด) ของกระดาน ER ที่มีตารางเยอะ
// ไม่เห็นงาน GPU (เช่น เบลอเงา) — ตัวเลขใช้เทียบก่อน/หลังแก้ ไม่ใช่ fps จริง
// รัน: flutter test test/perf --tags perf  (ไม่ได้ข้ามในชุดปกติ เพราะเร็วพอ)
@Tags(['perf'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/project_controller.dart';
import 'package:nsl_nebular/ui/canvas/canvas_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

Project bigEr(int n) {
  final tables = <TableModel>[];
  final rels = <RelationModel>[];
  for (var i = 0; i < n; i++) {
    tables.add(TableModel(
      id: 't$i',
      name: 'table_$i',
      x: (i % 8) * 300.0,
      y: (i ~/ 8) * 320.0,
      columns: [
        ColumnModel(id: 't${i}c0', name: 'id', isPrimaryKey: true, notNull: true, autoIncrement: true),
        for (var k = 1; k < 9; k++) ColumnModel(id: 't${i}c$k', name: 'col_$k', type: DataType.varchar, length: 100),
      ],
    ));
    if (i > 0) {
      rels.add(RelationModel(
          id: 'r$i', fromTableId: 't$i', fromColumnId: 't${i}c1', toTableId: 't${(i - 1) ~/ 2}', toColumnId: 't${(i - 1) ~/ 2}c0'));
    }
  }
  return Project(name: 'bench', tables: tables, relations: rels);
}

/// ค่าเฉลี่ย ms ต่อเฟรมของ [frames] เฟรมที่ [step] เปลี่ยนสถานะแล้ว pump
Future<double> measure(WidgetTester tester, int frames, void Function(int i) step) async {
  // อุ่นเครื่อง
  for (var i = 0; i < 3; i++) {
    step(i);
    await tester.pump();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < frames; i++) {
    step(i);
    await tester.pump();
  }
  return sw.elapsedMicroseconds / frames / 1000;
}

void main() {
  for (final n in [40, 150]) {
    testWidgets('ER $n ตาราง: แพน / ซูม / ลากตาราง / เลือกตาราง', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(initialProject: Workspace.single(bigEr(n))));
      await tester.pump(const Duration(milliseconds: 500));
      final ctx = tester.element(find.byType(HomePage));
      final c = ctx.read<ProjectController>();
      final cv = ctx.read<CanvasController>();
      cv.resetZoom();
      cv.zoomCenter(0.6);
      await tester.pumpAndSettle();

      final pan = await measure(tester, 30, (i) => cv.panBy(Offset(i.isEven ? 6 : -6, 3)));
      final zoom = await measure(tester, 30, (i) => cv.zoomCenter(i.isEven ? 1.05 : 1 / 1.05));
      final t = c.project.tables[n ~/ 2];
      final drag = await measure(tester, 30, (i) => c.moveTable(t.id, t.x + (i.isEven ? 4 : -4), t.y));
      final select = await measure(tester, 20, (i) => c.selectTable(c.project.tables[i % n].id));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('PERF ER n=$n  pan=${pan.toStringAsFixed(2)}ms  zoom=${zoom.toStringAsFixed(2)}ms  '
          'drag=${drag.toStringAsFixed(2)}ms  select=${select.toStringAsFixed(2)}ms');
    });
  }
}
