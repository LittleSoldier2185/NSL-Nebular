import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/doc_ref.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/status_bar.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// แถบสถานะ (Phase 1): สูง 28px + จำนวนเอกสาร / ลิงก์ข้ามเอกสาร
void main() {
  test('linkCount: 0 ตอนเริ่ม ; เพิ่มเมื่อผูก ; ลดเมื่อเลิกผูก', () {
    final w = WorkspaceController(Workspace.single(base()));
    addTearDown(w.dispose);
    w.mainEr.addBuiltTable(TableModel(id: 'ord', name: 'orders'));
    expect(w.linkCount, 0);
    final d = w.dfdController(w.addDocument(DocType.dfd, name: 'L0')!.id)!;
    final s = d.addNode(DfdKind.store, 100, 100)!.id;
    d.setStoreTable(s, DocRef(docId: w.mainEr.docId, elementId: 'ord', kind: DocRefKind.storeTable));
    expect(w.linkCount, 1);
    d.setStoreTable(s, null);
    expect(w.linkCount, 0);
  });

  testWidgets('แถบสถานะสูง 28 และแสดง "เอกสาร N · ลิงก์ข้ามเอกสาร M" ตามจริง', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
    final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    await tester.pump();
    expect(tester.getSize(find.byType(StatusBar)).height, 28);
    expect(find.text('เอกสาร 1 · ลิงก์ข้ามเอกสาร 0'), findsOneWidget);

    w.mainEr.addBuiltTable(TableModel(id: 'ord', name: 'orders'));
    final d = w.dfdController(w.addDocument(DocType.dfd, name: 'L0')!.id)!;
    final s = d.addNode(DfdKind.store, 100, 100)!.id;
    d.setStoreTable(s, DocRef(docId: w.mainEr.docId, elementId: 'ord', kind: DocRefKind.storeTable));
    await tester.pumpAndSettle();
    expect(find.text('เอกสาร 2 · ลิงก์ข้ามเอกสาร 1'), findsOneWidget);
  });

  testWidgets('ภาษาอังกฤษ: ข้อความนับไม่มีไทยหลุด', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.en)));
    await tester.pump();
    expect(find.text('Documents 1 · cross-document links 0'), findsOneWidget);
  });
}
