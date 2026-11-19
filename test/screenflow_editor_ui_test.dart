import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/api_ref.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/screenflow_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 16: ตัวแก้ไข Screen Flow ตามดีไซน์ (Artifact "NSL Nebular — ตัวแก้ไข Screen Flow")
void main() {
  late WorkspaceController w;
  late ScreenFlowController f;

  Workspace sample() {
    final api = ApiDocument(title: 'Lib', endpoints: [ApiEndpoint(id: 'e_loan', method: ApiMethod.post, path: '/loans', summary: 'ยืม')]);
    final books = WireframeDiagram(device: WfDevice.desktop, components: [
      WfComponent(id: 'b_btn', kind: WfKind.button, text: 'Borrow', x: 40, y: 40, w: 120, h: 40)..api = const ApiRef(docId: 'api', endpointId: 'e_loan'),
    ]);
    final loan = WireframeDiagram(device: WfDevice.mobile, components: [
      WfComponent(id: 'l_title', kind: WfKind.heading, text: 'Loan', x: 20, y: 20, w: 200, h: 40),
    ]);
    final flow = ScreenFlowDiagram(nodes: [
      SfNode(id: 'start', kind: SfKind.start, title: 'Open', x: 0, y: 100),
      SfNode(id: 'books', kind: SfKind.screen, title: 'Books', wireframeId: 'wf_books', x: 200, y: 40),
      SfNode(id: 'loan', kind: SfKind.screen, title: 'Loan', wireframeId: 'wf_loan', x: 520, y: 40),
      SfNode(id: 'orphan', kind: SfKind.screen, title: 'Help', x: 520, y: 400),
    ], edges: [
      SfEdge(id: 's1', fromId: 'start', toId: 'books'),
      SfEdge(id: 's2', fromId: 'books', toId: 'loan', label: 'Borrow', condition: 'available'),
      SfEdge(id: 's3', fromId: 'loan', toId: 'books', label: 'Back'),
      SfEdge(id: 's4', fromId: 'books', toId: 'orphan', label: 'Help'),
    ]);
    return Workspace(name: 'Lib')
      ..documents.addAll([
        ProjectDocument.er(id: 'er', name: 'ER', content: Project(name: 'Lib', dialect: Dialect.mysql)),
        ProjectDocument.wireframe(id: 'wf_books', name: 'Books page', content: books),
        ProjectDocument.wireframe(id: 'wf_loan', name: 'Loan page', content: loan),
        ProjectDocument.wireframe(id: 'wf_extra', name: 'Extra page', content: WireframeDiagram()),
        ProjectDocument.screenflow(id: 'sf', name: 'Flow', content: flow),
        ProjectDocument.api(id: 'api', name: 'API', content: api),
      ]);
  }

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, Size size = const Size(1600, 950)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => currentLang = Lang.th);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang)));
    final ctx = tester.element(find.byType(HomePage));
    w = ctx.read<WorkspaceController>();
    w.loadWorkspace(sample(), null);
    w.openDocument('sf');
    await tester.pumpAndSettle();
    f = ctx.read<ScreenFlowController>();
  }

  testWidgets('แถบเครื่องมือเต็มความกว้าง ; ปุ่มวางโหนดอยู่แผงซ้าย ; สลับภาพย่อ Wireframe', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('sf-toolbar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sf-tool-edge')));
    await tester.pump();
    expect(f.tool, SfTool.edge);
    await tester.tap(find.byKey(const ValueKey('sf-tool-screen')));
    await tester.pump();
    expect(f.tool, SfTool.node);
    expect(f.toolKind, SfKind.screen);
    await tester.tap(find.byKey(const ValueKey('sf-tool-select')));
    await tester.pump();
    expect(f.showThumbnails, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('sf-thumbnails'))); // แถบซ้ายเลื่อนได้เมื่อแคบ
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sf-thumbnails')));
    await tester.pump();
    expect(f.showThumbnails, isFalse);
    expect(find.byKey(const ValueKey('sf-minimap')), findsOneWidget);
  });

  testWidgets('แผงซ้าย: หน้าจอบอกชนิดอุปกรณ์ ; การเปลี่ยนหน้าพับไว้ ; "จาก Wireframe…" เพิ่มหน้าจอที่ผูกแล้ว', (tester) async {
    await boot(tester);
    expect(find.descendant(of: find.byKey(const ValueKey('sf-item-books')), matching: find.text('เดสก์ท็อป')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('sf-item-loan')), matching: find.text('มือถือ')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('sf-item-orphan')), matching: find.text('ไม่ผูก')), findsOneWidget);
    expect(find.byKey(const ValueKey('sf-edge-s2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sf-group-edges')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sf-edge-s2')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sf-from-wireframe')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extra page').last);
    await tester.pumpAndSettle();
    final added = f.diagram.nodes.where((n) => n.wireframeId == 'wf_extra').toList();
    expect(added.length, 1);
    expect(added.single.title, 'Extra page');
  });

  testWidgets('แผงขวา หน้าจอ: การ์ด Wireframe + ไปต่อ/มาจาก (เงื่อนไข) + ผลตรวจรายโหนด', (tester) async {
    await boot(tester);
    f.selectBox('books');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sf-wireframe-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('sf-open-wireframe')), findsOneWidget);
    expect(find.text('ปุ่มเรียก API 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('sf-io-s2-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('sf-io-s3-in')), findsOneWidget);
    expect(find.text('available'), findsOneWidget);

    f.selectBox('orphan');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sf-create-wireframe')), findsOneWidget);
  });

  testWidgets('แผงขวา การเปลี่ยนหน้า: แนะนำ endpoint จากปุ่มใน Wireframe ที่ชื่อตรง trigger ; กดใช้แล้วผูก', (tester) async {
    await boot(tester);
    f.selectEdge('s2');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sf-api-suggestion')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sf-api-suggest')));
    await tester.pumpAndSettle();
    expect(f.diagram.edgeById('s2')!.api?.endpointId, 'e_loan');
    expect(find.byKey(const ValueKey('sf-api-suggestion')), findsNothing);
  });

  testWidgets('ภาพรวม: ตัวเลขสรุป · หน้าจอที่ยังไม่ผูก · เส้นทางจากจุดเริ่ม', (tester) async {
    await boot(tester);
    f.clearSelection();
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('sf-stat-linked')), matching: find.text('2/3')), findsOneWidget);
    expect(find.byKey(const ValueKey('sf-unlinked-orphan')), findsOneWidget);
    expect(find.byKey(const ValueKey('sf-path-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('sf-path-loan')), findsOneWidget);
  });

  testWidgets('ภาษาอังกฤษ หน้าต่างแคบ: ไม่ล้น ไม่มีไทยหลุด', (tester) async {
    await boot(tester, lang: Lang.en, size: const Size(1100, 760));
    f.selectBox('books');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Place nodes'), findsOneWidget);
    final thai = RegExp('[฀-๿]');
    final leaked = [
      for (final e in find.byType(Text).evaluate())
        if (thai.hasMatch((e.widget as Text).data ?? '')) (e.widget as Text).data,
    ];
    expect(leaked, isEmpty, reason: '$leaked');
  });
}
