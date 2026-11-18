import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/review_note.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/doc_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 5c: หมุดโน้ตบนแคนวาสทุกชนิดเอกสาร
void main() {
  late WorkspaceController w;

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    await tester.pumpAndSettle();
  }

  /// เปิดเอกสารชนิด [t] (ER = ตัวหลัก) แล้วคืน controller
  Future<DocController> open(WidgetTester tester, DocType t) async {
    final id = t == DocType.er ? w.mainEr.docId : w.addDocument(t, name: t.name)!.id;
    w.openDocument(id);
    await tester.pumpAndSettle();
    return w.controllerOf(id)!;
  }

  for (final t in DocType.values) {
    testWidgets('${t.name}: หมุดแสดงบนแคนวาส ; คลิกเปิดการ์ด ติ๊กเสร็จได้ ; Shift+N ซ่อน/แสดง', (tester) async {
      await boot(tester);
      final c = await open(tester, t);
      final n = c.addReviewNote('ตรวจตรงนี้', x: 200, y: 160)!;
      await tester.pumpAndSettle();
      final pin = find.byKey(ValueKey('note-pin-${n.id}'));
      expect(pin, findsOneWidget);
      expect(find.descendant(of: pin, matching: find.text('1')), findsOneWidget);

      await tester.tap(pin);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('note-card-${n.id}')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('note-card-done-${n.id}')));
      await tester.pumpAndSettle();
      expect(c.reviewNoteById(n.id)!.done, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(w.notePinsVisible, isFalse);
      expect(pin, findsNothing);
      w.toggleNotePins(true);
      await tester.pumpAndSettle();
      expect(pin, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ลากหมุด = ย้ายตามระยะเมาส์หารซูม ; undo ขั้นเดียวคืนตำแหน่งเดิม', (tester) async {
    await boot(tester);
    final c = await open(tester, DocType.flowchart);
    final n = c.addReviewNote('ย้ายฉัน', x: 100, y: 100)!;
    await tester.pumpAndSettle();
    final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('note-pin-${n.id}'))));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(15, 10));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    final moved = c.reviewNoteById(n.id)!;
    expect(moved.x, isNot(100));
    expect(moved.y, isNot(100));
    c.undo();
    expect((c.reviewNoteById(n.id)!.x, c.reviewNoteById(n.id)!.y), (100.0, 100.0));
  });

  testWidgets('ปักหมุดจากแผงโน้ต: กดปุ่มหมุด แล้วคลิกบนแคนวาส = โน้ตใหม่ปักที่ตำแหน่งนั้น', (tester) async {
    await boot(tester);
    final c = await open(tester, DocType.dfd);
    w.showNotesPanel(true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('notes-new')), 'ที่เก็บนี้ต้องผูกตาราง');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('notes-add-pin')));
    await tester.pumpAndSettle();
    expect(w.pinRequest, isNotNull);
    final target = find.byKey(const ValueKey('note-pin-target'));
    expect(target, findsOneWidget);
    await tester.tapAt(tester.getTopLeft(target) + const Offset(300, 250));
    await tester.pumpAndSettle();
    expect(w.pinRequest, isNull);
    final n = c.reviewNotes.single;
    expect(n.text, 'ที่เก็บนี้ต้องผูกตาราง');
    expect(n.pinned, isTrue);
    expect(find.byKey(ValueKey('note-pin-${n.id}')), findsOneWidget);
  });

  testWidgets('ปักหมุดโน้ตเดิมจากเมนู ; Esc ยกเลิกคำขอ ; สลับเอกสาร = เลิกคำขอ', (tester) async {
    await boot(tester);
    final c = await open(tester, DocType.wireframe);
    final n = c.addReviewNote('ยังไม่ปัก', kind: NoteKind.question)!;
    w.requestPin(noteId: n.id);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(w.pinRequest, isNull);

    w.requestPin(noteId: n.id);
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('note-pin-target'));
    await tester.tapAt(tester.getCenter(target));
    await tester.pumpAndSettle();
    expect(c.reviewNoteById(n.id)!.pinned, isTrue);
    expect(c.reviewNotes, hasLength(1)); // ไม่ได้สร้างโน้ตใหม่

    w.requestPin(noteId: n.id);
    w.openDocument(w.mainEr.docId);
    expect(w.pinRequest, isNull);
  });

  testWidgets('คลิกพื้นที่ว่างรอบหมุดยังทำงานกับแคนวาสตามปกติ (ชั้นหมุดไม่บังการคลิก)', (tester) async {
    await boot(tester);
    final c = await open(tester, DocType.flowchart);
    c.addReviewNote('อยู่มุมหนึ่ง', x: 0, y: 0);
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('fc-canvas'));
    final hit = tester.hitTestOnBinding(tester.getCenter(canvas));
    expect(hit.path.any((e) => e.target == tester.renderObject(canvas)), isTrue);
  });
}
