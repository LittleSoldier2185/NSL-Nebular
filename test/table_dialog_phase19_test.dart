import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/check_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/index_model.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/project_controller.dart';
import 'package:nsl_nebular/ui/app_actions.dart';
import 'package:nsl_nebular/ui/create_table_dialog.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/seed_grid_editor.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// Phase 19 ชั้นที่ 6: กล่องสร้าง/แก้ตาราง 4 แท็บ (คอลัมน์แบบ C · ดัชนี · CHECK · ข้อมูลตั้งต้น) + แถบ SQL
void main() {
  Project hotel([Dialect d = Dialect.mysql]) => Project(name: 'hotel', dialect: d, tables: [
        TableModel(id: 'tb', name: 'bookings', columns: [
          col('b1', 'id', pk: true, ai: true, type: DataType.bigint),
          col('b2', 'check_in', type: DataType.date, nn: true),
          col('b3', 'check_out', type: DataType.date, nn: true),
          ColumnModel(id: 'b4', name: 'status', type: DataType.varchar, length: 20, notNull: true, defaultValue: 'pending', allowedValues: ['pending', 'confirmed']),
          col('b5', 'total', type: DataType.decimal, len: 10, scale: 2),
        ], checks: [
          CheckModel(id: 'k1', name: 'chk_bookings_dates', expr: 'check_out > check_in'),
        ], indexes: [
          IndexModel(id: 'i1', name: 'idx_room_dates', columnIds: ['b2', 'b3'], unique: false),
        ], seedRows: [
          {'b2': '2026-01-01', 'b3': '2026-01-03', 'b4': 'confirmed', 'b5': '100.00'},
        ]),
      ]);

  late ProjectController c;

  Future<void> boot(WidgetTester tester, {Dialect d = Dialect.mysql, Lang lang = Lang.th, Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => currentLang = Lang.th);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang)));
    c = tester.element(find.byType(HomePage)).read<ProjectController>();
    c.loadProject(hotel(d), null);
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, {TableDialogTab tab = TableDialogTab.columns}) async {
    final ctx = tester.element(find.byType(HomePage));
    AppActions(ctx).editTableStructure('tb', tab);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> tabTo(WidgetTester tester, String name) => tapKey(tester, 'ct-tab-$name');

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ct-save')));
    await tester.pumpAndSettle();
  }

  /// หาข้อความเฉพาะในกล่อง (ข้างหลังกล่องมีแถบ SQL ของทั้งโปรเจกต์ที่มีข้อความคล้ายกัน)
  Finder inDialog(String text) => find.descendant(of: find.byType(CreateTableDialog), matching: find.textContaining(text));

  /// เลือกชนิดของคอลัมน์ที่ [i] (เลื่อนให้เห็นก่อนกด)
  Future<void> pickType(WidgetTester tester, int i, String label) async {
    await tapKey(tester, 'ct-type-$i');
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  TableModel table() => c.project.tableById('tb')!;
  bool saveEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const ValueKey('ct-save'))).onPressed != null;

  group('buildTableFromDrafts', () {
    test('CHECK ที่ไม่มีนิพจน์ถูกข้าม ; id ใหม่ให้ถ้ายังไม่มี', () {
      var n = 0;
      final t = buildTableFromDrafts(
        newId: (p) => '$p${++n}',
        name: 't',
        comment: '',
        drafts: [ColumnDraft(name: 'a')],
        checks: [CheckDraft(name: 'one', expr: 'a > 0'), CheckDraft(name: 'blank', expr: '  '), CheckDraft(id: 'k9', name: 'keep', expr: 'a < 9')],
      );
      expect(t.checks.map((k) => (k.id, k.name, k.expr)), [('k2', 'one', 'a > 0'), ('k9', 'keep', 'a < 9')]);
    });

    test('ค่าที่อนุญาตติดไปเฉพาะชนิดที่รองรับ', () {
      final a = ColumnDraft(name: 'a', type: DataType.varchar, allowed: ['x', 'y']);
      final b = ColumnDraft(name: 'b', type: DataType.integer, allowed: ['1']);
      final t = buildTableFromDrafts(newId: (p) => p, name: 't', comment: '', drafts: [a, b]);
      expect(t.columns[0].allowedValues, ['x', 'y']);
      expect(t.columns[1].allowedValues, isEmpty);
    });

    test('ดัชนีหลายคอลัมน์ + ข้อมูลตั้งต้นใช้คีย์ร่าง แล้วแปลงเป็น id จริง (คอลัมน์ใหม่ได้ id ใหม่)', () {
      var n = 0;
      final a = ColumnDraft(name: 'a');
      final b = ColumnDraft(name: 'b');
      final t = buildTableFromDrafts(
        newId: (p) => '$p${++n}',
        name: 't',
        comment: '',
        drafts: [a, b],
        indexDrafts: [IndexDraft(name: 'ix', cols: [b.key, a.key, 'ghost'], unique: true), IndexDraft(name: 'empty', cols: ['ghost'])],
        seedRows: [
          {a.key: '1', b.key: 'x'},
        ],
      );
      expect(t.indexes.map((i) => '${i.name}|${i.unique}|${i.columnIds.join(',')}'), ['ix|true|${t.columns[1].id},${t.columns[0].id}'], reason: 'คอลัมน์ผีถูกตัด ดัชนีที่ไม่เหลือคอลัมน์ถูกข้าม');
      expect(t.seedRows.single, {t.columns[0].id: '1', t.columns[1].id: 'x'});
    });

    test('ไม่ส่ง indexDrafts/seedRows = คงดัชนีหลายคอลัมน์และข้อมูลตั้งต้นเดิม (พฤติกรรมเดิม)', () {
      final ex = hotel().tables.single;
      final drafts = [for (final c in ex.columns) ColumnDraft.fromColumn(ex, c)];
      final t = buildTableFromDrafts(newId: (p) => p, name: 'bookings', comment: '', drafts: drafts, existing: ex);
      expect(t.indexes.single.columnIds, ['b2', 'b3']);
      expect(t.seedRows.length, 1);
      expect(t.columns[3].allowedValues, ['pending', 'confirmed']);
    });
  });

  group('กล่อง 4 แท็บ', () {
    testWidgets('มี 4 แท็บพร้อมตัวเลข ; เริ่มที่คอลัมน์ ; สลับแท็บได้ ; เปิดตรงแท็บข้อมูลตั้งต้นได้', (tester) async {
      await boot(tester);
      await open(tester);
      for (final k in ['columns', 'indexes', 'checks', 'seed']) {
        expect(find.byKey(ValueKey('ct-tab-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const ValueKey('ct-name-0')), findsOneWidget);
      await tabTo(tester, 'indexes');
      expect(find.byKey(const ValueKey('ct-idx-name-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('ct-name-0')), findsNothing);
      await tabTo(tester, 'checks');
      expect(find.byKey(const ValueKey('ct-check-name-0')), findsOneWidget);
      await tabTo(tester, 'seed');
      expect(find.byKey(const ValueKey('seed-add-row')), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      await open(tester, tab: TableDialogTab.seed);
      expect(find.byKey(const ValueKey('seed-add-row')), findsOneWidget);
    });

    testWidgets('ปุ่มข้อมูลตั้งต้นที่แผงขวา เปิดกล่องนี้ที่แท็บข้อมูลตั้งต้น', (tester) async {
      await boot(tester);
      c.selectTable('tb');
      await tester.pumpAndSettle();
      final btn = find.byKey(const ValueKey('seed-open'));
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(find.byType(CreateTableDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('seed-add-row')), findsOneWidget);
    });
  });

  group('แท็บคอลัมน์: ค่าที่อนุญาต (แบบ C)', () {
    testWidgets('คอลัมน์ที่มีค่าที่อนุญาตขึ้นป้าย ENUM n และเปิดแถบรายละเอียดอัตโนมัติ ; ซ่อน/แสดงได้', (tester) async {
      await boot(tester);
      await open(tester);
      expect(find.byKey(const ValueKey('ct-enum-badge-3')), findsOneWidget);
      expect(find.text('ENUM 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('ct-detail-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('ct-detail-1')), findsNothing);
      await tapKey(tester, 'ct-expand-3');
      expect(find.byKey(const ValueKey('ct-detail-3')), findsNothing);
      await tapKey(tester, 'ct-enum-badge-3'); // คลิกป้าย = เปิดแถบ
      expect(find.byKey(const ValueKey('ct-detail-3')), findsOneWidget);
    });

    testWidgets('เพิ่มค่า (Enter) / ซ้ำถูกข้าม / วางหลายค่าคั่นจุลภาค / ลบชิป / บันทึกลงตาราง', (tester) async {
      await boot(tester);
      await open(tester);
      final add = find.byKey(const ValueKey('ct-allowed-add-3'));
      await tester.enterText(add, 'cancelled');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(add, 'pending'); // ซ้ำ
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(add, 'a, b ,c');
      await tester.pumpAndSettle();
      expect(find.text('ENUM 6'), findsOneWidget);
      await tapKey(tester, 'ct-allowed-rm-3-1'); // ลบ confirmed
      expect(find.text('ENUM 5'), findsOneWidget);
      await save(tester);
      expect(table().columnById('b4')!.allowedValues, ['pending', 'cancelled', 'a', 'b', 'c']);
      // ค่าเริ่มต้น pending ยังอยู่ในรายการ
      expect(table().columnById('b4')!.defaultValue, 'pending');
      c.undo();
      expect(table().columnById('b4')!.allowedValues, ['pending', 'confirmed']);
    });

    testWidgets('ค่าเริ่มต้นเป็นรายการเลือกจากค่าที่อนุญาต ; ลบค่าที่เป็นค่าเริ่มต้นทิ้ง = แจ้งและบันทึกไม่ได้', (tester) async {
      await boot(tester);
      await open(tester);
      expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
      expect(saveEnabled(tester), isTrue);
      await tapKey(tester, 'ct-allowed-rm-3-0'); // ลบ pending ซึ่งเป็นค่าเริ่มต้น
      expect(find.text('ไม่อยู่ในค่าที่อนุญาต'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      // เปลี่ยนค่าเริ่มต้นเป็นค่าที่เหลือ = บันทึกได้
      await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField<String> && w.key.toString().contains('ct-default-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('confirmed').last);
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await save(tester);
      expect(table().columnById('b4')!.defaultValue, 'confirmed');
      expect(table().columnById('b4')!.allowedValues, ['confirmed']);
    });

    testWidgets('เปลี่ยนชนิดเป็นชนิดที่ไม่รองรับ = ล้างค่าที่อนุญาต ป้ายหาย ; แถบรายละเอียดบอกว่าใช้ได้กับ VARCHAR/TEXT', (tester) async {
      await boot(tester);
      await open(tester);
      await pickType(tester, 3, 'BIGINT');
      expect(find.byKey(const ValueKey('ct-enum-badge-3')), findsNothing);
      expect(find.byKey(const ValueKey('ct-allowed-add-3')), findsNothing);
      expect(find.text('ค่าที่อนุญาตใช้ได้กับ VARCHAR / TEXT'), findsOneWidget);
      // เปลี่ยนกลับ = เริ่มใหม่ (ค่าเดิมหายแล้ว)
      await tapKey(tester, 'ct-type-3');
      await tester.pumpAndSettle();
      await tester.tap(find.text('VARCHAR').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ct-enum-badge-3')), findsNothing);
    });

    testWidgets('หมายเหตุคอลัมน์อยู่ในแถบรายละเอียด และบันทึกได้', (tester) async {
      await boot(tester);
      await open(tester);
      await tapKey(tester, 'ct-expand-1');
      await tester.enterText(find.byKey(const ValueKey('ct-comment-1')), 'วันเข้าพัก');
      await save(tester);
      expect(table().columnById('b2')!.comment, 'วันเข้าพัก');
    });
  });

  group('แท็บ CHECK', () {
    testWidgets('แสดงรายการเดิม ; ตรวจคอลัมน์ที่อ้างถึง ; เตือนเมื่ออ้างคอลัมน์ที่ไม่มี', (tester) async {
      await boot(tester);
      await open(tester, tab: TableDialogTab.checks);
      expect(find.byKey(const ValueKey('ct-check-note-0')), findsOneWidget);
      expect(find.textContaining('ผ่านการตรวจ'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('ct-check-expr-0')), 'check_out > missing_col');
      await tester.pumpAndSettle();
      expect(find.textContaining('ไม่พบคอลัมน์ missing_col'), findsOneWidget);
    });

    testWidgets('แม่แบบ "ช่วงค่า a > b" เลือกคอลัมน์วันที่สองตัวแรก ; "ค่าไม่ติดลบ" เลือกคอลัมน์ตัวเลขที่ไม่ใช่ PK ; ตั้งชื่อให้', (tester) async {
      await boot(tester);
      await open(tester, tab: TableDialogTab.checks);
      await tapKey(tester, 'ct-check-tpl-range');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('ct-check-expr-1'))).controller!.text, 'check_out > check_in');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('ct-check-name-1'))).controller!.text, 'chk_bookings_2');
      await tapKey(tester, 'ct-check-tpl-pos');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('ct-check-expr-2'))).controller!.text, 'total >= 0');
    });

    testWidgets('เพิ่ม/ลบ ; รายการที่นิพจน์ว่างไม่ถูกบันทึก ; ชื่อซ้ำแจ้งและบันทึกไม่ได้ ; บันทึกแล้ว undo ได้', (tester) async {
      await boot(tester);
      await open(tester, tab: TableDialogTab.checks);
      await tapKey(tester, 'ct-check-add'); // ว่าง
      await tapKey(tester, 'ct-check-add');
      await tester.enterText(find.byKey(const ValueKey('ct-check-expr-2')), 'total >= 0');
      await tester.enterText(find.byKey(const ValueKey('ct-check-name-2')), 'CHK_bookings_dates'); // ซ้ำกับรายการแรก (ไม่สนตัวพิมพ์)
      await tester.pumpAndSettle();
      expect(find.text('ชื่อซ้ำ'), findsNWidgets(2));
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const ValueKey('ct-check-name-2')), 'chk_total');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await save(tester);
      expect(table().checks.map((k) => (k.name, k.expr)), [('chk_bookings_dates', 'check_out > check_in'), ('chk_total', 'total >= 0')]);
      c.undo();
      expect(table().checks.length, 1);

      await open(tester, tab: TableDialogTab.checks);
      await tapKey(tester, 'ct-check-del-0');
      await save(tester);
      expect(table().checks, isEmpty);
    });

    testWidgets('MySQL: มีหมายเหตุเรื่องรุ่นที่ไม่บังคับ CHECK ; dialect อื่นไม่มี', (tester) async {
      await boot(tester);
      await open(tester, tab: TableDialogTab.checks);
      expect(find.textContaining('MySQL ก่อน 8.0.16'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      c.loadProject(hotel(Dialect.postgres), null);
      await tester.pump();
      await open(tester, tab: TableDialogTab.checks);
      expect(find.textContaining('MySQL ก่อน 8.0.16'), findsNothing);
    });
  });

  group('แท็บดัชนี', () {
    testWidgets('แสดงดัชนีหลายคอลัมน์เดิมตามลำดับ ; ดัชนีคอลัมน์เดียวไม่อยู่ในแท็บนี้', (tester) async {
      await boot(tester);
      c.updateColumn('tb', 'b5', (x) => x.unique = false);
      await open(tester, tab: TableDialogTab.indexes);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('ct-idx-name-0'))).controller!.text, 'idx_room_dates');
      expect(find.text('1. check_in'), findsOneWidget);
      expect(find.text('2. check_out'), findsOneWidget);
      expect(find.byKey(const ValueKey('ct-idx-name-1')), findsNothing);
    });

    testWidgets('เพิ่มดัชนี: เลือกคอลัมน์ตามลำดับ ติ๊ก UNIQUE บันทึกลงตาราง ; เอาคอลัมน์ออก/ลบดัชนี ; ไม่มีคอลัมน์ = แจ้งและบันทึกไม่ได้', (tester) async {
      await boot(tester);
      await open(tester, tab: TableDialogTab.indexes);
      await tapKey(tester, 'ct-idx-add');
      expect(saveEnabled(tester), isFalse, reason: 'ดัชนีใหม่ยังไม่มีคอลัมน์');
      expect(find.text('เลือกคอลัมน์อย่างน้อย 1'), findsOneWidget);
      await tapKey(tester, 'ct-idx-col-add-1');
      await tester.tap(find.text('status').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'ct-idx-col-add-1');
      await tester.tap(find.text('total').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'ct-idx-unique-1');
      expect(saveEnabled(tester), isTrue);
      await save(tester);
      final ix = table().indexes.firstWhere((i) => i.unique);
      expect(ix.columnIds, ['b4', 'b5']);
      expect(table().indexes.length, 2);
      c.undo();
      expect(table().indexes.length, 1);

      await open(tester, tab: TableDialogTab.indexes);
      await tapKey(tester, 'ct-idx-col-rm-0-0'); // เอา check_in ออก
      await save(tester);
      expect(table().indexes.single.columnIds, ['b3']);
      // ดัชนีที่เหลือคอลัมน์เดียว = ย้ายไปเป็นช่อง Index (INDEX) ในแท็บคอลัมน์ ไม่อยู่ในแท็บดัชนีแล้ว (ตามดีไซน์)
      await open(tester, tab: TableDialogTab.indexes);
      expect(find.byKey(const ValueKey('ct-idx-name-0')), findsNothing);
      expect(find.byKey(const ValueKey('ct-index-empty')), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      // ลบดัชนีหลายคอลัมน์ทั้งดัชนี
      c.loadProject(hotel(), null);
      await tester.pump();
      await open(tester, tab: TableDialogTab.indexes);
      await tapKey(tester, 'ct-idx-del-0');
      await save(tester);
      expect(table().indexes, isEmpty);
    });

    testWidgets('ลบคอลัมน์ที่ดัชนีใช้อยู่ในแท็บคอลัมน์ = ดัชนีเหลือคอลัมน์น้อยลง ; ชื่อดัชนีว่าง/ซ้ำ = บันทึกไม่ได้', (tester) async {
      await boot(tester);
      await open(tester, tab: TableDialogTab.indexes);
      await tester.enterText(find.byKey(const ValueKey('ct-idx-name-0')), '');
      await tester.pumpAndSettle();
      expect(find.text('ต้องตั้งชื่อดัชนี'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const ValueKey('ct-idx-name-0')), 'idx_x');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await tabTo(tester, 'columns');
      await tester.tap(find.byKey(const ValueKey('ct-remove-1'))); // ลบ check_in
      await tester.pumpAndSettle();
      await tabTo(tester, 'indexes');
      expect(find.text('1. check_out'), findsOneWidget);
      expect(find.text('1. check_in'), findsNothing);
    });
  });

  group('แท็บข้อมูลตั้งต้น', () {
    testWidgets('แสดงแถวเดิม ; คอลัมน์ที่มีค่าที่อนุญาตเป็นรายการเลือก ; เลือกค่าแล้วบันทึกได้ ; ค่านอกรายการเป็นปัญหา', (tester) async {
      await boot(tester);
      await open(tester, tab: TableDialogTab.seed);
      final statusCell = find.byKey(const ValueKey('seed-0-b4'));
      expect(tester.widget(statusCell), isA<DropdownButtonFormField<String>>());
      expect(tester.widget(find.byKey(const ValueKey('seed-0-b5'))), isA<TextField>());
      expect(find.byKey(const ValueKey('seed-problems')), findsNothing);

      await tapKey(tester, 'seed-add-row');
      expect(find.byKey(const ValueKey('seed-1-b4')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('seed-1-b4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('pending').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('seed-1-b2')), '2026-02-01');
      await tester.enterText(find.byKey(const ValueKey('seed-1-b3')), '2026-02-02');
      await tester.pumpAndSettle();
      await save(tester);
      expect(table().seedRows.length, 2);
      expect(table().seedRows[1]['b4'], 'pending');
    });

    testWidgets('ลบค่าที่อนุญาตที่ข้อมูลตั้งต้นใช้อยู่ = ช่องขึ้นแดง ป้ายแท็บเป็นสีแดง (ยังบันทึกได้ แต่ Export ข้อมูลตั้งต้นจะไม่ผ่าน)', (tester) async {
      await boot(tester);
      await open(tester, tab: TableDialogTab.seed);
      await tabTo(tester, 'columns');
      await tapKey(tester, 'ct-allowed-rm-3-1'); // ลบ confirmed (แถวตัวอย่างใช้ค่านี้)
      await tabTo(tester, 'seed');
      expect(find.byKey(const ValueKey('seed-problems')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('คอลัมน์ใหม่ที่เพิ่มในกล่อง + ข้อมูลตั้งต้นของคอลัมน์นั้น = บันทึกด้วย id จริงของคอลัมน์', (tester) async {
      await boot(tester);
      await open(tester);
      await tapKey(tester, 'ct-add');
      await tester.enterText(find.byKey(const ValueKey('ct-name-5')), 'note');
      await tester.pumpAndSettle();
      await tabTo(tester, 'seed');
      await tester.enterText(find.byType(TextField).last, 'ขอห้องเงียบ');
      await tester.pumpAndSettle();
      await save(tester);
      final note = table().columns.firstWhere((x) => x.name == 'note');
      expect(table().seedRows.first[note.id], 'ขอห้องเงียบ');
      expect(table().seedRows.first['b4'], 'confirmed');
    });
  });

  group('แถบตัวอย่าง SQL', () {
    testWidgets('MySQL: ENUM(...) และ CONSTRAINT CHECK ถูกไฮไลต์ ; ตามที่แก้สด', (tester) async {
      await boot(tester);
      await open(tester);
      expect(find.byKey(const ValueKey('ct-sql-bar')), findsOneWidget);
      expect(inDialog("ENUM('pending', 'confirmed')"), findsOneWidget);
      expect(inDialog('CHECK (check_out > check_in)'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('ct-sql-hi')), findsNWidgets(2));
      await tapKey(tester, 'ct-allowed-rm-3-1');
      expect(inDialog("ENUM('pending')"), findsOneWidget);
    });

    testWidgets('PostgreSQL: varchar + CONSTRAINT ชื่อ CHECK (col IN (...))', (tester) async {
      await boot(tester, d: Dialect.postgres);
      await open(tester);
      expect(inDialog('CONSTRAINT "chk_bookings_status" CHECK ("status" IN (\'pending\', \'confirmed\'))'), findsOneWidget);
      expect(inDialog('ENUM('), findsNothing);
    });

    testWidgets('พับ/กางได้ และจำการเลือกของผู้ใช้ ; หน้าต่างเตี้ย = พับเป็นค่าเริ่มต้น', (tester) async {
      await boot(tester);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('ct-sql-toggle')));
      await tester.pumpAndSettle();
      expect(inDialog("ENUM('pending'"), findsNothing);
      await tester.tap(find.byKey(const ValueKey('ct-sql-toggle')));
      await tester.pumpAndSettle();
      expect(inDialog("ENUM('pending'"), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1440, 700);
      await tester.pumpAndSettle();
      await open(tester);
      expect(inDialog("ENUM('pending'"), findsNothing);
    });

    testWidgets('ข้อมูลที่ยังกรอกไม่ครบ (ความยาวผิด ชื่อว่าง) ไม่ทำให้แถบ SQL พัง', (tester) async {
      await boot(tester);
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('ct-len-3')), 'abc');
      await tester.enterText(find.byKey(const ValueKey('ct-name-3')), '');
      await tester.enterText(find.byKey(const ValueKey('ct-table-name')), '');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ct-sql-bar')), findsOneWidget);
    });
  });

  group('สร้างตารางใหม่', () {
    testWidgets('สร้างพร้อมค่าที่อนุญาต CHECK และข้อมูลตั้งต้น ในครั้งเดียว', (tester) async {
      await boot(tester);
      final ctx = tester.element(find.byType(HomePage));
      AppActions(ctx).createTableFromForm();
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ct-table-name')), 'payments');
      await tester.enterText(find.byKey(const ValueKey('ct-count')), '3');
      await tester.tap(find.byKey(const ValueKey('ct-apply-count')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ct-name-1')), 'method');
      await pickType(tester, 1, 'VARCHAR');
      await tapKey(tester, 'ct-expand-1');
      final add = find.byKey(const ValueKey('ct-allowed-add-1'));
      await tester.enterText(add, 'card, cash, transfer');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ct-name-2')), 'amount');
      await pickType(tester, 2, 'DECIMAL');
      await tabTo(tester, 'checks');
      await tapKey(tester, 'ct-check-tpl-pos');
      await tabTo(tester, 'seed');
      await tapKey(tester, 'seed-add-row');
      await tester.enterText(find.descendant(of: find.byType(SeedGridEditor), matching: find.byType(TextField)).at(1), '5'); // คอลัมน์ id (AI) ช่องแรก ; amount ช่องที่สอง
      await save(tester);
      expect(find.byType(CreateTableDialog), findsNothing);
      final t = c.project.tables.firstWhere((x) => x.name == 'payments');
      expect(t.columns[1].allowedValues, ['card', 'cash', 'transfer']);
      expect(t.checks.single.expr, 'amount >= 0');
    });
  });

  testWidgets('ภาษาอังกฤษ: ข้อความของแท็บใหม่ไม่มีไทยหลุด', (tester) async {
    await boot(tester, lang: Lang.en);
    await open(tester);
    final thai = RegExp(r'[฀-๿]');
    void check(String where) {
      for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(CreateTableDialog), matching: find.byType(Text)))) {
        final s = t.data ?? t.textSpan?.toPlainText() ?? '';
        expect(thai.hasMatch(s), isFalse, reason: '$where: $s');
      }
    }

    check('columns');
    for (final k in ['indexes', 'checks', 'seed']) {
      await tabTo(tester, k);
      check(k);
    }
  });
}
