import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/activity_rail.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// แถบไอคอนชนิดเอกสารด้านซ้ายสุด (Phase 1)
void main() {
  group('ActivityRail.targetFor / go', () {
    test('ชนิดที่ยังไม่มีเอกสาร: ไม่มีปลายทาง ; go สร้างใหม่และเปิดทันที', () {
      final w = WorkspaceController();
      expect(ActivityRail.targetFor(w, DocType.flowchart), isNull);
      ActivityRail.go(w, DocType.flowchart);
      expect(w.activeDocument.type, DocType.flowchart);
      expect(w.documents.where((d) => d.type == DocType.flowchart).length, 1);
    });

    test('มีอยู่แล้ว: กดซ้ำไม่สร้างเพิ่ม ; สลับไปมาระหว่างชนิดได้', () {
      final w = WorkspaceController();
      ActivityRail.go(w, DocType.dfd);
      final dfdId = w.activeId;
      ActivityRail.go(w, DocType.er);
      expect(w.activeDocument.type, DocType.er);
      ActivityRail.go(w, DocType.dfd);
      expect(w.activeId, dfdId);
      expect(w.documents.where((d) => d.type == DocType.dfd).length, 1);
    });

    test('ชนิดที่เปิดอยู่แล้ว: ปลายทางคือเอกสารที่เปิดอยู่ (ไม่กระโดดไปอันอื่นของชนิดเดียวกัน)', () {
      final w = WorkspaceController();
      final a = w.addDocument(DocType.dfd, name: 'A')!;
      final b = w.addDocument(DocType.dfd, name: 'B')!;
      w.openDocument(b.id);
      expect(ActivityRail.targetFor(w, DocType.dfd), b.id);
      w.openDocument(a.id);
      expect(ActivityRail.targetFor(w, DocType.dfd), a.id);
    });

    test('หน้า Project Home ไม่ถูกนับว่ากำลังเปิดชนิดใด ; กดปุ่มแล้วออกจาก Home', () {
      final w = WorkspaceController();
      w.showHome();
      expect(w.homeView, true);
      ActivityRail.go(w, DocType.er);
      expect(w.homeView, false);
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

    testWidgets('มีปุ่มครบ 5 ชนิด กว้างตามดีไซน์ และ ER ไฮไลต์ตอนเริ่ม', (tester) async {
      await boot(tester);
      expect(tester.getSize(find.byKey(const ValueKey('activity-rail'))).width, kActivityRailWidth);
      for (final t in ['er', 'dfd', 'flowchart', 'wireframe', 'screenflow']) {
        expect(find.byKey(ValueKey('rail-$t')), findsOneWidget, reason: t);
      }
      // ปุ่มมีป้ายอ่านออกเสียง (ผู้ใช้โปรแกรมอ่านหน้าจอ)
      expect(find.bySemanticsLabel(tr('ER Diagram (ตารางฐานข้อมูล)')), findsOneWidget);
    });

    testWidgets('กดปุ่ม Flowchart = สร้างและเปิดแท็บ Flowchart ; กดปุ่ม ER = กลับไป ER', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('rail-flowchart')));
      await tester.pumpAndSettle();
      expect(w.activeDocument.type, DocType.flowchart);
      await tester.tap(find.byKey(const ValueKey('rail-er')));
      await tester.pumpAndSettle();
      expect(w.activeDocument.type, DocType.er);
      // กดซ้ำ Flowchart: ไม่สร้างอันที่สอง
      await tester.tap(find.byKey(const ValueKey('rail-flowchart')));
      await tester.pumpAndSettle();
      expect(w.documents.where((d) => d.type == DocType.flowchart).length, 1);
    });

    testWidgets('ภาษาอังกฤษ: คำอธิบายปุ่มไม่มีไทยหลุด', (tester) async {
      await boot(tester, lang: Lang.en);
      final thai = RegExp(r'[฀-๿]');
      for (final t in ['er', 'dfd', 'flowchart', 'wireframe', 'screenflow']) {
        final tip = tester.widget<Tooltip>(find.descendant(of: find.byKey(ValueKey('rail-$t')), matching: find.byType(Tooltip)).first);
        expect(thai.hasMatch(tip.message ?? ''), false, reason: '$t: ${tip.message}');
      }
    });

    testWidgets('ปุ่ม Use Case บนแถบ: กด = เปิดหน้า Use Case ; กดซ้ำ = กลับเอกสาร ; ไฮไลต์ตอนเปิด ; ป้ายบอกจำนวน', (tester) async {
      await boot(tester);
      final btn = find.byKey(const ValueKey('rail-usecase'));
      expect(btn, findsOneWidget);
      expect(tester.widget<Tooltip>(find.descendant(of: btn, matching: find.byType(Tooltip)).first).message, contains('Use Case'));

      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(w.page, WorkspacePage.useCases);
      expect(find.byKey(const ValueKey('usecase-view')), findsOneWidget);
      // ปุ่มชนิดเอกสารไม่ไฮไลต์ขณะอยู่หน้านี้ (ปุ่ม ER ไม่มีแถบสีซ้าย)
      w.addUseCase(name: 'จองห้อง', actor: 'Guest');
      await tester.pumpAndSettle();
      expect(tester.widget<Tooltip>(find.descendant(of: btn, matching: find.byType(Tooltip)).first).message, contains('1'));

      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(w.page, WorkspacePage.document);
      expect(find.byKey(const ValueKey('usecase-view')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('แถบไอคอนพอดีหน้าต่างเตี้ย (560px) : ไม่ล้น และปุ่ม Use Case ยังอยู่', (tester) async {
      tester.view.physicalSize = const Size(1200, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th)));
      await tester.pump();
      expect(find.byKey(const ValueKey('rail-usecase')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
