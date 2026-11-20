import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/diagram.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_file.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// Phase 22: แท็บเอกสารแบบ VS Code — × = ปิดแท็บ (เอกสารยังอยู่) ; ยังไม่บันทึก = ถาม บันทึก/ไม่บันทึก/ยกเลิก
void main() {
  group('WorkspaceController: ปิดแท็บ / ย้อนเป็นตอนบันทึก', () {
    late WorkspaceController w;

    setUp(() => w = WorkspaceController(Workspace.single(base())));
    tearDown(() => w.dispose());

    test('ปิดแท็บ: เอกสารยังอยู่ ไม่นับเป็นการแก้ ; เปิดใหม่ได้', () {
      final dfd = w.addDocument(DocType.dfd)!;
      w.markSaved('x.nsln');
      w.closeTab(dfd.id);
      expect(w.documentById(dfd.id), isNotNull);
      expect(w.isTabOpen(dfd.id), isFalse);
      expect(w.activeId, kErDiagramId);
      expect(w.dirty, isFalse);
      expect(w.openDocument(dfd.id), isTrue);
      expect(w.isTabOpen(dfd.id), isTrue);
      expect(w.activeId, dfd.id);
    });

    test('ปิดได้ทุกแท็บ (รวม ER อันสุดท้าย) ; ปิดหมด = หน้า Project Home ; ออกจาก Home = เปิดแท็บกลับมา', () {
      w.closeTab(kErDiagramId);
      expect(w.openTabIds, isEmpty);
      expect(w.homeView, isTrue);
      expect(w.documentById(kErDiagramId), isNotNull);
      w.showHome(false);
      expect(w.homeView, isFalse);
      expect(w.openTabIds, [kErDiagramId]);
    });

    test('ย้อนเป็นตอนบันทึกล่าสุด: เนื้อหากลับ ไม่ dirty ; Ctrl+Z เอาการแก้คืน', () {
      final er = w.mainEr;
      w.markSaved('x.nsln');
      final before = er.project.tables.length;
      er.addTable(name: 'later');
      expect(w.documentDirty(kErDiagramId), isTrue);

      expect(w.revertDocument(kErDiagramId), isTrue);
      expect(er.project.tables.length, before);
      expect(w.documentDirty(kErDiagramId), isFalse);
      expect(w.dirty, isFalse);

      er.undo();
      expect(er.project.tables.any((t) => t.name == 'later'), isTrue);
    });

    test('ย้อนเอกสารที่ไม่ได้แก้ = ไม่ทำอะไร ; controller ที่สร้างทีหลังจำเนื้อหาตามไฟล์', () {
      expect(w.revertDocument(kErDiagramId), isFalse);
      final dfd = w.addDocument(DocType.dfd)!;
      w.markSaved('x.nsln');
      final d = w.dfdController(dfd.id)!;
      d.addNode(DfdKind.process, 100, 100);
      expect(w.revertDocument(dfd.id), isTrue);
      expect(d.diagram.nodes, isEmpty);
    });
  });

  group('แท็บบนหน้าจอ', () {
    late WorkspaceController w;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.loadProject(base(), null);
      await tester.pump();
    }

    testWidgets('เอกสารบันทึกแล้ว: × ปิดทันทีไม่ถาม ; เอกสารยังอยู่', (tester) async {
      await boot(tester);
      final dfd = w.addDocument(DocType.dfd)!;
      w.markSaved('x.nsln');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('tab-close-${dfd.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-tab-dialog')), findsNothing);
      expect(find.byKey(ValueKey('tab-${dfd.id}')), findsNothing);
      expect(w.documentById(dfd.id), isNotNull);
    });

    testWidgets('ยังไม่บันทึก: ถามก่อน ; ไม่บันทึก = ย้อนเนื้อหาแล้วปิด', (tester) async {
      await boot(tester);
      final dfd = w.addDocument(DocType.dfd)!;
      w.markSaved('x.nsln');
      w.dfdController(dfd.id)!.addNode(DfdKind.process, 100, 100);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('tab-dirty-${dfd.id}')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('tab-close-${dfd.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-tab-dialog')), findsOneWidget);
      expect(find.text('บันทึกการแก้ไขใน "${dfd.name}" ไหม'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-tab-discard')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('tab-${dfd.id}')), findsNothing);
      expect(w.dfdController(dfd.id)!.diagram.nodes, isEmpty);
      expect(w.dirty, isFalse);
    });

    testWidgets('ยังไม่บันทึก: บันทึก = เขียนไฟล์โปรเจกต์แล้วปิด', (tester) async {
      await boot(tester);
      final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('nsl_tab_close'));
      addTearDown(() => dir!.deleteSync(recursive: true));
      final path = '${dir!.path}${Platform.pathSeparator}p.nsln';
      final dfd = w.addDocument(DocType.dfd)!;
      w.markSaved(path);
      w.dfdController(dfd.id)!.addNode(DfdKind.process, 100, 100);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('tab-close-${dfd.id}')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('close-tab-save')));
        for (var i = 0; i < 50 && w.isTabOpen(dfd.id); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(w.isTabOpen(dfd.id), isFalse);
      expect(w.dirty, isFalse);
      final saved = await tester.runAsync(() => ProjectFile.load(path));
      expect(saved!.documentById(dfd.id)!.dfd!.nodes, hasLength(1));
    });

    testWidgets('ยังไม่บันทึก: ยกเลิก = ไม่ปิด การแก้ยังอยู่', (tester) async {
      await boot(tester);
      w.markSaved('x.nsln');
      w.mainEr.addTable(name: 'later');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-close-$kErDiagramId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('close-tab-cancel')));
      await tester.pumpAndSettle();
      expect(w.isTabOpen(kErDiagramId), isTrue);
      expect(w.mainEr.project.tables.any((t) => t.name == 'later'), isTrue);
    });

    testWidgets('ปุ่มกลางเมาส์ปิดแท็บ ; คลิกขวามี "ปิดแท็บ"', (tester) async {
      await boot(tester);
      final a = w.addDocument(DocType.dfd)!;
      final b = w.addDocument(DocType.flowchart)!;
      w.markSaved('x.nsln');
      await tester.pumpAndSettle();

      final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('tab-${a.id}'))),
          kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await g.up();
      await tester.pumpAndSettle();
      expect(w.isTabOpen(a.id), isFalse);

      final r = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('tab-${b.id}'))),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await r.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('ปิดแท็บ'));
      await tester.pumpAndSettle();
      expect(w.isTabOpen(b.id), isFalse);
      expect(w.documentById(b.id), isNotNull);
    });

    testWidgets('ปิดแท็บสุดท้าย = หน้า Project Home ; ภาษาอังกฤษแปลกล่องถาม', (tester) async {
      await boot(tester, lang: Lang.en);
      w.markSaved('x.nsln');
      w.mainEr.addTable(name: 'later');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-close-$kErDiagramId')));
      await tester.pumpAndSettle();
      expect(find.text('Save changes to "ER"?'), findsOneWidget);
      expect(find.text("Don't save"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-tab-discard')));
      await tester.pumpAndSettle();
      expect(w.openTabIds, isEmpty);
      expect(w.homeView, isTrue);
    });
  });
}
