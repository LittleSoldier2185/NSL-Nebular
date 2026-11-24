import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/requirement.dart';
import 'package:nsl_nebular/core/models/use_case.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/project_history.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 29: Undo/Redo ข้อมูลระดับโปรเจกต์ (ความต้องการ · Use Case · ค่าตั้ง Mock)
void main() {
  group('ProjectHistory', () {
    test('record → undo → redo ; ย้อนคืนสแนปช็อตก่อนแก้ ; redo ถูกล้างเมื่อมีการแก้ใหม่', () {
      final h = ProjectHistory();
      expect((h.canUndo, h.canRedo), (false, false));
      h.record('A', 's0');
      h.record('B', 's1');
      expect((h.undoLabel, h.undoCount), ('B', 2));
      expect(h.undo('s2'), 's1');
      expect((h.undoLabel, h.redoLabel), ('A', 'B'));
      expect(h.undo('s1'), 's0');
      expect(h.canUndo, isFalse);
      expect(h.redo('s0'), 's1', reason: 'ทำซ้ำ = คืนค่าตอนที่ย้อน');
      expect(h.redo('s1'), 's2');
      expect(h.redo('s2'), isNull);
      h.undo('s2');
      h.record('C', 's1');
      expect(h.canRedo, isFalse);
    });

    test('จำกัดที่ maxSteps ; ขั้นเก่าสุดถูกทิ้ง', () {
      final h = ProjectHistory();
      for (var i = 0; i < ProjectHistory.maxSteps + 20; i++) {
        h.record('x$i', 's$i');
      }
      expect(h.undoCount, ProjectHistory.maxSteps);
      expect(h.undoLabel, 'x${ProjectHistory.maxSteps + 19}');
    });

    test('coalesce: key เดียวกันติดกันภายในช่วงเวลา = ขั้นเดียว (เก็บสแนปช็อตแรกสุด) ; เกินช่วงหรือ key ต่าง = ขั้นใหม่', () {
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final h = ProjectHistory(clock: () => now);
      h.record('พิมพ์', 'before', coalesce: 'k');
      now = now.add(const Duration(milliseconds: 500));
      h.record('พิมพ์', 'mid', coalesce: 'k');
      now = now.add(const Duration(milliseconds: 900)); // ต่ออายุทีละ <1.5 วินาที
      h.record('พิมพ์', 'mid2', coalesce: 'k');
      expect(h.undoCount, 1);
      expect(h.undo('after'), 'before');
      h.redo('before');
      now = now.add(const Duration(seconds: 5));
      h.record('พิมพ์', 'after', coalesce: 'k');
      expect(h.undoCount, 2, reason: 'เกินช่วงเวลา');
      h.record('อื่น', 'x', coalesce: 'j');
      expect(h.undoCount, 3, reason: 'key ต่าง');
    });
  });

  group('WorkspaceController', () {
    late WorkspaceController w;
    setUp(() => w = WorkspaceController());
    tearDown(() => w.dispose());

    Set<String> reqIds() => {for (final r in w.requirements) r.id};

    test('ความต้องการ: เพิ่ม/แก้/ลบ/ผูกลิงก์ ย้อนและทำซ้ำได้ ; ป้ายบอกการกระทำ', () {
      w.showTrace();
      final r = w.addRequirement(text: 'จองห้อง');
      expect(w.undoLabel, 'เพิ่มความต้องการ');
      w.updateRequirement(r.id, (x) => x.text = 'จองห้องออนไลน์');
      expect(w.undoLabel, 'แก้ความต้องการ');
      w.toggleTraceLink(r.id, DocType.er, TraceLink(w.mainEr.docId, 't'));
      expect(w.undoLabel, 'ผูกลิงก์ความต้องการ');
      w.deleteRequirement(r.id);
      expect(w.requirements, isEmpty);

      w.undo(); // ลบ
      expect(w.requirements.single.text, 'จองห้องออนไลน์');
      expect(w.requirements.single.cells[DocType.er]?.links, isNotEmpty);
      w.undo(); // ผูก
      expect(w.requirements.single.cells[DocType.er]?.links ?? [], isEmpty);
      w.undo(); // แก้
      expect(w.requirements.single.text, 'จองห้อง');
      w.undo(); // เพิ่ม
      expect(w.requirements, isEmpty);
      expect(w.canUndo, isFalse);

      w.redo();
      w.redo();
      expect(w.requirements.single.text, 'จองห้องออนไลน์');
      expect(reqIds().length, 1);
    });

    test('การแก้ที่ไม่เปลี่ยนอะไร ไม่เข้าประวัติ', () {
      w.showUseCases();
      final u = w.addUseCase(name: 'A', actor: 'x');
      w.setMockSettings(const MockSettings(port: 9001)); // ครั้งแรกจากที่ไม่มีคีย์ในไฟล์ = เปลี่ยนจริง
      final before = w.projectHistory.undoCount;
      w.updateUseCase(u.id, (x) => x.name = 'A'); // เท่าเดิม
      w.setMockSettings(const MockSettings(port: 9001)); // เท่าเดิม
      expect(w.projectHistory.undoCount, before);
    });

    test('Use Case: ชื่อการกระทำตั้งอัตโนมัติจากสิ่งที่เปลี่ยน ; ย้อนได้ทุกแบบ', () {
      w.showUseCases();
      final u = w.addUseCase(name: 'จองห้อง', actor: 'Guest');
      final other = w.addUseCase(name: 'ชำระเงิน', actor: 'Guest');
      void expectLabel(String l) => expect(w.undoLabel, l);

      w.updateUseCase(u.id, (x) => x.goal = 'เป้าหมาย');
      expectLabel('แก้ Use Case');
      w.updateUseCase(u.id, (x) => x.steps..add(UcStep(id: 's1', text: 'เลือก'))..add(UcStep(id: 's2', text: 'ยืนยัน')));
      expectLabel('เพิ่มขั้นตอน');
      w.updateUseCase(u.id, (x) => x.steps.insert(0, x.steps.removeAt(1)));
      expectLabel('ย้ายขั้นตอน');
      w.updateUseCase(u.id, (x) => x.stepById('s1')!.links.add(TraceLink(w.mainEr.docId)));
      expectLabel('ผูกลิงก์ขั้นตอน');
      w.updateUseCase(u.id, (x) => x.branches.add(UcBranch(id: 'b1', atStepId: 's1', ends: true)));
      expectLabel('เพิ่มทางเลือก/ข้อผิดพลาด');
      w.updateUseCase(u.id, (x) => x.reqIds.add('r1'));
      expectLabel('ผูกความต้องการ');
      w.updateUseCase(u.id, (x) => x.includes.add(other.id));
      expectLabel('แก้การเรียกใช้ Use Case');
      w.updateUseCase(u.id, (x) => x.branches.clear());
      expectLabel('ลบทางเลือก/ข้อผิดพลาด');
      w.updateUseCase(u.id, (x) => x.steps.removeWhere((s) => s.id == 's2'));
      expectLabel('ลบขั้นตอน');

      // ย้อนทีละขั้นกลับถึงจุดเริ่ม
      var n = 0;
      while (w.canUndo) {
        w.undo();
        n++;
      }
      expect(n, 11, reason: 'เพิ่ม UC 2 + แก้ 9');
      expect(w.useCases, isEmpty);
      for (var i = 0; i < n; i++) {
        w.redo();
      }
      final back = w.useCaseById(u.id)!;
      expect(back.steps.map((s) => s.id), ['s1']);
      expect(back.includes, [other.id]);
      expect(back.reqIds, ['r1']);
    });

    test('ลบ Use Case แล้วย้อน = กลับมาพร้อมการเรียกใช้ (include) ของข้ออื่นที่ถูกเอาออกตอนลบ', () {
      w.showUseCases();
      final a = w.addUseCase(name: 'A', actor: 'x');
      final b = w.addUseCase(name: 'B', actor: 'x');
      w.updateUseCase(a.id, (x) => x.includes.add(b.id));
      w.deleteUseCase(b.id);
      expect(w.useCaseById(a.id)!.includes, isEmpty);
      w.undo();
      expect(w.useCaseById(b.id), isNotNull);
      expect(w.useCaseById(a.id)!.includes, [b.id]);
    });

    test('Mock: ตั้งค่าแล้วย้อนได้ ; ค่าที่ไม่เคยตั้ง → ย้อนแล้วเอาคีย์ออก ; พิมพ์หน่วงต่อเนื่อง = ขั้นเดียว', () {
      w.showMock();
      expect(w.workspace.meta.extra.containsKey('mock'), isFalse);
      w.setMockSettings(const MockSettings(port: 9001));
      expect(w.undoLabel, 'ตั้งค่า Mock Server');
      final s = w.mockSettings;
      for (final ms in [3, 35, 350]) {
        w.setMockSettings(s.withEndpoint('e1', MockEndpointSetting(delayMs: ms)), coalesce: 'delay-e1');
      }
      expect(w.projectHistory.undoCount, 2, reason: 'ตั้งพอร์ต 1 + พิมพ์หน่วง 1');
      expect(w.mockSettings.of('e1').delayMs, 350);
      w.undo();
      expect(w.mockSettings.of('e1').delayMs, 0);
      expect(w.mockSettings.port, 9001);
      w.undo();
      expect(w.workspace.meta.extra.containsKey('mock'), isFalse, reason: 'ไม่เคยตั้ง = ไม่มีคีย์ในไฟล์');
      w.redo();
      expect(w.mockSettings.port, 9001);
    });

    test('เลือก stack ตามหน้า: Use Case/ความต้องการ/Mock = ของโปรเจกต์ ; เอกสาร/พจนานุกรม/Home = ของเอกสาร', () {
      w.mainEr.project.tables.isEmpty; // ER ว่าง ไม่มีประวัติเอกสาร
      w.showUseCases();
      w.addUseCase(name: 'A', actor: 'x');
      expect(w.canUndo, isTrue);
      expect(w.usesProjectHistory, isTrue);
      w.showTrace();
      expect(w.usesProjectHistory, isTrue);
      expect(w.canUndo, isTrue, reason: 'ประวัติโปรเจกต์ใช้ร่วมทุกหน้าของมัน');
      w.showMock();
      expect(w.usesProjectHistory, isTrue);
      w.showDictionary();
      expect(w.usesProjectHistory, isFalse);
      expect(w.canUndo, w.mainEr.canUndo, reason: 'พจนานุกรมแก้ ER จึงใช้ undo ของ ER เหมือนเดิม');
      w.showHome();
      expect(w.usesProjectHistory, isFalse);
      w.openDocument(w.mainEr.docId);
      expect(w.usesProjectHistory, isFalse);
      expect(w.undoLabel, isNull);
    });

    test('Undo ที่หน้าโปรเจกต์ไม่แตะเอกสาร และ Undo ที่เอกสารไม่แตะข้อมูลโปรเจกต์', () {
      w.mainEr.project.tables.clear();
      final r = w.addRequirement(text: 'x');
      w.showUseCases();
      w.undo();
      expect(w.requirements, isEmpty, reason: 'ย้อนข้อมูลโปรเจกต์');
      w.redo();
      w.openDocument(w.mainEr.docId);
      w.undo(); // ของเอกสาร (ER ไม่มีอะไรให้ย้อน)
      expect(w.requirements.map((e) => e.id), [r.id], reason: 'ไม่แตะข้อมูลโปรเจกต์');
    });

    test('เปิด/โหลดโปรเจกต์ใหม่ = ล้างประวัติ', () {
      w.showUseCases();
      w.addUseCase(name: 'A', actor: 'x');
      expect(w.projectHistory.canUndo, isTrue);
      w.loadWorkspace(Workspace(name: 'ใหม่')..documents.addAll(w.workspace.documents), null);
      expect(w.projectHistory.canUndo, isFalse);
      w.showUseCases();
      expect(w.canUndo, isFalse);
    });

    test('การย้อนทำให้ dirty และส่งต่อการเปลี่ยนแปลงให้หน้าจอ (notify)', () {
      w.showUseCases();
      final u = w.addUseCase(name: 'A', actor: 'x');
      w.markSaved('x.nsln');
      expect(w.dirty, isFalse);
      var notified = 0;
      w.addListener(() => notified++);
      w.undo();
      expect(w.dirty, isTrue);
      expect(notified, greaterThan(0));
      expect(w.useCaseById(u.id), isNull);
    });
  });

  group('หน้าจอ', () {
    late WorkspaceController wc;
    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      wc.showUseCases();
      await tester.pumpAndSettle();
    }

    Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+Z / Ctrl+Shift+Z บนหน้า Use Case ย้อน/ทำซ้ำข้อมูล ; ปุ่มบนแถบบนเปิดใช้และบอกการกระทำ', (tester) async {
      await boot(tester);
      expect(find.byTooltip('ย้อนกลับ (Ctrl+Z)'), findsOneWidget, reason: 'ยังไม่มีอะไรให้ย้อน');
      await tester.tap(find.byKey(const ValueKey('uc-add')));
      await tester.pumpAndSettle();
      expect(wc.useCases.length, 1);
      expect(find.byTooltip('ย้อนกลับ · เพิ่ม Use Case (Ctrl+Z)'), findsOneWidget);

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(wc.useCases, isEmpty);
      expect(find.byKey(const ValueKey('uc-empty')), findsOneWidget, reason: 'หน้าจอตามทัน');
      expect(find.byTooltip('ทำซ้ำ · เพิ่ม Use Case (Ctrl+Shift+Z)'), findsOneWidget);

      await ctrl(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(wc.useCases.length, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('คลิกปุ่มย้อนกลับบนแถบบน = ย้อนข้อมูลโปรเจกต์ ; ย้อนแล้วเลือกข้อที่หายไม่ล้ม', (tester) async {
      await boot(tester);
      wc.addUseCase(name: 'ข้อ 1', actor: 'Guest');
      final second = wc.addUseCase(name: 'ข้อ 2', actor: 'Guest');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('uc-item-${second.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ย้อนกลับ · เพิ่ม Use Case (Ctrl+Z)'));
      await tester.pumpAndSettle();
      expect(wc.useCases.length, 1);
      expect(find.byKey(ValueKey('uc-item-${second.id}')), findsNothing);
      expect(tester.takeException(), isNull, reason: 'ข้อที่เลือกอยู่ถูกย้อนหาย → หน้าจอกลับไปข้อแรก');
    });

    testWidgets('ขณะพิมพ์ในช่องข้อความ Ctrl+Z เป็นของช่องข้อความ ไม่ย้อนข้อมูลโปรเจกต์', (tester) async {
      await boot(tester);
      final u = wc.addUseCase(name: 'A', actor: 'Guest');
      await tester.pumpAndSettle();
      final before = wc.projectHistory.undoCount;
      await tester.tap(find.descendant(of: find.byKey(ValueKey('uc-goal-${u.id}')), matching: find.byType(TextField)));
      await tester.enterText(find.descendant(of: find.byKey(ValueKey('uc-goal-${u.id}')), matching: find.byType(TextField)), 'พิมพ์ค้าง');
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(wc.projectHistory.undoCount, before, reason: 'ไม่ได้ย้อนประวัติโปรเจกต์');
      expect(wc.useCaseById(u.id), isNotNull);
    });
  });
}
