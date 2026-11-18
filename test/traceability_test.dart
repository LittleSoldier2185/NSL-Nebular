import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/html_doc_export.dart';
import 'package:nsl_nebular/core/export/markdown_export.dart';
import 'package:nsl_nebular/core/export/trace_export.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/requirement.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/traceability.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 9: ความต้องการและการไล่ตาม
void main() {
  late WorkspaceController w;
  late ProjectDocument dfd, api;
  late ApiEndpoint ep;
  setUp(() {
    w = WorkspaceController();
    w.mainEr.project.tables.add(TableModel(id: 'o', name: 'orders'));
    dfd = w.addDocument(DocType.dfd, name: 'ระดับ 0')!;
    dfd.dfd!.nodes.add(DfdNode(id: 'p2', kind: DfdKind.process, name: 'รับคำสั่งซื้อ', number: '2.0'));
    api = w.addDocument(DocType.api, name: 'Store API')!;
    ep = w.apiController(api.id)!.addEndpoint(method: ApiMethod.post, path: '/orders')!;
  });
  tearDown(() => w.dispose());

  test('รหัสถัดไปต่อจากเลขสูงสุด ; เพิ่ม = dirty', () {
    w.markSaved('x.nsln');
    expect(w.addRequirement(text: 'สั่งซื้อ').code, 'REQ-01');
    w.updateRequirement(w.requirements.first.id, (r) => r.code = 'REQ-07');
    expect(w.addRequirement().code, 'REQ-08');
    expect(w.dirty, isTrue);
  });

  test('สถานะช่อง: ผูก = ครอบคลุม ; ไม่จำเป็น ; ไม่มี = ยังไม่มี ; ความต้องการครบเมื่อไม่มีช่องที่ยังไม่มี', () {
    final r = w.addRequirement(text: 'ลูกค้าสั่งซื้อได้');
    w.toggleTraceLink(r.id, DocType.er, TraceLink(w.mainEr.docId, 'o'));
    w.toggleTraceLink(r.id, DocType.dfd, TraceLink(dfd.id, 'p2'));
    w.toggleTraceLink(r.id, DocType.api, TraceLink(api.id, ep.id));
    for (final t in [DocType.flowchart, DocType.wireframe]) {
      w.setTraceNotNeeded(r.id, t, true);
    }
    expect(traceStatus(w.workspace, r, DocType.er), TraceStatus.covered);
    expect(traceStatus(w.workspace, r, DocType.flowchart), TraceStatus.notNeeded);
    expect(traceStatus(w.workspace, r, DocType.screenflow), TraceStatus.missing);
    expect(requirementCovered(w.workspace, r), isFalse);
    w.setTraceNotNeeded(r.id, DocType.screenflow, true);
    expect(requirementCovered(w.workspace, r), isTrue);
    final s = traceSummary(w.workspace);
    expect((s.total, s.covered, s.missingScreens, s.missingApi), (1, 1, 0, 0));
    expect(s.unlinkedDocs, isEmpty);
    // ผูกแล้วยกเลิก "ไม่จำเป็น" อัตโนมัติ ; สลับซ้ำ = เอาลิงก์ออก
    w.toggleTraceLink(r.id, DocType.er, TraceLink(w.mainEr.docId, 'o'));
    expect(traceStatus(w.workspace, r, DocType.er), TraceStatus.missing);
  });

  test('ลบเอกสาร/วัตถุที่ผูก = ช่องกลับเป็น "ยังไม่มี" และไม่นับครอบคลุม', () {
    final r = w.addRequirement();
    w.toggleTraceLink(r.id, DocType.api, TraceLink(api.id, ep.id));
    w.toggleTraceLink(r.id, DocType.dfd, TraceLink(dfd.id, 'p2'));
    expect(traceSummary(w.workspace).missingApi, 0);
    w.apiController(api.id)!.deleteEndpoint(ep.id);
    expect(traceStatus(w.workspace, r, DocType.api), TraceStatus.missing);
    expect(traceSummary(w.workspace).missingApi, 1);
    w.deleteDocument(dfd.id);
    expect(traceStatus(w.workspace, r, DocType.dfd), TraceStatus.missing);
  });

  test('เอกสารที่ไม่ได้ผูกกับความต้องการใด ; ผู้สมัครแต่ละคอลัมน์ ; ป้าย P2', () {
    final r = w.addRequirement();
    w.toggleTraceLink(r.id, DocType.dfd, TraceLink(dfd.id, 'p2'));
    expect(traceSummary(w.workspace).unlinkedDocs.map((d) => d.id).toSet(), {w.mainEr.docId, api.id});
    expect(traceCandidates(w.workspace, DocType.er).map((c) => c.label), ['orders']);
    expect(traceCandidates(w.workspace, DocType.dfd).single.label, 'P2 รับคำสั่งซื้อ');
    expect(traceCandidates(w.workspace, DocType.api).single.label, 'POST /orders');
    expect(traceCandidates(w.workspace, DocType.wireframe), isEmpty);
  });

  test('สร้างเอกสารใหม่ที่ผูกจากช่อง "ยังไม่มี" แล้วเปิด', () {
    final r = w.addRequirement(text: 'หน้าตะกร้า');
    final d = w.createTracedDocument(r.id, DocType.wireframe)!;
    expect(d.name, 'หน้าตะกร้า');
    expect(w.activeId, d.id);
    expect(traceStatus(w.workspace, r, DocType.wireframe), TraceStatus.covered);
  });

  test('บันทึก/เปิดซ้ำ ; อยู่ใน meta ; ชนิดเอกสารที่ไม่รู้จักในช่องเขียนกลับครบ', () {
    final r = w.addRequirement(text: 'ก', priority: ReqPriority.high);
    w.toggleTraceLink(r.id, DocType.er, TraceLink(w.mainEr.docId, 'o'));
    w.setTraceNotNeeded(r.id, DocType.flowchart, true);
    final j = jsonDecode(jsonEncode(encodeProjectMap(w.workspace))) as Map<String, dynamic>;
    final rj = ((j['meta'] as Map)['requirements'] as List).single as Map;
    (rj['cells'] as Map)['future'] = {'na': true};
    rj['owner'] = 'x';
    final back = decodeProjectMap(j);
    final r2 = back.requirements.single;
    expect((r2.code, r2.text, r2.priority), ('REQ-01', 'ก', ReqPriority.high));
    expect(r2.cells[DocType.flowchart]!.notNeeded, isTrue);
    expect(back.meta.extra.containsKey('requirements'), isFalse);
    final again = jsonDecode(jsonEncode(encodeProjectMap(back))) as Map<String, dynamic>;
    final rj2 = ((again['meta'] as Map)['requirements'] as List).single as Map;
    expect((rj2['cells'] as Map)['future'], {'na': true});
    expect(rj2['owner'], 'x');
    // ไม่มีความต้องการ = ไม่เขียนคีย์
    expect((jsonDecode(jsonEncode(encodeProjectMap(Workspace()))) as Map)['meta'], isNot(contains('requirements')));
  });

  test('ส่งออก: เอกสารสเปก Markdown + อยู่ในเอกสาร HTML/Markdown ; ไม่มีความต้องการ = ไม่มีส่วนนี้', () {
    expect(exportWorkspaceDictionary(w.workspace), isNot(contains('ความต้องการและการไล่ตาม')));
    final r = w.addRequirement(text: 'ลูกค้า | สั่งซื้อ');
    w.toggleTraceLink(r.id, DocType.api, TraceLink(api.id, ep.id));
    final md = exportTraceMarkdown(w.workspace);
    expect(md, contains('| REQ-01 | ลูกค้า \\| สั่งซื้อ | กลาง |'));
    expect(md, contains('POST /orders'));
    expect(md, contains('ยังไม่มี'));
    expect(exportWorkspaceDictionary(w.workspace), contains('## ความต้องการและการไล่ตาม'));
    expect(exportHtmlDocument(w.workspace, includeDiagrams: false), contains('id="requirements"'));
  });

  group('หน้าจอ', () {
    late WorkspaceController wc;
    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      wc.mainEr.project.tables.add(TableModel(id: 'o', name: 'orders'));
      wc.showTrace();
      await tester.pumpAndSettle();
    }

    testWidgets('เพิ่มความต้องการ ; กดช่อง ER เลือกตาราง = ครอบคลุม ; สรุปอัปเดต ; สร้าง Wireframe จากช่องว่าง', (tester) async {
      await boot(tester);
      expect(find.byKey(const ValueKey('trace-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trace-add')));
      await tester.pumpAndSettle();
      final r = wc.requirements.single;
      expect(find.byKey(ValueKey('trace-cell-${r.id}-er')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('trace-cell-${r.id}-er')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('orders').last);
      await tester.pumpAndSettle();
      expect(traceStatus(wc.workspace, r, DocType.er), TraceStatus.covered);
      expect(find.descendant(of: find.byKey(ValueKey('trace-cell-${r.id}-er')), matching: find.text('orders')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('trace-cell-${r.id}-wireframe')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้าง Wireframe ใหม่ที่ผูกกับข้อนี้'));
      await tester.pumpAndSettle();
      expect(wc.activeDocument.type, DocType.wireframe);
      expect(find.byKey(const ValueKey('trace-view')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('เข้าได้จากปุ่มบน Project Home', (tester) async {
      await boot(tester);
      wc.showHome();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-trace')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('trace-view')), findsOneWidget);
    });
  });
}
