import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/api_ref.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/core/validate/workspace_validator.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/document_actions.dart' show brokenLinkLines;
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 8e: ลิงก์ย้อน — วัตถุในเอกสารอื่นเรียก endpoint ของเอกสาร API
void main() {
  /// API 1 อัน (POST /orders) + Wireframe ปุ่ม / Screen Flow เส้น / DFD กระบวนการ / Flowchart สัญลักษณ์ ที่เรียก endpoint นั้น
  ({ProjectDocument api, ApiEndpoint ep, ProjectDocument wf, ProjectDocument sf, ProjectDocument dfd, ProjectDocument fc}) seed(WorkspaceController w) {
    final api = w.addDocument(DocType.api, name: 'Store API')!;
    final ep = w.apiController(api.id)!.addEndpoint(method: ApiMethod.post, path: '/orders')!;
    final ref = ApiRef(docId: api.id, endpointId: ep.id);
    final wf = w.addDocument(DocType.wireframe, name: 'หน้าตะกร้า')!;
    wf.wireframe!.components.add(WfComponent(id: 'btn', kind: WfKind.button, text: 'สั่งซื้อ')..api = ref);
    final sf = w.addDocument(DocType.screenflow, name: 'แอป')!;
    sf.screenflow!.nodes.addAll([SfNode(id: 'a', kind: SfKind.screen, title: 'ตะกร้า'), SfNode(id: 'b', kind: SfKind.screen, title: 'ยืนยัน')]);
    sf.screenflow!.edges.add(SfEdge(id: 'e', fromId: 'a', toId: 'b', label: 'สั่งซื้อ')..api = ref);
    final dfd = w.addDocument(DocType.dfd, name: 'ระดับ 0')!;
    dfd.dfd!.nodes.add(DfdNode(id: 'p', kind: DfdKind.process, name: 'รับคำสั่งซื้อ', number: '2')..api = ref);
    final fc = w.addDocument(DocType.flowchart, name: 'ชำระเงิน')!;
    fc.flowchart!.nodes.add(FcNode(id: 'n', shape: FcShape.process, text: 'สร้างคำสั่งซื้อ')..api = ref);
    return (api: api, ep: ep, wf: wf, sf: sf, dfd: dfd, fc: fc);
  }

  test('ลิงก์ API บันทึก/เปิดซ้ำได้ทั้ง 4 ชนิด ; ไม่ผูก = ไม่เขียนคีย์', () {
    final w = WorkspaceController();
    addTearDown(w.dispose);
    final s = seed(w);
    final back = decodeProjectMap(jsonDecode(jsonEncode(encodeProjectMap(w.workspace))) as Map<String, dynamic>);
    final ref = ApiRef(docId: s.api.id, endpointId: s.ep.id);
    expect(back.documentById(s.wf.id)!.wireframe!.componentById('btn')!.api, ref);
    expect(back.documentById(s.sf.id)!.screenflow!.edgeById('e')!.api, ref);
    expect(back.documentById(s.dfd.id)!.dfd!.nodeById('p')!.api, ref);
    expect(back.documentById(s.fc.id)!.flowchart!.nodeById('n')!.api, ref);
    expect(SfEdge(id: 'x', fromId: 'a', toId: 'b').toJson().containsKey('api'), isFalse);
    expect(FcNode(id: 'x', shape: FcShape.process).toJson().containsKey('api'), isFalse);
  });

  test('"เรียกใช้จาก" = usagesOf ของ endpoint ครบ 4 ที่ ; ลบเอกสาร API บอกลิงก์ที่จะขาด', () {
    final w = WorkspaceController();
    addTearDown(w.dispose);
    final s = seed(w);
    final from = {for (final u in w.usagesOf(s.api.id, s.ep.id)) (u.$1, u.$2)};
    expect(from, {(s.wf.id, 'btn'), (s.sf.id, 'e'), (s.dfd.id, 'p'), (s.fc.id, 'n')});
    final lines = brokenLinkLines(w, s.api.id);
    expect(lines, hasLength(4));
    expect(lines.every((l) => l.contains('POST /orders')), isTrue);
    expect(lines, contains('หน้าตะกร้า · ปุ่ม "สั่งซื้อ" → endpoint POST /orders'));
    expect(lines, contains('แอป · สั่งซื้อ → endpoint POST /orders')); // เส้น Screen Flow ใช้ป้ายของเส้น
  });

  test('ลบ endpoint / ลบเอกสาร API = ปัญหาข้ามเอกสาร api_ref_missing ในทั้ง 4 เอกสาร', () {
    final w = WorkspaceController();
    addTearDown(w.dispose);
    final s = seed(w);
    expect(crossDocIssues(validateWorkspace(w.workspace)), isEmpty);
    w.apiController(s.api.id)!.deleteEndpoint(s.ep.id);
    final cross = crossDocIssues(validateWorkspace(w.workspace));
    expect(cross.map((x) => x.issue.code).toSet(), {'api_ref_missing'});
    expect(cross.map((x) => x.docId).toSet(), {s.wf.id, s.sf.id, s.dfd.id, s.fc.id});
    final sfIssue = cross.firstWhere((x) => x.docId == s.sf.id).issue;
    expect(sfIssue.relationId, 'e'); // เส้น: ไปที่เส้นได้
  });

  group('หน้าจอ', () {
    late WorkspaceController w;
    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      await tester.pump();
    }

    testWidgets('แผงขวา API: "เรียกใช้จาก" แสดงต้นทางครบ กดแล้วไปที่เส้น Screen Flow', (tester) async {
      await boot(tester);
      final s = seed(w);
      w.openDocument(s.api.id);
      w.apiController(s.api.id)!.select(s.ep.id);
      await tester.pumpAndSettle();
      for (final k in ['${s.wf.id}-btn', '${s.sf.id}-e', '${s.dfd.id}-p', '${s.fc.id}-n']) {
        expect(find.byKey(ValueKey('api-caller-$k')), findsOneWidget);
      }
      await tester.tap(find.byKey(ValueKey('api-caller-${s.sf.id}-e')));
      await tester.pumpAndSettle();
      expect(w.activeId, s.sf.id);
      expect(w.screenflowController(s.sf.id)!.selectedEdgeId, 'e');
    });

    testWidgets('แผงขวา Flowchart: เลือก endpoint ได้ ; ลิงก์ที่ขาดขึ้นคำเตือน', (tester) async {
      await boot(tester);
      final s = seed(w);
      final f = w.flowchartController(s.fc.id)!;
      w.openDocument(s.fc.id);
      f.selectNode('n');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('api-ref-picker')), findsOneWidget);
      expect(find.byKey(const ValueKey('api-ref-goto')), findsOneWidget);
      w.apiController(s.api.id)!.deleteEndpoint(s.ep.id);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('api-ref-broken')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
