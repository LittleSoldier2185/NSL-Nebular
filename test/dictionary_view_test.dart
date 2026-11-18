import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/dictionary_model.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/core/models/review_note.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/dictionary_view.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 6: หน้าพจนานุกรมข้อมูล
void main() {
  /// ER: customers(id PK มีคำอธิบาย, name) ; orders(id PK, customer_id FK → customers.id) — orders มีคำอธิบายตาราง
  void seed(WorkspaceController w) {
    final p = w.mainEr.project;
    p.tables
      ..add(TableModel(id: 'c', name: 'customers', columns: [
        ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true, comment: 'รหัสลูกค้า'),
        ColumnModel(id: 'c2', name: 'name'),
      ]))
      ..add(TableModel(id: 'o', name: 'orders', comment: 'คำสั่งซื้อ', columns: [
        ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true),
        ColumnModel(id: 'o2', name: 'customer_id', notNull: true),
      ]));
    p.relations.add(RelationModel(id: 'r', fromTableId: 'o', fromColumnId: 'o2', toTableId: 'c', toColumnId: 'c1'));
  }

  group('โมเดล', () {
    late WorkspaceController w;
    setUp(() {
      w = WorkspaceController();
      seed(w);
    });
    tearDown(() => w.dispose());

    test('ช่องที่ยังว่าง: ตาราง แล้วคอลัมน์ ตามลำดับ ; นับช่องทั้งหมด', () {
      final er = w.mainEr.docId;
      expect(missingDescriptions(w.workspace), [
        (docId: er, tableId: 'c', columnId: null),
        (docId: er, tableId: 'c', columnId: 'c2'),
        (docId: er, tableId: 'o', columnId: 'o1'),
        (docId: er, tableId: 'o', columnId: 'o2'),
      ]);
      expect(descriptionSlotCount(w.workspace), 6);
    });

    test('ช่องถัดไปวนกลับไปตัวแรก ; ไม่มีช่องว่าง = null', () {
      final all = missingDescriptions(w.workspace);
      expect(nextMissing(w.workspace, null), all.first);
      expect(nextMissing(w.workspace, all.last), all.first);
      expect(nextMissing(w.workspace, all[1]), all[2]);
      for (final t in w.mainEr.project.tables) {
        t.comment = 'x';
        for (final c in t.columns) {
          c.comment = 'y';
        }
      }
      expect(nextMissing(w.workspace, null), isNull);
    });

    test('ถูกอ้างถึงโดย / ปลายทาง FK', () {
      final p = w.mainEr.project;
      expect(referencedBy(p, 'c'), ['orders.customer_id']);
      expect(referencedBy(p, 'o'), isEmpty);
      expect(fkTarget(p, 'o', 'o2'), 'customers.id');
      expect(fkTarget(p, 'o', 'o1'), isNull);
    });

    test('ส่งออก: เลือกไม่ใส่โน้ตได้ ; เลือกภาษาได้โดยไม่เปลี่ยนภาษาของแอป', () {
      w.mainEr.doc.reviewNotes = [ReviewNote(id: 'n', text: 'เติมคำอธิบาย')];
      final withNotes = buildDictionaryExport(w.workspace, format: DictFormat.markdown);
      final noNotes = buildDictionaryExport(w.workspace, format: DictFormat.markdown, notes: false);
      expect(withNotes, contains('เติมคำอธิบาย'));
      expect(noNotes, isNot(contains('เติมคำอธิบาย')));
      final en = buildDictionaryExport(w.workspace, format: DictFormat.html, diagrams: false, lang: Lang.en);
      expect(en, contains('Notes &amp; to-dos'));
      expect(currentLang, Lang.th);
      expect(buildDictionaryExport(w.workspace, format: DictFormat.html, diagrams: false), contains('คำสั่งซื้อ'));
    });
  });

  late WorkspaceController w;
  final view = find.byKey(const ValueKey('dictionary-view'));

  Future<void> boot(WidgetTester tester, {Size size = const Size(1600, 950)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    seed(w);
    w.showDictionary();
    await tester.pumpAndSettle();
  }

  testWidgets('แสดงตาราง คอลัมน์ ชนิด Null PK/FK ถูกอ้างถึงโดย และตัวนับช่องว่าง', (tester) async {
    await boot(tester);
    expect(view, findsOneWidget);
    expect(find.text('customers'), findsWidgets);
    expect(find.text('ถูกอ้างถึงโดย'), findsOneWidget);
    expect(find.text('orders.customer_id'), findsOneWidget);
    expect(find.text('{0} ช่องยังไม่มีคำอธิบาย'.replaceFirst('{0}', '4')), findsOneWidget);
    expect(find.text('2 ตาราง · กรอกคำอธิบายแล้ว 2 จาก 6 ช่อง'), findsOneWidget);
    expect(find.text('+ เพิ่มคำอธิบาย (→ customers.id)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('แก้คำอธิบายในหน้า: บันทึกเมื่อกด Enter ; undo ได้ ; ตัวนับลดลง', (tester) async {
    await boot(tester);
    final field = find.descendant(of: find.byKey(ValueKey('dict-c-${w.mainEr.docId}-c-c2')), matching: find.byType(EditableText));
    await tester.tap(field);
    await tester.enterText(field, '  ชื่อ   ลูกค้า ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(w.mainEr.project.tableById('c')!.columnById('c2')!.comment, 'ชื่อ ลูกค้า');
    expect(find.text('3 ช่องยังไม่มีคำอธิบาย'), findsOneWidget);
    expect(w.dirty, isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    w.mainEr.undo();
    await tester.pumpAndSettle();
    expect(w.mainEr.project.tableById('c')!.columnById('c2')!.comment, '');
    expect(find.text('4 ช่องยังไม่มีคำอธิบาย'), findsOneWidget);
  });

  testWidgets('"ไปเติมทีละช่อง" โฟกัสช่องว่างถัดไปตามลำดับ', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('dict-next-missing')));
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus;
    final first = find.descendant(of: find.byKey(ValueKey('dict-t-${w.mainEr.docId}-c')), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(first).focusNode, focused);
    await tester.tap(find.byKey(const ValueKey('dict-next-missing')));
    await tester.pumpAndSettle();
    final second = find.descendant(of: find.byKey(ValueKey('dict-c-${w.mainEr.docId}-c-c2')), matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(second).focusNode, FocusManager.instance.primaryFocus);
  });

  testWidgets('"ใช้งานใน": ที่เก็บข้อมูล DFD ที่ผูกตาราง กดแล้วไปที่ DFD', (tester) async {
    await boot(tester);
    final d = w.addDocument(DocType.dfd, name: 'ระดับ 0')!;
    d.dfd!.nodes.add(DfdNode(id: 's', kind: DfdKind.store, name: 'คำสั่งซื้อ', tableId: 'o', tableDocId: w.mainEr.docId));
    w.showDictionary();
    await tester.pumpAndSettle();
    expect(find.text('ใช้งานใน'), findsOneWidget);
    await tester.tap(find.text('ระดับ 0 · คำสั่งซื้อ'));
    await tester.pumpAndSettle();
    expect(w.activeId, d.id);
    expect(view, findsNothing);
  });

  testWidgets('เข้าได้จากปุ่มบน Project Home ; เปิดเอกสาร = ออก ; คีย์ลัดแก้เอกสารไม่ทำงานในหน้านี้', (tester) async {
    await boot(tester);
    w.showHome();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-dictionary')));
    await tester.pumpAndSettle();
    expect(view, findsOneWidget);
    expect(w.homeView, isFalse);
    final before = w.mainEr.project.tables.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT); // เครื่องมือเพิ่มตาราง — ต้องไม่ทำงาน
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(w.mainEr.project.tables.length, before);
    w.openDocument(w.mainEr.docId);
    await tester.pumpAndSettle();
    expect(view, findsNothing);
  });

  testWidgets('หน้าต่างแคบ (1000px): ไม่ล้น สารบัญซ่อน แผงส่งออกต่อท้าย', (tester) async {
    await boot(tester, size: const Size(1000, 700));
    expect(find.byKey(const ValueKey('dict-next-missing-narrow')), findsOneWidget);
    expect(find.byKey(const ValueKey('dict-export')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
