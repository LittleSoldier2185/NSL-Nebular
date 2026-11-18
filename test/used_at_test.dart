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
import 'package:nsl_nebular/ui/right_panel.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// "ใช้งานที่" ในแผงขวาของ ER: เอกสารอื่นที่อ้างถึงตารางที่เลือก (Phase 1)
void main() {
  group('WorkspaceController.usagesOf', () {
    late WorkspaceController w;
    late String dfd, store;

    setUp(() {
      w = WorkspaceController(Workspace.single(base()));
      w.mainEr.addBuiltTable(TableModel(id: 'ord', name: 'orders'));
      w.mainEr.addBuiltTable(TableModel(id: 'cus', name: 'customers'));
      dfd = w.addDocument(DocType.dfd, name: 'L0')!.id;
      final d = w.dfdController(dfd)!;
      store = d.addNode(DfdKind.store, 100, 100)!.id;
      d.setStoreTable(store, DocRef(docId: w.mainEr.docId, elementId: 'ord', kind: DocRefKind.storeTable));
    });
    tearDown(() => w.dispose());

    test('ตารางที่ถูกผูก: เจอต้นทาง ; ตารางอื่น: ว่าง', () {
      final u = w.usagesOf(w.mainEr.docId, 'ord');
      expect(u.length, 1);
      expect((u.single.$1, u.single.$2), (dfd, store));
      expect(w.usagesOf(w.mainEr.docId, 'cus'), isEmpty);
    });

    test('เลิกผูกแล้วหายไป ; ลบตารางที่ผูกแล้วไม่เหลือค้าง', () {
      w.dfdController(dfd)!.setStoreTable(store, null);
      expect(w.usagesOf(w.mainEr.docId, 'ord'), isEmpty);
    });
  });

  group('บนจอ', () {
    late WorkspaceController w;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      await tester.pump();
    }

    // กล่อง "ใช้งานที่" อยู่ท้ายแผงขวา (ListView สร้างตอนเลื่อนถึง)
    Future<void> revealUsedAt(WidgetTester tester) => tester.scrollUntilVisible(
          find.byKey(const ValueKey('used-at')),
          300,
          scrollable: find.descendant(of: find.byType(RightPanel), matching: find.byType(Scrollable)).first,
        );

    void seed() {
      w.mainEr.addBuiltTable(TableModel(id: 'ord', name: 'orders'));
      w.mainEr.addBuiltTable(TableModel(id: 'cus', name: 'customers'));
      final dfd = w.addDocument(DocType.dfd, name: 'L0')!.id;
      final d = w.dfdController(dfd)!;
      final s = d.addNode(DfdKind.store, 100, 100)!.id;
      d.setStoreTable(s, DocRef(docId: w.mainEr.docId, elementId: 'ord', kind: DocRefKind.storeTable));
      w.openDocument(w.mainEr.docId);
    }

    testWidgets('เลือกตารางที่ถูกใช้: เห็นรายการ กดแล้วไปเปิดเอกสารนั้น', (tester) async {
      await boot(tester);
      seed();
      w.mainEr.selectTable('ord');
      await tester.pumpAndSettle();
      await revealUsedAt(tester);
      expect(find.byKey(const ValueKey('used-at')), findsOneWidget);
      expect(find.text('ใช้งานที่ · 1 จุด'), findsOneWidget);
      expect(find.text('L0'), findsWidgets);

      await tester.ensureVisible(find.byTooltip('ไปที่เอกสารนี้'));
      await tester.tap(find.byTooltip('ไปที่เอกสารนี้'));
      await tester.pumpAndSettle();
      expect(w.activeDocument.type, DocType.dfd);
    });

    testWidgets('เลือกตารางที่ไม่มีใครใช้: ขึ้น 0 จุดและข้อความบอก', (tester) async {
      await boot(tester);
      seed();
      w.mainEr.selectTable('cus');
      await tester.pumpAndSettle();
      await revealUsedAt(tester);
      expect(find.text('ใช้งานที่ · 0 จุด'), findsOneWidget);
      expect(find.byKey(const ValueKey('used-at-empty')), findsOneWidget);
    });

    testWidgets('ภาษาอังกฤษ: ไม่มีไทยหลุดในส่วนนี้', (tester) async {
      await boot(tester, lang: Lang.en);
      seed();
      w.mainEr.selectTable('ord');
      await tester.pumpAndSettle();
      await revealUsedAt(tester);
      expect(find.text('Used in · 1'), findsOneWidget);
      final thai = RegExp(r'[฀-๿]');
      final texts = tester.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('used-at')), matching: find.byType(Text)));
      for (final t in texts) {
        expect(thai.hasMatch(t.data ?? ''), false, reason: t.data);
      }
    });
  });
}
