import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/doc_ref.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/dfd_controller.dart';
import 'package:nsl_nebular/state/project_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'support/project_helpers.dart';

/// Phase 15: ตัวแก้ไข DFD ตามดีไซน์ (Artifact "NSL Nebular — ตัวแก้ไข DFD")
void main() {
  late ProjectController c;
  late DfdController d;
  late WorkspaceController w;
  late String dfdId;

  DfdDiagram sample() => DfdDiagram(
        nodes: [
          DfdNode(id: 'e', kind: DfdKind.entity, name: 'Customer', x: 0, y: 0),
          DfdNode(id: 'p', kind: DfdKind.process, name: 'Order', number: '1.0', x: 400, y: 0),
          DfdNode(id: 's', kind: DfdKind.store, name: 'Orders', number: 'D1', x: 800, y: 0),
        ],
        flows: [
          DfdFlow(id: 'f1', fromId: 'e', toId: 'p', label: 'Order'),
          DfdFlow(id: 'f2', fromId: 'p', toId: 's', label: 'Save'),
          DfdFlow(id: 'f3', fromId: 'p', toId: 'e', label: 'Receipt'),
        ],
      );

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, Size size = const Size(1600, 950)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => currentLang = Lang.th);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang)));
    final ctx = tester.element(find.byType(HomePage));
    c = ctx.read<ProjectController>();
    w = ctx.read<WorkspaceController>();
    final tab = c.addDiagram(DocType.dfd, name: 'L0')!;
    dfdId = tab.id;
    setDfd(c, tab.id, sample());
    await tester.pump();
    d = ctx.read<DfdController>();
    d.setTool(DfdTool.select);
    d.panBy(Offset.zero);
    await tester.pumpAndSettle();
  }

  testWidgets('แถบเครื่องมือเต็มความกว้าง: เลือก/เส้นข้อมูล ; ปุ่มวางวัตถุอยู่แผงซ้าย ; ขอบเขตระบบวางกลางจอ', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('dfd-toolbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('dfd-rules')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dfd-tool-flow')));
    await tester.pump();
    expect(d.tool, DfdTool.flow);
    await tester.tap(find.byKey(const ValueKey('dfd-tool-process')));
    await tester.pump();
    expect(d.tool, DfdTool.process);
    await tester.tap(find.byKey(const ValueKey('dfd-tool-select')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('dfd-tool-boundary')));
    await tester.pumpAndSettle();
    expect(d.diagram.boundaries.length, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // ปิดกล่องตั้งชื่อ
    await tester.pumpAndSettle();
  });

  testWidgets('แผงซ้าย: หมวดตามชนิด ; ที่เก็บข้อมูลบอกตาราง ER ; เส้นข้อมูลพับไว้ก่อน กดแล้วกาง', (tester) async {
    await boot(tester);
    final t = c.addTable(x: 40, y: 40, name: 'orders');
    d.setStoreTable('s', DocRef(docId: c.erDocumentId, elementId: t.id, kind: DocRefKind.storeTable));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dfd-item-p')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('dfd-item-s')), matching: find.text('orders')), findsOneWidget);
    expect(find.byKey(const ValueKey('dfd-flow-f1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dfd-group-flows')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dfd-flow-f1')), findsOneWidget);
  });

  testWidgets('แผงขวา กระบวนการ: หัวบอกเลข + จำนวนเข้า/ออก ; การ์ดระดับถัดไป ; ผลตรวจรายวัตถุ', (tester) async {
    await boot(tester);
    d.selectNode('p');
    await tester.pumpAndSettle();
    expect(find.text('กระบวนการ 1.0'), findsOneWidget);
    expect(find.text('ข้อมูลเข้า 1 · ออก 2'), findsOneWidget);
    expect(find.text('ระดับถัดไป'), findsOneWidget);
    expect(find.byKey(const ValueKey('dfd-child-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('dfd-io-f1-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('dfd-node-ok')), findsOneWidget);
  });

  testWidgets('แผงขวา ที่เก็บข้อมูล: การ์ดตาราง ER พร้อมคอลัมน์ + ไปที่ตาราง', (tester) async {
    await boot(tester);
    final t = c.addTable(x: 40, y: 40, name: 'orders');
    d.setStoreTable('s', DocRef(docId: c.erDocumentId, elementId: t.id, kind: DocRefKind.storeTable));
    d.selectNode('s');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dfd-store-card')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('dfd-store-card')), matching: find.text('PK')), findsOneWidget);
    expect(find.byKey(const ValueKey('dfd-store-goto')), findsOneWidget);
  });

  testWidgets('แผงขวา เส้นข้อมูล: จาก/ไป ; จัดเส้นอัตโนมัติใช้ไม่ได้เมื่อยังไม่ได้ดัด', (tester) async {
    await boot(tester);
    d.selectFlow('f2');
    await tester.pumpAndSettle();
    expect(find.text('จาก'), findsOneWidget);
    expect(find.text('ไป'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('dfd-reset-route'))).onPressed, isNull);
    expect(find.byKey(const ValueKey('dfd-flow-balance-note')), findsNothing); // ไม่มีแผนภาพแม่
  });

  testWidgets('แผนภาพย่อย: แถบระดับ + ป้ายสมดุล ; กดชื่อแผนภาพแม่ = กลับไป', (tester) async {
    await boot(tester);
    d.createChildFor('p');
    await tester.pumpAndSettle();
    expect(w.activeId, isNot(dfdId));
    expect(find.byKey(const ValueKey('dfd-level-bar')), findsOneWidget);
    expect(find.text('สมดุลกับแผนภาพแม่'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dfd-parent-p')));
    await tester.pumpAndSettle();
    expect(w.activeId, dfdId);
    expect(find.byKey(const ValueKey('dfd-level-bar')), findsNothing);
  });

  testWidgets('minimap มุมขวาล่าง', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('dfd-minimap')), findsOneWidget);
  });

  testWidgets('ภาษาอังกฤษ หน้าต่างแคบ: ไม่ล้น ไม่มีไทยหลุดในแถบเครื่องมือ/แผง', (tester) async {
    await boot(tester, lang: Lang.en, size: const Size(1100, 760));
    d.selectNode('p');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Next level'), findsOneWidget);
    expect(find.text('Place objects'), findsOneWidget);
    final thai = RegExp('[฀-๿]');
    final leaked = [
      for (final e in find.byType(Text).evaluate())
        if (thai.hasMatch((e.widget as Text).data ?? '')) (e.widget as Text).data,
    ];
    // ชื่อเอกสาร/วัตถุที่ผู้ใช้ตั้งเป็นไทยได้ — ตัวอย่างนี้ใช้ชื่ออังกฤษทั้งหมด
    expect(leaked, isEmpty, reason: '$leaked');
  });

  testWidgets('ปุ่มวางวัตถุไม่ล้นเมื่อแผงซ้ายแคบสุด (ความสูงปุ่มคงที่ ไม่ผันตามความกว้าง)', (tester) async {
    await boot(tester);
    final settings = tester.element(find.byType(HomePage)).read<AppSettings>();
    settings.layout.setLeft(PanelLayout.kLeftMin);
    await tester.pumpAndSettle();
    // เทสต์ล้มเองถ้ามี RenderFlex overflow ; ตรวจเพิ่มว่าทุกปุ่มสูงเท่ากัน 56
    for (final k in ['entity', 'process', 'store', 'boundary']) {
      expect(tester.getSize(find.byKey(ValueKey('dfd-tool-$k'))).height, 56, reason: k);
    }
    expect(tester.takeException(), isNull);
  });
}
