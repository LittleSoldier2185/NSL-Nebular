import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/review_note.dart';
import 'package:nsl_nebular/core/models/review_note_refs.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/notes_panel.dart';
import 'package:provider/provider.dart';

/// Phase 5b: แผงโน้ตและงานค้าง + คำอ้างอิง #
void main() {
  group('คำอ้างอิงและชื่อวัตถุ', () {
    late WorkspaceController w;
    setUp(() {
      w = WorkspaceController();
      w.mainEr.project.tables.add(TableModel(id: 't1', name: 'orders', columns: [ColumnModel(id: 'c1', name: 'id')]));
    });
    tearDown(() => w.dispose());

    test('#ชื่อเอกสาร (ช่องว่างพิมพ์เป็น _) มาก่อน #ชื่อตาราง ; ไม่สนตัวพิมพ์ ; ไม่พบ = null', () {
      final d = w.addDocument(DocType.wireframe, name: 'หน้า ตะกร้า')!;
      expect(resolveNoteRef(w.workspace, 'หน้า_ตะกร้า'), (docId: d.id, tableId: null));
      expect(resolveNoteRef(w.workspace, 'ORDERS'), (docId: w.mainEr.docId, tableId: 't1'));
      expect(resolveNoteRef(w.workspace, 'ไม่มี'), isNull);
    });

    test('ตารางชื่อซ้ำหลาย ER: เลือกของเอกสารที่ระบุก่อน', () {
      final e2 = w.addDocument(DocType.er, name: 'Billing')!;
      e2.er!.tables.add(TableModel(id: 't9', name: 'orders'));
      expect(resolveNoteRef(w.workspace, 'orders', preferDocId: e2.id), (docId: e2.id, tableId: 't9'));
      expect(resolveNoteRef(w.workspace, 'orders')!.docId, w.mainEr.docId);
    });

    test('ชื่อวัตถุที่โน้ตผูก: ตาราง ER / สัญลักษณ์ Flowchart ; ไม่พบ = null', () {
      expect(noteAnchorLabel(w.mainEr.doc, 't1'), 'orders');
      expect(noteAnchorLabel(w.mainEr.doc, 'x'), isNull);
      final f = w.addDocument(DocType.flowchart, name: 'F')!;
      f.flowchart!.nodes.add(FcNode(id: 'n', shape: FcShape.process, text: 'ตัด\nสต็อก'));
      expect(noteAnchorLabel(f, 'n'), 'ตัด สต็อก');
    });

    test('เลขหมุดนับเฉพาะโน้ตที่ปักหมุด ; งานค้างนับเฉพาะต้องทำ/คำถามที่ยังไม่เสร็จ', () {
      final doc = w.mainEr.doc;
      doc.reviewNotes = [
        ReviewNote(id: 'a', text: 'a'),
        ReviewNote(id: 'b', text: 'b', x: 1, y: 1),
        ReviewNote(id: 'c', text: 'c', x: 2, y: 2, kind: NoteKind.memo),
        ReviewNote(id: 'd', text: 'd', kind: NoteKind.question, done: true),
      ];
      expect([for (final id in ['a', 'b', 'c']) notePinNumber(doc, id)], [null, 1, 2]);
      expect(openNoteCount(w.workspace), 2); // a และ b (ต้องทำที่ยังไม่เสร็จ) ; c = บันทึก ; d = เสร็จแล้ว
    });
  });

  late WorkspaceController w;
  final panel = find.byKey(const ValueKey('notes-panel'));

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    w.mainEr.project.tables.add(TableModel(id: 't1', name: 'orders', columns: [ColumnModel(id: 'c1', name: 'id')]));
    await tester.pumpAndSettle();
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('status-notes')));
    await tester.pumpAndSettle();
  }

  Future<void> addNote(WidgetTester tester, String text, {NoteKind kind = NoteKind.todo}) async {
    await tester.enterText(find.byKey(const ValueKey('notes-new')), text);
    await tester.pump();
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('notes-kind')), matching: find.text(noteKindLabel(kind))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('notes-add')));
    await tester.pumpAndSettle();
  }

  testWidgets('ปุ่มในแถบสถานะเปิด/ปิดแผงโน้ต (แทนแผงขวา) ; แผงว่างบอกวิธีเพิ่ม', (tester) async {
    await boot(tester);
    expect(panel, findsNothing);
    await openPanel(tester);
    expect(panel, findsOneWidget);
    expect(find.byKey(const ValueKey('notes-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notes-close')));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(w.notesPanel, isFalse);
  });

  testWidgets('เพิ่มโน้ต → อยู่ในรายการ ตัวเลขค้างในแถบสถานะขึ้น ; ติ๊กเสร็จ ; ตัวกรอง ; undo เอาออก', (tester) async {
    await boot(tester);
    await openPanel(tester);
    expect(find.byKey(const ValueKey('notes-add')), findsOneWidget);
    await addNote(tester, 'เพิ่มคอลัมน์ status ใน #orders');
    await addNote(tester, 'ต้องเก็บประวัติราคาไหม', kind: NoteKind.question);
    await addNote(tester, 'ตกลงกับลูกค้าแล้ว', kind: NoteKind.memo);
    final notes = w.mainEr.reviewNotes;
    expect(notes.map((n) => n.kind), [NoteKind.todo, NoteKind.question, NoteKind.memo]);
    expect(find.text('ค้าง 2'), findsOneWidget);
    expect(w.dirty, isTrue);

    await tester.tap(find.byKey(ValueKey('note-done-${notes.first.id}')));
    await tester.pumpAndSettle();
    expect(notes.first.done, isTrue);
    expect(find.text('ค้าง 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notes-filter-question')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('note-${notes[1].id}')), findsOneWidget);
    expect(find.byKey(ValueKey('note-${notes[0].id}')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('notes-filter-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('note-${notes[0].id}')), findsOneWidget);

    w.mainEr.undo(); // ยกเลิกการติ๊กเสร็จ
    await tester.pumpAndSettle();
    expect(w.mainEr.reviewNotes.first.done, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('เมนูโน้ต: แก้ข้อความ / เปลี่ยนชนิด / ลบ', (tester) async {
    await boot(tester);
    final n = w.mainEr.addReviewNote('เดิม')!;
    await openPanel(tester);
    Future<void> menu(String item) async {
      await tester.tap(find.byKey(ValueKey('note-menu-${n.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    await menu('แก้ข้อความ…');
    await tester.enterText(find.byKey(const ValueKey('note-edit-field')), 'ใหม่');
    await tester.tap(find.byKey(const ValueKey('note-edit-ok')));
    await tester.pumpAndSettle();
    expect(w.mainEr.reviewNotes.single.text, 'ใหม่');

    await menu('เปลี่ยนเป็น "คำถาม"');
    expect(w.mainEr.reviewNotes.single.kind, NoteKind.question);

    await menu('ลบโน้ต');
    expect(w.mainEr.reviewNotes, isEmpty);
  });

  testWidgets('แท็บทั้งโปรเจกต์: รวมโน้ตทุกเอกสาร กดแล้วไปที่เอกสารนั้น', (tester) async {
    await boot(tester);
    final f = w.addDocument(DocType.flowchart, name: 'ขั้นตอนชำระเงิน')!;
    final fn = w.controllerOf(f.id)!.addReviewNote('ตรวจทางออก')!;
    w.openDocument(w.mainEr.docId);
    w.mainEr.addReviewNote('ของ ER');
    await tester.pumpAndSettle();
    await openPanel(tester);
    expect(find.text('หน้านี้ · 1'), findsOneWidget);
    expect(find.text('ทั้งโปรเจกต์ · 2'), findsOneWidget);
    expect(find.byKey(ValueKey('note-${fn.id}')), findsNothing);
    await tester.tap(find.text('ทั้งโปรเจกต์ · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('note-${fn.id}')));
    await tester.pumpAndSettle();
    expect(w.activeId, f.id);
    expect(panel, findsOneWidget); // แผงยังเปิดอยู่หลังสลับเอกสาร
  });

  testWidgets('คำอ้างอิง #ตาราง เป็นลิงก์: กดแล้วเปิด ER และเลือกตารางนั้น', (tester) async {
    await boot(tester);
    final f = w.addDocument(DocType.flowchart, name: 'F')!;
    w.controllerOf(f.id)!.addReviewNote('ใช้ตาราง #orders');
    await tester.pumpAndSettle();
    await openPanel(tester);
    final txt = find.byWidgetPredicate((wd) => wd is RichText && wd.text.toPlainText() == 'ใช้ตาราง #orders');
    expect(txt, findsOneWidget);
    // แตะที่ท้ายข้อความ (ตรงคำว่า #orders)
    final r = tester.getRect(txt);
    await tester.tapAt(Offset(r.right - 4, r.center.dy));
    await tester.pumpAndSettle();
    expect(w.activeId, w.mainEr.docId);
    expect(w.mainEr.selectedTableId, 't1');
  });

  testWidgets('ภาษาอังกฤษ: แผงโน้ตไม่มีอักษรไทยหลุด', (tester) async {
    await boot(tester, lang: Lang.en);
    addTearDown(() => currentLang = Lang.th);
    w.mainEr.addReviewNote('Check #orders');
    await openPanel(tester);
    expect(find.text('Notes & to-dos'), findsOneWidget);
    final thai = RegExp(r'[฀-๿]');
    for (final t in tester.widgetList<RichText>(find.descendant(of: panel, matching: find.byType(RichText)))) {
      expect(thai.hasMatch(t.text.toPlainText()), isFalse, reason: t.text.toPlainText());
    }
  });
}
